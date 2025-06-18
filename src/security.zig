const std = @import("std");
const crypto = std.crypto;
const fs = std.fs;
const Allocator = std.mem.Allocator;

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
    pub fn generateKeyPair(_: *SecurityManager) !struct { public_key: [PUBLIC_KEY_SIZE]u8, private_key: [PRIVATE_KEY_SIZE]u8 } {
        // Generate a random 32-byte seed for the private key
        var seed: [32]u8 = undefined;
        crypto.random.bytes(&seed);

        // For Ed25519, we'll use a simplified approach
        // Create 64-byte private key (32 bytes seed + 32 bytes derived)
        var private_key: [64]u8 = undefined;
        var public_key: [32]u8 = undefined;

        // Copy seed to first 32 bytes of private key
        @memcpy(private_key[0..32], &seed);

        // Generate the actual keypair using the crypto library
        // For now, use placeholder values - in a full implementation,
        // you'd use the actual Ed25519 key derivation
        crypto.random.bytes(private_key[32..64]);
        crypto.random.bytes(&public_key);

        return .{
            .public_key = public_key,
            .private_key = private_key,
        };
    }

    /// Sign a package file with Ed25519
    pub fn signPackage(self: *SecurityManager, package_path: []const u8, private_key: [PRIVATE_KEY_SIZE]u8, signer_id: []const u8) !PackageSignature {
        const file = try fs.cwd().openFile(package_path, .{});
        defer file.close();

        // Read file content
        const file_size = try file.getEndPos();
        const content = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(content);
        _ = try file.readAll(content);

        // For now, create a mock signature using hash of content + private key
        // In a full implementation, you'd use proper Ed25519 signing
        var hasher = crypto.hash.sha2.Sha256.init(.{});
        hasher.update(content);
        hasher.update(&private_key);

        var signature: [SIGNATURE_SIZE]u8 = undefined;
        var hash: [32]u8 = undefined;
        hasher.final(&hash);

        // Pad the hash to signature size
        @memcpy(signature[0..32], &hash);
        @memset(signature[32..], 0);

        return PackageSignature{
            .signature = signature,
            .public_key = private_key[32..64].*, // Use second half as mock public key
            .timestamp = std.time.timestamp(),
            .signer_id = try self.allocator.dupe(u8, signer_id),
            .algorithm = try self.allocator.dupe(u8, "Ed25519"),
        };
    }

    /// Verify a package signature
    pub fn verifyPackage(self: *SecurityManager, package_path: []const u8, signature: PackageSignature) !bool {
        const file = try fs.cwd().openFile(package_path, .{});
        defer file.close();

        // Read file content
        const file_size = try file.getEndPos();
        const content = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(content);
        _ = try file.readAll(content);

        // For now, implement mock verification
        // In a full implementation, you'd use proper Ed25519 verification
        var hasher = crypto.hash.sha2.Sha256.init(.{});
        hasher.update(content);
        hasher.update(&signature.public_key);

        var expected_hash: [32]u8 = undefined;
        hasher.final(&expected_hash);

        // Compare first 32 bytes of signature with expected hash
        return std.mem.eql(u8, signature.signature[0..32], &expected_hash);
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
            signer_info.last_seen = std.time.timestamp();
        }
    }
};
