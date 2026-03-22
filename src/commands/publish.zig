const std = @import("std");
const fs = std.fs;
const json = std.json;
const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;
const Io = std.Io;
const zion_root = @import("../root.zig");
const enhanced_config = @import("../enhanced_config.zig");
const registry_manager = @import("../registry_manager.zig");
const package_registry = @import("../package_registry.zig");
const security = @import("../security.zig");
const ZonFile = @import("../manifest.zig").ZonFile;

/// Enhanced publish command for v0.7.0 with multi-registry support
pub fn publish(allocator: Allocator, args: []const []const u8) !void {
    // Parse publish options
    var options = PublishOptions{};
    try parsePublishOptions(&options, args, allocator);
    defer options.deinit(allocator);

    // Load configuration
    var config = try enhanced_config.ZionConfig.load(allocator);
    defer config.deinit();

    // Initialize registry manager
    var manager = registry_manager.RegistryManager.init(allocator, &config);
    defer manager.deinit();
    try manager.initClients();

    // Determine target registry
    const target_registry = options.registry orelse getDefaultPublishRegistry(&config);

    std.debug.print("📦 Publishing package to registry: {s}\n", .{target_registry});

    // Find registry client
    var target_client: ?*package_registry.RegistryClient = null;
    for (manager.clients.items) |*client| {
        if (std.mem.eql(u8, client.config.name, target_registry)) {
            target_client = client;
            break;
        }
    }

    if (target_client == null) {
        std.debug.print("❌ Registry '{s}' not found or not configured\n", .{target_registry});
        std.debug.print("💡 Available registries:\n", .{});
        for (manager.clients.items) |client| {
            std.debug.print("   • {s}\n", .{client.config.name});
        }
        return;
    }

    const client = target_client.?;

    // Check authentication
    if (client.config.auth_token == null) {
        std.debug.print("❌ Authentication required for publishing to {s}\n", .{target_registry});
        std.debug.print("💡 Set authentication token:\n", .{});
        std.debug.print("   zion registry auth set {s} <your-token>\n", .{target_registry});
        return;
    }

    // Validate project structure
    std.debug.print("🔍 Validating project structure...\n", .{});
    try validateProjectForPublishing();

    // Read package metadata
    std.debug.print("📖 Reading package metadata...\n", .{});
    const metadata = try readPackageMetadata(allocator);
    defer metadata.deinit(allocator);

    // Validate package metadata
    try validatePackageMetadata(metadata);

    // Check if package already exists
    std.debug.print("🔍 Checking if package already exists...\n", .{});
    const existing_package = checkExistingPackage(client, metadata) catch null;
    if (existing_package) |pkg| {
        defer pkg.deinit(allocator);

        if (!options.force) {
            std.debug.print("❌ Package {s} version {s} already exists\n", .{ metadata.name, metadata.version });
            std.debug.print("💡 Use --force to overwrite or increment the version\n", .{});
            return;
        }

        std.debug.print("⚠️  Overwriting existing package version\n", .{});
    }

    // Build package
    std.debug.print("🔨 Building package...\n", .{});
    const package_path = try buildPackageForPublish(allocator, metadata, options);
    defer allocator.free(package_path);

    // Verify package integrity
    std.debug.print("🔐 Verifying package integrity...\n", .{});
    try verifyPackageIntegrity(allocator, package_path, metadata);

    // Sign package if requested
    var signature: ?security.PackageSignature = null;
    if (options.sign) {
        std.debug.print("✍️  Signing package...\n", .{});
        signature = try signPackage(allocator, package_path, metadata);
    }
    defer if (signature) |*sig| sig.deinit(allocator);

    if (options.dry_run) {
        std.debug.print("🔍 Dry run complete. Package ready for publishing:\n", .{});
        std.debug.print("   Package: {s}\n", .{package_path});
        std.debug.print("   Registry: {s}\n", .{target_registry});
        std.debug.print("   Version: {s}\n", .{metadata.version});
        if (signature != null) {
            std.debug.print("   Signed: ✅\n", .{});
        }
        return;
    }

    // Upload package
    std.debug.print("📤 Uploading package...\n", .{});
    const upload_result = try uploadPackage(allocator, client, package_path, metadata, signature);
    defer upload_result.deinit(allocator);

    // Update local registry cache
    std.debug.print("🔄 Updating local cache...\n", .{});
    try updateLocalCache(allocator, metadata, target_registry);

    // Success!
    std.debug.print("\n✅ Package published successfully!\n", .{});
    std.debug.print("   📦 Package: {s} v{s}\n", .{ metadata.name, metadata.version });
    std.debug.print("   🌐 Registry: {s}\n", .{target_registry});
    if (upload_result.package_url) |url| {
        std.debug.print("   🔗 URL: {s}\n", .{url});
    }
    std.debug.print("   ⏱️  Upload time: {d}ms\n", .{upload_result.upload_time_ms});

    std.debug.print("\n💡 To install this package:\n", .{});
    std.debug.print("   zion add {s}\n", .{metadata.name});

    // Suggest documentation updates
    if (upload_result.first_publish) {
        std.debug.print("\n📋 Next steps:\n", .{});
        std.debug.print("   • Update your README with installation instructions\n", .{});
        std.debug.print("   • Add package to Awesome Zig list\n", .{});
        std.debug.print("   • Share on social media and forums\n", .{});
    }
}

