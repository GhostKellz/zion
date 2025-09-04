const std = @import("std");
const gpg_keyring = @import("../gpg_keyring.zig");
const Allocator = std.mem.Allocator;

pub fn keyring(allocator: Allocator, args: [][:0]u8) !void {
    if (args.len < 3) {
        printUsage();
        return;
    }
    
    const subcommand = args[2];
    
    if (std.mem.eql(u8, subcommand, "list")) {
        try listKeys(allocator);
    } else if (std.mem.eql(u8, subcommand, "trust")) {
        if (args.len < 4) {
            std.debug.print("Usage: zion keyring trust <fingerprint>\n", .{});
            return;
        }
        try trustFingerprint(allocator, args[3]);
    } else if (std.mem.eql(u8, subcommand, "verify-arch")) {
        try verifyArchKeyrings(allocator);
    } else if (std.mem.eql(u8, subcommand, "status")) {
        try showKeyringsStatus(allocator);
    } else if (std.mem.eql(u8, subcommand, "refresh")) {
        try refreshKeyrings(allocator);
    } else {
        std.debug.print("❌ Unknown keyring subcommand: {s}\n", .{subcommand});
        printUsage();
    }
}

fn printUsage() void {
    std.debug.print("🔑 Zion Keyring Management\n\n", .{});
    std.debug.print("Usage: zion keyring <command>\n\n", .{});
    std.debug.print("Commands:\n", .{});
    std.debug.print("  list          - List all available GPG keys\n", .{});
    std.debug.print("  trust <fp>    - Mark a fingerprint as trusted\n", .{});
    std.debug.print("  verify-arch   - Verify Arch Linux keyrings\n", .{});
    std.debug.print("  status        - Show keyring status\n", .{});
    std.debug.print("  refresh       - Refresh keyrings from system\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Examples:\n", .{});
    std.debug.print("  zion keyring list\n", .{});
    std.debug.print("  zion keyring trust 478D3EFD1D9694F6BAD0AC1F777538754BA2B57D\n", .{});
    std.debug.print("  zion keyring verify-arch\n", .{});
}

fn listKeys(allocator: Allocator) !void {
    std.debug.print("🔍 Loading GPG keyrings...\n", .{});
    
    var gpg_ring = gpg_keyring.GPGKeyring.initializeComplete(allocator) catch |err| {
        std.debug.print("❌ Failed to initialize keyring: {}\n", .{err});
        return;
    };
    defer gpg_ring.deinit();
    
    std.debug.print("\n📋 Available Keys:\n", .{});
    std.debug.print("==================\n", .{});
    
    const fingerprints = gpg_ring.getTrustedFingerprints();
    defer allocator.free(fingerprints);
    
    if (fingerprints.len == 0) {
        std.debug.print("🔍 No trusted fingerprints found.\n", .{});
        std.debug.print("💡 Try running 'gpg --list-keys' to see your available keys.\n", .{});
        return;
    }
    
    for (fingerprints, 0..) |fp, i| {
        std.debug.print("{d:2}. {s}\n", .{ i + 1, fp });
    }
    
    std.debug.print("\n✅ Total: {} trusted fingerprints\n", .{fingerprints.len});
    std.debug.print("🏠 System keyrings: {}\n", .{gpg_ring.system_keyrings.items.len});
}

