const std = @import("std");
const Allocator = std.mem.Allocator;

/// Simple HTTP client replacement for ghostnet
/// Provides basic HTTP/1.1 functionality using Zig's standard library
pub const HttpClient = struct {
    allocator: Allocator,
    
    pub fn init(allocator: Allocator, runtime: anytype) !*HttpClient {
        _ = runtime; // Ignore runtime parameter for compatibility
        
        const client = try allocator.create(HttpClient);
        client.* = .{
            .allocator = allocator,
        };
        return client;
    }
    
    pub fn deinit(self: *HttpClient) void {
        self.allocator.destroy(self);
    }
    
    pub fn get(self: *HttpClient, url: []const u8) !HttpResponse {
        // Parse URL
        const uri = try std.Uri.parse(url);
        
        // Create HTTP client
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();
        
        // Prepare request
        var req = try client.open(.GET, uri, .{
            .server_header_buffer = try self.allocator.alloc(u8, 4096),
        });
        defer req.deinit();
        defer self.allocator.free(req.server_header_buffer);
        
        // Send request
        try req.send();
        try req.finish();
        try req.wait();
        
        // Read response body
        const body = try req.readAll(self.allocator);
        
        return HttpResponse{
            .allocator = self.allocator,
            .status_code = @intFromEnum(req.response.status),
            .body = body,
        };
    }
    
    pub fn post(self: *HttpClient, url: []const u8, data: []const u8) !HttpResponse {
        // Parse URL
        const uri = try std.Uri.parse(url);
        
        // Create HTTP client
        var client = std.http.Client{ .allocator = self.allocator };
        defer client.deinit();
        
        // Prepare request
        var req = try client.open(.POST, uri, .{
            .server_header_buffer = try self.allocator.alloc(u8, 4096),
        });
        defer req.deinit();
        defer self.allocator.free(req.server_header_buffer);
        
        // Set content length
        req.transfer_encoding = .{ .content_length = data.len };
        
        // Send request
        try req.send();
        try req.writeAll(data);
        try req.finish();
        try req.wait();
        
        // Read response body
        const body = try req.readAll(self.allocator);
        
        return HttpResponse{
            .allocator = self.allocator,
            .status_code = @intFromEnum(req.response.status),
            .body = body,
        };
    }
};

pub const HttpResponse = struct {
    allocator: Allocator,
    status_code: u16,
    body: ?[]const u8,
    
    pub fn deinit(self: *HttpResponse, allocator: Allocator) void {
        _ = allocator; // Use the allocator from the struct instead
        if (self.body) |body| {
            self.allocator.free(body);
        }
    }
};