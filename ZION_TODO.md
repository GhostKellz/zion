# 🚀 Zion Registry Integration TODO

> **Changes needed in Zion to support custom package registries like Zepplin**

This document outlines the exact modifications needed in Zion to enable seamless integration with custom package registries while maintaining full backward compatibility with GitHub.

---

## 🎯 **Overview**

Currently, Zion is hardcoded to use GitHub's API (`api.github.com`). To support custom registries like Zepplin, we need to:

1. **Add registry configuration support** via environment variables
2. **Make API endpoints configurable** instead of hardcoded
3. **Add fallback registry support** for availability/package discovery
4. **Enhance error handling** for registry failures
5. **Add registry detection** and capability discovery

---

## 🔧 **Phase 1: Environment Variable Support**

### **1.1 Update `enhanced_config.zig`**

Add registry configuration fields to the `ZionConfig` struct:

```zig
// Add to ZionConfig struct (around line 10):
// Registry settings
registry_url: ?[]const u8 = null,
fallback_registries: std.ArrayList([]const u8),
registry_timeout_sec: u32 = 30,
registry_retries: u32 = 3,
prefer_registry_over_github: bool = true,

// Initialize in init() method (around line 35):
pub fn init(allocator: Allocator) ZionConfig {
    var config = ZionConfig{
        .github_orgs = std.ArrayList([]const u8).init(allocator),
        .dependency_aliases = std.StringHashMap(std.ArrayList([]const u8)).init(allocator),
        .fallback_registries = std.ArrayList([]const u8).init(allocator), // ADD THIS
        .allocator = allocator,
        .trust_level_required = "medium",
    };
    
    // Set up default aliases
    config.setupDefaultAliases() catch {};
    
    return config;
}

// Update deinit() method (around line 45):
pub fn deinit(self: *ZionConfig) void {
    // ...existing code...
    
    // Add cleanup for fallback registries
    for (self.fallback_registries.items) |registry| {
        self.allocator.free(registry);
    }
    self.fallback_registries.deinit();
    
    // Clean up registry_url if allocated
    if (self.registry_url) |url| {
        self.allocator.free(url);
    }
    
    // ...existing code...
}
```

### **1.2 Add Registry Environment Variables**

Update the `loadFromEnvironment()` method (around line 100):

```zig
/// Load configuration from environment variables
fn loadFromEnvironment(self: *ZionConfig) !void {
    // ...existing code...
    
    // Registry configuration
    if (std.posix.getenv("ZION_REGISTRY_URL")) |url| {
        self.registry_url = try self.allocator.dupe(u8, url);
        std.debug.print("🔧 Using custom registry: {s}\n", .{url});
    }
    
    // Fallback registries (comma-separated)
    if (std.posix.getenv("ZION_FALLBACK_REGISTRIES")) |registries_str| {
        var it = std.mem.splitScalar(u8, registries_str, ',');
        while (it.next()) |registry| {
            const trimmed = std.mem.trim(u8, registry, " ");
            if (trimmed.len > 0) {
                try self.fallback_registries.append(try self.allocator.dupe(u8, trimmed));
            }
        }
    } else {
        // Default fallback to GitHub
        try self.fallback_registries.append(try self.allocator.dupe(u8, "https://api.github.com"));
    }
    
    // Registry timeout
    if (std.posix.getenv("ZION_REGISTRY_TIMEOUT")) |val| {
        self.registry_timeout_sec = std.fmt.parseInt(u32, val, 10) catch 30;
    }
    
    // Registry retries
    if (std.posix.getenv("ZION_REGISTRY_RETRIES")) |val| {
        self.registry_retries = std.fmt.parseInt(u32, val, 10) catch 3;
    }
    
    // Prefer registry over GitHub
    if (std.posix.getenv("ZION_PREFER_REGISTRY")) |val| {
        self.prefer_registry_over_github = std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "1");
    }
    
    // ...existing code...
}
```

---

## 🌐 **Phase 2: Configurable API Endpoints**

### **2.1 Create Registry Abstraction (`src/registry.zig`)**

Create a new file to handle different registry types:

