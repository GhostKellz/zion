const std = @import("std");
const phantom = @import("phantom");
const Allocator = std.mem.Allocator;

pub const TUIError = error{
    TerminalNotSupported,
    InvalidInput,
    RenderFailed,
};

pub const Theme = struct {
    primary: u8 = 33,    // Yellow
    secondary: u8 = 36,  // Cyan  
    success: u8 = 32,    // Green
    warning: u8 = 33,    // Yellow
    error_color: u8 = 31,      // Red
    info: u8 = 34,       // Blue
    muted: u8 = 90,      // Gray
    background: u8 = 0,  // Black
    foreground: u8 = 37, // White
};

pub const Package = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    author: []const u8,
    downloads: u64,
    stars: u32,
    last_updated: []const u8,
    categories: [][]const u8,
    dependencies: [][]const u8,
    
    pub fn deinit(self: *Package, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.version);
        allocator.free(self.description);
        allocator.free(self.author);
        allocator.free(self.last_updated);
        
        for (self.categories) |cat| {
            allocator.free(cat);
        }
        allocator.free(self.categories);
        
        for (self.dependencies) |dep| {
            allocator.free(dep);
        }
        allocator.free(self.dependencies);
    }
};

pub const SearchState = struct {
    query: std.ArrayList(u8),
    results: []Package,
    selected_index: usize,
    scroll_offset: usize,
    total_results: u64,
    loading: bool,
    
    pub fn init(allocator: Allocator) SearchState {
        _ = allocator;
        return SearchState{
            .query = .{},
            .results = &[_]Package{},
            .selected_index = 0,
            .scroll_offset = 0,
            .total_results = 0,
            .loading = false,
        };
    }
    
    pub fn deinit(self: *SearchState, allocator: Allocator) void {
        self.query.deinit(allocator);
        
        for (self.results) |*pkg| {
            pkg.deinit(allocator);
        }
        allocator.free(self.results);
    }
};

pub const InstallationStatus = enum {
    pending,
    downloading,
    extracting,
    building,
    completed,
    failed,
};

pub const InstallationProgress = struct {
    package_name: []const u8,
    status: InstallationStatus,
    progress_percent: u8,
    current_step: []const u8,
    error_message: ?[]const u8,
    
    pub fn deinit(self: *InstallationProgress, allocator: Allocator) void {
        allocator.free(self.package_name);
        allocator.free(self.current_step);
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
    }
};

pub const TUIState = enum {
    main_menu,
    package_search,
    package_details,
    installation_progress,
    dependency_tree,
    settings,
    help,
};

