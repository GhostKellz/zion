//! Hash Conversion Module for Zion
//! Converts between SHA256 hex format and Zig's native hash format.
//!
//! Zig native format: `{name}-{version}-{base64url_multihash}`
//! Where multihash is: 0x12 (sha256) + 0x20 (32 bytes) + sha256_digest
//!
//! Example: "zsync-0.7.8-KAuheQufGABcQSjcE59uKuXJtH8PNSe39fxrTiFlsTYl"

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Errors that can occur during hash conversion
pub const ConversionError = error{
    InvalidHexLength,
    InvalidHexChar,
    InvalidZigHashFormat,
    InvalidBase64,
    InvalidMultihashPrefix,
    OutOfMemory,
};

/// Parsed components of a Zig native hash
pub const ZigHashComponents = struct {
    name: []const u8,
    version: []const u8,
    base64_hash: []const u8,
};

/// Convert SHA256 hex string to Zig native hash format
/// Input: 64-character hex string (e.g., "abc123...")
/// Output: "name-version-{base64url}" where base64url encodes 0x1220 + sha256_bytes
pub fn hexToZigNativeHash(
    allocator: Allocator,
    sha256_hex: []const u8,
    name: []const u8,
    version: []const u8,
) ConversionError![]const u8 {
    // Validate hex length (SHA256 = 32 bytes = 64 hex chars)
    if (sha256_hex.len != 64) {
        return ConversionError.InvalidHexLength;
    }

    // Convert hex to bytes
    var sha256_bytes: [32]u8 = undefined;
    for (0..32) |i| {
        const high = hexCharToNibble(sha256_hex[i * 2]) orelse return ConversionError.InvalidHexChar;
        const low = hexCharToNibble(sha256_hex[i * 2 + 1]) orelse return ConversionError.InvalidHexChar;
        sha256_bytes[i] = (@as(u8, high) << 4) | @as(u8, low);
    }

    // Create multihash: 0x12 (sha256) + 0x20 (32 bytes) + digest
    var multihash: [34]u8 = undefined;
    multihash[0] = 0x12; // SHA256 identifier
    multihash[1] = 0x20; // 32 bytes length
    @memcpy(multihash[2..], &sha256_bytes);

    // Encode to base64url (no padding)
    const encoder = std.base64.url_safe_no_pad.Encoder;
    var base64_buf: [46]u8 = undefined; // ceil(34 * 4 / 3) = 46
    const base64_hash = encoder.encode(&base64_buf, &multihash);

    // Build final string: name-version-hash
    const result = std.fmt.allocPrint(allocator, "{s}-{s}-{s}", .{
        name,
        version,
        base64_hash,
    }) catch return ConversionError.OutOfMemory;

    return result;
}

/// Convert Zig native hash to SHA256 hex string
/// Input: "name-version-{base64url}"
/// Output: 64-character lowercase hex string
pub fn zigNativeHashToHex(
    allocator: Allocator,
    zig_hash: []const u8,
) ConversionError![]const u8 {
    const components = parseZigNativeHash(zig_hash) orelse return ConversionError.InvalidZigHashFormat;

    // Decode base64url
    const decoder = std.base64.url_safe_no_pad.Decoder;
    var multihash: [34]u8 = undefined;

    decoder.decode(&multihash, components.base64_hash) catch {
        return ConversionError.InvalidBase64;
    };

    // Verify multihash prefix (0x12 = sha256, 0x20 = 32 bytes)
    if (multihash[0] != 0x12 or multihash[1] != 0x20) {
        return ConversionError.InvalidMultihashPrefix;
    }

    // Convert bytes to hex
    const sha256_bytes = multihash[2..];
    const hex_result = std.fmt.allocPrint(allocator, "{s}", .{
        std.fmt.fmtSliceHexLower(sha256_bytes),
    }) catch return ConversionError.OutOfMemory;

    return hex_result;
}

