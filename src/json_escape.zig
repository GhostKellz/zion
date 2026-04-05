//! JSON String Escaping Utility
//!
//! Provides proper JSON string escaping to prevent injection attacks
//! and ensure valid JSON output in lockfiles and other serialization.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Escapes a string for safe inclusion in JSON.
/// Handles: " \ / newline carriage-return tab and control characters.
pub fn escapeJsonString(allocator: Allocator, input: []const u8) ![]u8 {
    // Calculate required size first to minimize allocations
    var required_size: usize = 0;
    for (input) |c| {
        required_size += switch (c) {
            '"', '\\', '/' => 2,
            '\n', '\r', '\t', 0x08, 0x0C => 2, // \n, \r, \t, \b, \f
            else => if (c < 0x20) 6 else 1, // \uXXXX for other control chars
        };
    }

    var output = try allocator.alloc(u8, required_size);
    var pos: usize = 0;

    for (input) |c| {
        switch (c) {
            '"' => {
                output[pos] = '\\';
                output[pos + 1] = '"';
                pos += 2;
            },
            '\\' => {
                output[pos] = '\\';
                output[pos + 1] = '\\';
                pos += 2;
            },
            '/' => {
                // Forward slash escaping is optional in JSON but safer
                output[pos] = '\\';
                output[pos + 1] = '/';
                pos += 2;
            },
            '\n' => {
                output[pos] = '\\';
                output[pos + 1] = 'n';
                pos += 2;
            },
            '\r' => {
                output[pos] = '\\';
                output[pos + 1] = 'r';
                pos += 2;
            },
            '\t' => {
                output[pos] = '\\';
                output[pos + 1] = 't';
                pos += 2;
            },
            0x08 => { // backspace
                output[pos] = '\\';
                output[pos + 1] = 'b';
                pos += 2;
            },
            0x0C => { // form feed
                output[pos] = '\\';
                output[pos + 1] = 'f';
                pos += 2;
            },
            else => {
                if (c < 0x20) {
                    // Control characters: \uXXXX
                    output[pos] = '\\';
                    output[pos + 1] = 'u';
                    output[pos + 2] = '0';
                    output[pos + 3] = '0';
                    const hex_chars = "0123456789abcdef";
                    output[pos + 4] = hex_chars[(c >> 4) & 0x0F];
                    output[pos + 5] = hex_chars[c & 0x0F];
                    pos += 6;
                } else {
                    output[pos] = c;
                    pos += 1;
                }
            },
        }
    }

    return output;
}

/// Check if a string needs escaping (for optimization)
pub fn needsEscaping(input: []const u8) bool {
    for (input) |c| {
        switch (c) {
            '"', '\\', '/', '\n', '\r', '\t', 0x08, 0x0C => return true,
            else => if (c < 0x20) return true,
        }
    }
    return false;
}

/// Escape a string only if needed, otherwise return a copy
/// Returns owned memory that must be freed
pub fn escapeIfNeeded(allocator: Allocator, input: []const u8) ![]u8 {
    if (needsEscaping(input)) {
        return escapeJsonString(allocator, input);
    }
    return allocator.dupe(u8, input);
}

test "basic escaping" {
    const allocator = std.testing.allocator;

    // Test quote escaping
    const quoted = try escapeJsonString(allocator, "hello \"world\"");
    defer allocator.free(quoted);
    try std.testing.expectEqualStrings("hello \\\"world\\\"", quoted);

    // Test backslash escaping
    const backslash = try escapeJsonString(allocator, "path\\to\\file");
    defer allocator.free(backslash);
    try std.testing.expectEqualStrings("path\\\\to\\\\file", backslash);

    // Test newline escaping
    const newline = try escapeJsonString(allocator, "line1\nline2");
    defer allocator.free(newline);
    try std.testing.expectEqualStrings("line1\\nline2", newline);
}

test "control character escaping" {
    const allocator = std.testing.allocator;

    // Test tab
    const tab = try escapeJsonString(allocator, "col1\tcol2");
    defer allocator.free(tab);
    try std.testing.expectEqualStrings("col1\\tcol2", tab);

    // Test control char (bell = 0x07)
    const bell = try escapeJsonString(allocator, "alert\x07here");
    defer allocator.free(bell);
    try std.testing.expectEqualStrings("alert\\u0007here", bell);
}

test "no escaping needed" {
    const allocator = std.testing.allocator;

    const clean = try escapeJsonString(allocator, "simple string");
    defer allocator.free(clean);
    try std.testing.expectEqualStrings("simple string", clean);

    try std.testing.expect(!needsEscaping("simple string"));
    try std.testing.expect(needsEscaping("has \"quotes\""));
}