```zig
const std = @import("std");
const http = std.http;
const json = std.json;
const Allocator = std.mem.Allocator;
const ZionConfig = @import("enhanced_config.zig").ZionConfig;

pub const RegistryType = enum {
    github,
    zepplin,
    custom,
    
    pub fn fromUrl(url: []const u8) RegistryType {
        if (std.mem.indexOf(u8, url, "api.github.com")) |_| {
            return .github;
        } else if (std.mem.indexOf(u8, url, "/api/v1")) |_| {
            return .zepplin; // Assume Zepplin-compatible
        }
        return .custom;
    }
};

pub const RegistryClient = struct {
    allocator: Allocator,
    base_url: []const u8,
    registry_type: RegistryType,
    timeout_sec: u32,
    
    pub fn init(allocator: Allocator, base_url: []const u8, timeout_sec: u32) RegistryClient {
        return RegistryClient{
            .allocator = allocator,
            .base_url = base_url,
            .registry_type = RegistryType.fromUrl(base_url),
            .timeout_sec = timeout_sec,
        };
    }
    
    /// Build API URL for releases endpoint
    pub fn getReleasesUrl(self: *const RegistryClient, owner: []const u8, repo: []const u8) ![]const u8 {
        return switch (self.registry_type) {
            .github => try std.fmt.allocPrint(self.allocator, "{s}/repos/{s}/{s}/releases", .{ self.base_url, owner, repo }),
            .zepplin => try std.fmt.allocPrint(self.allocator, "{s}/packages/{s}/{s}/releases", .{ self.base_url, owner, repo }),
            .custom => try std.fmt.allocPrint(self.allocator, "{s}/repos/{s}/{s}/releases", .{ self.base_url, owner, repo }), // Default to GitHub format
        };
    }
    
    /// Build API URL for tags endpoint  
    pub fn getTagsUrl(self: *const RegistryClient, owner: []const u8, repo: []const u8) ![]const u8 {
        return switch (self.registry_type) {
            .github => try std.fmt.allocPrint(self.allocator, "{s}/repos/{s}/{s}/tags", .{ self.base_url, owner, repo }),
            .zepplin => try std.fmt.allocPrint(self.allocator, "{s}/packages/{s}/{s}/tags", .{ self.base_url, owner, repo }),
            .custom => try std.fmt.allocPrint(self.allocator, "{s}/repos/{s}/{s}/tags", .{ self.base_url, owner, repo }),
        };
    }
    
    /// Build API URL for search endpoint
    pub fn getSearchUrl(self: *const RegistryClient, query: []const u8) ![]const u8 {
        return switch (self.registry_type) {
            .github => try std.fmt.allocPrint(self.allocator, "{s}/search/repositories?q={s}+language:zig&sort=stars&order=desc&per_page=10", .{ self.base_url, query }),
            .zepplin => try std.fmt.allocPrint(self.allocator, "{s}/search?q={s}&language=zig&sort=stars&order=desc&per_page=10", .{ self.base_url, query }),
            .custom => try std.fmt.allocPrint(self.allocator, "{s}/search/repositories?q={s}+language:zig", .{ self.base_url, query }),
        };
    }
    
    /// Check if registry supports alias resolution
    pub fn supportsAliases(self: *const RegistryClient) bool {
        return self.registry_type == .zepplin;
    }
    
    /// Get alias resolution URL (Zepplin-specific)
    pub fn getAliasUrl(self: *const RegistryClient, short_name: []const u8) ![]const u8 {
        if (!self.supportsAliases()) return error.AliasNotSupported;
        return try std.fmt.allocPrint(self.allocator, "{s}/resolve/{s}", .{ self.base_url, short_name });
    }
};

/// Get the primary registry client from config
pub fn getPrimaryRegistry(allocator: Allocator, config: *const ZionConfig) RegistryClient {
    const base_url = config.registry_url orelse "https://api.github.com";
    return RegistryClient.init(allocator, base_url, config.registry_timeout_sec);
}

/// Get fallback registry clients
pub fn getFallbackRegistries(allocator: Allocator, config: *const ZionConfig) ![]RegistryClient {
    var registries = std.ArrayList(RegistryClient).init(allocator);
    
    for (config.fallback_registries.items) |registry_url| {
        try registries.append(RegistryClient.init(allocator, registry_url, config.registry_timeout_sec));
    }
    
    return try registries.toOwnedSlice();
}
```

### **2.2 Update `github.zig` to use Registry Abstraction**

Replace hardcoded URLs with configurable registry support:

