const std = @import("std");
const signature_verification = @import("../signature_verification.zig");
const gpg_keyring = @import("../gpg_keyring.zig");
const zion_root = @import("../root.zig");
const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;
const Io = std.Io;

pub fn verify(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len < 4) {
        std.debug.print("Usage: zion verify <package_file> <signature_file> [keystore_file]\n", .{});
        std.debug.print("\nVerifies the authenticity and integrity of a package using digital signatures.\n", .{});
        return;
    }
    
    const package_file = args[2];
    const signature_file = args[3]; 
    const keystore_file = if (args.len > 4) args[4] else "~/.zion/trusted_keys.json";
    
    std.debug.print("🔐 Verifying package signature...\n", .{});
    std.debug.print("  Package: {s}\n", .{package_file});
    std.debug.print("  Signature: {s}\n", .{signature_file});
    std.debug.print("  Keystore: {s}\n", .{keystore_file});

    // Get I/O context
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Load package data
    const package_data = cwd.readFileAlloc(io, package_file, allocator, Io.Limit.limited(100 * 1024 * 1024)) catch |err| {
        std.debug.print("❌ Failed to read package file: {}\n", .{err});
        return;
    };
    defer allocator.free(package_data);

    // Load signature data
    const signature_data = cwd.readFileAlloc(io, signature_file, allocator, Io.Limit.limited(1024 * 1024)) catch |err| {
        std.debug.print("❌ Failed to read signature file: {}\n", .{err});
        return;
    };
    defer allocator.free(signature_data);
    
    // Load trusted keys  
    var key_store = signature_verification.TrustedKeyStore.init(allocator);
    defer key_store.deinit();
    std.debug.print("🔑 Using empty keystore for demo\n", .{});
    
    // Enhanced verification with GPG integration
    const is_valid = gpg_keyring.verifyPackageWithGPG(allocator, package_data, signature_data) catch |err| {
        std.debug.print("❌ Enhanced signature verification failed: {}\n", .{err});
        
        // Try basic verification as fallback
        std.debug.print("🔄 Trying basic signature verification...\n", .{});
        const basic_valid = signature_verification.verifyPackage(allocator, package_data, signature_data, &key_store) catch false;
        if (basic_valid) {
            std.debug.print("✅ Package verified using basic signature verification\n", .{});
            return;
        } else {
            std.debug.print("❌ All signature verification methods failed\n", .{});
            std.process.exit(1);
        }
    };
    
    if (is_valid) {
        std.debug.print("✅ Package signature is valid and trusted\n", .{});
        std.debug.print("🔒 Package integrity verified with enhanced GPG support\n", .{});
    } else {
        std.debug.print("❌ Package signature verification failed\n", .{});
        std.debug.print("⚠️  Package may be tampered with or untrusted\n", .{});
        std.process.exit(1);
    }
}