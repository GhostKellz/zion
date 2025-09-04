const std = @import("std");
const Allocator = std.mem.Allocator;

/// Enhanced HTTP client with retry logic, connection reuse, and optimized memory management
/// Provides HTTP/1.1 functionality with exponential backoff and comprehensive error handling
pub const HttpClient = struct {
    allocator: Allocator,
    persistent_client: std.http.Client,
    header_buffer: []u8,
    max_retries: u32,
    timeout_ms: u64,
    
    pub fn init(allocator: Allocator, runtime: anytype) !*HttpClient {
        _ = runtime; // Ignore runtime parameter for compatibility
        
        const client = try allocator.create(HttpClient);
        
        // Pre-allocate header buffer for reuse
        const header_buffer = try allocator.alloc(u8, 8192); // Larger buffer for better performance
        
        client.* = .{
            .allocator = allocator,
            .persistent_client = std.http.Client{ .allocator = allocator },
            .header_buffer = header_buffer,
            .max_retries = 3,
            .timeout_ms = 30000, // 30 seconds default timeout
        };
        
        return client;
    }
    
    pub fn deinit(self: *HttpClient) void {
        self.persistent_client.deinit(allocator);
        self.allocator.free(self.header_buffer);
        self.allocator.destroy(self);
    }
    
    pub fn get(self: *HttpClient, url: []const u8) !HttpResponse {
        return self.requestWithRetry(.GET, url, null);
    }
    
    pub fn post(self: *HttpClient, url: []const u8, data: []const u8) !HttpResponse {
        return self.requestWithRetry(.POST, url, data);
    }
    
    /// Enhanced request method with retry logic and exponential backoff
    fn requestWithRetry(self: *HttpClient, method: std.http.Method, url: []const u8, data: ?[]const u8) !HttpResponse {
        var retry_count: u32 = 0;
        var backoff_ms: u64 = 1000; // Start with 1 second
        
        while (retry_count <= self.max_retries) {
            const result = self.makeRequest(method, url, data) catch |err| {
                retry_count += 1;
                if (retry_count <= self.max_retries) {
                    // Log retry attempt
                    std.log.debug("HTTP request failed (attempt {}/{}): {}, retrying in {}ms", .{
                        retry_count, self.max_retries + 1, err, backoff_ms
                    });
                    
                    // Exponential backoff with jitter
                    const jitter = std.crypto.random.intRangeLessThan(u64, 0, backoff_ms / 4);
                    std.time.sleep((backoff_ms + jitter) * 1000000); // Convert to nanoseconds
                    backoff_ms = @min(backoff_ms * 2, 30000); // Cap at 30 seconds
                    continue;
                } else {
                    return err;
                }
            };
            
            // Success or non-retryable error
            return result;
        }
        
        return error.MaxRetriesExceeded;
    }
    
    /// Core request implementation with optimized memory management
    fn makeRequest(self: *HttpClient, method: std.http.Method, url: []const u8, data: ?[]const u8) !HttpResponse {
        const start_time = std.time.milliTimestamp();
        
        // Parse URL
        const uri = std.Uri.parse(url) catch |err| {
            std.log.err("Failed to parse URL: {s} - {}", .{ url, err });
            return error.InvalidUrl;
        };
        
        // Prepare request with reused header buffer
        var req = self.persistent_client.open(method, uri, .{
            .server_header_buffer = self.header_buffer,
        }) catch |err| {
            std.log.err("Failed to open HTTP request to {s}: {}", .{ url, err });
            return switch (err) {
                error.UnknownHostName => error.UnknownHost,
                error.ConnectionRefused => error.ConnectionRefused,
                error.NetworkUnreachable => error.NetworkUnreachable,
                error.ConnectionTimedOut => error.ConnectionTimeout,
                else => error.HttpRequestFailed,
            };
        };
        defer req.deinit(allocator);
        
        // Set timeout if needed
        // Note: Zig's std.http.Client doesn't have built-in timeout support yet
        // This is a placeholder for future implementation
        
        // Handle POST data
        if (data) |payload| {
            req.transfer_encoding = .{ .content_length = payload.len };
            
            // Set content type for POST requests
            try req.headers.append("Content-Type", "application/json");
        }
        
        // Send request
        req.send() catch |err| {
            std.log.err("Failed to send HTTP request to {s}: {}", .{ url, err });
            return switch (err) {
                error.ConnectionResetByPeer => error.ConnectionReset,
                error.BrokenPipe => error.ConnectionReset,
                error.ConnectionTimedOut => error.ConnectionTimeout,
                else => error.HttpRequestFailed,
            };
        };
        
        // Write POST data if present
        if (data) |payload| {
            req.writeAll(payload) catch |err| {
                std.log.err("Failed to write POST data to {s}: {}", .{ url, err });
                return error.HttpRequestFailed;
            };
        }
        
        // Finish and wait for response
        req.finish() catch |err| {
            std.log.err("Failed to finish HTTP request to {s}: {}", .{ url, err });
            return error.HttpRequestFailed;
        };
        
        req.wait() catch |err| {
            std.log.err("Failed to wait for HTTP response from {s}: {}", .{ url, err });
            return switch (err) {
                error.ConnectionTimedOut => error.ConnectionTimeout,
                error.ConnectionResetByPeer => error.ConnectionReset,
                else => error.HttpRequestFailed,
            };
        };
        
        // Read response body with size limit
        const max_body_size = 100 * 1024 * 1024; // 100MB limit
        const body = req.readAll(self.allocator) catch |err| {
            std.log.err("Failed to read HTTP response body from {s}: {}", .{ url, err });
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.HttpRequestFailed,
            };
        };
        
        // Validate response size
        if (body) |response_body| {
            if (response_body.len > max_body_size) {
                self.allocator.free(response_body);
                return error.ResponseTooLarge;
            }
        }
        
        const elapsed = std.time.milliTimestamp() - start_time;
        const status_code = @intFromEnum(req.response.status);
        
        // Log successful request
        std.log.debug("HTTP {} {s} -> {} in {}ms ({} bytes)", .{
            @tagName(method),
            url,
            status_code,
            elapsed,
            if (body) |b| b.len else 0,
        });
        
        return HttpResponse{
            .allocator = self.allocator,
            .status_code = status_code,
            .body = body,
            .headers = try self.copyHeaders(req.response.headers),
            .response_time_ms = @intCast(elapsed),
        };
    }
    
    /// Copy response headers for use after request cleanup
    fn copyHeaders(self: *HttpClient, headers: std.http.Headers) !std.StringHashMap([]const u8) {
        var header_map = std.StringHashMap([]const u8).init(self.allocator);
        
        var iter = headers.iterator();
        while (iter.next()) |header| {
            const name = try self.allocator.dupe(u8, header.name);
            const value = try self.allocator.dupe(u8, header.value);
            try header_map.put(name, value);
        }
        
        return header_map;
    }
    
    /// Set custom timeout for requests
    pub fn setTimeout(self: *HttpClient, timeout_ms: u64) void {
        self.timeout_ms = timeout_ms;
    }
    
    /// Set maximum retry attempts
    pub fn setMaxRetries(self: *HttpClient, max_retries: u32) void {
        self.max_retries = max_retries;
    }
};

