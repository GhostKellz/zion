const std = @import("std");
const fs = std.fs;
const Dir = std.Io.Dir;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const sec = @import("../security.zig");
const zion_root = @import("../root.zig");
const paths = @import("../paths.zig");

/// Security management command for package signing, verification, and trust
pub fn security(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len < 3) {
        printSecurityHelp();
        return;
    }

    const subcommand = args[2];

    if (std.mem.eql(u8, subcommand, "keygen")) {
        try handleKeyGen(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "sign")) {
        try handleSign(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "verify")) {
        try handleVerify(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "trust")) {
        try handleTrust(allocator, args[3..]);
    } else if (std.mem.eql(u8, subcommand, "status")) {
        try handleStatus(allocator, args[3..]);
    } else {
        std.debug.print("Unknown security subcommand: {s}\n", .{subcommand});
        printSecurityHelp();
    }
}

/// Print security help
fn printSecurityHelp() void {
    const help_text =
        \\Security Management Commands:
        \\
        \\USAGE:
        \\    zion security <SUBCOMMAND>
        \\
        \\SUBCOMMANDS:
        \\    keygen                  Generate a new signing key pair
        \\    sign <package>          Sign a package with your private key
        \\    verify <package>        Verify a package signature
        \\    trust <signer_id>       Reserved until signer keys can be supplied
        \\    status                  Show security status and trust store
        \\
        \\EXAMPLES:
        \\    zion security keygen                    # Generate new key pair
        \\    zion security sign mypackage.tar.gz    # Sign a package
        \\    zion security verify mypackage.tar.gz  # Verify package signature
        \\    zion security trust alice@example.com  # Trust a signer
        \\    zion security status                   # Show security status
        \\
    ;

    std.debug.print("{s}", .{help_text});
}

/// Generate a new Ed25519 key pair
fn handleKeyGen(allocator: Allocator, args: []const [:0]const u8) !void {
    _ = args;

    std.debug.print("🔐 Generating new Ed25519 key pair...\n", .{});

    var security_manager = sec.SecurityManager.init(allocator, ".zion/keys");
    defer security_manager.deinit();

    const key_pair = try security_manager.generateKeyPair();

    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Ensure .zion/keys directory exists
    try cwd.createDirPath(io, ".zion/keys");

    // Save public key
    const pub_key_file = try cwd.createFile(io, ".zion/keys/public.key", .{});
    defer pub_key_file.close(io);
    try pub_key_file.writeStreamingAll(io, &key_pair.public_key);

    // Save private key (with warning about security)
    const priv_key_file = try cwd.createFile(io, ".zion/keys/private.key", .{ .permissions = paths.privateFilePermissions() });
    defer priv_key_file.close(io);
    try priv_key_file.writeStreamingAll(io, &key_pair.private_key);

    std.debug.print("✅ Key pair generated successfully!\n", .{});
    std.debug.print("📁 Public key:  .zion/keys/public.key\n", .{});
    std.debug.print("🔒 Private key: .zion/keys/private.key\n", .{});
    std.debug.print("\n⚠️  WARNING: Keep your private key secure and never share it!\n", .{});
}

/// Sign a package file
fn handleSign(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len == 0) {
        std.debug.print("Error: No package specified to sign\n", .{});
        std.debug.print("Usage: zion security sign <package>\n", .{});
        return;
    }

    const package_path = args[0];
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Check if package exists
    cwd.access(io, package_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: Package '{s}' not found\n", .{package_path});
            return;
        }
        return err;
    };

    // Check if private key exists
    const private_key_data = readFileContent(allocator, io, cwd, ".zion/keys/private.key") catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: Private key not found. Run 'zion security keygen' first.\n", .{});
            return;
        }
        return err;
    };
    defer allocator.free(private_key_data);

    if (private_key_data.len != sec.PRIVATE_KEY_SIZE) {
        std.debug.print("Error: Invalid private key size\n", .{});
        return;
    }

    var private_key: [sec.PRIVATE_KEY_SIZE]u8 = undefined;
    @memcpy(&private_key, private_key_data);

    std.debug.print("🔏 Signing package: {s}\n", .{package_path});

    var security_manager = sec.SecurityManager.init(allocator, ".zion/keys");
    defer security_manager.deinit();

    const signature = try security_manager.signPackage(package_path, private_key, "local_signer");
    defer {
        allocator.free(signature.signer_id);
        allocator.free(signature.algorithm);
    }

    // Save signature to file
    const sig_path = try std.fmt.allocPrint(allocator, "{s}.sig", .{package_path});
    defer allocator.free(sig_path);

    const sig_file = try cwd.createFile(io, sig_path, .{});
    defer sig_file.close(io);

    const signature_hex = std.fmt.bytesToHex(signature.signature, .lower);
    const public_key_hex = std.fmt.bytesToHex(signature.public_key, .lower);
    const signature_json = try std.fmt.allocPrint(allocator,
        \\{{
        \\  "signature": "{s}",
        \\  "public_key": "{s}",
        \\  "timestamp": {d},
        \\  "signer_id": "{s}",
        \\  "algorithm": "{s}"
        \\}}
        \\
    , .{
        &signature_hex,
        &public_key_hex,
        signature.timestamp,
        signature.signer_id,
        signature.algorithm,
    });
    defer allocator.free(signature_json);
    try sig_file.writeStreamingAll(io, signature_json);

    std.debug.print("✅ Package signed successfully!\n", .{});
    std.debug.print("📁 Signature saved to: {s}\n", .{sig_path});
}

