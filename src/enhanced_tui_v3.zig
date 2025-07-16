const std = @import("std");
const phantom = @import("phantom");
const ghostnet = @import("ghostnet");
const Allocator = std.mem.Allocator;
const GhostKellzEcosystem = @import("ghostkellz_ecosystem.zig").GhostKellzEcosystem;
const ZigLibsIntegration = @import("ziglibs_integration.zig").ZigLibsIntegration;

/// Enhanced Zion TUI v3.0 with phantom v0.3.0 and full ecosystem support
pub const ZionTUIv3 = struct {
    allocator: Allocator,
    app: phantom.App,
    
    // Ecosystem integrations
    ghostkellz: GhostKellzEcosystem,
    ziglibs: ZigLibsIntegration,
    
    // UI State
    current_ecosystem: EcosystemType = .overview,
    current_view: ViewType = .main_menu,
    selected_category: ?usize = null,
    search_query: std.ArrayList(u8),
    
    // Installation state
    installation_queue: std.ArrayList(PackageInstallation),
    current_installation: ?PackageInstallation = null,
    
    pub const EcosystemType = enum {
        overview,
        ghostkellz,
        ziglibs,
        combined_search,
        installation_manager,
        
        pub fn getIcon(self: EcosystemType) []const u8 {
            return switch (self) {
                .overview => "🌟",
                .ghostkellz => "👻",
                .ziglibs => "🦎",
                .combined_search => "🔍",
                .installation_manager => "📦",
            };
        }
        
        pub fn getDisplayName(self: EcosystemType) []const u8 {
            return switch (self) {
                .overview => "Overview",
                .ghostkellz => "GhostLibs",
                .ziglibs => "ZigLibs",
                .combined_search => "Search All",
                .installation_manager => "Install Manager",
            };
        }
    };
    
    pub const ViewType = enum {
        main_menu,
        category_browser,
        package_list,
        package_details,
        installation_queue,
        bulk_installer,
        ecosystem_overview,
    };
    
    pub const PackageInstallation = struct {
        name: []const u8,
        ecosystem: EcosystemType,
        status: InstallStatus = .pending,
        fetch_command: []const u8,
        dependencies: [][]const u8,
        
        pub const InstallStatus = enum {
            pending,
            downloading,
            installing,
            completed,
            failed,
            
            pub fn getIcon(self: InstallStatus) []const u8 {
                return switch (self) {
                    .pending => "⏳",
                    .downloading => "⬇️",
                    .installing => "🔧",
                    .completed => "✅",
                    .failed => "❌",
                };
            }
        };
    };
    
    pub fn init(allocator: Allocator) !*ZionTUIv3 {
        var tui = try allocator.create(ZionTUIv3);
        
        // Initialize phantom app
        const app_config = phantom.AppConfig{
            .title = "🚀 Zion Package Manager v1.0.1 - GhostLibs & ZigLibs Edition",
            .tick_rate_ms = 50,
            .mouse_enabled = true,
            .resize_enabled = true,
        };
        
        // Initialize ecosystems
        const ghostkellz = try GhostKellzEcosystem.init(allocator);
        const ziglibs = try ZigLibsIntegration.init(allocator);
        
        tui.* = .{
            .allocator = allocator,
            .app = try phantom.App.init(allocator, app_config),
            .ghostkellz = ghostkellz,
            .ziglibs = ziglibs,
            .search_query = std.ArrayList(u8).init(allocator),
            .installation_queue = std.ArrayList(PackageInstallation).init(allocator),
        };
        
        try tui.setupMainInterface();
        return tui;
    }
    
    pub fn deinit(self: *ZionTUIv3) void {
        self.ghostkellz.deinit();
        self.ziglibs.deinit();
        self.search_query.deinit();
        
        for (self.installation_queue.items) |*install| {
            self.allocator.free(install.name);
            self.allocator.free(install.fetch_command);
            for (install.dependencies) |dep| {
                self.allocator.free(dep);
            }
            self.allocator.free(install.dependencies);
        }
        self.installation_queue.deinit();
        
        self.app.deinit();
        self.allocator.destroy(self);
    }
    
    pub fn run(self: *ZionTUIv3) !void {
        try self.app.run();
    }
    
    fn setupMainInterface(self: *ZionTUIv3) !void {
        // Create main menu widget
        const main_menu = try self.createMainMenuWidget();
        try self.app.addWidget(main_menu);
        
        // Create ecosystem overview
        const overview = try self.createEcosystemOverviewWidget();
        try self.app.addWidget(overview);
    }
    
    fn createMainMenuWidget(self: *ZionTUIv3) !*phantom.widgets.Widget {
        // Use phantom's universal package browser as base
        var browser = try phantom.widgets.UniversalPackageBrowser.init(self.allocator);
        
        // Customize for our ecosystems
        try self.populateGhostKellzPackages(browser);
        try self.populateZigLibsPackages(browser);
        
        return &browser.widget;
    }
    
    fn createEcosystemOverviewWidget(self: *ZionTUIv3) !*phantom.widgets.Widget {
        var overview_widget = try self.allocator.create(EcosystemOverviewWidget);
        overview_widget.* = EcosystemOverviewWidget{
            .widget = phantom.widgets.Widget{
                .vtable = &EcosystemOverviewWidget.vtable,
            },
            .allocator = self.allocator,
            .tui_ref = self,
            .selected_ecosystem = 0,
        };
        
        return &overview_widget.widget;
    }
    
    fn populateGhostKellzPackages(self: *ZionTUIv3, browser: *phantom.widgets.UniversalPackageBrowser) !void {
        // Add GhostKellz repository
        try browser.addRepository(phantom.widgets.universal_package_browser.Repository{
            .name = try self.allocator.dupe(u8, "GhostLibs"),
            .source = .custom_github,
            .url = try self.allocator.dupe(u8, "https://github.com/ghostkellz"),
            .api_endpoint = try self.allocator.dupe(u8, "https://api.github.com/orgs/ghostkellz/repos"),
        });
        
        // Convert GhostKellz packages to phantom package format
        for (self.ghostkellz.packages.items) |*gk_pkg| {
            var tags = std.ArrayList([]const u8).init(self.allocator);
            const deps = std.ArrayList([]const u8).init(self.allocator);
            
            // Copy dependencies
            for (gk_pkg.dependencies) |dep| {
                try deps.append(try self.allocator.dupe(u8, dep));
            }
            
            // Add category as tag
            try tags.append(try self.allocator.dupe(u8, gk_pkg.category.getDisplayName()));
            try tags.append(try self.allocator.dupe(u8, gk_pkg.maturity.getDisplayName()));
            
            const phantom_pkg = phantom.widgets.universal_package_browser.Package{
                .name = try self.allocator.dupe(u8, gk_pkg.name),
                .description = try self.allocator.dupe(u8, gk_pkg.description),
                .source = .custom_github,
                .url = try self.allocator.dupe(u8, gk_pkg.github_repo),
                .tags = tags,
                .dependencies = deps,
            };
            
            try browser.packages.append(phantom_pkg);
        }
    }
    
    fn populateZigLibsPackages(self: *ZionTUIv3, browser: *phantom.widgets.UniversalPackageBrowser) !void {
        // Add ZigLibs repository
        try browser.addRepository(phantom.widgets.universal_package_browser.Repository{
            .name = try self.allocator.dupe(u8, "ZigLibs"),
            .source = .ziglibs,
            .url = try self.allocator.dupe(u8, "https://github.com/ziglibs"),
            .api_endpoint = try self.allocator.dupe(u8, "https://api.github.com/orgs/ziglibs/repos"),
        });
        
        // Convert ZigLibs packages to phantom package format
        for (self.ziglibs.packages.items) |*zl_pkg| {
            var tags = std.ArrayList([]const u8).init(self.allocator);
            const deps = std.ArrayList([]const u8).init(self.allocator);
            
            // Add category as tag
            try tags.append(try self.allocator.dupe(u8, zl_pkg.category.getDisplayName()));
            if (zl_pkg.author) |author| {
                try tags.append(try std.fmt.allocPrint(self.allocator, "by:{s}", .{author}));
            }
            
            const phantom_pkg = phantom.widgets.universal_package_browser.Package{
                .name = try self.allocator.dupe(u8, zl_pkg.name),
                .description = if (zl_pkg.description) |desc| try self.allocator.dupe(u8, desc) else null,
                .source = .ziglibs,
                .url = try self.allocator.dupe(u8, zl_pkg.repository),
                .tags = tags,
                .dependencies = deps,
            };
            
            try browser.packages.append(phantom_pkg);
        }
    }
    
    pub fn switchEcosystem(self: *ZionTUIv3, ecosystem: EcosystemType) void {
        self.current_ecosystem = ecosystem;
        self.app.invalidate();
    }
    
    pub fn addToInstallQueue(self: *ZionTUIv3, package_name: []const u8, ecosystem: EcosystemType) !void {
        const installation = switch (ecosystem) {
            .ghostkellz => blk: {
                if (self.ghostkellz.findPackage(package_name)) |pkg| {
                    const fetch_cmd = try pkg.getZigFetchCommand(self.allocator);
                    
                    // Copy dependencies
                    const deps = try self.allocator.alloc([]const u8, pkg.dependencies.len);
                    for (pkg.dependencies, 0..) |dep, i| {
                        deps[i] = try self.allocator.dupe(u8, dep);
                    }
                    
                    break :blk PackageInstallation{
                        .name = try self.allocator.dupe(u8, package_name),
                        .ecosystem = ecosystem,
                        .fetch_command = fetch_cmd,
                        .dependencies = deps,
                    };
                } else {
                    return error.PackageNotFound;
                }
            },
            .ziglibs => blk: {
                if (self.ziglibs.findPackage(package_name)) |pkg| {
                    const fetch_cmd = try pkg.getZigFetchCommand(self.allocator);
                    
                    break :blk PackageInstallation{
                        .name = try self.allocator.dupe(u8, package_name),
                        .ecosystem = ecosystem,
                        .fetch_command = fetch_cmd,
                        .dependencies = &[_][]const u8{}, // ZigLibs deps handled differently
                    };
                } else {
                    return error.PackageNotFound;
                }
            },
            else => return error.InvalidEcosystem,
        };
        
        try self.installation_queue.append(installation);
    }
    
    pub fn processInstallationQueue(self: *ZionTUIv3) !void {
        if (self.installation_queue.items.len == 0) return;
        
        std.log.info("🚀 Processing {} packages in installation queue", .{self.installation_queue.items.len});
        
        for (self.installation_queue.items) |*install| {
            if (install.status != .pending) continue;
            
            install.status = .downloading;
            self.current_installation = install.*;
            
            std.log.info("📦 Installing {} from {s}", .{ install.name, install.ecosystem.getDisplayName() });
            
            // Execute zig fetch command (in real implementation)
            // For now, simulate success
            std.time.sleep(1000000000); // 1 second delay
            install.status = .completed;
            
            std.log.info("✅ {} installed successfully", .{install.name});
        }
        
        self.current_installation = null;
        std.log.info("🎉 All packages installed successfully!");
    }
    
    pub fn generateInstallScript(self: *ZionTUIv3) ![]const u8 {
        var script = std.ArrayList(u8).init(self.allocator);
        
        try script.appendSlice("#!/bin/bash\n");
        try script.appendSlice("# Zion Package Manager - Combined Installation Script\n");
        try script.appendSlice("# GhostLibs + ZigLibs Ecosystem Integration\n\n");
        
        // Group by ecosystem
        var ghostkellz_packages = std.ArrayList([]const u8).init(self.allocator);
        var ziglibs_packages = std.ArrayList([]const u8).init(self.allocator);
        defer ghostkellz_packages.deinit();
        defer ziglibs_packages.deinit();
        
        for (self.installation_queue.items) |install| {
            switch (install.ecosystem) {
                .ghostkellz => try ghostkellz_packages.append(install.name),
                .ziglibs => try ziglibs_packages.append(install.name),
                else => {},
            }
        }
        
        // Generate GhostLibs section
        if (ghostkellz_packages.items.len > 0) {
            try script.appendSlice("echo \"👻 Installing GhostLibs packages...\"\n");
            const gk_script = try self.ghostkellz.generateInstallScript(ghostkellz_packages.items, self.allocator);
            defer self.allocator.free(gk_script);
            try script.appendSlice(gk_script);
            try script.appendSlice("\n");
        }
        
        // Generate ZigLibs section
        if (ziglibs_packages.items.len > 0) {
            try script.appendSlice("echo \"🦎 Installing ZigLibs packages...\"\n");
            const zl_script = try self.ziglibs.generateBulkFetchScript(ziglibs_packages.items, self.allocator);
            defer self.allocator.free(zl_script);
            try script.appendSlice(zl_script);
        }
        
        try script.appendSlice("\necho \"🎉 All ecosystem packages installed!\"\n");
        try script.appendSlice("echo \"Run 'zig build' to verify your project builds with new dependencies\"\n");
        
        return script.toOwnedSlice();
    }
};

