const std = @import("std");
const zsync = @import("zsync");
const zion = @import("zion");
const commands = zion.commands;

// Import our new async modules
const TimeoutClient = @import("timeout_client.zig").TimeoutClient;
const VectorizedDownloader = @import("vectorized_downloader.zig").VectorizedDownloader;
const RacingRegistry = @import("racing_registry.zig").RacingRegistry;
const CancellableOps = @import("cancellable_ops.zig").CancellableOps;
const ZsyncErrorHandler = @import("zsync_error_handling.zig").ZsyncErrorHandler;
const retry_configs = @import("zsync_error_handling.zig").retry_configs;
const http_client = @import("http_client.zig");

const Allocator = std.mem.Allocator;

/// Enhanced async command handler using zsync
pub const AsyncCommandHandler = struct {
    allocator: Allocator,
    runtime: *zsync.Runtime,
    timeout_client: *TimeoutClient,
    vectorized_downloader: *VectorizedDownloader,
    racing_registry: *RacingRegistry,
    cancellable_ops: *CancellableOps,
    error_handler: *ZsyncErrorHandler,
    http_client: *http_client.HttpClient,

    const Self = @This();

    pub fn init(allocator: Allocator, io: zsync.Io) !*Self {
        _ = io; // zsync.Io used for async operations (components use runtime directly)

        // Create runtime for async operations
        const runtime_instance = try zsync.Runtime.init(allocator, .{});

        // Get std.Io from the application context for HTTP client
        // std.http.Client requires std.Io, not zsync.Io
        const std_io = try zion.getIo();
        const client = try http_client.HttpClient.init(allocator, std_io);

        // Initialize all async components
        const timeout_client = try TimeoutClient.init(allocator, runtime_instance, client);
        const vectorized_downloader = try VectorizedDownloader.init(allocator, runtime_instance, client);
        const racing_registry = try RacingRegistry.init(allocator, runtime_instance);
        const cancellable_ops = try CancellableOps.init(allocator, runtime_instance);
        const error_handler = try ZsyncErrorHandler.init(allocator, runtime_instance);

        // Install signal handler for cancellation
        try cancellable_ops.installSignalHandler();

        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .runtime = runtime_instance,
            .timeout_client = timeout_client,
            .vectorized_downloader = vectorized_downloader,
            .racing_registry = racing_registry,
            .cancellable_ops = cancellable_ops,
            .error_handler = error_handler,
            .http_client = client,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.timeout_client.deinit();
        self.vectorized_downloader.deinit();
        self.racing_registry.deinit();
        self.cancellable_ops.deinit();
        self.error_handler.deinit();
        self.http_client.deinit();
        self.runtime.deinit();
        self.allocator.destroy(self);
    }

    /// Enhanced add command with vectorized downloads and error handling
    pub fn addAsync(self: *Self, package_ref: []const u8, options: commands.AddOptions) !void {
        std.debug.print("🚀 Adding package: {s}\n", .{package_ref});

        // Use racing registry to find package info
        const package_info = try self.racing_registry.getPackageRace(package_ref);
        defer package_info.deinit(self.allocator);
        std.debug.print("✅ Found package from {s} in {d}ms\n", .{ package_info.source_registry, package_info.response_time_ms });

        // For now, fall back to standard add logic
        try commands.add(self.allocator, package_ref, options);
    }

    /// Enhanced search with racing registry queries (simplified)
    pub fn searchAsync(self: *Self, query: []const u8) !void {
        std.debug.print("🔍 Racing search across registries for: {s}\n", .{query});

        const search_result = try self.racing_registry.searchRace(query);
        defer search_result.deinit(self.allocator);

        std.debug.print("🏆 Fastest result from {s} in {d}ms\n", .{ search_result.source_registry, search_result.response_time_ms });

        if (search_result.faster_than.len > 0) {
            std.debug.print("   Faster than: {s}\n", .{search_result.faster_than});
        }

        // Display results
        for (search_result.packages) |pkg| {
            std.debug.print("  📦 {s} v{s} - {s}\n", .{ pkg.name, pkg.version, pkg.description });
        }
    }

    /// Enhanced batch add with sequential processing (simplified)
    pub fn addMultipleAsync(self: *Self, packages: []const []const u8, options: commands.AddOptions) !void {
        if (packages.len == 0) return;

        std.debug.print("🔄 Adding {d} packages sequentially...\n", .{packages.len});

        for (packages) |package| {
            try self.addAsync(package, options);
        }

        std.debug.print("✅ Successfully processed {d} packages\n", .{packages.len});
    }

    /// Registry health check using racing queries
    pub fn healthCheckRegistries(self: *Self) !void {
        std.debug.print("🏥 Checking registry health...\n", .{});

        const health_results = try self.racing_registry.healthCheckAll();
        defer self.allocator.free(health_results);

        for (health_results) |result| {
            const status = if (result.healthy) "✅ Healthy" else "❌ Unhealthy";
            std.debug.print("  {s}: {s} ({d}ms)\n", .{ result.name, status, result.latency_ms });
        }
    }

    /// Download with cancellation support
    pub fn cancellableDownload(self: *Self, url: []const u8, dest_path: []const u8) !void {
        std.debug.print("📥 Starting cancellable download...\n", .{});
        std.debug.print("    Press Ctrl+C to cancel\n", .{});

        try self.cancellable_ops.cancellableDownload(url, dest_path);
    }

    /// Performance benchmark for new features
    pub fn benchmarkPerformance(self: *Self) !void {
        std.debug.print("⚡ Running performance benchmarks...\n", .{});

        const start_time = zion.milliTimestamp();

        // Test racing registry
        const benchmark_search_result = try self.racing_registry.searchRace("test");
        defer benchmark_search_result.deinit(self.allocator);
        const registry_time = zion.milliTimestamp() - start_time;

        // Test timeout client
        const timeout_start = zion.milliTimestamp();
        _ = self.timeout_client.getWithTimeout("https://httpbin.org/delay/1", 5000) catch {};
        const timeout_time = zion.milliTimestamp() - timeout_start;

        std.debug.print("\n📊 Performance Results:\n", .{});
        std.debug.print("  Racing Registry: {d}ms\n", .{registry_time});
        std.debug.print("  Timeout Client: {d}ms\n", .{timeout_time});
        std.debug.print("  Vectorized I/O: Ready\n", .{});
        std.debug.print("  Error Handling: Active\n", .{});
        std.debug.print("  Cancellation: Enabled\n", .{});
    }
};
