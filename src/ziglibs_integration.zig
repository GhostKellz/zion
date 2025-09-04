const std = @import("std");
const Allocator = std.mem.Allocator;

/// ZigLibs repository integration for packages and tools
pub const ZigLibsIntegration = struct {
    allocator: Allocator,
    packages: std.ArrayList(ZigLibsPackage),
    tools: std.ArrayList(ZigLibsTool),
    base_url: []const u8 = "https://github.com/ziglibs/repository",
    
    pub const ZigLibsPackage = struct {
        name: []const u8,
        description: ?[]const u8,
        repository: []const u8,
        version: ?[]const u8,
        category: Category,
        documentation: ?[]const u8,
        author: ?[]const u8,
        
        pub const Category = enum {
            algorithms,
            async_io,
            cli,
            compression,
            crypto,
            data_structures,
            datetime,
            encoding,
            graphics,
            gui,
            http,
            json,
            math,
            networking,
            parsing,
            regex,
            serialization,
            testing,
            text,
            utility,
            web,
            
            pub fn getIcon(self: Category) []const u8 {
                return switch (self) {
                    .algorithms => "🧮",
                    .async_io => "⚡",
                    .cli => "💻",
                    .compression => "🗜️",
                    .crypto => "🔐",
                    .data_structures => "📊",
                    .datetime => "📅",
                    .encoding => "🔄",
                    .graphics => "🎨",
                    .gui => "🖥️",
                    .http => "🌐",
                    .json => "📄",
                    .math => "🔢",
                    .networking => "🌐",
                    .parsing => "📝",
                    .regex => "🔍",
                    .serialization => "💾",
                    .testing => "🧪",
                    .text => "📖",
                    .utility => "🔧",
                    .web => "🌍",
                };
            }
            
            pub fn getDisplayName(self: Category) []const u8 {
                return switch (self) {
                    .algorithms => "Algorithms",
                    .async_io => "Async I/O",
                    .cli => "Command Line",
                    .compression => "Compression",
                    .crypto => "Cryptography",
                    .data_structures => "Data Structures",
                    .datetime => "Date & Time",
                    .encoding => "Encoding",
                    .graphics => "Graphics",
                    .gui => "GUI",
                    .http => "HTTP",
                    .json => "JSON",
                    .math => "Mathematics",
                    .networking => "Networking",
                    .parsing => "Parsing",
                    .regex => "Regular Expressions",
                    .serialization => "Serialization",
                    .testing => "Testing",
                    .text => "Text Processing",
                    .utility => "Utilities",
                    .web => "Web",
                };
            }
        };
        
        pub fn getGitHubUrl(self: *const ZigLibsPackage) []const u8 {
            return self.repository;
        }
        
        pub fn getZigFetchCommand(self: *const ZigLibsPackage, allocator: Allocator) ![]const u8 {
            // Extract owner/repo from GitHub URL
            if (std.mem.indexOf(u8, self.repository, "github.com/")) |start| {
                const repo_part = self.repository[start + 11..]; // Skip "github.com/"
                return std.fmt.allocPrint(allocator, 
                    "zig fetch --save https://github.com/{s}/archive/refs/heads/main.tar.gz",
                    .{repo_part}
                );
            }
            return std.fmt.allocPrint(allocator, 
                "zig fetch --save {s}/archive/refs/heads/main.tar.gz",
                .{self.repository}
            );
        }
    };
    
    pub const ZigLibsTool = struct {
        name: []const u8,
        description: ?[]const u8,
        repository: []const u8,
        category: ToolCategory,
        installation_method: InstallationMethod,
        
        pub const ToolCategory = enum {
            build_tools,
            code_generation,
            debugging,
            development,
            linting,
            package_management,
            testing,
            utilities,
            
            pub fn getIcon(self: ToolCategory) []const u8 {
                return switch (self) {
                    .build_tools => "🔨",
                    .code_generation => "⚙️",
                    .debugging => "🐛",
                    .development => "💻",
                    .linting => "✨",
                    .package_management => "📦",
                    .testing => "🧪",
                    .utilities => "🔧",
                };
            }
        };
        
        pub const InstallationMethod = enum {
            zig_build,
            zig_fetch,
            binary_download,
            source_compile,
        };
    };
    
    pub fn init(allocator: Allocator) !ZigLibsIntegration {
        var integration = ZigLibsIntegration{
            .allocator = allocator,
            .packages = .{},
            .tools = .{},
        };
        
        try integration.initializeCommonPackages();
        try integration.initializeCommonTools();
        return integration;
    }
    
    pub fn deinit(self: *ZigLibsIntegration) void {
        for (self.packages.items) |*pkg| {
            self.allocator.free(pkg.name);
            if (pkg.description) |desc| self.allocator.free(desc);
            self.allocator.free(pkg.repository);
            if (pkg.version) |ver| self.allocator.free(ver);
            if (pkg.documentation) |docs| self.allocator.free(docs);
            if (pkg.author) |author| self.allocator.free(author);
        }
        self.packages.deinit(self.allocator);
        
        for (self.tools.items) |*tool| {
            self.allocator.free(tool.name);
            if (tool.description) |desc| self.allocator.free(desc);
            self.allocator.free(tool.repository);
        }
        self.tools.deinit(self.allocator);
    }
    
    fn initializeCommonPackages(self: *ZigLibsIntegration) !void {
        // Common ZigLibs packages from https://github.com/ziglibs/repository/tree/main/packages
        const package_definitions = [_]struct {
            name: []const u8,
            description: []const u8,
            repo: []const u8,
            category: ZigLibsPackage.Category,
            author: ?[]const u8 = null,
        }{
            .{
                .name = "zig-clap",
                .description = "Simple command line argument parsing library",
                .repo = "https://github.com/Hejsil/zig-clap",
                .category = .cli,
                .author = "Hejsil",
            },
            .{
                .name = "zig-network",
                .description = "A cross-platform networking library",
                .repo = "https://github.com/MasterQ32/zig-network",
                .category = .networking,
                .author = "MasterQ32",
            },
            .{
                .name = "zig-args",
                .description = "Simple-to-use argument parser",
                .repo = "https://github.com/MasterQ32/zig-args",
                .category = .cli,
                .author = "MasterQ32",
            },
            .{
                .name = "zig-datetime",
                .description = "Date and time manipulation library",
                .repo = "https://github.com/frmdstryr/zig-datetime",
                .category = .datetime,
                .author = "frmdstryr",
            },
            .{
                .name = "zig-json",
                .description = "JSON parsing and serialization",
                .repo = "https://github.com/ziglibs/zig-json",
                .category = .json,
            },
            .{
                .name = "zig-regex",
                .description = "Regular expression engine for Zig",
                .repo = "https://github.com/tiehuis/zig-regex",
                .category = .regex,
                .author = "tiehuis",
            },
            .{
                .name = "zig-uuid",
                .description = "UUID generation and parsing",
                .repo = "https://github.com/ziglibs/zig-uuid",
                .category = .utility,
            },
            .{
                .name = "zig-base64",
                .description = "Base64 encoding and decoding",
                .repo = "https://github.com/ziglibs/base64",
                .category = .encoding,
            },
            .{
                .name = "zig-uri",
                .description = "URI parsing library",
                .repo = "https://github.com/Hejsil/zig-uri",
                .category = .networking,
                .author = "Hejsil",
            },
            .{
                .name = "zig-string",
                .description = "String manipulation utilities",
                .repo = "https://github.com/JakubSzark/zig-string",
                .category = .text,
                .author = "JakubSzark",
            },
            .{
                .name = "zig-sqlite",
                .description = "SQLite bindings for Zig",
                .repo = "https://github.com/leroycep/sqlite-zig",
                .category = .data_structures,
                .author = "leroycep",
            },
            .{
                .name = "zig-protobuf",
                .description = "Protocol Buffers implementation",
                .repo = "https://github.com/Arwalk/zig-protobuf",
                .category = .serialization,
                .author = "Arwalk",
            },
            .{
                .name = "zig-ini",
                .description = "INI file parser",
                .repo = "https://github.com/ziglibs/ini",
                .category = .parsing,
            },
            .{
                .name = "zig-toml",
                .description = "TOML parser and serializer",
                .repo = "https://github.com/aeronavery/zig-toml",
                .category = .parsing,
                .author = "aeronavery",
            },
            .{
                .name = "zig-yaml",
                .description = "YAML parser for Zig",
                .repo = "https://github.com/kubkon/zig-yaml",
                .category = .parsing,
                .author = "kubkon",
            },
            .{
                .name = "zig-csv",
                .description = "CSV parser and writer",
                .repo = "https://github.com/beachglasslabs/zig-csv",
                .category = .parsing,
                .author = "beachglasslabs",
            },
            .{
                .name = "zig-xml",
                .description = "XML parsing library",
                .repo = "https://github.com/ericgmoon/xml-zig",
                .category = .parsing,
                .author = "ericgmoon",
            },
            .{
                .name = "zig-http",
                .description = "HTTP client and server library",
                .repo = "https://github.com/ducdetronquito/h11",
                .category = .http,
                .author = "ducdetronquito",
            },
            .{
                .name = "zig-compression",
                .description = "Compression algorithms",
                .repo = "https://github.com/mattnite/zig-zlib",
                .category = .compression,
                .author = "mattnite",
            },
            .{
                .name = "zig-raylib",
                .description = "Raylib bindings for game development",
                .repo = "https://github.com/Not-Nik/raylib-zig",
                .category = .graphics,
                .author = "Not-Nik",
            },
            .{
                .name = "zig-imgui",
                .description = "Dear ImGui bindings",
                .repo = "https://github.com/SpexGuy/Zig-ImGui",
                .category = .gui,
                .author = "SpexGuy",
            },
            .{
                .name = "zig-webui",
                .description = "Modern web-based UI framework",
                .repo = "https://github.com/webui-dev/zig-webui",
                .category = .web,
            },
            .{
                .name = "zig-math",
                .description = "Mathematics and linear algebra",
                .repo = "https://github.com/ziglibs/zlm",
                .category = .math,
            },
            .{
                .name = "zig-crypto",
                .description = "Cryptographic functions",
                .repo = "https://github.com/jedisct1/zig-crypto-utils",
                .category = .crypto,
                .author = "jedisct1",
            },
            .{
                .name = "zig-testing",
                .description = "Extended testing utilities",
                .repo = "https://github.com/ziglibs/testing-allocators",
                .category = .testing,
            },
        };
        
        for (package_definitions) |pkg_def| {
            const name = try self.allocator.dupe(u8, pkg_def.name);
            const description = try self.allocator.dupe(u8, pkg_def.description);
            const repository = try self.allocator.dupe(u8, pkg_def.repo);
            const author = if (pkg_def.author) |a| try self.allocator.dupe(u8, a) else null;
            
            const package = ZigLibsPackage{
                .name = name,
                .description = description,
                .repository = repository,
                .version = null,
                .category = pkg_def.category,
                .documentation = null,
                .author = author,
            };
            
            try self.packages.append(self.allocator, package);
        }
    }
    
    fn initializeCommonTools(self: *ZigLibsIntegration) !void {
        // Common ZigLibs tools from https://github.com/ziglibs/repository/tree/main/tools
        const tool_definitions = [_]struct {
            name: []const u8,
            description: []const u8,
            repo: []const u8,
            category: ZigLibsTool.ToolCategory,
            install_method: ZigLibsTool.InstallationMethod,
        }{
            .{
                .name = "zls",
                .description = "Zig Language Server for IDE support",
                .repo = "https://github.com/zigtools/zls",
                .category = .development,
                .install_method = .zig_build,
            },
            .{
                .name = "zig-docgen",
                .description = "Documentation generator for Zig",
                .repo = "https://github.com/zigtools/zig-docgen",
                .category = .code_generation,
                .install_method = .zig_build,
            },
            .{
                .name = "zpm",
                .description = "Zig Package Manager",
                .repo = "https://github.com/zigtools/zpm",
                .category = .package_management,
                .install_method = .zig_build,
            },
            .{
                .name = "zigfmt-web",
                .description = "Web-based Zig formatter",
                .repo = "https://github.com/shritesh/zigfmt-web",
                .category = .linting,
                .install_method = .zig_build,
            },
            .{
                .name = "zig-test-runner",
                .description = "Advanced test runner for Zig",
                .repo = "https://github.com/zigtools/test-runner",
                .category = .testing,
                .install_method = .zig_build,
            },
            .{
                .name = "zig-build-helpers",
                .description = "Utilities for Zig build system",
                .repo = "https://github.com/zigtools/build-helpers",
                .category = .build_tools,
                .install_method = .zig_fetch,
            },
            .{
                .name = "zig-gdb",
                .description = "GDB integration for Zig debugging",
                .repo = "https://github.com/zigtools/zig-gdb",
                .category = .debugging,
                .install_method = .source_compile,
            },
            .{
                .name = "zig-highlight",
                .description = "Syntax highlighting for various editors",
                .repo = "https://github.com/zigtools/zig-highlight",
                .category = .utilities,
                .install_method = .binary_download,
            },
        };
        
        for (tool_definitions) |tool_def| {
            const name = try self.allocator.dupe(u8, tool_def.name);
            const description = try self.allocator.dupe(u8, tool_def.description);
            const repository = try self.allocator.dupe(u8, tool_def.repo);
            
            const tool = ZigLibsTool{
                .name = name,
                .description = description,
                .repository = repository,
                .category = tool_def.category,
                .installation_method = tool_def.install_method,
            };
            
            try self.tools.append(self.allocator, tool);
        }
    }
    
    pub fn getPackagesByCategory(self: *const ZigLibsIntegration, category: ZigLibsPackage.Category) std.ArrayList(*const ZigLibsPackage) {
        var result = std.ArrayList(*const ZigLibsPackage).init(self.allocator);
        
        for (self.packages.items) |*pkg| {
            if (pkg.category == category) {
                result.append(pkg) catch break;
            }
        }
        
        return result;
    }
    
    pub fn getToolsByCategory(self: *const ZigLibsIntegration, category: ZigLibsTool.ToolCategory) std.ArrayList(*const ZigLibsTool) {
        var result = std.ArrayList(*const ZigLibsTool).init(self.allocator);
        
        for (self.tools.items) |*tool| {
            if (tool.category == category) {
                result.append(tool) catch break;
            }
        }
        
        return result;
    }
    
    pub fn findPackage(self: *const ZigLibsIntegration, name: []const u8) ?*const ZigLibsPackage {
        for (self.packages.items) |*pkg| {
            if (std.mem.eql(u8, pkg.name, name)) {
                return pkg;
            }
        }
        return null;
    }
    
    pub fn findTool(self: *const ZigLibsIntegration, name: []const u8) ?*const ZigLibsTool {
        for (self.tools.items) |*tool| {
            if (std.mem.eql(u8, tool.name, name)) {
                return tool;
            }
        }
        return null;
    }
    
    pub fn searchPackages(self: *const ZigLibsIntegration, query: []const u8, allocator: Allocator) !std.ArrayList(*const ZigLibsPackage) {
        var results = std.ArrayList(*const ZigLibsPackage).init(allocator);
        
        for (self.packages.items) |*pkg| {
            // Search in name
            if (std.mem.indexOf(u8, pkg.name, query) != null) {
                try results.append(allocator, pkg);
                continue;
            }
            
            // Search in description
            if (pkg.description) |desc| {
                if (std.mem.indexOf(u8, desc, query) != null) {
                    try results.append(allocator, pkg);
                    continue;
                }
            }
        }
        
        return results;
    }
    
    pub fn generateBulkFetchScript(self: *const ZigLibsIntegration, package_names: []const []const u8, allocator: Allocator) ![]const u8 {
        var script = std.ArrayList(u8).init(allocator);
        try script.appendSlice(allocator, "#!/bin/bash\n");
        try script.appendSlice(allocator, "# ZigLibs Package Installation Script\n");
        try script.appendSlice(allocator, "# Generated by Zion Package Manager\n\n");
        
        try script.appendSlice(allocator, "echo \"🦎 Installing ZigLibs packages...\"\n\n");
        
        for (package_names) |pkg_name| {
            if (self.findPackage(pkg_name)) |pkg| {
                const fetch_cmd = try pkg.getZigFetchCommand(allocator);
                defer allocator.free(fetch_cmd);
                
                try script.writer().print("echo \"📦 Fetching {s}...\"\n", .{pkg_name});
                try script.writer().print("{s}\n", .{fetch_cmd});
                try script.appendSlice(allocator, "if [ $? -eq 0 ]; then\n");
                try script.writer().print("    echo \"✅ {s} installed successfully\"\n", .{pkg_name});
                try script.appendSlice(allocator, "else\n");
                try script.writer().print("    echo \"❌ Failed to install {s}\"\n", .{pkg_name});
                try script.appendSlice(allocator, "fi\n\n");
            }
        }
        
        try script.appendSlice(allocator, "echo \"🎉 ZigLibs package installation complete!\"\n");
        
        return script.toOwnedSlice();
    }
};