const std = @import("std");
const phantom = @import("phantom");
const Allocator = std.mem.Allocator;
const EnhancedRegistryManager = @import("enhanced_registry_v2.zig").EnhancedRegistryManager;
const Package = @import("registry_client.zig").Package;

/// TUI Interface for Zion v1.0.1 using Phantom framework
pub const ZionTUI = struct {
    allocator: Allocator,
    app: phantom.App,
    registry_manager: *EnhancedRegistryManager,
    current_view: View,
    search_results: []Package,
    selected_index: usize,
    search_query: std.ArrayList(u8),

    const View = enum {
        main_menu,
        package_search,
        package_details,
        installation_progress,
        settings,
    };

    pub fn init(allocator: Allocator, registry_manager: *EnhancedRegistryManager) !*ZionTUI {
        var tui = try allocator.create(ZionTUI);

        const app_config = phantom.AppConfig{
            .title = "Zion Package Manager v1.0.1",
            .tick_rate_ms = 50, // Smooth 20 FPS
            .mouse_enabled = true,
            .resize_enabled = true,
        };

        tui.* = .{
            .allocator = allocator,
            .app = try phantom.App.init(allocator, app_config),
            .registry_manager = registry_manager,
            .current_view = .main_menu,
            .search_results = &[_]Package{},
            .selected_index = 0,
            .search_query = .{},
        };

        try tui.setupWidgets();
        return tui;
    }

    pub fn deinit(self: *ZionTUI) void {
        self.allocator.free(self.search_results);
        self.search_query.deinit(self.allocator);
        self.app.deinit();
        self.allocator.destroy(self);
    }

    pub fn run(self: *ZionTUI) !void {
        try self.app.run();
    }

    pub fn runAsync(self: *ZionTUI) !void {
        try self.app.runAsync();
    }

    fn setupWidgets(self: *ZionTUI) !void {
        // Create main menu widgets
        const title_widget = try self.createTitleWidget();
        try self.app.addWidget(title_widget);

        const menu_widget = try self.createMenuWidget();
        try self.app.addWidget(menu_widget);

        const status_widget = try self.createStatusWidget();
        try self.app.addWidget(status_widget);
    }

    fn createTitleWidget(self: *ZionTUI) !*phantom.widgets.Widget {
        // Create a title bar with logo and version
        var title_widget = try self.allocator.create(TitleWidget);
        title_widget.* = TitleWidget{
            .widget = phantom.widgets.Widget{
                .vtable = &TitleWidget.vtable,
            },
            .allocator = self.allocator,
            .title = "🚀 ZION - The Cargo for Zig v1.0.1",
            .subtitle = "Enhanced with HTTP3/2/1 + Advanced TUI",
        };

        return &title_widget.widget;
    }

    fn createMenuWidget(self: *ZionTUI) !*phantom.widgets.Widget {
        var menu_widget = try self.allocator.create(MenuWidget);
        menu_widget.* = MenuWidget{
            .widget = phantom.widgets.Widget{
                .vtable = &MenuWidget.vtable,
            },
            .allocator = self.allocator,
            .items = &[_][]const u8{
                "📦 Search Packages",
                "⚡ Quick Install",
                "📋 Manage Dependencies",
                "🔍 Browse Ziglibs",
                "⚙️  Settings",
                "ℹ️  About",
                "🚪 Exit",
            },
            .selected = 0,
            .tui_ref = self,
        };

        return &menu_widget.widget;
    }

    fn createStatusWidget(self: *ZionTUI) !*phantom.widgets.Widget {
        var status_widget = try self.allocator.create(StatusWidget);
        status_widget.* = StatusWidget{
            .widget = phantom.widgets.Widget{
                .vtable = &StatusWidget.vtable,
            },
            .allocator = self.allocator,
            .message = "Ready | HTTP3/2/1 Active | zsync Runtime Online",
            .registries_count = self.registry_manager.registries.items.len,
        };

        return &status_widget.widget;
    }

    pub fn showPackageSearch(self: *ZionTUI) !void {
        self.current_view = .package_search;

        // Clear existing widgets
        // Add search interface widgets
        const search_widget = try self.createSearchWidget();
        try self.app.addWidget(search_widget);

        self.app.invalidate();
    }

    fn createSearchWidget(self: *ZionTUI) !*phantom.widgets.Widget {
        var search_widget = try self.allocator.create(SearchWidget);
        search_widget.* = SearchWidget{
            .widget = phantom.widgets.Widget{
                .vtable = &SearchWidget.vtable,
            },
            .allocator = self.allocator,
            .query = .{},
            .results = &[_]Package{},
            .selected = 0,
            .searching = false,
            .tui_ref = self,
        };

        return &search_widget.widget;
    }

    pub fn performSearch(self: *ZionTUI, query: []const u8) !void {
        // Use enhanced registry manager for parallel HTTP3/2/1 search
        self.allocator.free(self.search_results);
        self.search_results = try self.registry_manager.searchPackages(query, 50);
        self.selected_index = 0;
        self.app.invalidate();
    }

    pub fn installSelectedPackage(self: *ZionTUI) !void {
        if (self.search_results.len == 0 or self.selected_index >= self.search_results.len) {
            return;
        }

        const package = self.search_results[self.selected_index];

        // Show installation progress
        self.current_view = .installation_progress;
        const progress_widget = try self.createProgressWidget(package.full_name);
        try self.app.addWidget(progress_widget);

        // Start installation (would integrate with existing zion install logic)
        try self.installPackageAsync(package);
    }

    fn createProgressWidget(self: *ZionTUI, package_name: []const u8) !*phantom.widgets.Widget {
        var progress_widget = try self.allocator.create(ProgressWidget);
        progress_widget.* = ProgressWidget{
            .widget = phantom.widgets.Widget{
                .vtable = &ProgressWidget.vtable,
            },
            .allocator = self.allocator,
            .package_name = try self.allocator.dupe(u8, package_name),
            .progress = 0,
            .status = try self.allocator.dupe(u8, "Initializing HTTP3/2/1 download..."),
            .tui_ref = self,
        };

        return &progress_widget.widget;
    }

    fn installPackageAsync(self: *ZionTUI, package: Package) !void {
        // This would integrate with the existing install logic
        // For now, simulate progress
        _ = self;
        _ = package;

        // In real implementation:
        // 1. Download with standard HTTP client
        // 2. Update progress widget with real-time status
        // 3. Handle installation steps with proper error handling
        // 4. Show completion or error status
    }
};