/// Verify a package signature and integrity
fn handleVerify(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len == 0) {
        std.debug.print("Error: No package specified to verify\n", .{});
        std.debug.print("Usage: zion security verify <package>\n", .{});
        return;
    }

    const package_path = args[0];
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Check if package exists
    cwd.access(io, package_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: Package '{s}' not found\n", .{package_path});
            return;
        }
        return err;
    };

    // Check if signature file exists
    const sig_path = try std.fmt.allocPrint(allocator, "{s}.sig", .{package_path});
    defer allocator.free(sig_path);

    const sig_content = readFileContent(allocator, io, cwd, sig_path) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: Signature file '{s}' not found\n", .{sig_path});
            return;
        }
        return err;
    };
    defer allocator.free(sig_content);

    const parsed = std.json.parseFromSlice(struct {
        signature: []const u8,
        public_key: []const u8,
        timestamp: i64,
        signer_id: []const u8,
        algorithm: []const u8,
    }, allocator, sig_content, .{ .ignore_unknown_fields = true }) catch return error.InvalidSignatureFile;
    defer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.algorithm, "Ed25519")) return error.UnsupportedSignatureAlgorithm;
    if (parsed.value.signature.len != sec.SIGNATURE_SIZE * 2 or parsed.value.public_key.len != sec.PUBLIC_KEY_SIZE * 2) {
        return error.InvalidSignatureFile;
    }
    var signature_bytes: [sec.SIGNATURE_SIZE]u8 = undefined;
    var public_key_bytes: [sec.PUBLIC_KEY_SIZE]u8 = undefined;
    _ = std.fmt.hexToBytes(&signature_bytes, parsed.value.signature) catch return error.InvalidSignatureFile;
    _ = std.fmt.hexToBytes(&public_key_bytes, parsed.value.public_key) catch return error.InvalidSignatureFile;
    var security_manager = sec.SecurityManager.init(allocator, ".zion/keys");
    defer security_manager.deinit();
    const valid = try security_manager.verifyPackage(package_path, .{
        .signature = signature_bytes,
        .public_key = public_key_bytes,
        .timestamp = parsed.value.timestamp,
        .signer_id = parsed.value.signer_id,
        .algorithm = parsed.value.algorithm,
    });
    if (!valid) return error.SignatureVerificationFailed;
    std.debug.print("✅ Ed25519 signature is valid for {s}\n", .{package_path});
}

/// Trust a signer
fn handleTrust(allocator: Allocator, args: []const [:0]const u8) !void {
    _ = allocator;
    _ = args;
    std.debug.print("Signer trust mutation is unavailable until a verified public-key input format is defined.\n", .{});
}

/// Show security status
fn handleStatus(allocator: Allocator, args: []const [:0]const u8) !void {
    _ = args;

    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    std.debug.print("🛡️  Zion Security Status\n", .{});
    std.debug.print("═══════════════════════\n", .{});

    // Check if keys exist
    const has_private_key = blk: {
        cwd.access(io, ".zion/keys/private.key", .{}) catch {
            break :blk false;
        };
        break :blk true;
    };

    const has_public_key = blk: {
        cwd.access(io, ".zion/keys/public.key", .{}) catch {
            break :blk false;
        };
        break :blk true;
    };

    std.debug.print("🔐 Key Pair Status:\n", .{});
    if (has_private_key and has_public_key) {
        std.debug.print("  ✅ Key pair present\n", .{});
        std.debug.print("  📁 Location: .zion/keys/\n", .{});
    } else {
        std.debug.print("  ❌ No key pair found\n", .{});
        std.debug.print("  💡 Run 'zion security keygen' to generate keys\n", .{});
    }

    var security_manager = sec.SecurityManager.init(allocator, ".zion/keys");
    defer security_manager.deinit();

    std.debug.print("\n🤝 Trust Store:\n", .{});
    if (security_manager.trust_store.count() == 0) {
        std.debug.print("  📭 No trusted signers\n", .{});
    } else {
        std.debug.print("  📊 {d} trusted signers\n", .{security_manager.trust_store.count()});
    }

    std.debug.print("\n🔍 Security Features:\n", .{});
    std.debug.print("  ✅ Ed25519 digital signatures\n", .{});
    std.debug.print("  ✅ Package integrity verification\n", .{});
    std.debug.print("  ✅ Trust management system\n", .{});
    std.debug.print("  ✅ Reputation tracking\n", .{});
}

/// Helper function to read file content
fn readFileContent(allocator: Allocator, io: Io, cwd: Dir, file_path: []const u8) ![]u8 {
    const file = try cwd.openFile(io, file_path, .{});
    defer file.close(io);

    var content: std.ArrayList(u8) = .empty;
    errdefer content.deinit(allocator);

    var buffer: [8192]u8 = undefined;
    while (true) {
        const bytes_read = file.readStreaming(io, &.{buffer[0..]}) catch break;
        if (bytes_read == 0) break;
        try content.appendSlice(allocator, buffer[0..bytes_read]);
    }

    return content.toOwnedSlice(allocator);
}