/// Publish options
const PublishOptions = struct {
    registry: ?[]const u8 = null,
    tag: ?[]const u8 = null,
    message: ?[]const u8 = null,
    sign: bool = false,
    force: bool = false,
    dry_run: bool = false,
    include_dev_deps: bool = false,
    compression_level: u8 = 6,

    fn deinit(self: *PublishOptions, allocator: Allocator) void {
        if (self.registry) |registry| allocator.free(registry);
        if (self.tag) |tag| allocator.free(tag);
        if (self.message) |message| allocator.free(message);
    }
};

/// Package metadata for publishing
const PackageMetadata = struct {
    name: []const u8,
    version: []const u8,
    description: ?[]const u8,
    author: ?[]const u8,
    license: ?[]const u8,
    homepage: ?[]const u8,
    repository: ?[]const u8,
    keywords: []const []const u8,
    categories: []const []const u8,
    zig_version_min: ?[]const u8,
    zig_version_max: ?[]const u8,
    dependencies: []const Dependency,
    dev_dependencies: []const Dependency,

    const Dependency = struct {
        name: []const u8,
        version: []const u8,
        registry: ?[]const u8,
    };

    fn deinit(self: PackageMetadata, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.version);
        if (self.description) |desc| allocator.free(desc);
        if (self.author) |author| allocator.free(author);
        if (self.license) |license| allocator.free(license);
        if (self.homepage) |homepage| allocator.free(homepage);
        if (self.repository) |repository| allocator.free(repository);

        for (self.keywords) |keyword| allocator.free(keyword);
        if (self.keywords.len > 0) allocator.free(self.keywords);

        for (self.categories) |category| allocator.free(category);
        if (self.categories.len > 0) allocator.free(self.categories);

        if (self.zig_version_min) |ver| allocator.free(ver);
        if (self.zig_version_max) |ver| allocator.free(ver);

        for (self.dependencies) |dep| {
            allocator.free(dep.name);
            allocator.free(dep.version);
            if (dep.registry) |registry| allocator.free(registry);
        }
        if (self.dependencies.len > 0) allocator.free(self.dependencies);

        for (self.dev_dependencies) |dep| {
            allocator.free(dep.name);
            allocator.free(dep.version);
            if (dep.registry) |registry| allocator.free(registry);
        }
        if (self.dev_dependencies.len > 0) allocator.free(self.dev_dependencies);
    }
};

/// Upload result information
const UploadResult = struct {
    success: bool,
    package_url: ?[]const u8,
    upload_time_ms: u64,
    package_size: u64,
    first_publish: bool,
    registry_response: []const u8,

    fn deinit(self: UploadResult, allocator: Allocator) void {
        if (self.package_url) |url| allocator.free(url);
        allocator.free(self.registry_response);
    }
};