```zig
// Add imports at the top
const registry = @import("registry.zig");
const enhanced_config = @import("enhanced_config.zig");

// Replace the existing fetchPackageVersions function (around line 45):
pub fn fetchPackageVersions(allocator: Allocator, package_ref: []const u8) ![]PackageVersion {
    // Load config to get registry settings
    var config = enhanced_config.ZionConfig.load(allocator) catch enhanced_config.ZionConfig.init(allocator);
    defer config.deinit();
    
    // Validate package reference format
    const slash_index = std.mem.indexOf(u8, package_ref, "/") orelse return error.InvalidPackageReference;
    const owner = package_ref[0..slash_index];
    const repo = package_ref[slash_index + 1..];
    
    var versions = std.ArrayList(PackageVersion).init(allocator);
    errdefer {
        for (versions.items) |*version| {
            version.deinit(allocator);
        }
        versions.deinit();
    }
    
    // Try primary registry first
    const primary_registry = registry.getPrimaryRegistry(allocator, &config);
    if (tryFetchFromRegistry(allocator, &primary_registry, owner, repo, &versions)) {
        return try versions.toOwnedSlice();
    } else |err| {
        std.debug.print("⚠️ Primary registry failed: {}\n", .{err});
    }
    
    // Try fallback registries
    const fallback_registries = try registry.getFallbackRegistries(allocator, &config);
    defer allocator.free(fallback_registries);
    
    for (fallback_registries) |fallback_registry| {
        if (tryFetchFromRegistry(allocator, &fallback_registry, owner, repo, &versions)) {
            return try versions.toOwnedSlice();
        } else |err| {
            std.debug.print("⚠️ Fallback registry failed: {}\n", .{err});
        }
    }
    
    return error.NoRegistriesAvailable;
}

// New helper function to try fetching from a specific registry
fn tryFetchFromRegistry(allocator: Allocator, reg: *const registry.RegistryClient, owner: []const u8, repo: []const u8, versions: *std.ArrayList(PackageVersion)) !void {
    // First try to get releases
    if (fetchReleasesFromRegistry(allocator, reg, owner, repo)) |releases| {
        defer {
            for (releases) |*release| {
                release.deinit(allocator);
            }
            allocator.free(releases);
        }
        
        // Add releases as versions
        for (releases) |release| {
            if (!release.prerelease) {
                try versions.append(PackageVersion{
                    .version = try allocator.dupe(u8, release.tag_name),
                    .url = try allocator.dupe(u8, release.tarball_url),
                    .is_tag = false,
                });
            }
        }
    } else |_| {
        // If releases fail, fall back to tags
        if (fetchTagsFromRegistry(allocator, reg, owner, repo)) |tags| {
            defer {
                for (tags) |*tag| {
                    tag.deinit(allocator);
                }
                allocator.free(tags);
            }
            
            // Add tags as versions
            for (tags) |tag| {
                try versions.append(PackageVersion{
                    .version = try allocator.dupe(u8, tag.name),
                    .url = try allocator.dupe(u8, tag.tarball_url),
                    .is_tag = true,
                });
            }
        } else |_| {
            return error.RegistryUnavailable;
        }
    }
}

// Update fetchReleases to use registry client (around line 160):
fn fetchReleasesFromRegistry(allocator: Allocator, reg: *const registry.RegistryClient, owner: []const u8, repo: []const u8) ![]GitHubRelease {
    const url = try reg.getReleasesUrl(owner, repo);
    defer allocator.free(url);
    
    // ...rest of the existing HTTP request logic...
    // (keep the existing HTTP client code, just use the dynamic URL)
}

// Update fetchTags to use registry client (around line 210):
fn fetchTagsFromRegistry(allocator: Allocator, reg: *const registry.RegistryClient, owner: []const u8, repo: []const u8) ![]GitHubTag {
    const url = try reg.getTagsUrl(owner, repo);
    defer allocator.free(url);
    
    // ...rest of the existing HTTP request logic...
    // (keep the existing HTTP client code, just use the dynamic URL)
}
```

---

## 🔍 **Phase 3: Enhanced Package Resolution**

### **3.1 Add Alias Resolution Support**

Update `commands/add.zig` to check for registry-based alias resolution:

```zig
// Update the addSingleDependency function (around line 40):
fn addSingleDependency(allocator: Allocator, package_ref: []const u8, config: *enhanced_config.ZionConfig) !void {
    var resolved_package: []const u8 = package_ref;
    var should_free_resolved = false;
    
    const slash_index = std.mem.indexOf(u8, package_ref, "/");
    if (slash_index == null) {
        // This is a short name, try multiple resolution methods
        
        // 1. Try local config resolution first
        if (config.resolvePackageName(package_ref)) |local_resolved| {
            resolved_package = local_resolved;
            should_free_resolved = true;
            std.debug.print("🔍 Resolved '{s}' to '{s}' (local config)\n", .{ package_ref, resolved_package });
        } 
        // 2. Try registry-based resolution
        else if (tryRegistryAliasResolution(allocator, package_ref, config)) |registry_resolved| {
            resolved_package = registry_resolved;
            should_free_resolved = true;
            std.debug.print("🔍 Resolved '{s}' to '{s}' (registry)\n", .{ package_ref, resolved_package });
        } 
        // 3. Fall back to error
        else {
            std.debug.print("❌ Cannot resolve '{s}'. Options:\n", .{package_ref});
            std.debug.print("  • Use format 'user/repo'\n", .{});
            std.debug.print("  • Configure your GitHub username: zion config set github_username your-username\n", .{});
            std.debug.print("  • Use a registry that supports aliases\n", .{});
            return error.InvalidPackageReference;
        }
    }
    defer if (should_free_resolved) allocator.free(resolved_package);
    
    // ...rest of existing function...
}

// New function to try registry alias resolution
fn tryRegistryAliasResolution(allocator: Allocator, short_name: []const u8, config: *enhanced_config.ZionConfig) ?[]const u8 {
    const reg = registry.getPrimaryRegistry(allocator, config);
    
    if (!reg.supportsAliases()) {
        return null;
    }
    
    const alias_url = reg.getAliasUrl(short_name) catch return null;
    defer allocator.free(alias_url);
    
    // Make HTTP request to resolve alias
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();
    
    var req = client.open(.GET, std.Uri.parse(alias_url) catch return null, .{
        .server_header_buffer = &[_]u8{0} ** 16384,
    }) catch return null;
    defer req.deinit();
    
    req.send() catch return null;
    req.finish() catch return null;
    req.wait() catch return null;
    
    if (req.response.status != .ok) {
        return null;
    }
    
    const body = req.reader().readAllAlloc(allocator, 1024 * 1024) catch return null;
    defer allocator.free(body);
    
    // Parse JSON response: {"short_name": "zcrypto", "full_name": "cktech/zcrypto", "resolved": true}
    const parsed = std.json.parseFromSlice(struct {
        short_name: []const u8,
        full_name: []const u8,
        resolved: bool,
    }, allocator, body, .{}) catch return null;
    defer parsed.deinit();
    
    if (parsed.value.resolved) {
        return allocator.dupe(u8, parsed.value.full_name) catch null;
    }
    
    return null;
}
```

### **3.2 Update Search Command**

Update `commands/search.zig` to use multiple registries:

```zig
// Add import at the top
const registry = @import("../registry.zig");
const enhanced_config = @import("../enhanced_config.zig");

// Replace searchGitHub function with searchRegistries (around line 40):
fn searchRegistries(allocator: Allocator, term: []const u8) !void {
    var config = enhanced_config.ZionConfig.load(allocator) catch enhanced_config.ZionConfig.init(allocator);
    defer config.deinit();
    
    std.debug.print("\n🔍 Registry Search Results:\n", .{});
    
    // Search primary registry
    const primary_registry = registry.getPrimaryRegistry(allocator, &config);
    std.debug.print("\n📦 Primary Registry ({s}):\n", .{primary_registry.base_url});
    trySearchRegistry(allocator, &primary_registry, term) catch |err| {
        std.debug.print("⚠️ Primary registry search failed: {}\n", .{err});
    };
    
    // Search fallback registries
    const fallback_registries = try registry.getFallbackRegistries(allocator, &config);
    defer allocator.free(fallback_registries);
    
    for (fallback_registries) |fallback_registry| {
        std.debug.print("\n📦 Fallback Registry ({s}):\n", .{fallback_registry.base_url});
        trySearchRegistry(allocator, &fallback_registry, term) catch |err| {
            std.debug.print("⚠️ Fallback registry search failed: {}\n", .{err});
        };
    }
}

fn trySearchRegistry(allocator: Allocator, reg: *const registry.RegistryClient, term: []const u8) !void {
    const search_url = try reg.getSearchUrl(term);
    defer allocator.free(search_url);
    
    // ...existing HTTP request logic with the dynamic URL...
}

// Update the main search function (around line 25):
pub fn search(allocator: Allocator, args: []const []const u8) !void {
    if (args.len < 3) {
        std.debug.print("Error: 'zion search' requires a search term\n", .{});
        std.debug.print("Usage: zion search <term>\n", .{});
        std.debug.print("Example: zion search json\n", .{});
        return;
    }

    const search_term = args[2];
    std.debug.print("🔍 Searching for packages matching '{s}'...\n", .{search_term});

    // Search multiple registries
    try searchRegistries(allocator, search_term);
    try searchZigPackageIndex(allocator, search_term);
    try searchAwesome(allocator, search_term);
}
```

