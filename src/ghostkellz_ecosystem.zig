const std = @import("std");
const Allocator = std.mem.Allocator;

/// Complete GhostKellz package ecosystem definition
pub const GhostKellzEcosystem = struct {
    allocator: Allocator,
    packages: std.ArrayList(GhostKellzPackage),
    
    pub const GhostKellzPackage = struct {
        name: []const u8,
        description: []const u8,
        category: Category,
        github_repo: []const u8,
        main_features: []const []const u8,
        dependencies: []const []const u8,
        zig_version: []const u8,
        maturity: Maturity,
        
        pub const Category = enum {
            crypto,
            networking,
            database,
            runtime,
            development_tools,
            system_tools,
            tui_framework,
            async_framework,
            virtualization,
            security,
            
            pub fn getIcon(self: Category) []const u8 {
                return switch (self) {
                    .crypto => "🔐",
                    .networking => "🌐",
                    .database => "🗄️",
                    .runtime => "⚡",
                    .development_tools => "🛠️",
                    .system_tools => "🔧",
                    .tui_framework => "🎨",
                    .async_framework => "⚡",
                    .virtualization => "📦",
                    .security => "🛡️",
                };
            }
            
            pub fn getDisplayName(self: Category) []const u8 {
                return switch (self) {
                    .crypto => "Cryptography",
                    .networking => "Networking",
                    .database => "Database",
                    .runtime => "Runtime",
                    .development_tools => "Development Tools",
                    .system_tools => "System Tools", 
                    .tui_framework => "TUI Framework",
                    .async_framework => "Async Framework",
                    .virtualization => "Virtualization",
                    .security => "Security",
                };
            }
        };
        
        pub const Maturity = enum {
            alpha,
            beta,
            stable,
            mature,
            
            pub fn getIcon(self: Maturity) []const u8 {
                return switch (self) {
                    .alpha => "🚧",
                    .beta => "⚠️",
                    .stable => "✅",
                    .mature => "🏆",
                };
            }
            
            pub fn getDisplayName(self: Maturity) []const u8 {
                return switch (self) {
                    .alpha => "Alpha",
                    .beta => "Beta", 
                    .stable => "Stable",
                    .mature => "Mature",
                };
            }
        };
        
        pub fn getGitHubUrl(self: *const GhostKellzPackage) []const u8 {
            return self.github_repo;
        }
        
        pub fn getZigFetchCommand(self: *const GhostKellzPackage, allocator: Allocator) ![]const u8 {
            return std.fmt.allocPrint(allocator, 
                "zig fetch --save https://github.com/ghostkellz/{s}/archive/refs/heads/main.tar.gz",
                .{self.name}
            );
        }
    };
    
    pub fn init(allocator: Allocator) !GhostKellzEcosystem {
        var ecosystem = GhostKellzEcosystem{
            .allocator = allocator,
            .packages = std.ArrayList(GhostKellzPackage).init(allocator),
        };
        
        try ecosystem.initializePackages();
        return ecosystem;
    }
    
    pub fn deinit(self: *GhostKellzEcosystem) void {
        for (self.packages.items) |*pkg| {
            self.allocator.free(pkg.name);
            self.allocator.free(pkg.description);
            self.allocator.free(pkg.github_repo);
            self.allocator.free(pkg.zig_version);
            
            for (pkg.main_features) |feature| {
                self.allocator.free(feature);
            }
            self.allocator.free(pkg.main_features);
            
            for (pkg.dependencies) |dep| {
                self.allocator.free(dep);
            }
            self.allocator.free(pkg.dependencies);
        }
        self.packages.deinit();
    }
    
    fn initializePackages(self: *GhostKellzEcosystem) !void {
        // Core GhostKellz ecosystem packages
        const package_definitions = [_]struct {
            name: []const u8,
            description: []const u8,
            category: GhostKellzPackage.Category,
            features: []const []const u8,
            deps: []const []const u8,
            maturity: GhostKellzPackage.Maturity,
        }{
            .{
                .name = "zcrypt",
                .description = "High-performance cryptographic library with quantum-resistant algorithms",
                .category = .crypto,
                .features = &[_][]const u8{ "AES-256", "ChaCha20-Poly1305", "Ed25519", "Quantum-safe NIST PQC", "Hardware acceleration" },
                .deps = &[_][]const u8{ "zsync" },
                .maturity = .stable,
            },
            .{
                .name = "zquic",
                .description = "Ultra-fast QUIC (HTTP/3) protocol implementation",
                .category = .networking,
                .features = &[_][]const u8{ "HTTP/3 support", "0-RTT connection", "Multiplexing", "Auto congestion control", "TLS 1.3" },
                .deps = &[_][]const u8{ "zcrypt", "zsync" },
                .maturity = .beta,
            },
            .{
                .name = "shroud",
                .description = "Advanced privacy and anonymization toolkit",
                .category = .security,
                .features = &[_][]const u8{ "Onion routing", "Traffic obfuscation", "Anonymous messaging", "Steganography" },
                .deps = &[_][]const u8{ "zcrypt", "ghostnet" },
                .maturity = .alpha,
            },
            .{
                .name = "zqlite",
                .description = "Lightning-fast embedded SQL database optimized for Zig",
                .category = .database,
                .features = &[_][]const u8{ "ACID compliance", "Zero-copy operations", "Async I/O", "Memory-mapped storage", "SQL compatibility" },
                .deps = &[_][]const u8{ "zsync" },
                .maturity = .stable,
            },
            .{
                .name = "ghostnet",
                .description = "Context-aware HTTP3/2/1 client with intelligent protocol selection",
                .category = .networking,
                .features = &[_][]const u8{ "HTTP/3 auto-negotiation", "Resume downloads", "Smart retry", "Connection pooling" },
                .deps = &[_][]const u8{ "zsync", "zcrypt", "zquic" },
                .maturity = .stable,
            },
            .{
                .name = "phantom",
                .description = "Next-generation TUI framework with advanced widgets and animations",
                .category = .tui_framework,
                .features = &[_][]const u8{ "Real-time rendering", "Widget animations", "Universal package browser", "Theme system" },
                .deps = &[_][]const u8{ "zsync" },
                .maturity = .stable,
            },
            .{
                .name = "zsync",
                .description = "Rust-inspired async runtime for Zig with structured concurrency",
                .category = .async_framework,
                .features = &[_][]const u8{ "Structured concurrency", "Future combinators", "Thread pool", "Timer system" },
                .deps = &[_][]const u8{},
                .maturity = .mature,
            },
            .{
                .name = "flash",
                .description = "Blazing-fast build system and package manager for Zig",
                .category = .development_tools,
                .features = &[_][]const u8{ "Incremental builds", "Parallel compilation", "Smart caching", "Cross-compilation" },
                .deps = &[_][]const u8{ "zsync", "ghostnet" },
                .maturity = .beta,
            },
            .{
                .name = "jaguar",
                .description = "High-performance JIT compiler framework",
                .category = .runtime,
                .features = &[_][]const u8{ "LLVM integration", "Hot reloading", "Adaptive optimization", "Debug support" },
                .deps = &[_][]const u8{ "zsync" },
                .maturity = .alpha,
            },
            .{
                .name = "zeus",
                .description = "Distributed computing and orchestration platform",
                .category = .virtualization,
                .features = &[_][]const u8{ "Container orchestration", "Service mesh", "Auto-scaling", "Load balancing" },
                .deps = &[_][]const u8{ "ghostnet", "zsync", "zcrypt" },
                .maturity = .alpha,
            },
            .{
                .name = "zeke",
                .description = "Advanced system monitoring and profiling toolkit",
                .category = .system_tools,
                .features = &[_][]const u8{ "Real-time metrics", "Memory profiling", "CPU analysis", "Network monitoring" },
                .deps = &[_][]const u8{ "phantom", "zsync" },
                .maturity = .beta,
            },
            .{
                .name = "wraith",
                .description = "Stealth debugging and reverse engineering framework",
                .category = .security,
                .features = &[_][]const u8{ "Memory injection", "API hooking", "Process hollowing", "Anti-detection" },
                .deps = &[_][]const u8{ "zcrypt", "shroud" },
                .maturity = .alpha,
            },
            .{
                .name = "zvm",
                .description = "Zig Virtual Machine with sandboxing and isolation",
                .category = .virtualization,
                .features = &[_][]const u8{ "Bytecode execution", "Memory isolation", "Resource limits", "Security sandbox" },
                .deps = &[_][]const u8{ "zsync", "zcrypt" },
                .maturity = .beta,
            },
            .{
                .name = "zns",
                .description = "Zero-configuration DNS server with advanced filtering",
                .category = .networking,
                .features = &[_][]const u8{ "DoH/DoT support", "Ad blocking", "Geographic filtering", "DNSSEC validation" },
                .deps = &[_][]const u8{ "ghostnet", "zcrypt" },
                .maturity = .beta,
            },
            .{
                .name = "cns",
                .description = "Content-addressable network storage system",
                .category = .database,
                .features = &[_][]const u8{ "Distributed storage", "Content deduplication", "Encryption at rest", "P2P sync" },
                .deps = &[_][]const u8{ "zcrypt", "ghostnet", "zqlite" },
                .maturity = .alpha,
            },
            .{
                .name = "reaper",
                .description = "Resource management and cleanup automation",
                .category = .system_tools,
                .features = &[_][]const u8{ "Automatic cleanup", "Resource tracking", "Policy engine", "Audit logging" },
                .deps = &[_][]const u8{ "zsync", "zeke" },
                .maturity = .stable,
            },
            .{
                .name = "ghostbridge",
                .description = "Universal protocol bridge and translation layer",
                .category = .networking,
                .features = &[_][]const u8{ "Protocol translation", "Legacy support", "API gateway", "Traffic shaping" },
                .deps = &[_][]const u8{ "ghostnet", "zquic", "zcrypt" },
                .maturity = .beta,
            },
            .{
                .name = "zsig",
                .description = "Digital signature and verification framework",
                .category = .crypto,
                .features = &[_][]const u8{ "EdDSA signatures", "Multi-signature schemes", "Ring signatures", "Schnorr signatures" },
                .deps = &[_][]const u8{ "zcrypt", "zsync" },
                .maturity = .stable,
            },
            .{
                .name = "zwallet",
                .description = "Cryptocurrency wallet framework with multi-chain support",
                .category = .crypto,
                .features = &[_][]const u8{ "HD wallet support", "Multi-chain compatibility", "Hardware wallet integration", "Secure key management" },
                .deps = &[_][]const u8{ "zcrypt", "zsig", "ghostnet" },
                .maturity = .beta,
            },
            .{
                .name = "zledger",
                .description = "Distributed ledger technology and blockchain framework",
                .category = .database,
                .features = &[_][]const u8{ "Consensus algorithms", "Smart contracts", "Block validation", "P2P networking" },
                .deps = &[_][]const u8{ "zcrypt", "zsig", "ghostnet", "zqlite" },
                .maturity = .alpha,
            },
        };
        
        for (package_definitions) |pkg_def| {
            // Allocate and copy strings
            const name = try self.allocator.dupe(u8, pkg_def.name);
            const description = try self.allocator.dupe(u8, pkg_def.description);
            const github_repo = try std.fmt.allocPrint(self.allocator, "https://github.com/ghostkellz/{s}", .{pkg_def.name});
            const zig_version = try self.allocator.dupe(u8, "0.14.0");
            
            // Copy features
            const features = try self.allocator.alloc([]const u8, pkg_def.features.len);
            for (pkg_def.features, 0..) |feature, i| {
                features[i] = try self.allocator.dupe(u8, feature);
            }
            
            // Copy dependencies
            const deps = try self.allocator.alloc([]const u8, pkg_def.deps.len);
            for (pkg_def.deps, 0..) |dep, i| {
                deps[i] = try self.allocator.dupe(u8, dep);
            }
            
            const package = GhostKellzPackage{
                .name = name,
                .description = description,
                .category = pkg_def.category,
                .github_repo = github_repo,
                .main_features = features,
                .dependencies = deps,
                .zig_version = zig_version,
                .maturity = pkg_def.maturity,
            };
            
            try self.packages.append(package);
        }
    }
    
    pub fn getPackagesByCategory(self: *const GhostKellzEcosystem, category: GhostKellzPackage.Category) std.ArrayList(*const GhostKellzPackage) {
        var result = std.ArrayList(*const GhostKellzPackage).init(self.allocator);
        
        for (self.packages.items) |*pkg| {
            if (pkg.category == category) {
                result.append(pkg) catch break;
            }
        }
        
        return result;
    }
    
    pub fn findPackage(self: *const GhostKellzEcosystem, name: []const u8) ?*const GhostKellzPackage {
        for (self.packages.items) |*pkg| {
            if (std.mem.eql(u8, pkg.name, name)) {
                return pkg;
            }
        }
        return null;
    }
    
    pub fn getDependencyTree(self: *const GhostKellzEcosystem, package_name: []const u8, allocator: Allocator) !std.ArrayList([]const u8) {
        var deps = std.ArrayList([]const u8).init(allocator);
        var visited = std.StringHashMap(void).init(allocator);
        defer visited.deinit();
        
        try self.collectDependencies(package_name, &deps, &visited);
        return deps;
    }
    
    fn collectDependencies(
        self: *const GhostKellzEcosystem,
        package_name: []const u8,
        deps: *std.ArrayList([]const u8),
        visited: *std.StringHashMap(void),
    ) !void {
        if (visited.contains(package_name)) return;
        try visited.put(package_name, {});
        
        if (self.findPackage(package_name)) |pkg| {
            for (pkg.dependencies) |dep| {
                try deps.append(dep);
                try self.collectDependencies(dep, deps, visited);
            }
        }
    }
    
    pub fn generateInstallScript(self: *const GhostKellzEcosystem, package_names: []const []const u8, allocator: Allocator) ![]const u8 {
        var script = std.ArrayList(u8).init(allocator);
        try script.appendSlice("#!/bin/bash\n");
        try script.appendSlice("# GhostKellz Package Installation Script\n");
        try script.appendSlice("# Generated by Zion Package Manager\n\n");
        
        var all_deps = std.StringHashMap(void).init(allocator);
        defer all_deps.deinit();
        
        // Collect all unique dependencies
        for (package_names) |pkg_name| {
            const deps = try self.getDependencyTree(pkg_name, allocator);
            defer deps.deinit();
            
            for (deps.items) |dep| {
                try all_deps.put(dep, {});
            }
            try all_deps.put(pkg_name, {});
        }
        
        // Generate zig fetch commands in dependency order
        var dep_iterator = all_deps.iterator();
        while (dep_iterator.next()) |entry| {
            const pkg_name = entry.key_ptr.*;
            if (self.findPackage(pkg_name)) |pkg| {
                const fetch_cmd = try pkg.getZigFetchCommand(allocator);
                defer allocator.free(fetch_cmd);
                
                try script.writer().print("echo \"📦 Fetching {s}...\"\n", .{pkg_name});
                try script.writer().print("{s}\n", .{fetch_cmd});
                try script.appendSlice("echo \"✅ {s} added to dependencies\"\n\n");
            }
        }
        
        try script.appendSlice("echo \"🎉 All GhostKellz packages installed successfully!\"\n");
        try script.appendSlice("echo \"Run 'zig build' to verify integration\"\n");
        
        return script.toOwnedSlice();
    }
};