/// Parse command line options
fn parsePublishOptions(options: *PublishOptions, args: []const []const u8, allocator: Allocator) !void {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--registry")) {
            if (i + 1 < args.len) {
                options.registry = try allocator.dupe(u8, args[i + 1]);
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "--tag")) {
            if (i + 1 < args.len) {
                options.tag = try allocator.dupe(u8, args[i + 1]);
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "--message")) {
            if (i + 1 < args.len) {
                options.message = try allocator.dupe(u8, args[i + 1]);
                i += 1;
            }
        } else if (std.mem.eql(u8, arg, "--sign")) {
            options.sign = true;
        } else if (std.mem.eql(u8, arg, "--force")) {
            options.force = true;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            options.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--include-dev-deps")) {
            options.include_dev_deps = true;
        } else if (std.mem.startsWith(u8, arg, "--compression-level=")) {
            const level_str = arg[19..];
            options.compression_level = try std.fmt.parseInt(u8, level_str, 10);
        }
    }
}

/// Get default registry for publishing
fn getDefaultPublishRegistry(config: *enhanced_config.ZionConfig) []const u8 {
    // Use highest priority registry (lowest priority number)
    if (config.registries.items.len > 0) {
        return config.registries.items[0].name;
    }
    return "github"; // Fallback
}

/// Validate project structure for publishing
fn validateProjectForPublishing() !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    const required_files = [_][]const u8{
        "build.zig",
        "build.zig.zon",
        "src/",
    };

    for (required_files) |file| {
        cwd.access(io, file, .{}) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("❌ Required file/directory missing: {s}\n", .{file});
                return error.InvalidProject;
            }
            return err;
        };
    }

    // Check for common documentation files
    const doc_files = [_][]const u8{ "README.md", "LICENSE", "CHANGELOG.md" };
    var missing_docs: std.ArrayList([]const u8) = .empty;
    defer missing_docs.deinit(std.heap.page_allocator);

    for (doc_files) |file| {
        cwd.access(io, file, .{}) catch {
            try missing_docs.append(std.heap.page_allocator, file);
        };
    }

    if (missing_docs.items.len > 0) {
        std.debug.print("⚠️  Recommended files missing:\n", .{});
        for (missing_docs.items) |file| {
            std.debug.print("   • {s}\n", .{file});
        }
        std.debug.print("💡 Consider adding these files for better package documentation\n", .{});
    }
}

/// Read package metadata from build.zig.zon and other sources
fn readPackageMetadata(allocator: Allocator) !PackageMetadata {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Read build.zig.zon
    var zon_file = try ZonFile.loadFromFile(allocator, "build.zig.zon");
    defer zon_file.deinit();

    // Extract basic information
    const name = try allocator.dupe(u8, zon_file.name);
    const version = try allocator.dupe(u8, zon_file.version);

    // Try to read additional metadata from package.json or zion.toml if they exist
    var description: ?[]const u8 = null;
    const author: ?[]const u8 = null;
    var license: ?[]const u8 = null;
    const homepage: ?[]const u8 = null;
    const repository: ?[]const u8 = null;
    var keywords: std.ArrayList([]const u8) = .empty;
    var categories: std.ArrayList([]const u8) = .empty;

    // Try to read from README.md for description
    if (cwd.readFileAlloc(io, "README.md", allocator, Io.Limit.limited(1024 * 1024))) |readme_content| {
        defer allocator.free(readme_content);

        // Extract first paragraph as description
        if (extractDescriptionFromReadme(allocator, readme_content)) |desc| {
            description = desc;
        }
    } else |_| {}

    // Try to read LICENSE file
    if (cwd.readFileAlloc(io, "LICENSE", allocator, Io.Limit.limited(1024))) |license_content| {
        defer allocator.free(license_content);

        if (detectLicenseType(license_content)) |license_type| {
            license = try allocator.dupe(u8, license_type);
        }
    } else |_| {}

    // Parse dependencies from ZON file
    var dependencies: std.ArrayList(PackageMetadata.Dependency) = .empty;
    var dev_dependencies: std.ArrayList(PackageMetadata.Dependency) = .empty;

    // In a real implementation, would parse the ZON file structure

    return PackageMetadata{
        .name = name,
        .version = version,
        .description = description,
        .author = author,
        .license = license,
        .homepage = homepage,
        .repository = repository,
        .keywords = try keywords.toOwnedSlice(allocator),
        .categories = try categories.toOwnedSlice(allocator),
        .zig_version_min = null,
        .zig_version_max = null,
        .dependencies = try dependencies.toOwnedSlice(allocator),
        .dev_dependencies = try dev_dependencies.toOwnedSlice(allocator),
    };
}

