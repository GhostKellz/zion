const std = @import("std");

const Allocator = std.mem.Allocator;

/// Simplified HTTP client for the current Zion I/O boundary.
pub const SimpleHttpClient = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator, runtime: anytype) !*SimpleHttpClient {
        _ = runtime;
        const client = try allocator.create(SimpleHttpClient);
        client.* = .{
            .allocator = allocator,
        };
        return client;
    }

    pub fn deinit(self: *SimpleHttpClient) void {
        self.allocator.destroy(self);
    }

    pub fn get(self: *SimpleHttpClient, url: []const u8) !SimpleHttpResponse {
        _ = url;
        // Mock implementation for now
        return SimpleHttpResponse{
            .allocator = self.allocator,
            .status_code = 200,
            .body = try self.allocator.dupe(u8, "Mock response from simple HTTP client"),
            .headers = std.StringHashMap([]const u8).init(self.allocator),
            .response_time_ms = 50,
        };
    }

    pub fn post(self: *SimpleHttpClient, url: []const u8, data: []const u8) !SimpleHttpResponse {
        _ = url;
        _ = data;
        return SimpleHttpResponse{
            .allocator = self.allocator,
            .status_code = 200,
            .body = try self.allocator.dupe(u8, "Mock POST response"),
            .headers = std.StringHashMap([]const u8).init(self.allocator),
            .response_time_ms = 75,
        };
    }

    pub fn setTimeout(self: *SimpleHttpClient, timeout_ms: u64) void {
        _ = self;
        _ = timeout_ms;
        // No-op for mock implementation
    }

    pub fn setMaxRetries(self: *SimpleHttpClient, max_retries: u32) void {
        _ = self;
        _ = max_retries;
        // No-op for mock implementation
    }
};

pub const SimpleHttpResponse = struct {
    allocator: Allocator,
    status_code: u16,
    body: ?[]const u8,
    headers: std.StringHashMap([]const u8),
    response_time_ms: u64,

    pub fn deinit(self: *SimpleHttpResponse, allocator: Allocator) void {
        _ = allocator;

        if (self.body) |body| {
            self.allocator.free(body);
        }

        var iter = self.headers.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
    }

    pub fn isSuccess(self: *const SimpleHttpResponse) bool {
        return self.status_code >= 200 and self.status_code < 300;
    }

    pub fn getHeader(self: *const SimpleHttpResponse, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }
};
