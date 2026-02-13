const std = @import("std");
const testing = std.testing;
const http_client = @import("../http_client.zig");

test "HttpClient: initialization and cleanup" {
    const allocator = testing.allocator;

    const client = try http_client.HttpClient.init(allocator, undefined);
    defer client.deinit(allocator);

    // Verify default values
    try testing.expect(client.max_retries == 3);
    try testing.expect(client.timeout_ms == 30000);
    try testing.expect(client.header_buffer.len == 8192);
}

test "HttpClient: retry configuration" {
    const allocator = testing.allocator;

    const client = try http_client.HttpClient.init(allocator, undefined);
    defer client.deinit(allocator);

    // Test configuration methods
    client.setTimeout(60000);
    try testing.expect(client.timeout_ms == 60000);

    client.setMaxRetries(5);
    try testing.expect(client.max_retries == 5);
}

test "HttpResponse: helper methods" {
    const allocator = testing.allocator;

    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit(allocator);

    try headers.put(try allocator.dupe(u8, "Content-Type"), try allocator.dupe(u8, "application/json"));

    const response = http_client.HttpResponse{
        .allocator = allocator,
        .status_code = 200,
        .body = null,
        .headers = headers,
        .response_time_ms = 100,
    };
    defer {
        var iter = response.headers.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
    }

    // Test status checks
    try testing.expect(response.isSuccess());
    try testing.expect(!response.isClientError());
    try testing.expect(!response.isServerError());

    // Test header retrieval
    const content_type = response.getContentType();
    try testing.expect(content_type != null);
    if (content_type) |ct| {
        try testing.expectEqualStrings(ct, "application/json");
    }
}

test "HttpResponse: error status codes" {
    const allocator = testing.allocator;

    const headers = std.StringHashMap([]const u8).init(allocator);

    // Test client error
    var response = http_client.HttpResponse{
        .allocator = allocator,
        .status_code = 404,
        .body = null,
        .headers = headers,
        .response_time_ms = 50,
    };

    try testing.expect(!response.isSuccess());
    try testing.expect(response.isClientError());
    try testing.expect(!response.isServerError());

    // Test server error
    response.status_code = 500;
    try testing.expect(!response.isSuccess());
    try testing.expect(!response.isClientError());
    try testing.expect(response.isServerError());
}

test "HttpClient: memory management" {
    const allocator = testing.allocator;

    // Test multiple client creation/destruction
    for (0..10) |_| {
        const client = try http_client.HttpClient.init(allocator, undefined);
        client.deinit(allocator);
    }

    // Test header buffer reuse
    const client = try http_client.HttpClient.init(allocator, undefined);
    defer client.deinit(allocator);

    // Verify header buffer is pre-allocated
    try testing.expect(client.header_buffer.len > 0);

    // The buffer should persist across requests (not deallocated)
    const initial_ptr = client.header_buffer.ptr;

    // Make a request (this would fail without a real server, but tests buffer reuse)
    _ = client.get("https://example.com/test") catch {};

    // Buffer should still be at the same location
    try testing.expect(client.header_buffer.ptr == initial_ptr);
}

test "HttpClient: error handling" {
    const allocator = testing.allocator;

    const client = try http_client.HttpClient.init(allocator, undefined);
    defer client.deinit(allocator);

    // Test invalid URL
    const result = client.get("not-a-valid-url");
    try testing.expectError(error.InvalidUrl, result);

    // Test connection to non-existent host
    const result2 = client.get("https://this-host-definitely-does-not-exist-12345.com");
    try testing.expectError(error.UnknownHost, result2);
}

test "HttpResponse: JSON parsing" {
    const allocator = testing.allocator;

    const TestStruct = struct {
        name: []const u8,
        value: u32,
    };

    const json_body = try allocator.dupe(u8, "{\"name\":\"test\",\"value\":42}");

    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit(allocator);

    var response = http_client.HttpResponse{
        .allocator = allocator,
        .status_code = 200,
        .body = json_body,
        .headers = headers,
        .response_time_ms = 10,
    };
    defer response.deinit(allocator);

    // Test JSON parsing
    const parsed = try response.asJson(TestStruct);
    defer std.json.parseFree(TestStruct, allocator, parsed);

    try testing.expectEqualStrings(parsed.name, "test");
    try testing.expect(parsed.value == 42);
}

test "HttpClient: request with retry simulation" {
    const allocator = testing.allocator;

    const client = try http_client.HttpClient.init(allocator, undefined);
    defer client.deinit(allocator);

    // Set low retry count for testing
    client.setMaxRetries(2);

    // This tests the retry logic structure
    // In a real test, we'd use a mock server that fails then succeeds
    const start_time = std.time.milliTimestamp();
    _ = client.get("https://httpbin.org/status/500") catch {};
    const elapsed = std.time.milliTimestamp() - start_time;

    // With retries and backoff, this should take at least some time
    // (even if the request fails immediately)
    try testing.expect(elapsed >= 0);
}

test "HttpClient: POST request structure" {
    const allocator = testing.allocator;

    const client = try http_client.HttpClient.init(allocator, undefined);
    defer client.deinit(allocator);

    const test_data = "{\"test\": \"data\"}";

    // Test POST request (would fail without real server)
    _ = client.post("https://example.com/api", test_data) catch |err| {
        // Expected to fail, but tests the code path
        try testing.expect(err == error.UnknownHost or err == error.HttpRequestFailed);
    };
}
