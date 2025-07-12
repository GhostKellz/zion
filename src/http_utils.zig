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
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();
    
    // Set connection timeout
    const timeout_ns = @as(u64, timeout_sec) * std.time.ns_per_s;
    
    var req = client.open(.GET, try std.Uri.parse(url), .{
        .server_header_buffer = &[_]u8{0} ** 16384,
        .connection = .{ .timeout_ms = @intCast(timeout_sec * 1000) },
    }) catch return HttpError.NetworkError;
    defer req.deinit();
    
    // Use timeout for operations
    const start_time = std.time.nanoTimestamp();
    
    req.send() catch return HttpError.NetworkError;
    req.finish() catch return HttpError.NetworkError;
    req.wait() catch return HttpError.NetworkError;
    
    // Check if we've exceeded timeout
    const elapsed_ns = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));
    if (elapsed_ns > timeout_ns) {
        return HttpError.Timeout;
    }
    
    if (req.response.status != .ok) {
        return HttpError.InvalidResponse;
    }
    
    var output_buf = std.ArrayList(u8).init(allocator);
    defer output_buf.deinit();
    
    var read_buf: [4096]u8 = undefined;
    while (true) {
        const bytes_read = req.readAll(read_buf[0..]) catch return HttpError.InvalidResponse;
        if (bytes_read == 0) break;
        output_buf.appendSlice(read_buf[0..bytes_read]) catch return HttpError.InvalidResponse;
    }
    
    return allocator.dupe(u8, output_buf.items) catch HttpError.InvalidResponse;
}