---

## 🛠️ **Phase 4: Enhanced CLI Commands**

### **4.1 Add Registry Configuration Commands**

Create `commands/registry.zig`:

```zig
const std = @import("std");
const enhanced_config = @import("../enhanced_config.zig");
const registry = @import("../registry.zig");

pub fn registryCommand(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 3) {
        try showRegistryHelp();
        return;
    }
    
    const subcommand = args[2];
    
    if (std.mem.eql(u8, subcommand, "list")) {
        try listRegistries(allocator);
    } else if (std.mem.eql(u8, subcommand, "add")) {
        if (args.len < 4) {
            std.debug.print("Usage: zion registry add <url>\n", .{});
            return;
        }
        try addRegistry(allocator, args[3]);
    } else if (std.mem.eql(u8, subcommand, "remove")) {
        if (args.len < 4) {
            std.debug.print("Usage: zion registry remove <url>\n", .{});
            return;
        }
        try removeRegistry(allocator, args[3]);
    } else if (std.mem.eql(u8, subcommand, "test")) {
        if (args.len >= 4) {
            try testRegistry(allocator, args[3]);
        } else {
            try testAllRegistries(allocator);
        }
    } else {
        try showRegistryHelp();
    }
}

fn showRegistryHelp() !void {
    std.debug.print(
        \\Registry Management Commands:
        \\
        \\  zion registry list              List configured registries
        \\  zion registry add <url>         Add a fallback registry
        \\  zion registry remove <url>      Remove a fallback registry  
        \\  zion registry test [url]        Test registry connectivity
        \\
        \\Environment Variables:
        \\  ZION_REGISTRY_URL              Primary registry URL
        \\  ZION_FALLBACK_REGISTRIES       Comma-separated fallback URLs
        \\  ZION_REGISTRY_TIMEOUT          Request timeout in seconds
        \\
        \\Examples:
        \\  zion registry add https://packages.company.com
        \\  zion registry test https://api.github.com
        \\
    );
}

fn listRegistries(allocator: std.mem.Allocator) !void {
    var config = enhanced_config.ZionConfig.load(allocator) catch enhanced_config.ZionConfig.init(allocator);
    defer config.deinit();
    
    std.debug.print("🔧 Registry Configuration:\n\n", .{});
    
    const primary_url = config.registry_url orelse "https://api.github.com";
    std.debug.print("📍 Primary: {s}\n", .{primary_url});
    
    if (config.fallback_registries.items.len > 0) {
        std.debug.print("🔄 Fallbacks:\n", .{});
        for (config.fallback_registries.items) |fallback| {
            std.debug.print("  • {s}\n", .{fallback});
        }
    } else {
        std.debug.print("🔄 Fallbacks: None configured\n", .{});
    }
    
    std.debug.print("\n💡 Use environment variables to configure:\n", .{});
    std.debug.print("   export ZION_REGISTRY_URL=https://your-registry.com\n", .{});
}

fn testRegistry(allocator: std.mem.Allocator, url: []const u8) !void {
    std.debug.print("🧪 Testing registry: {s}\n", .{url});
    
    const reg = registry.RegistryClient.init(allocator, url, 10);
    
    // Test basic connectivity by trying to fetch a well-known endpoint
    const test_url = switch (reg.registry_type) {
        .github => try std.fmt.allocPrint(allocator, "{s}/rate_limit", .{url}),
        .zepplin => try std.fmt.allocPrint(allocator, "{s}/registry/config", .{url}),
        .custom => try std.fmt.allocPrint(allocator, "{s}/", .{url}),
    };
    defer allocator.free(test_url);
    
    // Make HTTP request
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();
    
    var req = client.open(.GET, std.Uri.parse(test_url) catch {
        std.debug.print("❌ Invalid URL format\n", .{});
        return;
    }, .{
        .server_header_buffer = &[_]u8{0} ** 4096,
    }) catch {
        std.debug.print("❌ Connection failed\n", .{});
        return;
    };
    defer req.deinit();
    
    req.send() catch {
        std.debug.print("❌ Request failed\n", .{});
        return;
    };
    req.finish() catch {
        std.debug.print("❌ Request finish failed\n", .{});
        return;
    };
    req.wait() catch {
        std.debug.print("❌ Request wait failed\n", .{});
        return;
    };
    
    std.debug.print("✅ Registry responding (Status: {})\n", .{req.response.status});
    std.debug.print("🔧 Registry type: {}\n", .{reg.registry_type});
    
    if (reg.supportsAliases()) {
        std.debug.print("🏷️  Supports package aliases\n", .{});
    }
}

fn testAllRegistries(allocator: std.mem.Allocator) !void {
    var config = enhanced_config.ZionConfig.load(allocator) catch enhanced_config.ZionConfig.init(allocator);
    defer config.deinit();
    
    std.debug.print("🧪 Testing all configured registries...\n\n", .{});
    
    // Test primary registry
    const primary_url = config.registry_url orelse "https://api.github.com";
    try testRegistry(allocator, primary_url);
    
    // Test fallback registries
    for (config.fallback_registries.items) |fallback| {
        std.debug.print("\n", .{});
        try testRegistry(allocator, fallback);
    }
}
```