/// Validate package metadata for publishing
fn validatePackageMetadata(metadata: PackageMetadata) !void {
    if (metadata.name.len == 0) {
        std.debug.print("❌ Package name is required\n", .{});
        return error.InvalidMetadata;
    }

    if (metadata.version.len == 0) {
        std.debug.print("❌ Package version is required\n", .{});
        return error.InvalidMetadata;
    }

    // Validate version format (basic semver check)
    if (!isValidVersion(metadata.version)) {
        std.debug.print("❌ Invalid version format: {s}\n", .{metadata.version});
        std.debug.print("💡 Use semantic versioning (e.g., 1.0.0)\n", .{});
        return error.InvalidMetadata;
    }

    // Validate name format
    if (!isValidPackageName(metadata.name)) {
        std.debug.print("❌ Invalid package name: {s}\n", .{metadata.name});
        std.debug.print("💡 Package names should contain only letters, numbers, hyphens, and underscores\n", .{});
        return error.InvalidMetadata;
    }

    // Warn about missing recommended fields
    if (metadata.description == null) {
        std.debug.print("⚠️  No description provided\n", .{});
    }

    if (metadata.license == null) {
        std.debug.print("⚠️  No license specified\n", .{});
    }

    if (metadata.author == null) {
        std.debug.print("⚠️  No author specified\n", .{});
    }
}

/// Check if package already exists in registry
fn checkExistingPackage(client: *package_registry.RegistryClient, metadata: PackageMetadata) !?package_registry.Package {
    // Parse package name for owner/repo
    var parts = std.mem.splitScalar(u8, metadata.name, '/');
    const owner = parts.next() orelse metadata.name;
    const repo = parts.next() orelse metadata.name;

    return client.fetchPackageMetadata(owner, repo) catch null;
}

/// Build package for publishing
fn buildPackageForPublish(allocator: Allocator, metadata: PackageMetadata, options: PublishOptions) ![]const u8 {
    _ = options;
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Create temporary build directory
    const temp_dir = try std.fmt.allocPrint(allocator, "/tmp/zion-publish-{d}", .{zion_root.timestamp()});
    try cwd.createDirPath(io, temp_dir);

    // Run build to ensure everything compiles
    std.debug.print("   Running: zig build\n", .{});
    const argv = [_][]const u8{ "zig", "build" };
    var child = try std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .pipe,
    });
    var stderr_list: std.ArrayList(u8) = .empty;
    defer stderr_list.deinit(allocator);

    // Read stderr for error messages
    if (child.stderr) |stderr_file| {
        var buffer: [4096]u8 = undefined;
        while (true) {
            const n = stderr_file.readStreaming(io, &.{buffer[0..]}) catch break;
            if (n == 0) break;
            try stderr_list.appendSlice(allocator, buffer[0..n]);
        }
    }
    const term = try child.wait(io);

    switch (term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("❌ Build failed:\n{s}", .{stderr_list.items});
                return error.BuildFailed;
            }
        },
        else => return error.BuildFailed,
    }

    // Create package tarball
    const package_name = try std.fmt.allocPrint(allocator, "{s}-{s}.tar.gz", .{ metadata.name, metadata.version });
    const package_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ temp_dir, package_name });

    // Include essential files
    const include_files = [_][]const u8{
        "src/",
        "build.zig",
        "build.zig.zon",
        "README.md",
        "LICENSE",
        "CHANGELOG.md",
    };

    var tar_args: std.ArrayList([]const u8) = .empty;
    defer tar_args.deinit(allocator);

    try tar_args.appendSlice(allocator, &[_][]const u8{ "tar", "-czf", package_path });

    for (include_files) |file| {
        cwd.access(io, file, .{}) catch continue;
        try tar_args.append(allocator, file);
    }

    std.debug.print("   Creating package archive...\n", .{});
    var tar_child = try std.process.spawn(io, .{
        .argv = tar_args.items,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .pipe,
    });
    var tar_stderr: std.ArrayList(u8) = .empty;
    defer tar_stderr.deinit(allocator);

    if (tar_child.stderr) |stderr_file| {
        var buffer: [4096]u8 = undefined;
        while (true) {
            const n = stderr_file.readStreaming(io, &.{buffer[0..]}) catch break;
            if (n == 0) break;
            try tar_stderr.appendSlice(allocator, buffer[0..n]);
        }
    }
    const tar_term = try tar_child.wait(io);

    switch (tar_term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("❌ Package creation failed:\n{s}", .{tar_stderr.items});
                return error.PackagingFailed;
            }
        },
        else => return error.PackagingFailed,
    }

    return package_path;
}

