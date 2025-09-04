const std = @import("std");
const signature_verification = @import("signature_verification.zig");
const Allocator = std.mem.Allocator;

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
            .system_keyrings = .{},
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
        const home_dir = std.posix.getenv("HOME") orelse return error.NoHomeDirectory;
        const gpg_dir = try std.fmt.allocPrint(self.allocator, "{s}/.gnupg", .{home_dir});
        defer self.allocator.free(gpg_dir);
        
        std.debug.print("🔑 Loading user GPG keys from {s}\n", .{gpg_dir});
        
        // Run gpg command to list keys
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "gpg", "--list-keys", "--with-colons", "--fingerprint" },
            .max_output_bytes = 1024 * 1024, // 1MB max output
        }) catch |err| {
            std.debug.print("⚠️  Failed to run GPG command: {}\n", .{err});
            return;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            std.debug.print("⚠️  GPG command failed with exit code: {}\n", .{result.term.Exited});
            return;
        }
        
        try self.parseGPGOutput(result.stdout);
    }
    
    /// Load system keyrings (like Arch Linux keyring)
    pub fn loadSystemKeyrings(self: *GPGKeyring) !void {
        const system_keyring_paths = [_][]const u8{
            "/usr/share/pacman/keyrings/archlinux.gpg",
            "/usr/share/pacman/keyrings/archlinux-trusted",
            "/etc/pacman.d/gnupg/pubring.gpg",
        };
        
        for (system_keyring_paths) |keyring_path| {
            // Check if keyring exists
            std.fs.cwd().access(keyring_path, .{}) catch |err| switch (err) {
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
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ 
                "gpg", 
                "--list-keys", 
                "--keyring", keyring_path,
                "--with-colons", 
                "--fingerprint" 
            },
            .max_output_bytes = 1024 * 1024,
        }) catch |err| {
            std.debug.print("⚠️  Failed to load keyring {s}: {}\n", .{ keyring_path, err });
            return;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            std.debug.print("⚠️  GPG keyring command failed for {s}: exit code {}\n", .{ keyring_path, result.term.Exited });
            return;
        }
        
        try self.parseGPGOutput(result.stdout);
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
                    const short_fp = if (fp.len > 8) fp[fp.len - 8..] else fp;
                    std.debug.print("👤 User ID for {s}: {s}\n", .{ short_fp, userid });
                }
            }
        }
    }
    
    /// Verify a signature using GPG
    pub fn verifySignature(self: *GPGKeyring, signed_data: []const u8, signature_data: []const u8) !bool {
        // Write signed data to temporary file
        const temp_data_path = "/tmp/zion_verify_data";
        const temp_sig_path = "/tmp/zion_verify_signature";
        
        // Write data file
        const data_file = try std.fs.cwd().createFile(temp_data_path, .{});
        defer data_file.close();
        try data_file.writeAll(signed_data);
        
        // Write signature file
        const sig_file = try std.fs.cwd().createFile(temp_sig_path, .{});
        defer sig_file.close();
        try sig_file.writeAll(signature_data);
        
        // Run GPG verification
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ 
                "gpg", 
                "--verify", 
                temp_sig_path,
                temp_data_path
            },
            .max_output_bytes = 1024 * 1024,
        }) catch |err| {
            std.debug.print("⚠️  GPG verify command failed: {}\n", .{err});
            return false;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        // Cleanup temp files
        std.fs.cwd().deleteFile(temp_data_path) catch {};
        std.fs.cwd().deleteFile(temp_sig_path) catch {};
        
        if (result.term.Exited == 0) {
            std.debug.print("✅ GPG signature verification successful\n", .{});
            return true;
        } else {
            std.debug.print("❌ GPG signature verification failed\n", .{});
            if (result.stderr.len > 0) {
                std.debug.print("GPG Error: {s}\n", .{result.stderr});
            }
            return false;
        }
    }
    
    /// Check if a fingerprint is trusted
    pub fn isFingerprintTrusted(self: *const GPGKeyring, fingerprint: []const u8) bool {
        return self.trusted_fingerprints.contains(fingerprint);
    }
    
    /// Get list of trusted fingerprints
    pub fn getTrustedFingerprints(self: *const GPGKeyring) []const []const u8 {
        var fingerprints: std.ArrayList([]const u8) = .{};
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