### **4.2 Update Main CLI to Include Registry Commands**

Update `main.zig` to include the new registry command:

```zig
// Add import at the top (around line 4):
const registry_cmd = @import("commands/registry.zig");

// Add to the command handling section (around line 50):
} else if (std.mem.eql(u8, command, "registry")) {
    try registry_cmd.registryCommand(allocator, args);
} else if (std.mem.eql(u8, command, "search")) {
```

### **4.3 Update Help Command**

Update `commands/help.zig` to include registry commands:

```zig
// Add to the help text (around line 20):
\\
\\Registry Management:
\\  registry list              List configured registries
\\  registry add <url>         Add a fallback registry
\\  registry remove <url>      Remove a fallback registry
\\  registry test [url]        Test registry connectivity
\\
\\Environment Variables:
\\  ZION_REGISTRY_URL          Primary registry URL (e.g., http://localhost:8080)
\\  ZION_FALLBACK_REGISTRIES   Comma-separated fallback URLs
\\  ZION_REGISTRY_TIMEOUT      Request timeout in seconds (default: 30)
\\  ZION_PREFER_REGISTRY       Prefer registry over GitHub (true/false)
\\
```

---

## 🔒 **Phase 5: Error Handling & Resilience**

### **5.1 Add Retry Logic**

Create `src/http_utils.zig` for robust HTTP requests:

```zig
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
```

### **5.2 Update Registry Client to Use Resilient Requests**

Update `registry.zig` to use the new HTTP utils:

```zig
// Add import at the top
const http_utils = @import("http_utils.zig");

// Add to RegistryClient struct:
pub fn makeRequest(self: *const RegistryClient, allocator: Allocator, url: []const u8) ![]u8 {
    return http_utils.makeResilientRequest(allocator, url, 3, self.timeout_sec);
}
```

---

## 📝 **Phase 6: Documentation & Usage**

### **6.1 Update README.md**

Add a section about registry configuration:

```markdown
## 🔧 Registry Configuration

Zion supports custom package registries in addition to GitHub. This enables private registries, faster package resolution, and enhanced features like package aliases.

### Environment Variables

```bash
# Primary registry (will be checked first)
export ZION_REGISTRY_URL="http://localhost:8080"

# Fallback registries (comma-separated, GitHub is default fallback)
export ZION_FALLBACK_REGISTRIES="https://api.github.com,https://alt-registry.com"

# Registry timeout in seconds
export ZION_REGISTRY_TIMEOUT=30

# Number of retry attempts
export ZION_REGISTRY_RETRIES=3

# Prefer registry over GitHub for package resolution
export ZION_PREFER_REGISTRY=true
```

### Registry Management Commands

```bash
# List configured registries
zion registry list