pub const EnhancedTUI = struct {
    allocator: Allocator,
    theme: Theme,
    state: TUIState,
    terminal_width: u16,
    terminal_height: u16,
    search_state: SearchState,
    installations: std.ArrayList(InstallationProgress),
    selected_package: ?Package,
    show_dependencies: bool,
    
    pub fn init(allocator: Allocator) !EnhancedTUI {
        const size = try getTerminalSize();
        
        return EnhancedTUI{
            .allocator = allocator,
            .theme = Theme{},
            .state = .main_menu,
            .terminal_width = size.width,
            .terminal_height = size.height,
            .search_state = SearchState.init(allocator),
            .installations = .{},
            .selected_package = null,
            .show_dependencies = false,
        };
    }
    
    pub fn deinit(self: *EnhancedTUI) void {
        self.search_state.deinit(self.allocator);
        
        for (self.installations.items) |*install| {
            install.deinit(self.allocator);
        }
        self.installations.deinit(self.allocator);
        
        if (self.selected_package) |*pkg| {
            pkg.deinit(self.allocator);
        }
    }
    
    pub fn run(self: *EnhancedTUI) !void {
        try self.setupTerminal();
        defer self.restoreTerminal();
        
        while (true) {
            try self.render();
            
            const input = try self.getInput();
            const should_exit = try self.handleInput(input);
            if (should_exit) break;
        }
    }
    
    fn setupTerminal(self: *EnhancedTUI) !void {
        // Enable raw mode
        std.debug.print("\x1b[?1049h", .{}); // Alternative screen
        std.debug.print("\x1b[?25l", .{});   // Hide cursor
        std.debug.print("\x1b[2J", .{});     // Clear screen
        
        _ = self;
    }
    
    fn restoreTerminal(self: *EnhancedTUI) void {
        std.debug.print("\x1b[?25h", .{}); // Show cursor
        std.debug.print("\x1b[?1049l", .{}); // Restore screen
        _ = self;
    }
    
    fn render(self: *EnhancedTUI) !void {
        // Use debug.print for terminal output
        
        // Clear screen and reset cursor
        std.debug.print("\x1b[2J\x1b[H", .{});
        
        // Render header
        try self.renderHeader(writer);
        
        // Render content based on current state
        switch (self.state) {
            .main_menu => try self.renderMainMenu(writer),
            .package_search => try self.renderPackageSearch(writer),
            .package_details => try self.renderPackageDetails(writer),
            .installation_progress => try self.renderInstallationProgress(writer),
            .dependency_tree => try self.renderDependencyTree(writer),
            .settings => try self.renderSettings(writer),
            .help => try self.renderHelp(writer),
        }
        
        // Render footer
        try self.renderFooter(writer);
        
        try writer.print("\x1b[H", .{}); // Reset cursor to top
    }
    
    fn renderHeader(self: *EnhancedTUI, writer: anytype) !void {
        const title = "🌟 Zion Package Manager - Interactive Mode";
        const version = "v1.0.5";
        
        // Top border
        try writer.print("\x1b[{d}m", .{self.theme.primary});
        for (0..self.terminal_width) |_| try writer.print("═", .{});
        try writer.print("\n", .{});
        
        // Title line
        const padding = (self.terminal_width - title.len - version.len - 2) / 2;
        for (0..padding) |_| try writer.print(" ", .{});
        try writer.print("{s}", .{title});
        for (0..padding) |_| try writer.print(" ", .{});
        try writer.print("\x1b[{d}m{s}\x1b[{d}m", .{ self.theme.muted, version, self.theme.primary });
        try writer.print("\n", .{});
        
        // Bottom border
        for (0..self.terminal_width) |_| try writer.print("═", .{});
        try writer.print("\x1b[0m\n", .{});
    }
    
    fn renderMainMenu(self: *EnhancedTUI, writer: anytype) !void {
        try writer.print("\n", .{});
        
        const menu_items = [_]struct { key: u8, name: []const u8, desc: []const u8 }{
            .{ .key = '1', .name = "🔍 Search Packages", .desc = "Search and browse available packages" },
            .{ .key = '2', .name = "📦 Manage Dependencies", .desc = "View and manage project dependencies" },
            .{ .key = '3', .name = "🌳 Dependency Tree", .desc = "Visualize dependency relationships" },
            .{ .key = '4', .name = "📥 Installation Progress", .desc = "Monitor ongoing installations" },
            .{ .key = '5', .name = "⚙️  Settings", .desc = "Configure Zion preferences" },
            .{ .key = '6', .name = "❓ Help", .desc = "View help and documentation" },
            .{ .key = 'q', .name = "🚪 Quit", .desc = "Exit the interactive mode" },
        };
        
        const box_width = 60;
        const start_col = (self.terminal_width - box_width) / 2;
        
        for (menu_items) |item| {
            // Center the menu item
            for (0..start_col) |_| try writer.print(" ", .{});
            
            try writer.print("\x1b[{d}m[{c}]\x1b[{d}m {s}", .{ self.theme.primary, item.key, self.theme.foreground, item.name });
            
            const remaining_width = box_width - 4 - item.name.len;
            for (0..@min(remaining_width, 20)) |_| try writer.print(" ", .{});
            
            try writer.print("\x1b[{d}m{s}\x1b[0m\n", .{ self.theme.muted, item.desc });
        }
        
        try writer.print("\n", .{});
        
        // Stats section
        for (0..start_col) |_| try writer.print(" ", .{});
        try writer.print("\x1b[{d}m┌─ Quick Stats ─────────────────────────────────────────┐\x1b[0m\n", .{self.theme.secondary});
        
        const stats = [_]struct { label: []const u8, value: []const u8 }{
            .{ .label = "Installed packages", .value = "24" },
            .{ .label = "Available updates", .value = "3" },
            .{ .label = "Registry status", .value = "Online ✓" },
            .{ .label = "Cache size", .value = "156 MB" },
        };
        
        for (stats) |stat| {
            for (0..start_col) |_| try writer.print(" ", .{});
            try writer.print("\x1b[{d}m│\x1b[0m {s}: \x1b[{d}m{s}\x1b[0m", .{ self.theme.secondary, stat.label, self.theme.primary, stat.value });
            
            const padding_needed = box_width - 4 - stat.label.len - stat.value.len;
            for (0..padding_needed) |_| try writer.print(" ", .{});
            try writer.print("\x1b[{d}m│\x1b[0m\n", .{self.theme.secondary});
        }
        
        for (0..start_col) |_| try writer.print(" ", .{});
        try writer.print("\x1b[{d}m└───────────────────────────────────────────────────────┘\x1b[0m\n", .{self.theme.secondary});
    }
    
    fn renderPackageSearch(self: *EnhancedTUI, writer: anytype) !void {
        // Search input box
        try writer.print("\n\x1b[{d}m┌─ Package Search ─────────────────────────────────────────┐\x1b[0m\n", .{self.theme.primary});
        try writer.print("\x1b[{d}m│\x1b[0m Search: \x1b[{d}m{s}\x1b[0m", .{ self.theme.primary, self.theme.foreground, self.search_state.query.items });
        
        const query_padding = self.terminal_width - 12 - self.search_state.query.items.len;
        for (0..query_padding) |_| try writer.print(" ", .{});
        try writer.print("\x1b[{d}m│\x1b[0m\n", .{self.theme.primary});
        try writer.print("\x1b[{d}m└─────────────────────────────────────────────────────────┘\x1b[0m\n\n", .{self.theme.primary});
        
        if (self.search_state.loading) {
            try writer.print("  \x1b[{d}m🔄 Searching...\x1b[0m\n", .{self.theme.info});
            return;
        }
        
        if (self.search_state.results.len == 0) {
            if (self.search_state.query.items.len > 0) {
                try writer.print("  \x1b[{d}m❌ No packages found for '{s}'\x1b[0m\n", .{ self.theme.warning, self.search_state.query.items });
            } else {
                try writer.print("  \x1b[{d}m💡 Enter a search term to find packages\x1b[0m\n", .{self.theme.info});
            }
            return;
        }
        
        // Results header
        try writer.print("  Found \x1b[{d}m{d}\x1b[0m packages:\n\n", .{ self.theme.primary, self.search_state.total_results });
        
        // Render package list
        const visible_results = @min(self.search_state.results.len, self.terminal_height - 10);
        const end_index = @min(self.search_state.scroll_offset + visible_results, self.search_state.results.len);
        
        for (self.search_state.scroll_offset..end_index) |i| {
            const pkg = self.search_state.results[i];
            const is_selected = i == self.search_state.selected_index;
            
            if (is_selected) {
                try writer.print("  \x1b[{d}m▶ \x1b[0m", .{self.theme.primary});
            } else {
                try writer.print("    ", .{});
            }
            
            // Package name and version
            try writer.print("\x1b[{d}m{s}\x1b[0m \x1b[{d}mv{s}\x1b[0m", .{ self.theme.foreground, pkg.name, self.theme.muted, pkg.version });
            
            // Stats
            try writer.print(" \x1b[{d}m({d} ⬇ {d} ⭐)\x1b[0m\n", .{ self.theme.muted, pkg.downloads, pkg.stars });
            
            // Description
            const desc_prefix = if (is_selected) "    " else "      ";
            try writer.print("{s}\x1b[{d}m{s}\x1b[0m\n", .{ desc_prefix, self.theme.muted, pkg.description });
            
            // Categories
            if (pkg.categories.len > 0) {
                try writer.print("{s}\x1b[{d}m", .{ desc_prefix, self.theme.info });
                for (pkg.categories, 0..) |cat, cat_i| {
                    if (cat_i > 0) try writer.print(" • ", .{});
                    try writer.print("{s}", .{cat});
                }
                try writer.print("\x1b[0m\n", .{});
            }
            
            try writer.print("\n", .{});
        }
        
        // Scroll indicators
        if (self.search_state.scroll_offset > 0) {
            try writer.print("  \x1b[{d}m↑ More results above\x1b[0m\n", .{self.theme.muted});
        }
        if (end_index < self.search_state.results.len) {
            try writer.print("  \x1b[{d}m↓ More results below\x1b[0m\n", .{self.theme.muted});
        }
    }
    
    fn renderPackageDetails(self: *EnhancedTUI, writer: anytype) !void {
        if (self.selected_package == null) {
            try writer.print("\n  \x1b[{d}m❌ No package selected\x1b[0m\n", .{self.theme.error_color});
            return;
        }
        
        const pkg = self.selected_package.?;
        
        // Package header
        try writer.print("\n\x1b[{d}m┌─ Package Details ────────────────────────────────────────┐\x1b[0m\n", .{self.theme.primary});
        try writer.print("\x1b[{d}m│\x1b[0m \x1b[1m{s}\x1b[0m v{s}", .{ self.theme.primary, pkg.name, pkg.version });
        
        const header_padding = self.terminal_width - 4 - pkg.name.len - pkg.version.len - 2;
        for (0..header_padding) |_| try writer.print(" ", .{});
        try writer.print("\x1b[{d}m│\x1b[0m\n", .{self.theme.primary});
        try writer.print("\x1b[{d}m└─────────────────────────────────────────────────────────┘\x1b[0m\n\n", .{self.theme.primary});
        
        // Package info
        try writer.print("  \x1b[{d}mAuthor:\x1b[0m {s}\n", .{ self.theme.info, pkg.author });
        try writer.print("  \x1b[{d}mDescription:\x1b[0m {s}\n", .{ self.theme.info, pkg.description });
        try writer.print("  \x1b[{d}mDownloads:\x1b[0m \x1b[{d}m{d}\x1b[0m\n", .{ self.theme.info, self.theme.primary, pkg.downloads });
        try writer.print("  \x1b[{d}mStars:\x1b[0m \x1b[{d}m{d}\x1b[0m\n", .{ self.theme.info, self.theme.primary, pkg.stars });
        try writer.print("  \x1b[{d}mLast Updated:\x1b[0m {s}\n\n", .{ self.theme.info, pkg.last_updated });
        
        // Categories
        if (pkg.categories.len > 0) {
            try writer.print("  \x1b[{d}mCategories:\x1b[0m ", .{self.theme.info});
            for (pkg.categories, 0..) |cat, i| {
                if (i > 0) try writer.print(", ", .{});
                try writer.print("\x1b[{d}m{s}\x1b[0m", .{ self.theme.secondary, cat });
            }
            try writer.print("\n\n", .{});
        }
        
        // Dependencies
        if (pkg.dependencies.len > 0) {
            try writer.print("  \x1b[{d}mDependencies ({d}):\x1b[0m\n", .{ self.theme.info, pkg.dependencies.len });
            for (pkg.dependencies) |dep| {
                try writer.print("    • \x1b[{d}m{s}\x1b[0m\n", .{ self.theme.foreground, dep });
            }
            try writer.print("\n", .{});
        }
        
        // Actions
        try writer.print("  \x1b[{d}mActions:\x1b[0m\n", .{self.theme.primary});
        try writer.print("    \x1b[{d}m[i]\x1b[0m Install package\n", .{self.theme.success});
        try writer.print("    \x1b[{d}m[d]\x1b[0m Show dependencies\n", .{self.theme.info});
        try writer.print("    \x1b[{d}m[ESC]\x1b[0m Back to search\n", .{self.theme.muted});
    }
    
    fn renderInstallationProgress(self: *EnhancedTUI, writer: anytype) !void {
        try writer.print("\n\x1b[{d}m┌─ Installation Progress ──────────────────────────────────┐\x1b[0m\n", .{self.theme.primary});
        
        if (self.installations.items.len == 0) {
            try writer.print("\x1b[{d}m│\x1b[0m  No installations in progress", .{self.theme.primary});
            const padding = self.terminal_width - 32;
            for (0..padding) |_| try writer.print(" ", .{});
            try writer.print("\x1b[{d}m│\x1b[0m\n", .{self.theme.primary});
        } else {
            for (self.installations.items) |install| {
                try writer.print("\x1b[{d}m│\x1b[0m  ", .{self.theme.primary});
                
                // Status icon
                const icon = switch (install.status) {
                    .pending => "⏳",
                    .downloading => "⬇️ ",
                    .extracting => "📦",
                    .building => "🔨",
                    .completed => "✅",
                    .failed => "❌",
                };
                try writer.print("{s} \x1b[{d}m{s}\x1b[0m", .{ icon, self.theme.foreground, install.package_name });
                
                // Progress bar
                const bar_width = 20;
                const filled = (install.progress_percent * bar_width) / 100;
                try writer.print(" [", .{});
                
                for (0..bar_width) |i| {
                    if (i < filled) {
                        try writer.print("\x1b[{d}m█\x1b[0m", .{self.theme.success});
                    } else {
                        try writer.print("░", .{});
                    }
                }
                
                try writer.print("] {d}%%", .{install.progress_percent});
                
                const line_length = 6 + install.package_name.len + bar_width + 6;
                const remaining = self.terminal_width - line_length - 2;
                for (0..remaining) |_| try writer.print(" ", .{});
                try writer.print("\x1b[{d}m│\x1b[0m\n", .{self.theme.primary});
                
                // Current step
                try writer.print("\x1b[{d}m│\x1b[0m    \x1b[{d}m{s}\x1b[0m", .{ self.theme.primary, self.theme.muted, install.current_step });
                const step_padding = self.terminal_width - 6 - install.current_step.len;
                for (0..step_padding) |_| try writer.print(" ", .{});
                try writer.print("\x1b[{d}m│\x1b[0m\n", .{self.theme.primary});
                
                // Error message
                if (install.error_message) |error_msg| {
                    try writer.print("\x1b[{d}m│\x1b[0m    \x1b[{d}m⚠️  {s}\x1b[0m", .{ self.theme.primary, self.theme.error_color, error_msg });
                    const error_padding = self.terminal_width - 8 - error_msg.len;
                    for (0..error_padding) |_| try writer.print(" ", .{});
                    try writer.print("\x1b[{d}m│\x1b[0m\n", .{self.theme.primary});
                }
            }
        }
        
        try writer.print("\x1b[{d}m└─────────────────────────────────────────────────────────┘\x1b[0m\n", .{self.theme.primary});
    }
    
    fn renderDependencyTree(self: *EnhancedTUI, writer: anytype) !void {
        try writer.print("\n\x1b[{d}m┌─ Dependency Tree ────────────────────────────────────────┐\x1b[0m\n", .{self.theme.primary});
        try writer.print("\x1b[{d}m│\x1b[0m  📦 my-project v1.0.0", .{self.theme.primary});
        const padding = self.terminal_width - 20;
        for (0..padding) |_| try writer.print(" ", .{});
        try writer.print("\x1b[{d}m│\x1b[0m\n", .{self.theme.primary});
        
        // Sample dependency tree
        const deps = [_]struct { name: []const u8, version: []const u8, level: u8 }{
            .{ .name = "std", .version = "builtin", .level = 1 },
            .{ .name = "allocator-lib", .version = "2.1.0", .level = 1 },
            .{ .name = "json-parser", .version = "1.5.2", .level = 1 },
            .{ .name = "base64", .version = "0.3.1", .level = 2 },
            .{ .name = "crypto-utils", .version = "3.2.1", .level = 2 },
            .{ .name = "http-client", .version = "4.1.0", .level = 1 },
            .{ .name = "tls-lib", .version = "1.8.3", .level = 2 },
        };
        
        for (deps) |dep| {
            try writer.print("\x1b[{d}m│\x1b[0m  ", .{self.theme.primary});
            
            // Indentation
            for (0..dep.level * 2) |_| try writer.print(" ", .{});
            
            // Branch character
            if (dep.level > 0) {
                try writer.print("├─ ", .{});
            }
            
            try writer.print("\x1b[{d}m{s}\x1b[0m \x1b[{d}mv{s}\x1b[0m", .{ self.theme.foreground, dep.name, self.theme.muted, dep.version });
            
            const line_len = 4 + dep.level * 2 + (if (dep.level > 0) @as(usize, 3) else 0) + dep.name.len + dep.version.len + 2;
            const remaining = self.terminal_width - line_len;
            for (0..remaining) |_| try writer.print(" ", .{});
            try writer.print("\x1b[{d}m│\x1b[0m\n", .{self.theme.primary});
        }
        
        try writer.print("\x1b[{d}m└─────────────────────────────────────────────────────────┘\x1b[0m\n", .{self.theme.primary});
    }
    
    fn renderSettings(self: *EnhancedTUI, writer: anytype) !void {
        try writer.print("\n\x1b[{d}m┌─ Settings ───────────────────────────────────────────────┐\x1b[0m\n", .{self.theme.primary});
        
        const settings = [_]struct { name: []const u8, value: []const u8, description: []const u8 }{
            .{ .name = "Default Registry", .value = "registry.zion.pm", .description = "Primary package registry" },
            .{ .name = "Cache Directory", .value = "~/.zion/cache", .description = "Local package cache location" },
            .{ .name = "Auto Update", .value = "enabled", .description = "Automatically check for updates" },
            .{ .name = "Parallel Downloads", .value = "4", .description = "Max concurrent downloads" },
            .{ .name = "Build Cache", .value = "enabled", .description = "Cache build artifacts" },
            .{ .name = "Theme", .value = "default", .description = "TUI color theme" },
        };
        
        for (settings) |setting| {
            try writer.print("\x1b[{d}m│\x1b[0m  \x1b[{d}m{s}:\x1b[0m \x1b[{d}m{s}\x1b[0m", .{ self.theme.primary, self.theme.info, setting.name, self.theme.foreground, setting.value });
            
            const line_len = 4 + setting.name.len + 2 + setting.value.len;
            const remaining = self.terminal_width - line_len - 2;
            for (0..remaining) |_| try writer.print(" ", .{});
            try writer.print("\x1b[{d}m│\x1b[0m\n", .{self.theme.primary});
            
            try writer.print("\x1b[{d}m│\x1b[0m    \x1b[{d}m{s}\x1b[0m", .{ self.theme.primary, self.theme.muted, setting.description });
            const desc_padding = self.terminal_width - 6 - setting.description.len;
            for (0..desc_padding) |_| try writer.print(" ", .{});
            try writer.print("\x1b[{d}m│\x1b[0m\n", .{self.theme.primary});
        }
        
        try writer.print("\x1b[{d}m└─────────────────────────────────────────────────────────┘\x1b[0m\n", .{self.theme.primary});
    }
    
    fn renderHelp(self: *EnhancedTUI, writer: anytype) !void {
        try writer.print("\n\x1b[{d}m┌─ Help & Keyboard Shortcuts ─────────────────────────────┐\x1b[0m\n", .{self.theme.primary});
        
        const help_items = [_]struct { key: []const u8, action: []const u8 }{
            .{ .key = "↑/↓ or j/k", .action = "Navigate lists" },
            .{ .key = "Enter", .action = "Select item" },
            .{ .key = "ESC", .action = "Go back / Cancel" },
            .{ .key = "Tab", .action = "Switch between panels" },
            .{ .key = "Ctrl+C", .action = "Force quit" },
            .{ .key = "q", .action = "Quit (from main menu)" },
            .{ .key = "/", .action = "Start search" },
            .{ .key = "i", .action = "Install package" },
            .{ .key = "r", .action = "Remove package" },
            .{ .key = "u", .action = "Update package" },
            .{ .key = "Space", .action = "Toggle selection" },
            .{ .key = "F1", .action = "Show this help" },
        };
        
        for (help_items) |item| {
            try writer.print("\x1b[{d}m│\x1b[0m  \x1b[{d}m{s}\x1b[0m", .{ self.theme.primary, self.theme.primary, item.key });
            
            const key_width = 15;
            const padding = key_width - item.key.len;
            for (0..padding) |_| try writer.print(" ", .{});
            
            try writer.print("{s}", .{item.action});
            
            const line_len = 4 + key_width + item.action.len;
            const remaining = self.terminal_width - line_len - 2;
            for (0..remaining) |_| try writer.print(" ", .{});
            try writer.print("\x1b[{d}m│\x1b[0m\n", .{self.theme.primary});
        }
        
        try writer.print("\x1b[{d}m└─────────────────────────────────────────────────────────┘\x1b[0m\n", .{self.theme.primary});
        
        // Additional help text
        try writer.print("\n  \x1b[{d}m💡 Tips:\x1b[0m\n", .{self.theme.info});
        try writer.print("    • Use fuzzy search to find packages quickly\n", .{});
        try writer.print("    • Dependencies are automatically resolved\n", .{});
        try writer.print("    • Build cache speeds up repeated builds\n", .{});
        try writer.print("    • Press F1 from any screen for context help\n", .{});
    }
    
    fn renderFooter(self: *EnhancedTUI, writer: anytype) !void {
        const footer_y = self.terminal_height - 2;
        try writer.print("\x1b[{d};1H", .{footer_y});
        
        // Status bar
        try writer.print("\x1b[{d}m", .{self.theme.muted});
        for (0..self.terminal_width) |_| try writer.print("─", .{});
        try writer.print("\n", .{});
        
        // Status text
        const status_text = switch (self.state) {
            .main_menu => "Main Menu - Press number keys to navigate",
            .package_search => "Search Mode - Type to search, ↑↓ to navigate, Enter to select",
            .package_details => "Package Details - Press 'i' to install, ESC to go back", 
            .installation_progress => "Installation Progress - ESC to return to main menu",
            .dependency_tree => "Dependency Tree - ESC to return to main menu",
            .settings => "Settings - ESC to return to main menu",
            .help => "Help - ESC to return to previous screen",
        };
        
        try writer.print("{s}", .{status_text});
        
        // Right-aligned info
        const right_info = "F1: Help | Ctrl+C: Quit";
        const info_padding = self.terminal_width - status_text.len - right_info.len;
        for (0..info_padding) |_| try writer.print(" ", .{});
        try writer.print("{s}\x1b[0m", .{right_info});
    }
    
    fn getInput(self: *EnhancedTUI) !u8 {
        _ = self;
        // Simple input reading - in a real implementation, this would handle
        // arrow keys, function keys, etc.
        var buf: [1]u8 = undefined;
        _ = try std.io.getStdIn().read(&buf);
        return buf[0];
    }
    
    fn handleInput(self: *EnhancedTUI, input: u8) !bool {
        switch (self.state) {
            .main_menu => {
                switch (input) {
                    '1' => self.state = .package_search,
                    '2' => {}, // Manage dependencies - could implement
                    '3' => self.state = .dependency_tree,
                    '4' => self.state = .installation_progress,
                    '5' => self.state = .settings,
                    '6' => self.state = .help,
                    'q', 'Q' => return true, // Quit
                    3 => return true, // Ctrl+C
                    else => {},
                }
            },
            .package_search => {
                switch (input) {
                    27 => self.state = .main_menu, // ESC
                    13 => { // Enter
                        if (self.search_state.results.len > 0) {
                            // Set selected package (simplified - would need proper cloning)
                            self.state = .package_details;
                        }
                    },
                    // Arrow keys would be handled here
                    else => {
                        // Add character to search query
                        if (input >= 32 and input <= 126) { // Printable ASCII
                            try self.search_state.query.append(self.allocator, input);
                            // Trigger search in real implementation
                        }
                    },
                }
            },
            else => {
                switch (input) {
                    27 => self.state = .main_menu, // ESC - return to main menu
                    3 => return true, // Ctrl+C
                    else => {},
                }
            },
        }
        
        return false;
    }
};

fn getTerminalSize() !struct { width: u16, height: u16 } {
    // Simplified terminal size detection
    return .{ .width = 80, .height = 24 };
}

// Example usage
pub fn runInteractiveTUI(allocator: Allocator) !void {
    var tui = try EnhancedTUI.init(allocator);
    defer tui.deinit();
    
    try tui.run();
}