/// Parse a Zig native hash into its components
/// Returns null if format is invalid
pub fn parseZigNativeHash(hash: []const u8) ?ZigHashComponents {
    // Find the last two hyphens to split name-version-hash
    // Hash is base64url which can contain hyphens, so we need to be careful
    // The base64url hash is always 44-46 chars for SHA256 multihash

    // Work backwards to find the hash portion (after last hyphen before base64)
    var hyphen_positions: [32]usize = undefined;
    var hyphen_count: usize = 0;

    for (hash, 0..) |c, i| {
        if (c == '-' and hyphen_count < 32) {
            hyphen_positions[hyphen_count] = i;
            hyphen_count += 1;
        }
    }

    // Need at least 2 hyphens (name-version-hash)
    if (hyphen_count < 2) return null;

    // The version should be a semver-like string
    // Try to find where version ends and hash begins
    // Hash is typically 44-46 chars of base64url

    // Strategy: the last segment should be ~44-46 chars (base64url encoded 34 bytes)
    const last_hyphen = hyphen_positions[hyphen_count - 1];
    const potential_hash = hash[last_hyphen + 1 ..];

    // Base64url encoded 34 bytes = ceil(34 * 4 / 3) = 46 chars (no padding)
    // But it could be slightly less depending on exact encoding
    if (potential_hash.len >= 40 and potential_hash.len <= 50) {
        // This looks like the hash portion
        // Now find the second-to-last hyphen for version
        if (hyphen_count >= 2) {
            const version_hyphen = hyphen_positions[hyphen_count - 2];
            return ZigHashComponents{
                .name = hash[0..version_hyphen],
                .version = hash[version_hyphen + 1 .. last_hyphen],
                .base64_hash = potential_hash,
            };
        }
    }

    // Fallback: assume format is simple name-version-hash with no hyphens in name
    if (hyphen_count == 2) {
        return ZigHashComponents{
            .name = hash[0..hyphen_positions[0]],
            .version = hash[hyphen_positions[0] + 1 .. hyphen_positions[1]],
            .base64_hash = hash[hyphen_positions[1] + 1 ..],
        };
    }

    return null;
}

/// Validate that a string is a valid Zig native hash format
pub fn validateZigNativeHash(hash: []const u8) bool {
    const components = parseZigNativeHash(hash) orelse return false;

    // Validate base64url characters
    for (components.base64_hash) |c| {
        if (!isBase64UrlChar(c)) return false;
    }

    // Try to decode and verify multihash prefix
    const decoder = std.base64.url_safe_no_pad.Decoder;
    var multihash: [34]u8 = undefined;

    decoder.decode(&multihash, components.base64_hash) catch return false;

    // Check multihash prefix
    return multihash[0] == 0x12 and multihash[1] == 0x20;
}

/// Extract version from a Zig native hash
pub fn extractVersion(hash: []const u8) ?[]const u8 {
    const components = parseZigNativeHash(hash) orelse return null;
    return components.version;
}

/// Extract name from a Zig native hash
pub fn extractName(hash: []const u8) ?[]const u8 {
    const components = parseZigNativeHash(hash) orelse return null;
    return components.name;
}

// Helper: convert hex character to nibble value
fn hexCharToNibble(c: u8) ?u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(c - 'a' + 10),
        'A'...'F' => @intCast(c - 'A' + 10),
        else => null,
    };
}

// Helper: check if character is valid base64url
fn isBase64UrlChar(c: u8) bool {
    return switch (c) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '_' => true,
        else => false,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "hexToZigNativeHash basic conversion" {
    const allocator = std.testing.allocator;

    // Test with a known hex hash
    const hex = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const result = try hexToZigNativeHash(allocator, hex, "testpkg", "1.0.0");
    defer allocator.free(result);

    // Verify format
    try std.testing.expect(std.mem.startsWith(u8, result, "testpkg-1.0.0-"));
}

test "zigNativeHashToHex roundtrip" {
    const allocator = std.testing.allocator;

    const original_hex = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    // Convert to Zig native
    const zig_hash = try hexToZigNativeHash(allocator, original_hex, "mypackage", "2.1.0");
    defer allocator.free(zig_hash);

    // Convert back to hex
    const recovered_hex = try zigNativeHashToHex(allocator, zig_hash);
    defer allocator.free(recovered_hex);

    try std.testing.expectEqualStrings(original_hex, recovered_hex);
}

test "parseZigNativeHash" {
    // Test with real format from build.zig.zon
    const hash = "zsync-0.7.8-KAuheQufGABcQSjcE59uKuXJtH8PNSe39fxrTiFlsTYl";
    const components = parseZigNativeHash(hash).?;

    try std.testing.expectEqualStrings("zsync", components.name);
    try std.testing.expectEqualStrings("0.7.8", components.version);
    try std.testing.expectEqualStrings("KAuheQufGABcQSjcE59uKuXJtH8PNSe39fxrTiFlsTYl", components.base64_hash);
}

test "validateZigNativeHash" {
    // Valid hash from build.zig.zon
    try std.testing.expect(validateZigNativeHash("zsync-0.7.8-KAuheQufGABcQSjcE59uKuXJtH8PNSe39fxrTiFlsTYl"));

    // Invalid formats
    try std.testing.expect(!validateZigNativeHash("invalid"));
    try std.testing.expect(!validateZigNativeHash("no-hash-here"));
}

test "extractVersion" {
    const version = extractVersion("phantom-0.8.6-E0eWBNqFHgAnuoo2jT6-3n5xIu_ctULVZlBoCPFs-gzH");
    try std.testing.expect(version != null);
    try std.testing.expectEqualStrings("0.8.6", version.?);
}

test "extractName" {
    const name = extractName("ghostspec-0.9.5-RqtjsiA2AgCqsAQ_dM88Mt4dD7SiT25Cv9awwyTuHwCs");
    try std.testing.expect(name != null);
    try std.testing.expectEqualStrings("ghostspec", name.?);
}
