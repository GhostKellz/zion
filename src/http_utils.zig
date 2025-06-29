const std = @import("std");
const http = std.http;

pub const HttpError = error{
    RequestFailed,
    Timeout,
    InvalidResponse,
    NetworkError,
};

pub fn makeResilientRequest(
    allocator: std.mem.Allocator,
    url: []const u8,
    max_retries: u32,
    timeout_sec: u32,
) ![]u8 {
    var retry_count: u32 = 0;
    
    while (retry_count <= max_retries) : (retry_count += 1) {
        if (retry_count > 0) {
            std.debug.print("🔄 Retry attempt {} for {s}\n", .{ retry_count, url });
            std.time.sleep(1000 * 1000 * 1000); // 1 second delay
        }
        
        if (makeSingleRequest(allocator, url, timeout_sec)) |response| {
            return response;
        } else |err| {
            std.debug.print("⚠️ Request failed: {}\n", .{err});
            if (retry_count == max_retries) {
                return err;
            }
        }
    }
    
    return HttpError.RequestFailed;
}

fn makeSingleRequest(allocator: std.mem.Allocator, url: []const u8, timeout_sec: u32) ![]u8 {
    _ = timeout_sec; // TODO: Implement timeout
    
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();
    
    var req = client.open(.GET, try std.Uri.parse(url), .{
        .server_header_buffer = &[_]u8{0} ** 16384,
    }) catch return HttpError.NetworkError;
    defer req.deinit();
    
    req.send() catch return HttpError.NetworkError;
    req.finish() catch return HttpError.NetworkError;
    req.wait() catch return HttpError.NetworkError;
    
    if (req.response.status != .ok) {
        return HttpError.InvalidResponse;
    }
    
    return req.reader().readAllAlloc(allocator, 10 * 1024 * 1024) catch HttpError.InvalidResponse;
}