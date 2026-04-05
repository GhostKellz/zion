const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;
const Io = std.Io;
const zion_root = @import("../root.zig");
const ZonFile = @import("../manifest.zig").ZonFile;
const LockFile = @import("../lockfile.zig").LockFile;
const downloader = @import("../downloader.zig");
const enhanced_config = @import("../enhanced_config.zig");
const registry_manager = @import("../registry_manager.zig");
const package_registry = @import("../package_registry.zig");
const parallel_downloader = @import("../parallel_downloader.zig");
const security = @import("../security.zig");
const semver = @import("../semver.zig");
const version_resolver = @import("../version_resolver.zig");
const tar_extract = @import("../tar_extract.zig");

/// Result of parsing a GitHub shorthand reference
pub const GitHubShorthand = struct {
    owner: []const u8,
    repo: []const u8,
    ref: ?[]const u8,

    /// Returns the normalized "owner/repo" format
    pub fn toPackageRef(self: GitHubShorthand, allocator: Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}/{s}", .{ self.owner, self.repo });
    }
};

/// Parse GitHub shorthand syntax: gh/owner/repo[@ref] or gh:owner/repo[@ref]
/// Returns null if the input is not a valid shorthand
pub fn parseGitHubShorthand(package_ref: []const u8) ?GitHubShorthand {
    // Check for gh/ or gh: prefix
    const prefix_len: usize = 3;
    if (package_ref.len < prefix_len) return null;

    const has_slash_prefix = mem.startsWith(u8, package_ref, "gh/");
    const has_colon_prefix = mem.startsWith(u8, package_ref, "gh:");

    if (!has_slash_prefix and !has_colon_prefix) return null;

    const rest = package_ref[prefix_len..];

    // Split on @ for optional ref
    var path: []const u8 = undefined;
    var ref: ?[]const u8 = null;

    if (mem.indexOf(u8, rest, "@")) |at_pos| {
        path = rest[0..at_pos];
        ref = rest[at_pos + 1 ..];
        if (ref.?.len == 0) ref = null;
    } else {
        path = rest;
    }

    // Split path into owner/repo
    const slash_pos = mem.indexOf(u8, path, "/") orelse return null;
    if (slash_pos == 0 or slash_pos == path.len - 1) return null;

    const owner = path[0..slash_pos];
    const repo = path[slash_pos + 1 ..];

    // Validate owner and repo are not empty
    if (owner.len == 0 or repo.len == 0) return null;

    return GitHubShorthand{
        .owner = owner,
        .repo = repo,
        .ref = ref,
    };
}

/// Enhanced add command with multi-registry support
pub fn add(allocator: Allocator, package_ref: []const u8, options: AddOptions) !void {
    // Load enhanced configuration
    var config = try enhanced_config.ZionConfig.load(allocator);
    defer config.deinit();

    // Check if this is an alias first
    if (config.expandAlias(package_ref)) |dependencies| {
        std.debug.print("📦 Expanding alias '{s}' to {d} dependencies:\n", .{ package_ref, dependencies.len });
        for (dependencies) |dep| {
            std.debug.print("  • {s}\n", .{dep});
        }
        std.debug.print("\n", .{});

        // Add each dependency in the alias
        for (dependencies) |dep| {
            try addSingleDependency(allocator, dep, &config, options);
        }
        return;
    }

    // Single package add
    try addSingleDependency(allocator, package_ref, &config, options);
}

/// Options for the add command
pub const AddOptions = struct {
    // Version constraints
    version: ?[]const u8 = null,
    version_range: ?[]const u8 = null,

    // Development dependencies
    dev_only: bool = false,

    // Build integration
    auto_integrate: bool = true,

    // Registry options
    prefer_registry: ?[]const u8 = null,

    // Security options
    verify_signatures: bool = false,
    require_license: ?[]const u8 = null,

    // Update behavior
    update_if_exists: bool = false,

    // Dry run
    dry_run: bool = false,
};

