const std = @import("std");
const zsync = @import("zsync");
const http_client = @import("http_client.zig");

const Allocator = std.mem.Allocator;

/// HTTP client with timeout support using zsync futures
pub const TimeoutClient = struct {
    allocator: Allocator,
    client: *http_client.HttpClient,
    runtime: *zsync.Runtime,
    default_timeout_ms: u64 = 30000, // 30 seconds default
    
    const Self = @This();
    
    pub const TimeoutError = error{
        RequestTimeout,
        ConnectionTimeout,
        ReadTimeout,
    };
    
    pub const TimeoutConfig = struct {
        connect_timeout_ms: u64 = 10000, // 10 seconds
        read_timeout_ms: u64 = 30000,    // 30 seconds
        total_timeout_ms: u64 = 60000,   // 60 seconds
    };
    
    pub fn init(allocator: Allocator, runtime: *zsync.Runtime, client: *http_client.HttpClient) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .client = client,
            .runtime = runtime,
        };
        return self;
    }
    
    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }
    
    /// Perform GET request with timeout (simplified blocking approach)
    pub fn getWithTimeout(self: *Self, url: []const u8, timeout_ms: u64) !http_client.HttpResponse {
        _ = timeout_ms; // For now, just ignore timeout and use the default HTTP client timeout
        
        // Use the HTTP client directly since it already has retry and timeout logic
        return try self.client.get(url);
    }
    
    /// Perform POST request with timeout (simplified blocking approach)
    pub fn postWithTimeout(self: *Self, url: []const u8, data: []const u8, timeout_ms: u64) !http_client.HttpResponse {
        _ = timeout_ms; // For now, just ignore timeout and use the default HTTP client timeout
        
        // Use the HTTP client directly since it already has retry and timeout logic
        return try self.client.post(url, data);
    }
    
    /// Download file with configurable timeouts (simplified blocking approach)
    pub fn downloadWithTimeouts(self: *Self, url: []const u8, dest_path: []const u8, config: TimeoutConfig) !void {
        _ = config; // For now, ignore config and use simple download
        
        // Get response 
        const response = try self.client.get(url);
        defer response.deinit(self.allocator);
        
        if (!response.isSuccess()) {
            return error.DownloadFailed;
        }
        
        // Create destination file and write response body
        const file = try std.fs.cwd().createFile(dest_path, .{});
        defer file.close();
        
        if (response.body) |body| {
            try file.writeAll(body);
        }
    }
    
    /// Batch request with individual timeouts (simplified blocking approach)
    pub fn batchRequestsWithTimeout(self: *Self, urls: []const []const u8, timeout_ms: u64) ![]http_client.HttpResponse {
        _ = timeout_ms; // For now, ignore timeout and use simple sequential requests
        
        var responses = try self.allocator.alloc(http_client.HttpResponse, urls.len);
        errdefer {
            for (responses) |response| {
                response.deinit(self.allocator);
            }
            self.allocator.free(responses);
        }
        
        for (urls, 0..) |url, i| {
            responses[i] = try self.client.get(url);
        }
        
        return responses;
    }
};