# Test registry connectivity
zion registry test http://localhost:8080

# Test all configured registries
zion registry test

# Add a fallback registry
zion registry add https://packages.company.com
```

### Compatible Registries

- **GitHub** (default): `https://api.github.com`
- **Zepplin**: Any URL ending with `/api/v1` (supports aliases)
- **Custom**: Any GitHub-compatible API

### Example Usage

```bash
# Use Zepplin registry
export ZION_REGISTRY_URL="http://localhost:8080"
zion add zcrypto  # Resolves via registry aliases

# Fallback to GitHub if registry is unavailable
zion add mitchellh/libxev  # Will try registry first, then GitHub
```
```

### **6.2 Create Migration Guide**

Create `REGISTRY_MIGRATION.md`:

```markdown
# 🔄 Registry Migration Guide

## Migrating from GitHub-only to Custom Registry

### 1. Current Usage (GitHub only)
```bash
zion add mitchellh/libxev
zion add karlseguin/httpz
```

### 2. With Custom Registry (backward compatible)
```bash
# Set up registry
export ZION_REGISTRY_URL="http://localhost:8080"

# All existing commands work the same
zion add mitchellh/libxev  # Tries registry first, falls back to GitHub
zion add karlseguin/httpz

# New features available
zion add zcrypto           # Short names via registry aliases
zion registry list         # Show configured registries
```

### 3. Registry Priority Order

1. **Primary Registry**: `ZION_REGISTRY_URL` (if set)
2. **Fallback Registries**: `ZION_FALLBACK_REGISTRIES` (comma-separated)
3. **Default Fallback**: GitHub (always available)

### 4. Error Handling

- If primary registry fails → try fallback registries
- If all registries fail → clear error message with suggestions
- Network timeouts → automatic retry with exponential backoff
```

---

## ✅ **Implementation Checklist**

### **Phase 1: Environment Variables** 
- [ ] Add registry fields to `ZionConfig`
- [ ] Implement environment variable loading
- [ ] Update config initialization and cleanup
- [ ] Test environment variable parsing

### **Phase 2: Registry Abstraction**
- [ ] Create `registry.zig` with `RegistryClient` 
- [ ] Implement URL building for different registry types
- [ ] Add registry type detection
- [ ] Test URL generation for GitHub vs Zepplin

### **Phase 3: Update Core Functions**
- [ ] Modify `github.zig` to use configurable URLs
- [ ] Add fallback registry support in package fetching
- [ ] Implement alias resolution for Zepplin registries
- [ ] Update search to use multiple registries

### **Phase 4: CLI Enhancements**
- [ ] Create `commands/registry.zig`
- [ ] Add registry management commands
- [ ] Update main CLI router
- [ ] Update help text

### **Phase 5: Error Handling**
- [ ] Create `http_utils.zig` with retry logic
- [ ] Add timeout handling
- [ ] Improve error messages
- [ ] Add connection testing

### **Phase 6: Documentation**
- [ ] Update README with registry configuration
- [ ] Create migration guide
- [ ] Add troubleshooting section
- [ ] Update command examples

---

## 🧪 **Testing Commands**

After implementing these changes, test with:

```bash
# Test GitHub compatibility (should work as before)
zion add mitchellh/libxev

# Test custom registry
export ZION_REGISTRY_URL="http://localhost:8080"
zion registry test
zion add zcrypto  # Should resolve via registry

# Test fallback behavior
export ZION_REGISTRY_URL="http://invalid-registry.com"
zion add mitchellh/libxev  # Should fall back to GitHub

# Test registry management
zion registry list
zion registry add https://packages.company.com
```

---

## 🎯 **Success Criteria**

1. ✅ **Backward Compatibility**: All existing `zion` commands work exactly as before
2. ✅ **Custom Registry Support**: Can use `ZION_REGISTRY_URL` to point to Zepplin
3. ✅ **Fallback Behavior**: Gracefully falls back to GitHub if custom registry fails
4. ✅ **Alias Resolution**: Can resolve short names like `zcrypto` via registry
5. ✅ **Error Resilience**: Proper error handling and retry logic
6. ✅ **Registry Management**: CLI commands to manage and test registries

This implementation makes Zion **registry-agnostic** while maintaining full backward compatibility with GitHub-based workflows.