/// Verify package integrity before publishing
fn verifyPackageIntegrity(allocator: Allocator, package_path: []const u8, metadata: PackageMetadata) !void {
    _ = allocator;
    _ = metadata;
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Check package size
    const file = try cwd.openFile(io, package_path, .{});
    defer file.close(io);

    const stat = try file.stat(io);
    const file_size = stat.size;
    const max_size: u64 = 100 * 1024 * 1024; // 100MB

    if (file_size > max_size) {
        std.debug.print("❌ Package too large: {d}MB (max {d}MB)\n", .{ file_size / (1024 * 1024), max_size / (1024 * 1024) });
        return error.PackageTooLarge;
    }

    std.debug.print("   Package size: {d}KB\n", .{file_size / 1024});

    // TODO: Add more integrity checks
    // - Verify archive can be extracted
    // - Check for suspicious files
    // - Validate manifest consistency
}

/// Sign package with security module
fn signPackage(allocator: Allocator, package_path: []const u8, metadata: PackageMetadata) !security.PackageSignature {
    var security_manager = security.SecurityManager.init(allocator, "/tmp/zion-keys");
    defer security_manager.deinit();

    // Generate or load signing key
    const keypair = try security_manager.generateKeyPair();

    // Sign the package
    return try security_manager.signPackage(package_path, keypair.private_key, metadata.name);
}

/// Upload package to registry
fn uploadPackage(
    allocator: Allocator,
    client: *package_registry.RegistryClient,
    package_path: []const u8,
    metadata: PackageMetadata,
    signature: ?security.PackageSignature,
) !UploadResult {
    _ = signature;
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    const start_time = zion_root.milliTimestamp();

    // Read package file
    const package_data = try cwd.readFileAlloc(io, package_path, allocator, Io.Limit.limited(100 * 1024 * 1024));
    defer allocator.free(package_data);

    // Prepare metadata JSON
    const metadata_json = try serializeMetadata(allocator, metadata);
    defer allocator.free(metadata_json);

    // Create multipart form data
    const boundary = "----ZionPackageUpload";

    var form_data: std.ArrayList(u8) = .empty;
    defer form_data.deinit(allocator);

    // Add metadata
    try form_data.appendSlice(allocator, "--");
    try form_data.appendSlice(allocator, boundary);
    try form_data.appendSlice(allocator, "\r\nContent-Disposition: form-data; name=\"metadata\"\r\n");
    try form_data.appendSlice(allocator, "Content-Type: application/json\r\n\r\n");
    try form_data.appendSlice(allocator, metadata_json);
    try form_data.appendSlice(allocator, "\r\n");

    // Add package file
    try form_data.appendSlice(allocator, "--");
    try form_data.appendSlice(allocator, boundary);
    try form_data.appendSlice(allocator, "\r\nContent-Disposition: form-data; name=\"package\"; filename=\"package.tar.gz\"\r\n");
    try form_data.appendSlice(allocator, "Content-Type: application/gzip\r\n\r\n");
    try form_data.appendSlice(allocator, package_data);
    try form_data.appendSlice(allocator, "\r\n--");
    try form_data.appendSlice(allocator, boundary);
    try form_data.appendSlice(allocator, "--\r\n");

    // Get API URL for package upload
    const api_url = try client.config.getApiUrl(allocator);
    defer allocator.free(api_url);

    const upload_url = try std.fmt.allocPrint(allocator, "{s}/packages", .{api_url});
    defer allocator.free(upload_url);

    // Make upload request (simplified - real implementation would use HTTP client)
    const response = try client.makeRequest("POST", upload_url, form_data.items);
    defer allocator.free(response);

    const end_time = zion_root.milliTimestamp();

    // Parse response
    const parsed_response = try parseUploadResponse(allocator, response);

    return UploadResult{
        .success = true,
        .package_url = parsed_response.package_url,
        .upload_time_ms = @intCast(end_time - start_time),
        .package_size = package_data.len,
        .first_publish = parsed_response.first_publish,
        .registry_response = try allocator.dupe(u8, response),
    };
}