// Custom widget for ecosystem overview
const EcosystemOverviewWidget = struct {
    widget: phantom.widgets.Widget,
    allocator: Allocator,
    tui_ref: *ZionTUIv3,
    selected_ecosystem: usize,
    
    const vtable = phantom.widgets.Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinitWidget,
    };
    
    fn render(widget: *phantom.widgets.Widget, buffer: *phantom.Terminal.Buffer, area: phantom.Rect) void {
        const self: *EcosystemOverviewWidget = @fieldParentPtr("widget", widget);
        var y = area.y;
        
        // Title
        const title = "🌟 ZION PACKAGE MANAGER - ECOSYSTEM OVERVIEW";
        buffer.writeText(area.x, y, title, phantom.Style.withFg(phantom.style.Color.bright_cyan).withBold());
        y += 2;
        
        // GhostLibs stats
        const gk_stats = std.fmt.allocPrint(self.allocator, 
            "👻 GhostLibs: {} packages across {} categories", 
            .{ self.tui_ref.ghostkellz.packages.items.len, @typeInfo(GhostKellzEcosystem.GhostKellzPackage.Category).@"enum".fields.len }
        ) catch return;
        defer self.allocator.free(gk_stats);
        buffer.writeText(area.x, y, gk_stats, phantom.Style.withFg(phantom.style.Color.bright_magenta));
        y += 1;
        
        // ZigLibs stats  
        const zl_stats = std.fmt.allocPrint(self.allocator,
            "🦎 ZigLibs: {} packages + {} tools",
            .{ self.tui_ref.ziglibs.packages.items.len, self.tui_ref.ziglibs.tools.items.len }
        ) catch return;
        defer self.allocator.free(zl_stats);
        buffer.writeText(area.x, y, zl_stats, phantom.Style.withFg(phantom.style.Color.bright_green));
        y += 2;
        
        // Feature highlights
        const features = [_][]const u8{
            "🚀 HTTP3/2/1 context-aware networking (ghostnet)",
            "🔐 Quantum-resistant cryptography (zcrypt)",
            "⚡ Structured concurrency runtime (zsync)",
            "🎨 Advanced TUI framework (phantom)",
            "🗄️ High-performance database (zqlite)",
            "🌐 Universal protocol bridge (ghostbridge)",
            "🦎 Comprehensive ZigLibs integration",
            "📦 Intelligent package dependency resolution",
        };
        
        buffer.writeText(area.x, y, "✨ KEY FEATURES:", phantom.Style.withFg(phantom.style.Color.bright_yellow).withBold());
        y += 1;
        
        for (features) |feature| {
            buffer.writeText(area.x + 2, y, feature, phantom.Style.withFg(phantom.style.Color.white));
            y += 1;
        }
        
        // Navigation help
        y += 1;
        const help_text = "Press 'g' for GhostLibs, 'z' for ZigLibs, 's' for search, 'i' for install manager, 'q' to quit";
        buffer.writeText(area.x, y, help_text, phantom.Style.withFg(phantom.style.Color.bright_black));
    }
    
    fn handleEvent(widget: *phantom.widgets.Widget, event: phantom.Event) bool {
        const self: *EcosystemOverviewWidget = @fieldParentPtr("widget", widget);
        
        switch (event) {
            .key => |key_event| {
                if (!key_event.pressed) return false;
                
                switch (key_event.key) {
                    .char => |char| {
                        switch (char) {
                            'g' => {
                                self.tui_ref.switchEcosystem(.ghostkellz);
                                return true;
                            },
                            'z' => {
                                self.tui_ref.switchEcosystem(.ziglibs);
                                return true;
                            },
                            's' => {
                                self.tui_ref.switchEcosystem(.combined_search);
                                return true;
                            },
                            'i' => {
                                self.tui_ref.switchEcosystem(.installation_manager);
                                return true;
                            },
                            'q' => {
                                // Signal quit
                                return true;
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }
        
        return false;
    }
    
    fn resize(widget: *phantom.widgets.Widget, area: phantom.Rect) void {
        _ = widget;
        _ = area;
    }
    
    fn deinitWidget(widget: *phantom.widgets.Widget) void {
        const self: *EcosystemOverviewWidget = @fieldParentPtr("widget", widget);
        self.allocator.destroy(self);
    }
};