/// Add a single dependency with enhanced features
fn addSingleDependency(allocator: Allocator, package_ref: []const u8, config: *enhanced_config.ZionConfig, options: AddOptions) !void {
    // Parse GitHub shorthand if present (gh/owner/repo@ref or gh:owner/repo@ref)
    var normalized_ref: []const u8 = package_ref;
    var shorthand_ref: ?[]const u8 = null;
    var owns_normalized_ref = false;

    if (parseGitHubShorthand(package_ref)) |shorthand| {
        normalized_ref = try shorthand.toPackageRef(allocator);
        owns_normalized_ref = true;
        shorthand_ref = shorthand.ref;

        if (shorthand.ref) |ref| {
            std.debug.print("🔍 Resolving package: {s} (from gh/{s}/{s}@{s})\n", .{ normalized_ref, shorthand.owner, shorthand.repo, ref });
        } else {
            std.debug.print("🔍 Resolving package: {s} (from gh/{s}/{s})\n", .{ normalized_ref, shorthand.owner, shorthand.repo });
        }
    } else {
        std.debug.print("🔍 Resolving package: {s}\n", .{normalized_ref});
    }
    defer if (owns_normalized_ref) allocator.free(normalized_ref);

    // Initialize registry manager
    var manager = registry_manager.RegistryManager.init(allocator, config);
    defer manager.deinit();
    try manager.initClients();

    // Determine version constraint to use
    // GitHub shorthand ref takes precedence if no explicit version was provided
    var effective_version: ?[]const u8 = options.version orelse shorthand_ref;
    var version_constraint: ?[]const u8 = null;
    var owns_version_constraint = false;
    var resolved_via_constraint = false;

    // If version_range is provided, resolve the constraint to find the best version
    if (options.version_range) |constraint| {
        std.debug.print("   Constraint: {s}\n", .{constraint});
        version_constraint = constraint;

        // Parse and validate the constraint
        const range = semver.VersionRange.parse(constraint) catch {
            std.debug.print("❌ Invalid version constraint: {s}\n", .{constraint});
            std.debug.print("   Valid formats: ^1.0.0, ~2.1.0, >=1.0.0, <2.0.0, *, latest\n", .{});
            return error.InvalidVersionConstraint;
        };

        // Try to resolve the constraint using version_resolver
        var resolver = version_resolver.VersionResolver.init(allocator);
        if (resolver.resolve(normalized_ref, constraint)) |result| {
            var res = result;
            defer res.deinit(allocator);

            effective_version = try allocator.dupe(u8, res.version_string);
            resolved_via_constraint = true;

            const desc = range.describe(allocator) catch constraint;
            defer if (!std.mem.eql(u8, desc, constraint)) allocator.free(desc);
            std.debug.print("   Resolved: {s} -> {s}\n", .{ desc, res.version_string });
        } else |err| {
            std.debug.print("⚠️  Could not resolve via constraint ({s}), falling back to registry lookup\n", .{@errorName(err)});
            // Fall back to registry resolution without version constraint
        }
    }
    defer if (resolved_via_constraint and effective_version != null) allocator.free(effective_version.?);

    // Resolve package across registries
    const package = try manager.resolvePackage(normalized_ref, effective_version) orelse {
        std.debug.print("❌ Package not found: {s}\n", .{normalized_ref});

        // Suggest similar packages
        std.debug.print("🔍 Searching for similar packages...\n", .{});
        const search_results = try manager.searchPackages(normalized_ref, .{
            .per_page = 5,
        });
        defer {
            for (search_results) |pkg| pkg.deinit(allocator);
            allocator.free(search_results);
        }

        if (search_results.len > 0) {
            std.debug.print("\n💡 Did you mean:\n", .{});
            for (search_results) |pkg| {
                std.debug.print("  • {s} - {s}\n", .{ pkg.full_name, pkg.description orelse "No description" });
                if (pkg.registry_name.len > 0) {
                    std.debug.print("    Registry: {s}, Stars: {d}, Downloads: {d}\n", .{ pkg.registry_name, pkg.stars, pkg.download_count });
                }
            }
        }
        return error.PackageNotFound;
    };
    defer package.deinit(allocator);

    // If no constraint was provided, infer one from the resolved version
    if (version_constraint == null and package.version.len > 0) {
        version_constraint = semver.inferConstraint(package.version, allocator) catch null;
        owns_version_constraint = version_constraint != null;
    }
    defer if (owns_version_constraint and version_constraint != null) allocator.free(version_constraint.?);

    // Display package information
    std.debug.print("\n📦 Found package: {s}\n", .{package.full_name});
    std.debug.print("   Version: {s}\n", .{package.version});
    std.debug.print("   Registry: {s}\n", .{package.registry_name});
    if (package.description) |desc| {
        std.debug.print("   Description: {s}\n", .{desc});
    }
    if (package.license) |license| {
        std.debug.print("   License: {s}\n", .{license});
    }
    if (package.author) |author| {
        std.debug.print("   Author: {s}\n", .{author});
    }
    if (package.categories.len > 0) {
        std.debug.print("   Categories: ", .{});
        for (package.categories, 0..) |cat, i| {
            if (i > 0) std.debug.print(", ", .{});
            std.debug.print("{s}", .{cat});
        }
        std.debug.print("\n", .{});
    }

    // Check license compatibility
    if (options.require_license) |required_license| {
        if (package.license == null or !isLicenseCompatible(package.license.?, required_license)) {
            std.debug.print("❌ License incompatibility: package has {s}, but {s} is required\n", .{
                package.license orelse "no license",
                required_license,
            });
            return error.LicenseIncompatible;
        }
    }

    // Analyze dependencies
    std.debug.print("\n🔍 Analyzing dependencies...\n", .{});
    var dep_analysis = try manager.analyzeDependencies(package.full_name);
    defer dep_analysis.deinit();

    if (dep_analysis.total_dependencies > 0) {
        std.debug.print("   Total dependencies: {d}\n", .{dep_analysis.total_dependencies});
    }

    if (dep_analysis.conflicts.items.len > 0) {
        std.debug.print("\n⚠️  Dependency conflicts detected:\n", .{});
        for (dep_analysis.conflicts.items) |conflict| {
            std.debug.print("   • {s}: conflicting versions ", .{conflict.package});
            for (conflict.conflicting_versions) |ver| {
                std.debug.print("{s} ", .{ver});
            }
            std.debug.print("\n", .{});
        }

        if (!options.update_if_exists) {
            return error.DependencyConflict;
        }
    }

    if (options.dry_run) {
        std.debug.print("\n🔍 Dry run complete. No changes made.\n", .{});
        return;
    }

    // Check if build.zig.zon exists
    const zon_path = "build.zig.zon";
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    cwd.access(io, zon_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("❌ build.zig.zon not found. Run 'zion init' first.\n", .{});
            return error.FileNotFound;
        }
        return err;
    };

    // Get download information
    const download_info = try manager.getPackageDownload(package.full_name, package.version);
    defer {
        allocator.free(download_info.url);
        if (download_info.sha256_hash) |hash| allocator.free(hash);
        allocator.free(download_info.registry_name);
    }

    // Download with parallel downloader for performance
    std.debug.print("\n📥 Downloading from {s}...\n", .{download_info.registry_name});

    // Always use the registry-provided URL instead of re-resolving
    const download_result = if (config.concurrent_downloads > 1)
        try parallel_downloader.downloadSingleWithProgress(allocator, download_info.url, package.full_name)
    else
        try downloader.downloadFromUrl(allocator, download_info.url, package.full_name);

    defer {
        allocator.free(download_result.url);
        allocator.free(download_result.hash);
        allocator.free(download_result.cache_path);
    }

    // Verify download integrity against registry-provided hash
    if (download_info.sha256_hash) |expected_hash| {
        if (!std.mem.eql(u8, download_result.hash, expected_hash)) {
            std.debug.print("❌ Integrity check failed!\n", .{});
            std.debug.print("   Expected: {s}\n", .{expected_hash});
            std.debug.print("   Got:      {s}\n", .{download_result.hash});
            std.debug.print("   This may indicate a compromised download or registry mismatch.\n", .{});
            return error.IntegrityCheckFailed;
        }
        std.debug.print("✅ Integrity verified (SHA256 matches registry)\n", .{});
    }

    // Verify signatures if requested (with trust store validation)
    if (options.verify_signatures) {
        std.debug.print("🔐 Verifying package signatures...\n", .{});
        const verification_result = try security.verifyPackageSignatureWithTrust(allocator, download_result.cache_path, package.full_name);
        defer verification_result.deinit(allocator);

        if (!verification_result.trusted) {
            std.debug.print("❌ Signing key not trusted: {s}\n", .{verification_result.message});
            std.debug.print("   Key fingerprint: {s}\n", .{verification_result.fingerprint});
            std.debug.print("\n💡 To trust this key, run:\n", .{});
            std.debug.print("   zion keyring trust {s}\n", .{verification_result.fingerprint});
            std.debug.print("\n⚠️  Only trust keys from known publishers!\n", .{});
            return error.SignatureKeyNotTrusted;
        }

        if (!verification_result.valid) {
            std.debug.print("❌ Signature verification failed: {s}\n", .{verification_result.message});
            return error.SignatureVerificationFailed;
        }
        std.debug.print("✅ Signature verified (trusted key: {s}...)\n", .{verification_result.fingerprint[0..16]});
    }

    // Extract the package
    const package_name = package.name;
    try ensureDepsDir(options.dev_only);

    const deps_path = if (options.dev_only)
        try std.fmt.allocPrint(allocator, ".zion/dev-deps/{s}", .{package_name})
    else
        try std.fmt.allocPrint(allocator, ".zion/deps/{s}", .{package_name});
    defer allocator.free(deps_path);

    std.debug.print("📦 Extracting package to {s}...\n", .{deps_path});
    try tar_extract.extractPackage(allocator, download_result.cache_path, deps_path);

    // Update build.zig.zon
    std.debug.print("📝 Updating build.zig.zon...\n", .{});
    var zon_file = try ZonFile.loadFromFile(allocator, zon_path);
    defer zon_file.deinit();

    // Add dependency with metadata
    if (options.dev_only) {
        try zon_file.addDevDependency(package_name, download_result.url, download_result.hash);
    } else {
        try zon_file.addDependency(package_name, download_result.url, download_result.hash);
    }

    // Add metadata comments
    const metadata = try std.fmt.allocPrint(allocator,
        \\// {s} v{s} from {s}
        \\// License: {s}
        \\// Added: {d}
    , .{
        package.full_name,
        package.version,
        package.registry_name,
        package.license orelse "Unknown",
        zion_root.timestamp(),
    });
    defer allocator.free(metadata);

    try zon_file.addComment(package_name, metadata);
    try zon_file.saveToFile(zon_path);

    // Update lock file with enhanced information
    std.debug.print("🔒 Updating lock file...\n", .{});
    var lock_file = try LockFile.loadFromFile(allocator);
    defer lock_file.deinit();

    // Convert dependencies to the expected format
    var dep_names: std.ArrayList([]const u8) = .empty;
    defer dep_names.deinit(allocator);

    for (package.dependencies) |dep| {
        try dep_names.append(allocator, try allocator.dupe(u8, dep.name));
    }

    try lock_file.addPackageWithMetadata(
        package_name,
        download_result.url,
        download_result.hash,
        .{
            .version = package.version,
            .registry = package.registry_name,
            .resolved_from = package.full_name,
            .integrity = download_result.hash,
            .dependencies = if (dep_names.items.len > 0) try dep_names.toOwnedSlice(allocator) else null,
            .dev_only = options.dev_only,
            .version_constraint = version_constraint,
            .pinned = options.version != null, // Pin if exact version was specified
        },
    );
    try lock_file.saveToFile();

    // Auto-integrate into build.zig if requested
    if (options.auto_integrate) {
        std.debug.print("🔧 Updating build.zig...\n", .{});
        modifyBuildZigV2(allocator, package_name, deps_path, options.dev_only) catch |err| {
            std.debug.print("⚠️  Could not automatically update build.zig: {}\n", .{err});
            std.debug.print("\n📋 Manual integration required:\n", .{});
            try printEnhancedBuildInstructions(package_name, deps_path, options.dev_only);
        };
    }

    // Success summary
    std.debug.print("\n✅ Successfully added {s} v{s}\n", .{ package.full_name, package.version });
    std.debug.print("   📦 Package location: {s}\n", .{deps_path});
    std.debug.print("   🌐 Registry: {s}\n", .{package.registry_name});
    if (version_constraint) |vc| {
        std.debug.print("   📌 Constraint: {s}\n", .{vc});
    }
    if (package.homepage) |homepage| {
        std.debug.print("   🏠 Homepage: {s}\n", .{homepage});
    }
    if (package.repository_url) |repo_url| {
        std.debug.print("   📂 Repository: {s}\n", .{repo_url});
    }

    std.debug.print("\n🚀 Run 'zig build' to verify the integration.\n", .{});

    // Show update notification if package has newer version
    // This would check against the registry in a real implementation
}