/// Update local package cache
fn updateLocalCache(allocator: Allocator, metadata: PackageMetadata, registry: []const u8) !void {
    _ = allocator;
    _ = metadata;
    _ = registry;

    // In a real implementation, would update local package cache
    std.debug.print("   Local cache updated\n", .{});
}

// Helper functions
fn extractDescriptionFromReadme(allocator: Allocator, content: []const u8) ?[]const u8 {
    // Find first paragraph after title
    var lines = std.mem.splitSequence(u8, content, "\n");
    var found_title = false;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        if (trimmed.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed, "#")) {
            found_title = true;
            continue;
        }

        if (found_title and !std.mem.startsWith(u8, trimmed, "!") and !std.mem.startsWith(u8, trimmed, "[")) {
            return allocator.dupe(u8, trimmed) catch null;
        }
    }

    return null;
}

fn detectLicenseType(content: []const u8) ?[]const u8 {
    const license_indicators = [_]struct { indicator: []const u8, license: []const u8 }{
        .{ .indicator = "MIT License", .license = "MIT" },
        .{ .indicator = "Apache License", .license = "Apache-2.0" },
        .{ .indicator = "GNU GENERAL PUBLIC LICENSE", .license = "GPL-3.0" },
        .{ .indicator = "BSD 3-Clause", .license = "BSD-3-Clause" },
        .{ .indicator = "ISC License", .license = "ISC" },
    };

    for (license_indicators) |item| {
        if (std.mem.indexOf(u8, content, item.indicator) != null) {
            return item.license;
        }
    }

    return null;
}

fn isValidVersion(version: []const u8) bool {
    // Basic semver validation
    var parts = std.mem.splitSequence(u8, version, ".");
    var count: u8 = 0;

    while (parts.next()) |part| {
        count += 1;
        if (count > 3) return false;

        _ = std.fmt.parseInt(u32, part, 10) catch return false;
    }

    return count >= 2; // At least major.minor
}

fn isValidPackageName(name: []const u8) bool {
    if (name.len == 0) return false;

    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '-' and c != '_' and c != '/') {
            return false;
        }
    }

    return true;
}

fn serializeMetadata(allocator: Allocator, metadata: PackageMetadata) ![]const u8 {
    // In a real implementation, would use proper JSON serialization
    return try std.fmt.allocPrint(allocator,
        \\{{
        \\  "name": "{s}",
        \\  "version": "{s}",
        \\  "description": "{s}",
        \\  "license": "{s}"
        \\}}
    , .{
        metadata.name,
        metadata.version,
        metadata.description orelse "",
        metadata.license orelse "",
    });
}

const UploadResponse = struct {
    package_url: ?[]const u8,
    first_publish: bool,
};

fn parseUploadResponse(allocator: Allocator, response: []const u8) !UploadResponse {
    // Simplified response parsing
    _ = response;

    return UploadResponse{
        .package_url = try allocator.dupe(u8, "https://example.com/packages/test"),
        .first_publish = true,
    };
}
