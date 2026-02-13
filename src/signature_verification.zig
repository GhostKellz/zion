const std = @import("std");
const crypto = std.crypto;
const Allocator = std.mem.Allocator;

pub const SignatureError = error{
    InvalidSignature,
    UnsupportedAlgorithm,
    MalformedData,
    KeyNotFound,
};

pub const PublicKey = struct {
    algorithm: Algorithm,
    key_data: []const u8,

    pub const Algorithm = enum {
        ed25519,
        rsa2048,
        ecdsa_p256,
    };
};

pub const Signature = struct {
    algorithm: PublicKey.Algorithm,
    signature_data: []const u8,
    public_key_id: []const u8,
};

pub const PackageSignature = struct {
    package_name: []const u8,
    version: []const u8,
    file_hash: []const u8,
    timestamp: i64,
    signature: Signature,

    pub fn verify(self: *const PackageSignature, allocator: Allocator, public_key: PublicKey, package_data: []const u8) !bool {
        // Verify the package hash matches
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(package_data);
        var computed_hash: [32]u8 = undefined;
        hasher.final(&computed_hash);

        // Convert hash to hex string
        var expected_hash_buf: [64]u8 = undefined;
        const expected_hash = std.fmt.bufPrint(&expected_hash_buf, "{x}", .{computed_hash}) catch return false;

        if (!std.mem.eql(u8, expected_hash, self.file_hash)) {
            return false;
        }

        // Create message to verify
        const message = try std.fmt.allocPrint(allocator, "{s}:{s}:{s}:{d}", .{
            self.package_name,
            self.version,
            self.file_hash,
            self.timestamp,
        });
        defer allocator.free(message);

        // Verify signature based on algorithm
        return switch (self.signature.algorithm) {
            .ed25519 => verifyEd25519(message, self.signature.signature_data, public_key.key_data),
            .rsa2048 => verifyRsa2048(allocator, message, self.signature.signature_data, public_key.key_data),
            .ecdsa_p256 => verifyEcdsaP256(message, self.signature.signature_data, public_key.key_data),
        };
    }
};

fn verifyEd25519(message: []const u8, signature_data: []const u8, public_key_data: []const u8) bool {
    if (signature_data.len != 64 or public_key_data.len != 32) return false;

    const public_key = crypto.sign.Ed25519.PublicKey.fromBytes(public_key_data[0..32].*) catch return false;
    const signature = crypto.sign.Ed25519.Signature.fromBytes(signature_data[0..64].*);

    signature.verify(message, public_key) catch return false;
    return true;
}

fn verifyRsa2048(allocator: Allocator, message: []const u8, signature_data: []const u8, public_key_data: []const u8) bool {
    _ = allocator;
    _ = message;
    _ = signature_data;
    _ = public_key_data;
    // RSA verification would require additional crypto library
    // For now, return false as unsupported
    return false;
}

fn verifyEcdsaP256(message: []const u8, signature_data: []const u8, public_key_data: []const u8) bool {
    _ = message;
    _ = signature_data;
    _ = public_key_data;
    // ECDSA verification would require additional crypto library
    // For now, return false as unsupported
    return false;
}

pub const TrustedKeyStore = struct {
    allocator: Allocator,
    keys: std.StringHashMap(PublicKey),

    pub fn init(allocator: Allocator) TrustedKeyStore {
        return TrustedKeyStore{
            .allocator = allocator,
            .keys = std.StringHashMap(PublicKey).init(allocator),
        };
    }

    pub fn deinit(self: *TrustedKeyStore) void {
        var iterator = self.keys.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.key_data);
        }
        self.keys.deinit();
    }

    pub fn addKey(self: *TrustedKeyStore, key_id: []const u8, public_key: PublicKey) !void {
        const owned_id = try self.allocator.dupe(u8, key_id);
        const owned_key_data = try self.allocator.dupe(u8, public_key.key_data);

        const owned_key = PublicKey{
            .algorithm = public_key.algorithm,
            .key_data = owned_key_data,
        };

        try self.keys.put(owned_id, owned_key);
    }

    pub fn getKey(self: *const TrustedKeyStore, key_id: []const u8) ?PublicKey {
        return self.keys.get(key_id);
    }

    pub fn loadFromFile(allocator: Allocator, file_path: []const u8) !TrustedKeyStore {
        const store = init(allocator);

        const file_content = std.fs.cwd().readFileAlloc(file_path, allocator, @enumFromInt(1024 * 1024)) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("🔑 No trusted keys file found, starting with empty keystore\n", .{});
                return store;
            }
            return err;
        };
        defer allocator.free(file_content);

        _ = std.json.parseFromSlice(std.json.Value, allocator, file_content, .{}) catch |err| {
            std.debug.print("⚠️  Failed to parse trusted keys file: {}\n", .{err});
            return store;
        };

        return store;
    }
};

pub fn verifyPackage(allocator: Allocator, package_data: []const u8, signature_json: []const u8, key_store: *const TrustedKeyStore) !bool {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, signature_json, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const package_name = root.get("package_name").?.string;
    const version = root.get("version").?.string;
    const file_hash = root.get("file_hash").?.string;
    const timestamp = @as(i64, @intCast(root.get("timestamp").?.integer));

    const sig_obj = root.get("signature").?.object;
    const algorithm_str = sig_obj.get("algorithm").?.string;
    const signature_data = sig_obj.get("signature_data").?.string;
    const public_key_id = sig_obj.get("public_key_id").?.string;

    const algorithm = std.meta.stringToEnum(PublicKey.Algorithm, algorithm_str) orelse return SignatureError.UnsupportedAlgorithm;

    const signature = Signature{
        .algorithm = algorithm,
        .signature_data = signature_data,
        .public_key_id = public_key_id,
    };

    const pkg_signature = PackageSignature{
        .package_name = package_name,
        .version = version,
        .file_hash = file_hash,
        .timestamp = timestamp,
        .signature = signature,
    };

    const public_key = key_store.getKey(public_key_id) orelse return SignatureError.KeyNotFound;

    return pkg_signature.verify(allocator, public_key, package_data);
}