/// Add multiple packages with parallel processing
pub fn addMultiple(allocator: Allocator, packages: []const []const u8, options: AddOptions) !void {
    std.debug.print("📦 Adding {d} packages...\n\n", .{packages.len});

    var success_count: usize = 0;
    var error_count: usize = 0;
    var errors: std.ArrayList(struct { package: []const u8, err: anyerror }) = .empty;
    defer errors.deinit(allocator);

    // Process packages
    for (packages, 0..) |package_ref, i| {
        std.debug.print("[{d}/{d}] Processing {s}...\n", .{ i + 1, packages.len, package_ref });

        add(allocator, package_ref, options) catch |err| {
            error_count += 1;
            try errors.append(allocator, .{ .package = package_ref, .err = err });
            std.debug.print("❌ Failed to add {s}: {}\n\n", .{ package_ref, err });
            continue;
        };

        success_count += 1;
        std.debug.print("\n", .{});
    }

    // Summary
    std.debug.print("\n📊 Summary:\n", .{});
    std.debug.print("   ✅ Successful: {d}\n", .{success_count});
    std.debug.print("   ❌ Failed: {d}\n", .{error_count});

    if (errors.items.len > 0) {
        std.debug.print("\n❌ Failed packages:\n", .{});
        for (errors.items) |item| {
            std.debug.print("   • {s}: {}\n", .{ item.package, item.err });
        }
    }

    if (success_count > 0) {
        std.debug.print("\n🚀 Run 'zig build' to verify all integrations.\n", .{});
    }
}