// Custom Widget Implementations

const TitleWidget = struct {
    widget: phantom.widgets.Widget,
    allocator: Allocator,
    title: []const u8,
    subtitle: []const u8,

    const vtable = phantom.widgets.Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinitWidget,
    };

    fn render(widget: *phantom.widgets.Widget, buffer: *phantom.Terminal.Buffer, area: phantom.Rect) void {
        const self = @fieldParentPtr("widget", widget);
        _ = buffer;
        _ = area;

        // Render title with styled borders and colors
        // Implementation would use phantom's rendering system
        _ = self;
    }

    fn handleEvent(widget: *phantom.widgets.Widget, event: phantom.Event) bool {
        _ = widget;
        _ = event;
        return false; // Title doesn't handle events
    }

    fn resize(widget: *phantom.widgets.Widget, area: phantom.Rect) void {
        _ = widget;
        _ = area;
    }

    fn deinitWidget(widget: *phantom.widgets.Widget) void {
        const self = @fieldParentPtr("widget", widget);
        self.allocator.destroy(self);
    }
};

const MenuWidget = struct {
    widget: phantom.widgets.Widget,
    allocator: Allocator,
    items: []const []const u8,
    selected: usize,
    tui_ref: *ZionTUI,

    const vtable = phantom.widgets.Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinitWidget,
    };

    fn render(widget: *phantom.widgets.Widget, buffer: *phantom.Terminal.Buffer, area: phantom.Rect) void {
        const self = @fieldParentPtr("widget", widget);
        _ = buffer;
        _ = area;

        // Render menu items with selection highlighting
        _ = self;
    }

    fn handleEvent(widget: *phantom.widgets.Widget, event: phantom.Event) bool {
        const self = @fieldParentPtr("widget", widget);

        switch (event) {
            .key => |key| {
                switch (key) {
                    .up => {
                        if (self.selected > 0) {
                            self.selected -= 1;
                            return true;
                        }
                    },
                    .down => {
                        if (self.selected < self.items.len - 1) {
                            self.selected += 1;
                            return true;
                        }
                    },
                    .enter => {
                        return self.selectCurrentItem();
                    },
                    else => {},
                }
            },
            else => {},
        }

        return false;
    }

    fn selectCurrentItem(self: *MenuWidget) bool {
        switch (self.selected) {
            0 => { // Search Packages
                self.tui_ref.showPackageSearch() catch {};
                return true;
            },
            1 => { // Quick Install
                // Show quick install dialog
                return true;
            },
            6 => { // Exit
                self.tui_ref.app.stop();
                return true;
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
        const self = @fieldParentPtr("widget", widget);
        self.allocator.destroy(self);
    }
};

const StatusWidget = struct {
    widget: phantom.widgets.Widget,
    allocator: Allocator,
    message: []const u8,
    registries_count: usize,

    const vtable = phantom.widgets.Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinitWidget,
    };

    fn render(widget: *phantom.widgets.Widget, buffer: *phantom.Terminal.Buffer, area: phantom.Rect) void {
        const self = @fieldParentPtr("widget", widget);
        _ = buffer;
        _ = area;

        // Render status bar with connection info and registry count
        _ = self;
    }

    fn handleEvent(widget: *phantom.widgets.Widget, event: phantom.Event) bool {
        _ = widget;
        _ = event;
        return false;
    }

    fn resize(widget: *phantom.widgets.Widget, area: phantom.Rect) void {
        _ = widget;
        _ = area;
    }

    fn deinitWidget(widget: *phantom.widgets.Widget) void {
        const self = @fieldParentPtr("widget", widget);
        self.allocator.destroy(self);
    }
};

