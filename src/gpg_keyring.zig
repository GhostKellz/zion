const std = @import("std");
const signature_verification = @import("signature_verification.zig");
const zion_root = @import("root.zig");
const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;
const Io = std.Io;

/// GPG keyring integration for Zion package verification
/// Supports both user GPG keys and system keyrings like Arch Linux
pub const GPGKeyring = struct {
    allocator: Allocator,
    user_keyring_path: []const u8,
    system_keyrings: std.ArrayList([]const u8),
    trusted_fingerprints: std.StringHashMap(bool),

    pub fn init(allocator: Allocator) GPGKeyring {
        return GPGKeyring{
            .allocator = allocator,
            .user_keyring_path = "",
            .system_keyrings = .empty,
            .trusted_fingerprints = std.StringHashMap(bool).init(allocator),
        };
    }

    pub fn deinit(self: *GPGKeyring) void {
        for (self.system_keyrings.items) |keyring_path| {
            self.allocator.free(keyring_path);
        }
        self.system_keyrings.deinit(self.allocator);

        var fingerprint_iter = self.trusted_fingerprints.iterator();
        while (fingerprint_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.trusted_fingerprints.deinit();

        if (self.user_keyring_path.len > 0) {
            self.allocator.free(self.user_keyring_path);
        }
    }

    /// Load GPG keys from user keyring
    pub fn loadUserKeys(self: *GPGKeyring) !void {
        // Get user's GPG directory
        const home_dir = zion_root.getEnv("HOME") orelse return error.NoHomeDirectory;
        const gpg_dir = try std.fmt.allocPrint(self.allocator, "{s}/.gnupg", .{home_dir});
        defer self.allocator.free(gpg_dir);

        std.debug.print("🔑 Loading user GPG keys from {s}\n", .{gpg_dir});

        // Get I/O context
        const io = try zion_root.getIo();

        // Run gpg command to list keys
        const argv = [_][]const u8{ "gpg", "--list-keys", "--with-colons", "--fingerprint" };
        var child = std.process.spawn(io, .{
            .argv = &argv,
            .stdin = .ignore,
            .stdout = .pipe,
            .stderr = .pipe,
        }) catch |err| {
            std.debug.print("⚠️  Failed to run GPG command: {}\n", .{err});
            return;
        };

        // Read stdout
        var stdout_list: std.ArrayListUnmanaged(u8) = .empty;
        defer stdout_list.deinit(self.allocator);
        if (child.stdout) |stdout_file| {
            var buffer: [4096]u8 = undefined;
            while (true) {
                const n = stdout_file.readStreaming(io, &.{buffer[0..]}) catch break;
                if (n == 0) break;
                try stdout_list.appendSlice(self.allocator, buffer[0..n]);
            }
        }

        const term = try child.wait(io);
        switch (term) {
            .exited => |code| {
                if (code != 0) {
                    std.debug.print("⚠️  GPG command failed with exit code: {}\n", .{code});
                    return;
                }
            },
            else => return,
        }

        try self.parseGPGOutput(stdout_list.items);
    }

    /// Load system keyrings (like Arch Linux keyring)
    pub fn loadSystemKeyrings(self: *GPGKeyring) !void {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();

        const system_keyring_paths = [_][]const u8{
            "/usr/share/pacman/keyrings/archlinux.gpg",
            "/usr/share/pacman/keyrings/archlinux-trusted",
            "/etc/pacman.d/gnupg/pubring.gpg",
        };

        for (system_keyring_paths) |keyring_path| {
            // Check if keyring exists
            cwd.access(io, keyring_path, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    std.debug.print("🔍 Keyring not found: {s}\n", .{keyring_path});
                    continue;
                },
                else => return err,
            };

            std.debug.print("🔑 Loading system keyring: {s}\n", .{keyring_path});

            // Add to system keyrings list
            const owned_path = try self.allocator.dupe(u8, keyring_path);
            try self.system_keyrings.append(self.allocator, owned_path);

            // Load keys from this keyring
            try self.loadKeysFromKeyring(keyring_path);
        }
    }

    /// Load keys from a specific keyring file
    fn loadKeysFromKeyring(self: *GPGKeyring, keyring_path: []const u8) !void {
        const io = try zion_root.getIo();

        const argv = [_][]const u8{
            "gpg",
            "--list-keys",
            "--keyring",
            keyring_path,
            "--with-colons",
            "--fingerprint",
        };
        var child = std.process.spawn(io, .{
            .argv = &argv,
            .stdin = .ignore,
            .stdout = .pipe,
            .stderr = .pipe,
        }) catch |err| {
            std.debug.print("⚠️  Failed to load keyring {s}: {}\n", .{ keyring_path, err });
            return;
        };

        // Read stdout
        var stdout_list: std.ArrayListUnmanaged(u8) = .empty;
        defer stdout_list.deinit(self.allocator);
        if (child.stdout) |stdout_file| {
            var buffer: [4096]u8 = undefined;
            while (true) {
                const n = stdout_file.readStreaming(io, &.{buffer[0..]}) catch break;
                if (n == 0) break;
                try stdout_list.appendSlice(self.allocator, buffer[0..n]);
            }
        }

        const term = try child.wait(io);
        switch (term) {
            .exited => |code| {
                if (code != 0) {
                    std.debug.print("⚠️  GPG keyring command failed for {s}: exit code {}\n", .{ keyring_path, code });
                    return;
                }
            },
            else => return,
        }

        try self.parseGPGOutput(stdout_list.items);
    }

    /// Parse GPG --with-colons output format
    fn parseGPGOutput(self: *GPGKeyring, output: []const u8) !void {
        var lines = std.mem.splitSequence(u8, output, "\n");
        var current_fingerprint: ?[]const u8 = null;

        while (lines.next()) |line| {
            if (line.len == 0) continue;

            var fields = std.mem.splitSequence(u8, line, ":");
            const record_type = fields.next() orelse continue;

            if (std.mem.eql(u8, record_type, "pub")) {
                // Public key record: pub:validity:length:algorithm:keyid:creation:expiration:::::::::
                _ = fields.next(); // validity
                _ = fields.next(); // length
                _ = fields.next(); // algorithm
                const keyid = fields.next() orelse continue;

                std.debug.print("📋 Found public key: {s}\n", .{keyid});
            } else if (std.mem.eql(u8, record_type, "fpr")) {
                // Fingerprint record: fpr:::::::::fingerprint:
                for (0..9) |_| _ = fields.next(); // Skip to fingerprint field
                const fingerprint = fields.next() orelse continue;

                std.debug.print("🔑 Fingerprint: {s}\n", .{fingerprint});

                // Store fingerprint as trusted
                const owned_fingerprint = try self.allocator.dupe(u8, fingerprint);
                try self.trusted_fingerprints.put(owned_fingerprint, true);
                current_fingerprint = owned_fingerprint;
            } else if (std.mem.eql(u8, record_type, "uid")) {
                // User ID record: uid:validity:::::::::userid:
                for (0..9) |_| _ = fields.next(); // Skip to userid field
                const userid = fields.next() orelse continue;

                if (current_fingerprint) |fp| {
                    const short_fp = if (fp.len > 8) fp[fp.len - 8 ..] else fp;
                    std.debug.print("👤 User ID for {s}: {s}\n", .{ short_fp, userid });
                }
            }
        }
    }

    /// Verify a signature using GPG
    pub fn verifySignature(self: *GPGKeyring, signed_data: []const u8, signature_data: []const u8) !bool {
        const io = try zion_root.getIo();
        const cwd = Dir.cwd();

        // Write signed data to temporary file
        const temp_data_path = "/tmp/zion_verify_data";
        const temp_sig_path = "/tmp/zion_verify_signature";

        // Write data file
        const data_file = try cwd.createFile(io, temp_data_path, .{});
        defer data_file.close(io);
        try data_file.writeStreamingAll(io, signed_data);

        // Write signature file
        const sig_file = try cwd.createFile(io, temp_sig_path, .{});
        defer sig_file.close(io);
        try sig_file.writeStreamingAll(io, signature_data);

        // Run GPG verification
        const argv = [_][]const u8{
            "gpg",
            "--verify",
            temp_sig_path,
            temp_data_path,
        };
        var child = std.process.spawn(io, .{
            .argv = &argv,
            .stdin = .ignore,
            .stdout = .pipe,
            .stderr = .pipe,
        }) catch |err| {
            std.debug.print("⚠️  GPG verify command failed: {}\n", .{err});
            // Cleanup temp files
            cwd.deleteFile(io, temp_data_path) catch {};
            cwd.deleteFile(io, temp_sig_path) catch {};
            return false;
        };

        // Read stderr for error messages
        var stderr_list: std.ArrayListUnmanaged(u8) = .empty;
        defer stderr_list.deinit(self.allocator);
        if (child.stderr) |stderr_file| {
            var buffer: [4096]u8 = undefined;
            while (true) {
                const n = stderr_file.readStreaming(io, &.{buffer[0..]}) catch break;
                if (n == 0) break;
                try stderr_list.appendSlice(self.allocator, buffer[0..n]);
            }
        }

        const term = try child.wait(io);

        // Cleanup temp files
        cwd.deleteFile(io, temp_data_path) catch {};
        cwd.deleteFile(io, temp_sig_path) catch {};

        switch (term) {
            .exited => |code| {
                if (code == 0) {
                    std.debug.print("✅ GPG signature verification successful\n", .{});
                    return true;
                } else {
                    std.debug.print("❌ GPG signature verification failed\n", .{});
                    if (stderr_list.items.len > 0) {
                        std.debug.print("GPG Error: {s}\n", .{stderr_list.items});
                    }
                    return false;
                }
            },
            else => {
                std.debug.print("❌ GPG signature verification failed (abnormal termination)\n", .{});
                return false;
            },
        }
    }

    /// Check if a fingerprint is trusted
    pub fn isFingerprintTrusted(self: *const GPGKeyring, fingerprint: []const u8) bool {
        return self.trusted_fingerprints.contains(fingerprint);
    }

    /// Get list of trusted fingerprints
    pub fn getTrustedFingerprints(self: *const GPGKeyring) []const []const u8 {
        var fingerprints: std.ArrayListUnmanaged([]const u8) = .empty;
        defer fingerprints.deinit(self.allocator);

        var iter = self.trusted_fingerprints.iterator();
        while (iter.next()) |entry| {
            fingerprints.append(self.allocator, entry.key_ptr.*) catch continue;
        }

        return fingerprints.toOwnedSlice(self.allocator) catch &[_][]const u8{};
    }

    /// Initialize GPG keyring with both user and system keys
    pub fn initializeComplete(allocator: Allocator) !GPGKeyring {
        var keyring = GPGKeyring.init(allocator);

        std.debug.print("🚀 Initializing GPG keyring integration...\n", .{});

        // Load user keys
        keyring.loadUserKeys() catch |err| {
            std.debug.print("⚠️  Failed to load user GPG keys: {}\n", .{err});
        };

        // Load system keyrings
        keyring.loadSystemKeyrings() catch |err| {
            std.debug.print("⚠️  Failed to load system keyrings: {}\n", .{err});
        };

        const fingerprint_count = keyring.trusted_fingerprints.count();
        const keyring_count = keyring.system_keyrings.items.len;

        std.debug.print("✅ GPG integration complete: {} trusted fingerprints, {} system keyrings\n", .{ fingerprint_count, keyring_count });

        return keyring;
    }
};

/// Enhanced signature verification with GPG integration
pub fn verifyPackageWithGPG(allocator: Allocator, package_data: []const u8, signature_data: []const u8) !bool {
    // First try built-in signature verification
    var key_store = signature_verification.TrustedKeyStore.init(allocator);
    defer key_store.deinit();

    const builtin_result = signature_verification.verifyPackage(allocator, package_data, signature_data, &key_store) catch false;

    if (builtin_result) {
        std.debug.print("✅ Package verified using built-in signature verification\n", .{});
        return true;
    }

    // Fall back to GPG verification
    std.debug.print("🔄 Falling back to GPG verification...\n", .{});

    var gpg_keyring = GPGKeyring.initializeComplete(allocator) catch |err| {
        std.debug.print("❌ Failed to initialize GPG keyring: {}\n", .{err});
        return false;
    };
    defer gpg_keyring.deinit();

    return gpg_keyring.verifySignature(package_data, signature_data);
}