fn trustFingerprint(allocator: Allocator, fingerprint: []const u8) !void {
    std.debug.print("🔐 Adding fingerprint to trusted list: {s}\n", .{fingerprint});
    
    // Validate fingerprint format (should be 40 hex chars for SHA-1 or 64 for SHA-256)
    if (fingerprint.len != 40 and fingerprint.len != 64) {
        std.debug.print("❌ Invalid fingerprint length. Expected 40 or 64 hex characters.\n", .{});
        return;
    }
    
    for (fingerprint) |char| {
        if (!std.ascii.isHex(char)) {
            std.debug.print("❌ Invalid fingerprint format. Must contain only hex characters.\n", .{});
            return;
        }
    }
    
    // Load the trusted keys file and add this fingerprint
    const home_dir = std.posix.getenv("HOME") orelse {
        std.debug.print("❌ HOME environment variable not set\n", .{});
        return;
    };
    
    const zion_dir = try std.fmt.allocPrint(allocator, "{s}/.zion", .{home_dir});
    defer allocator.free(zion_dir);
    
    const trusted_keys_file = try std.fmt.allocPrint(allocator, "{s}/trusted_keys.json", .{zion_dir});
    defer allocator.free(trusted_keys_file);
    
    // Create .zion directory if it doesn't exist
    std.fs.cwd().makeDir(zion_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    
    // Simple JSON format for trusted keys
    const trusted_entry = try std.fmt.allocPrint(allocator, 
        "{{\"fingerprint\": \"{s}\", \"trusted\": true, \"added\": \"{d}\"}}\n", 
        .{ fingerprint, std.time.timestamp() });
    defer allocator.free(trusted_entry);
    
    // Append to file
    const file = std.fs.cwd().openFile(trusted_keys_file, .{ .mode = .write_only }) catch |err| switch (err) {
        error.FileNotFound => try std.fs.cwd().createFile(trusted_keys_file, .{}),
        else => return err,
    };
    defer file.close();
    
    try file.seekFromEnd(0);
    try file.writeAll(trusted_entry);
    
    std.debug.print("✅ Fingerprint added to trusted list\n", .{});
    std.debug.print("📁 Saved to: {s}\n", .{trusted_keys_file});
}

fn verifyArchKeyrings(allocator: Allocator) !void {
    std.debug.print("🐧 Verifying Arch Linux keyrings...\n", .{});
    
    const arch_keyrings = [_][]const u8{
        "/usr/share/pacman/keyrings/archlinux.gpg",
        "/usr/share/pacman/keyrings/archlinux-trusted",
        "/usr/share/pacman/keyrings/archlinux-revoked",
        "/etc/pacman.d/gnupg/pubring.gpg",
    };
    
    var found_keyrings: u32 = 0;
    var verified_keys: u32 = 0;
    
    for (arch_keyrings) |keyring_path| {
        std.fs.cwd().access(keyring_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("❌ Not found: {s}\n", .{keyring_path});
                continue;
            },
            else => return err,
        };
        
        found_keyrings += 1;
        std.debug.print("✅ Found: {s}\n", .{keyring_path});
        
        // Try to load keys from this keyring
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ 
                "gpg", 
                "--list-keys", 
                "--keyring", keyring_path,
                "--with-colons" 
            },
            .max_output_bytes = 1024 * 1024,
        }) catch |err| {
            std.debug.print("⚠️  Failed to read keyring {s}: {}\n", .{ keyring_path, err });
            continue;
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);
        
        if (result.term.Exited == 0) {
            // Count keys in output
            var key_count: u32 = 0;
            var lines = std.mem.splitSequence(u8, result.stdout, "\n");
            while (lines.next()) |line| {
                if (std.mem.startsWith(u8, line, "pub:")) {
                    key_count += 1;
                }
            }
            verified_keys += key_count;
            std.debug.print("   📊 Contains {} public keys\n", .{key_count});
        } else {
            std.debug.print("⚠️  Failed to verify keyring: {s}\n", .{keyring_path});
        }
    }
    
    std.debug.print("\n📈 Arch Linux Keyring Summary:\n", .{});
    std.debug.print("   Found keyrings: {}\n", .{found_keyrings});
    std.debug.print("   Verified keys: {}\n", .{verified_keys});
    
    if (found_keyrings == 0) {
        std.debug.print("\n💡 No Arch Linux keyrings found. Install 'archlinux-keyring' package if on Arch Linux.\n", .{});
    } else if (verified_keys == 0) {
        std.debug.print("\n⚠️  Found keyrings but no keys could be verified. Check GPG installation.\n", .{});
    } else {
        std.debug.print("\n✅ Arch Linux keyrings verified successfully!\n", .{});
    }
}