/// Check if two licenses are compatible
fn isLicenseCompatible(package_license: []const u8, required_license: []const u8) bool {
    // Simple compatibility check - in reality would use SPDX license compatibility matrix
    const compatible_pairs = [_][2][]const u8{
        .{ "MIT", "MIT" },
        .{ "MIT", "Apache-2.0" },
        .{ "Apache-2.0", "MIT" },
        .{ "BSD-3-Clause", "MIT" },
        .{ "ISC", "MIT" },
    };

    for (compatible_pairs) |pair| {
        if ((std.mem.eql(u8, package_license, pair[0]) and std.mem.eql(u8, required_license, pair[1])) or
            (std.mem.eql(u8, package_license, pair[1]) and std.mem.eql(u8, required_license, pair[0])))
        {
            return true;
        }
    }

    return std.mem.eql(u8, package_license, required_license);
}

/// Ensure the deps directory exists
fn ensureDepsDir(dev_only: bool) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Create .zion directory
    cwd.createDir(io, ".zion", .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Create appropriate deps directory
    const deps_dir = if (dev_only) ".zion/dev-deps" else ".zion/deps";
    cwd.createDir(io, deps_dir, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

/// Extract tarball (reused from original)
fn extractTarball(allocator: Allocator, tarball_path: []const u8, dest_path: []const u8) !void {
    const io = try zion_root.getIo();
    const cwd = Dir.cwd();

    // Remove existing directory if it exists
    cwd.deleteTree(io, dest_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };

    // Create destination directory
    try cwd.createDirPath(io, dest_path);

    // Use tar to extract
    const argv = [_][]const u8{
        "tar",
        "-xzf",
        tarball_path,
        "-C",
        dest_path,
        "--strip-components=1",
    };

    var child = try std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
    });

    // Read stderr using scatter/gather API
    var stderr_buf: std.ArrayList(u8) = .empty;
    defer stderr_buf.deinit(allocator);

    if (child.stderr) |stderr_pipe| {
        var read_buf: [4096]u8 = undefined;
        while (true) {
            const bytes_read = stderr_pipe.readStreaming(io, &.{read_buf[0..]}) catch break;
            if (bytes_read == 0) break;
            try stderr_buf.appendSlice(allocator, read_buf[0..bytes_read]);
        }
    }

    const term = try child.wait(io);

    switch (term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("tar extraction failed (exit code {d}): {s}\n", .{ code, stderr_buf.items });
                return error.ExtractionFailed;
            }
        },
        else => {
            std.debug.print("tar extraction terminated abnormally: {s}\n", .{stderr_buf.items});
            return error.ExtractionFailed;
        },
    }
}