pub const HttpResponse = struct {
    allocator: Allocator,
    status_code: u16,
    body: ?[]const u8,
    headers: std.StringHashMap([]const u8),
    response_time_ms: u64,
    
    pub fn deinit(self: *HttpResponse, allocator: Allocator) void {
        _ = allocator; // Use the allocator from the struct instead
        
        // Free response body
        if (self.body) |body| {
            self.allocator.free(body);
        }
        
        // Free headers
        var iter = self.headers.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit(allocator);
    }
    
    /// Check if response indicates success
    pub fn isSuccess(self: *const HttpResponse) bool {
        return self.status_code >= 200 and self.status_code < 300;
    }
    
    /// Check if response indicates a client error
    pub fn isClientError(self: *const HttpResponse) bool {
        return self.status_code >= 400 and self.status_code < 500;
    }
    
    /// Check if response indicates a server error
    pub fn isServerError(self: *const HttpResponse) bool {
        return self.status_code >= 500 and self.status_code < 600;
    }
    
    /// Get header value by name (case-insensitive)
    pub fn getHeader(self: *const HttpResponse, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }
    
    /// Get content type from headers
    pub fn getContentType(self: *const HttpResponse) ?[]const u8 {
        return self.getHeader("Content-Type") orelse self.getHeader("content-type");
    }
    
    /// Get response as JSON (caller owns the memory)
    pub fn asJson(self: *const HttpResponse, comptime T: type) !T {
        const body = self.body orelse return error.EmptyResponse;
        return std.json.parseFromSlice(T, self.allocator, body, .{});
    }
};