fn showKeyringsStatus(allocator: Allocator) !void {
    std.debug.print("📊 Zion Keyring Status\n", .{});
    std.debug.print("=====================\n\n", .{});
    
    // Check GPG installation
    const gpg_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "gpg", "--version" },
        .max_output_bytes = 4096,
    }) catch |err| {
        std.debug.print("❌ GPG not installed or not accessible: {}\n", .{err});
        return;
    };
    defer allocator.free(gpg_result.stdout);
    defer allocator.free(gpg_result.stderr);
    
    if (gpg_result.term.Exited == 0) {
        var lines = std.mem.splitSequence(u8, gpg_result.stdout, "\n");
        if (lines.next()) |first_line| {
            std.debug.print("✅ GPG: {s}\n", .{first_line});
        }
    } else {
        std.debug.print("❌ GPG installation issues detected\n", .{});
    }
    
    // Check user keyring
    const home_dir = std.posix.getenv("HOME") orelse "unknown";
    const gpg_dir = try std.fmt.allocPrint(allocator, "{s}/.gnupg", .{home_dir});
    defer allocator.free(gpg_dir);
    
    std.fs.cwd().access(gpg_dir, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("❌ User GPG directory not found: {s}\n", .{gpg_dir});
        },
        else => {
            std.debug.print("⚠️  Cannot access user GPG directory: {s}\n", .{gpg_dir});
        },
    };
    
    // If no error, it exists
    if (std.fs.cwd().access(gpg_dir, .{})) |_| {
        std.debug.print("✅ User GPG directory: {s}\n", .{gpg_dir});
    } else |_| {
        // Error already handled above
    }
    
    // Check system keyrings
    try verifyArchKeyrings(allocator);
    
    // Initialize full keyring and show summary
    std.debug.print("\n🔄 Loading complete keyring...\n", .{});
    var gpg_ring = gpg_keyring.GPGKeyring.initializeComplete(allocator) catch |err| {
        std.debug.print("❌ Failed to load complete keyring: {}\n", .{err});
        return;
    };
    defer gpg_ring.deinit();
    
    std.debug.print("\n✅ Keyring Status Summary:\n", .{});
    std.debug.print("   Trusted fingerprints: {}\n", .{gpg_ring.trusted_fingerprints.count()});
    std.debug.print("   System keyrings: {}\n", .{gpg_ring.system_keyrings.items.len});
    std.debug.print("   GPG integration: Ready\n", .{});
}

fn refreshKeyrings(allocator: Allocator) !void {
    std.debug.print("🔄 Refreshing keyrings from system...\n", .{});
    
    // Refresh GPG keys
    const refresh_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "gpg", "--refresh-keys" },
        .max_output_bytes = 1024 * 1024,
    }) catch |err| {
        std.debug.print("⚠️  GPG refresh failed: {}\n", .{err});
        return;
    };
    
    defer allocator.free(refresh_result.stdout);
    defer allocator.free(refresh_result.stderr);
    
    if (refresh_result.term.Exited == 0) {
        std.debug.print("✅ GPG keys refreshed successfully\n", .{});
    } else {
        std.debug.print("⚠️  GPG refresh completed with warnings\n", .{});
    }
    
    // Re-initialize keyrings
    std.debug.print("🔄 Reloading keyring configuration...\n", .{});
    
    var gpg_ring = gpg_keyring.GPGKeyring.initializeComplete(allocator) catch |err| {
        std.debug.print("❌ Failed to reload keyrings: {}\n", .{err});
        return;
    };
    defer gpg_ring.deinit();
    
    std.debug.print("✅ Keyrings refreshed successfully!\n", .{});
    std.debug.print("📊 Status: {} trusted fingerprints, {} system keyrings\n", .{ 
        gpg_ring.trusted_fingerprints.count(), 
        gpg_ring.system_keyrings.items.len 
    });
}