/// Enhanced build.zig modification
fn modifyBuildZigV2(allocator: Allocator, package_name: []const u8, deps_path: []const u8, dev_only: bool) !void {
    _ = allocator;
    _ = package_name;
    _ = deps_path;
    _ = dev_only;
    // Implementation would intelligently modify build.zig
    // with proper AST parsing and modification
    return error.NotImplemented;
}

/// Print enhanced build instructions
fn printEnhancedBuildInstructions(package_name: []const u8, deps_path: []const u8, dev_only: bool) !void {
    _ = deps_path;
    std.debug.print("\n", .{});
    if (dev_only) {
        std.debug.print("To use this development dependency in your project:\n", .{});
    } else {
        std.debug.print("To use this dependency in your project:\n", .{});
    }
    std.debug.print("\n", .{});

    std.debug.print("// In your build.zig, add:\n", .{});
    std.debug.print("const {s} = b.dependency(\"{s}\", .{{\n", .{ package_name, package_name });
    std.debug.print("    .target = target,\n", .{});
    std.debug.print("    .optimize = optimize,\n", .{});
    std.debug.print("}});\n", .{});
    std.debug.print("\n", .{});

    if (dev_only) {
        std.debug.print("// For test targets:\n", .{});
        std.debug.print("const test_step = b.step(\"test\", \"Run tests\");\n", .{});
        std.debug.print("test_step.dependOn(&{s}.artifact(\"test\").step);\n", .{package_name});
    } else {
        std.debug.print("// Add to your executable:\n", .{});
        std.debug.print("exe.root_module.addImport(\"{s}\", {s}.module(\"{s}\"));\n", .{ package_name, package_name, package_name });
    }
    std.debug.print("\n", .{});

    std.debug.print("// Then in your Zig code:\n", .{});
    std.debug.print("const {s} = @import(\"{s}\");\n", .{ package_name, package_name });
}
