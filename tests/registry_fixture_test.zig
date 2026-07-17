const std = @import("std");
const zion = @import("zion");

const RegistryClient = zion.package_registry.RegistryClient;
const RegistryConfig = zion.enhanced_config.RegistryConfig;

fn url(allocator: std.mem.Allocator, base: []const u8, path: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ base, path });
}

fn expectRequest(
    allocator: std.mem.Allocator,
    io: std.Io,
    config: RegistryConfig,
    base: []const u8,
    path: []const u8,
) !void {
    var client = RegistryClient.init(allocator, config, io);
    defer client.deinit();
    const request_url = try url(allocator, base, path);
    defer allocator.free(request_url);
    const response = try client.makeRequest("GET", request_url, null);
    defer allocator.free(response);
    try std.testing.expect(response.len > 0);
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedFixtureBaseUrl;
    const base = args[1];
    try zion.package_registry.validateRegistryUrl(base);
    const allocator = init.gpa;
    const io = init.io;

    const fast = RegistryConfig{
        .name = "fixture",
        .base_url = base,
        .timeout_ms = 1000,
        .retry_delay_ms = 1,
    };
    try expectRequest(allocator, io, fast, base, "/success");
    try expectRequest(allocator, io, fast, base, "/redirect");
    try expectRequest(allocator, io, .{
        .name = "fixture",
        .base_url = base,
        .auth_token = "fixture-token",
        .timeout_ms = 1000,
        .retry_delay_ms = 1,
    }, base, "/auth");
    try expectRequest(allocator, io, fast, base, "/rate-limit");
    try expectRequest(allocator, io, fast, base, "/retry");

    var timeout_client = RegistryClient.init(allocator, .{
        .name = "fixture",
        .base_url = base,
        .timeout_ms = 20,
        .retry_attempts = 1,
        .retry_delay_ms = 1,
    }, io);
    defer timeout_client.deinit();
    const timeout_url = try url(allocator, base, "/timeout");
    defer allocator.free(timeout_url);
    try std.testing.expectError(error.RegistryTimeout, timeout_client.makeRequest("GET", timeout_url, null));

    var malformed_client = RegistryClient.init(allocator, fast, io);
    defer malformed_client.deinit();
    try std.testing.expectError(error.SyntaxError, malformed_client.fetchPackageMetadata("malformed", "pkg"));

    const oversized_url = try url(allocator, base, "/oversized");
    defer allocator.free(oversized_url);
    try std.testing.expectError(error.ResponseTooLarge, malformed_client.makeRequest("GET", oversized_url, null));
}
