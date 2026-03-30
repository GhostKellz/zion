const std = @import("std");
const crypto = std.crypto;
const fs = std.fs;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const zion_root = @import("root.zig");

/// Cryptographic security system for Zion packages
/// Implements signing, verification, and trust management using std.crypto
/// Ed25519 signature size
pub const SIGNATURE_SIZE = 64; // crypto.sign.Ed25519.signature_length;
/// Ed25519 public key size
pub const PUBLIC_KEY_SIZE = 32; // crypto.sign.Ed25519.public_length;
/// Ed25519 private key size
pub const PRIVATE_KEY_SIZE = 64; // crypto.sign.Ed25519.secret_length;

/// Package signature metadata
pub const PackageSignature = struct {
    signature: [SIGNATURE_SIZE]u8,
    public_key: [PUBLIC_KEY_SIZE]u8,
    timestamp: i64,
    signer_id: []const u8,
    algorithm: []const u8,

    pub fn deinit(self: *PackageSignature, allocator: Allocator) void {
        allocator.free(self.signer_id);
        allocator.free(self.algorithm);
    }
};

/// Trust level for packages and signers
pub const TrustLevel = enum {
    untrusted,
    low,
    medium,
    high,
    verified,
};

/// Signer information and trust metadata
pub const SignerInfo = struct {
    public_key: [PUBLIC_KEY_SIZE]u8,
    signer_id: []const u8,
    trust_level: TrustLevel,
    verified_packages: u32,
    reputation_score: f32,
    first_seen: i64,
    last_seen: i64,

    pub fn deinit(self: *SignerInfo, allocator: Allocator) void {
        allocator.free(self.signer_id);
    }
};