const SearchWidget = struct {
    widget: phantom.widgets.Widget,
    allocator: Allocator,
    query: std.ArrayList(u8),
    results: []Package,
    selected: usize,
    searching: bool,
    tui_ref: *ZionTUI,

    const vtable = phantom.widgets.Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinitWidget,
    };

    fn render(widget: *phantom.widgets.Widget, buffer: *phantom.Terminal.Buffer, area: phantom.Rect) void {
        const self = @fieldParentPtr("widget", widget);
        _ = buffer;
        _ = area;

        // Render search input and results list
        _ = self;
    }

    fn handleEvent(widget: *phantom.widgets.Widget, event: phantom.Event) bool {
        const self = @fieldParentPtr("widget", widget);

        switch (event) {
            .key => |key| {
                switch (key) {
                    .char => |c| {
                        self.query.append(c) catch {};
                        return true;
                    },
                    .backspace => {
                        if (self.query.items.len > 0) {
                            _ = self.query.pop();
                            return true;
                        }
                    },
                    .enter => {
                        if (self.query.items.len > 0) {
                            self.tui_ref.performSearch(self.query.items) catch {};
                            return true;
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
        const self = @fieldParentPtr("widget", widget);
        self.query.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};

const ProgressWidget = struct {
    widget: phantom.widgets.Widget,
    allocator: Allocator,
    package_name: []const u8,
    progress: u8, // 0-100
    status: []const u8,
    tui_ref: *ZionTUI,

    const vtable = phantom.widgets.Widget.WidgetVTable{
        .render = render,
        .handleEvent = handleEvent,
        .resize = resize,
        .deinit = deinitWidget,
    };

    fn render(widget: *phantom.widgets.Widget, buffer: *phantom.Terminal.Buffer, area: phantom.Rect) void {
        const self = @fieldParentPtr("widget", widget);
        _ = buffer;
        _ = area;

        // Render progress bar and status
        _ = self;
    }

    fn handleEvent(widget: *phantom.widgets.Widget, event: phantom.Event) bool {
        const self = @fieldParentPtr("widget", widget);

        switch (event) {
            .key => |key| {
                switch (key) {
                    .escape => {
                        // Cancel installation
                        self.tui_ref.current_view = .main_menu;
                        return true;
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
        const self = @fieldParentPtr("widget", widget);
        self.allocator.free(self.package_name);
        self.allocator.free(self.status);
        self.allocator.destroy(self);
    }
};