/// Security manager for the package system
pub const SecurityManager = struct {
    allocator: Allocator,
    trust_store: std.HashMap([]const u8, SignerInfo, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    key_store_path: []const u8,

    pub fn init(allocator: Allocator, key_store_path: []const u8) SecurityManager {
        return SecurityManager{
            .allocator = allocator,
            .trust_store = std.HashMap([]const u8, SignerInfo, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .key_store_path = key_store_path,
        };
    }

    pub fn deinit(self: *SecurityManager) void {
        var it = self.trust_store.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.trust_store.deinit();
    }

    /// Generate a new Ed25519 key pair for signing
    /// Uses Zig's standard library Ed25519 implementation
    pub fn generateKeyPair(_: *SecurityManager) !struct { public_key: [PUBLIC_KEY_SIZE]u8, private_key: [PRIVATE_KEY_SIZE]u8 } {
        const io = try zion_root.getIo();

        // Generate a proper Ed25519 key pair using Zig's crypto library
        const keypair = crypto.sign.Ed25519.KeyPair.generate(io);

        return .{
            .public_key = keypair.public_key.toBytes(),
            .private_key = keypair.secret_key.toBytes(),
        };
    }

    /// Sign a package file with Ed25519
    /// Uses real Ed25519 cryptographic signatures
    pub fn signPackage(self: *SecurityManager, package_path: []const u8, private_key: [PRIVATE_KEY_SIZE]u8, signer_id: []const u8) !PackageSignature {
        const io = try zion_root.getIo();
        const cwd = std.Io.Dir.cwd();

        const file = try cwd.openFile(io, package_path, .{});
        defer file.close(io);

        // Read file content
        var content_list: std.ArrayList(u8) = .empty;
        defer content_list.deinit(self.allocator);

        var buffer: [8192]u8 = undefined;
        while (true) {
            const bytes_read = file.readStreaming(io, &.{buffer[0..]}) catch break;
            if (bytes_read == 0) break;
            try content_list.appendSlice(self.allocator, buffer[0..bytes_read]);
        }
        const content = content_list.items;

        // Reconstruct the key pair from the secret key bytes
        const secret_key = try crypto.sign.Ed25519.SecretKey.fromBytes(private_key);
        const keypair = try crypto.sign.Ed25519.KeyPair.fromSecretKey(secret_key);

        // Sign the content with real Ed25519 (deterministic signature, no noise)
        const sig = try keypair.sign(content, null);

        return PackageSignature{
            .signature = sig.toBytes(),
            .public_key = keypair.public_key.toBytes(),
            .timestamp = zion_root.timestamp(),
            .signer_id = try self.allocator.dupe(u8, signer_id),
            .algorithm = try self.allocator.dupe(u8, "Ed25519"),
        };
    }

    /// Verify a package signature using real Ed25519 verification
    pub fn verifyPackage(self: *SecurityManager, package_path: []const u8, signature: PackageSignature) !bool {
        const io = try zion_root.getIo();
        const cwd = std.Io.Dir.cwd();

        const file = try cwd.openFile(io, package_path, .{});
        defer file.close(io);

        // Read file content
        var content_list: std.ArrayList(u8) = .empty;
        defer content_list.deinit(self.allocator);

        var buffer: [8192]u8 = undefined;
        while (true) {
            const bytes_read = file.readStreaming(io, &.{buffer[0..]}) catch break;
            if (bytes_read == 0) break;
            try content_list.appendSlice(self.allocator, buffer[0..bytes_read]);
        }
        const content = content_list.items;

        // Reconstruct the public key and signature for verification
        const public_key = crypto.sign.Ed25519.PublicKey.fromBytes(signature.public_key) catch return false;
        const sig = crypto.sign.Ed25519.Signature.fromBytes(signature.signature);

        // Verify the signature cryptographically
        sig.verify(content, public_key) catch return false;
        return true;
    }

    /// Add a signer to the trust store
    pub fn addTrustedSigner(self: *SecurityManager, signer_info: SignerInfo) !void {
        const signer_id_copy = try self.allocator.dupe(u8, signer_info.signer_id);
        var info_copy = signer_info;
        info_copy.signer_id = try self.allocator.dupe(u8, signer_info.signer_id);

        try self.trust_store.put(signer_id_copy, info_copy);
    }

    /// Get trust level for a signer
    pub fn getTrustLevel(self: *SecurityManager, signer_id: []const u8) TrustLevel {
        if (self.trust_store.get(signer_id)) |signer_info| {
            return signer_info.trust_level;
        }
        return .untrusted;
    }

    /// Update signer reputation based on package verification
    pub fn updateReputation(self: *SecurityManager, signer_id: []const u8, success: bool) !void {
        if (self.trust_store.getPtr(signer_id)) |signer_info| {
            if (success) {
                signer_info.verified_packages += 1;
                signer_info.reputation_score = @min(10.0, signer_info.reputation_score + 0.1);
            } else {
                signer_info.reputation_score = @max(0.0, signer_info.reputation_score - 0.5);
            }
            signer_info.last_seen = zion_root.timestamp();
        }
    }
};

/// Verify package signature
/// Note: This requires a .sig file alongside the package with the signature data.
/// Returns valid=false if no signature is present (unsigned package).
pub fn verifyPackageSignature(allocator: Allocator, package_path: []const u8, package_name: []const u8) !struct {
    valid: bool,
    message: []const u8,
    signer: []const u8,

    pub fn deinit(self: @This()) void {
        _ = self;
        // Messages are static strings, no need to free
    }
} {
    _ = package_name;

    const io = zion_root.getIo() catch {
        return .{
            .valid = false,
            .message = "Failed to initialize I/O for verification",
            .signer = "unknown",
        };
    };
    const cwd = std.Io.Dir.cwd();

    // Look for signature file (.sig extension)
    var sig_path_buf: [512]u8 = undefined;
    const sig_path = std.fmt.bufPrint(&sig_path_buf, "{s}.sig", .{package_path}) catch {
        return .{
            .valid = false,
            .message = "Package path too long",
            .signer = "unknown",
        };
    };

    // Check if signature file exists
    const sig_file = cwd.openFile(io, sig_path, .{}) catch {
        // No signature file = unsigned package
        return .{
            .valid = false,
            .message = "Package is unsigned (no .sig file found)",
            .signer = "none",
        };
    };
    defer sig_file.close(io);

    // Read signature data (public_key:32 + signature:64 = 96 bytes minimum)
    var sig_data: [128]u8 = undefined;
    const bytes_read = sig_file.readStreaming(io, &.{sig_data[0..]}) catch {
        return .{
            .valid = false,
            .message = "Failed to read signature file",
            .signer = "unknown",
        };
    };

    if (bytes_read < 96) {
        return .{
            .valid = false,
            .message = "Invalid signature file format",
            .signer = "unknown",
        };
    }

    // Parse signature components
    const public_key_bytes: [32]u8 = sig_data[0..32].*;
    const signature_bytes: [64]u8 = sig_data[32..96].*;

    // Open and read the package file
    const pkg_file = cwd.openFile(io, package_path, .{}) catch {
        return .{
            .valid = false,
            .message = "Failed to open package file",
            .signer = "unknown",
        };
    };
    defer pkg_file.close(io);

    var content_list: std.ArrayList(u8) = .empty;
    defer content_list.deinit(allocator);

    var buffer: [8192]u8 = undefined;
    while (true) {
        const read_bytes = pkg_file.readStreaming(io, &.{buffer[0..]}) catch break;
        if (read_bytes == 0) break;
        content_list.appendSlice(allocator, buffer[0..read_bytes]) catch {
            return .{
                .valid = false,
                .message = "Memory allocation failed during verification",
                .signer = "unknown",
            };
        };
    }

    // Verify the Ed25519 signature
    const public_key = crypto.sign.Ed25519.PublicKey.fromBytes(public_key_bytes) catch {
        return .{
            .valid = false,
            .message = "Invalid public key in signature",
            .signer = "unknown",
        };
    };

    const sig = crypto.sign.Ed25519.Signature.fromBytes(signature_bytes);

    sig.verify(content_list.items, public_key) catch {
        return .{
            .valid = false,
            .message = "Signature verification failed - content may have been tampered",
            .signer = "unknown",
        };
    };

    return .{
        .valid = true,
        .message = "Package signature verified successfully",
        .signer = "verified",
    };
}
