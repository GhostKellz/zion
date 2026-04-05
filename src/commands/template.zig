const std = @import("std");
const fs = std.fs;
const Dir = std.Io.Dir;
const Allocator = std.mem.Allocator;

/// Project template functionality
/// Creates new projects from predefined templates
pub fn template(allocator: Allocator, args: []const [:0]const u8) !void {
    if (args.len < 3) {
        try printTemplateHelp();
        return;
    }

    const subcommand = args[2];

    if (std.mem.eql(u8, subcommand, "list")) {
        try listTemplates();
    } else if (std.mem.eql(u8, subcommand, "new")) {
        if (args.len < 5) {
            std.debug.print("Error: 'zion template new' requires template and project name\n", .{});
            std.debug.print("Usage: zion template new <template> <project-name>\n", .{});
            std.debug.print("Example: zion template new web-server my-api\n", .{});
            return;
        }
        try createFromTemplate(allocator, args[3], args[4]);
    } else if (std.mem.eql(u8, subcommand, "info")) {
        if (args.len < 4) {
            std.debug.print("Error: 'zion template info' requires a template name\n", .{});
            std.debug.print("Usage: zion template info <template>\n", .{});
            std.debug.print("Example: zion template info web-server\n", .{});
            return;
        }
        try showTemplateInfo(args[3]);
    } else {
        std.debug.print("Unknown template subcommand: {s}\n", .{subcommand});
        try printTemplateHelp();
    }
}

/// Print template help
fn printTemplateHelp() !void {
    const help_text =
        \\Zion Project Templates
        \\
        \\USAGE:
        \\    zion template <COMMAND>
        \\
        \\COMMANDS:
        \\    list                    List available templates
        \\    new <template> <name>   Create project from template
        \\    info <template>         Show template information
        \\
        \\EXAMPLES:
        \\    zion template list                  # List all templates
        \\    zion template new cli my-tool       # Create CLI project
        \\    zion template new web-server api    # Create web server
        \\    zion template info game             # Show game template info
        \\
    ;

    std.debug.print("{s}", .{help_text});
}

/// List available templates
fn listTemplates() !void {
    std.debug.print("📋 Available Project Templates:\n\n", .{});

    const templates = getAvailableTemplates();

    for (templates) |tmpl| {
        std.debug.print("🔧 {s}\n", .{tmpl.name});
        std.debug.print("   {s}\n", .{tmpl.description});
        std.debug.print("   Dependencies: {s}\n", .{tmpl.dependencies});
        std.debug.print("   💾 zion template new {s} <project-name>\n", .{tmpl.name});
        std.debug.print("\n", .{});
    }

    std.debug.print("💡 Use 'zion template info <template>' for detailed information\n", .{});
}

/// Show detailed template information
fn showTemplateInfo(template_name: []const u8) !void {
    const templates = getAvailableTemplates();

    for (templates) |tmpl| {
        if (std.mem.eql(u8, tmpl.name, template_name)) {
            std.debug.print("📖 Template: {s}\n", .{tmpl.name});
            std.debug.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
            std.debug.print("📝 Description: {s}\n", .{tmpl.description});
            std.debug.print("🎯 Use Case: {s}\n", .{tmpl.use_case});
            std.debug.print("📦 Dependencies: {s}\n", .{tmpl.dependencies});
            std.debug.print("🏗️  Structure:\n", .{});
            for (tmpl.structure) |file| {
                std.debug.print("   {s}\n", .{file});
            }
            std.debug.print("\n📚 Features:\n", .{});
            for (tmpl.features) |feature| {
                std.debug.print("   • {s}\n", .{feature});
            }
            std.debug.print("\n💾 Create: zion template new {s} <project-name>\n", .{tmpl.name});
            return;
        }
    }

    std.debug.print("❌ Template '{s}' not found\n", .{template_name});
    std.debug.print("💡 Run 'zion template list' to see available templates\n", .{});
}

/// Create project from template
fn createFromTemplate(allocator: Allocator, template_name: []const u8, project_name: []const u8) !void {
    const templates = getAvailableTemplates();

    // Find template
    const tmpl_info = for (templates) |tmpl| {
        if (std.mem.eql(u8, tmpl.name, template_name)) {
            break tmpl;
        }
    } else {
        std.debug.print("❌ Template '{s}' not found\n", .{template_name});
        std.debug.print("💡 Run 'zion template list' to see available templates\n", .{});
        return error.TemplateNotFound;
    };

    std.debug.print("🚀 Creating '{s}' project from '{s}' template...\n", .{ project_name, template_name });

    // Create project directory
    const cwd = Dir.cwd();
    try cwd.makeDir(project_name);

    std.debug.print("📁 Created directory: {s}/\n", .{project_name});

    // Generate files based on template
    try generateTemplateFiles(allocator, tmpl_info, project_name);

    std.debug.print("✅ Project '{s}' created successfully!\n", .{project_name});
    std.debug.print("\n🎯 Next steps:\n", .{});
    std.debug.print("   cd {s}\n", .{project_name});
    std.debug.print("   zig build\n", .{});

    if (tmpl_info.dependencies.len > 0 and !std.mem.eql(u8, tmpl_info.dependencies, "None")) {
        std.debug.print("   # Dependencies will be auto-installed on first build\n", .{});
    }

    std.debug.print("\n💡 See {s}/README.md for detailed instructions\n", .{project_name});
}

/// Generate template files
fn generateTemplateFiles(allocator: Allocator, tmpl_info: TemplateInfo, project_name: []const u8) !void {
    const cwd = Dir.cwd();

    // Create subdirectories
    try cwd.makePath(try std.fmt.allocPrint(allocator, "{s}/src", .{project_name}));

    if (std.mem.indexOf(u8, tmpl_info.name, "web") != null or
        std.mem.indexOf(u8, tmpl_info.name, "game") != null)
    {
        try cwd.makePath(try std.fmt.allocPrint(allocator, "{s}/assets", .{project_name}));
    }

    // Generate main.zig based on template type
    const main_zig_content = try generateMainZig(allocator, template);
    defer allocator.free(main_zig_content);

    const main_zig_path = try std.fmt.allocPrint(allocator, "{s}/src/main.zig", .{project_name});
    defer allocator.free(main_zig_path);

    const main_file = try cwd.createFile(main_zig_path, .{});
    defer main_file.close();
    try main_file.writeAll(main_zig_content);

    std.debug.print("📄 Generated: src/main.zig\n", .{});

    // Generate build.zig
    const build_zig_content = try generateBuildZig(allocator, template, project_name);
    defer allocator.free(build_zig_content);

    const build_zig_path = try std.fmt.allocPrint(allocator, "{s}/build.zig", .{project_name});
    defer allocator.free(build_zig_path);

    const build_file = try cwd.createFile(build_zig_path, .{});
    defer build_file.close();
    try build_file.writeAll(build_zig_content);

    std.debug.print("📄 Generated: build.zig\n", .{});

    // Generate build.zig.zon
    const zon_content = try generateZonFile(allocator, template, project_name);
    defer allocator.free(zon_content);

    const zon_path = try std.fmt.allocPrint(allocator, "{s}/build.zig.zon", .{project_name});
    defer allocator.free(zon_path);

    const zon_file = try cwd.createFile(zon_path, .{});
    defer zon_file.close();
    try zon_file.writeAll(zon_content);

    std.debug.print("📄 Generated: build.zig.zon\n", .{});

    // Generate README.md
    const readme_content = try generateReadme(allocator, template, project_name);
    defer allocator.free(readme_content);

    const readme_path = try std.fmt.allocPrint(allocator, "{s}/README.md", .{project_name});
    defer allocator.free(readme_path);

    const readme_file = try cwd.createFile(readme_path, .{});
    defer readme_file.close();
    try readme_file.writeAll(readme_content);

    std.debug.print("📄 Generated: README.md\n", .{});
}

/// Generate main.zig content based on template
fn generateMainZig(allocator: Allocator, tmpl_info: TemplateInfo) ![]const u8 {
    if (std.mem.eql(u8, tmpl_info.name, "cli")) {
        return try allocator.dupe(u8,
            \\const std = @import("std");
            \\const clap = @import("clap");
            \\
            \\pub fn main() !void {
            \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            \\    defer _ = gpa.deinit(allocator);
            \\    const allocator = gpa.allocator();
            \\
            \\    const params = comptime clap.parseParamsComptime(
            \\        \\-h, --help     Display this help and exit.
            \\        \\-v, --version  Display version and exit.
            \\        \\<file>...      Input files.
            \\    );
            \\
            \\    const parsers = comptime .{
            \\        .file = clap.parsers.string,
            \\    };
            \\
            \\    var diag = clap.Diagnostic{};
            \\    var res = clap.parse(clap.Help, &params, parsers, .{
            \\        .diagnostic = &diag,
            \\        .allocator = allocator,
            \\    }) catch |err| switch (err) {
            \\        error.InvalidArgument => {
            \\            var buffer: [4096]u8 = undefined;
            \\            try diag.report(std.io.getStdErr().writer(&buffer), err);
            \\            return;
            \\        },
            \\        else => return err,
            \\    };
            \\    defer res.deinit(allocator);
            \\
            \\    if (res.args.help != 0) {
            \\        var buffer2: [4096]u8 = undefined;
            \\        return clap.help(std.io.getStdErr().writer(&buffer2), clap.Help, &params, .{});
            \\    }
            \\    if (res.args.version != 0) {
            \\        var buffer3: [4096]u8 = undefined;
            \\        return std.io.getStdOut().writer(&buffer3).print("Version 1.0.0\n");
            \\    }
            \\
            \\    std.debug.print("Hello from CLI app!\n");
            \\    for (res.positionals) |file| {
            \\        std.debug.print("Processing file: {s}\n", .{file});
            \\    }
            \\}
            \\
        );
    } else if (std.mem.eql(u8, tmpl_info.name, "web-server")) {
        return try allocator.dupe(u8,
            \\const std = @import("std");
            \\const httpz = @import("httpz");
            \\
            \\pub fn main() !void {
            \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            \\    defer _ = gpa.deinit(allocator);
            \\    const allocator = gpa.allocator();
            \\
            \\    var server = try httpz.Server().init(allocator, .{
            \\        .port = 3000,
            \\        .address = "127.0.0.1",
            \\    });
            \\    defer server.deinit(allocator);
            \\
            \\    // Routes
            \\    var router = server.router();
            \\    router.get("/", index);
            \\    router.get("/api/health", health);
            \\    router.get("/api/users/:id", getUser);
            \\
            \\    std.debug.print("🚀 Server running on http://127.0.0.1:3000\n");
            \\    try server.listen();
            \\}
            \\
            \\fn index(req: *httpz.Request, res: *httpz.Response) !void {
            \\    _ = req;
            \\    res.status = 200;
            \\    res.body = "Hello, Web Server!";
            \\}
            \\
            \\fn health(req: *httpz.Request, res: *httpz.Response) !void {
            \\    _ = req;
            \\    res.status = 200;
            \\    res.body = "{\"status\": \"healthy\"}";
            \\}
            \\
            \\fn getUser(req: *httpz.Request, res: *httpz.Response) !void {
            \\    const user_id = req.param("id") orelse "unknown";
            \\    const response = try std.fmt.allocPrint(req.arena, 
            \\        "{{\"id\": \"{s}\", \"name\": \"User {s}\"}}", .{user_id, user_id});
            \\    res.status = 200;
            \\    res.body = response;
            \\}
            \\
        );
    } else if (std.mem.eql(u8, tmpl_info.name, "game")) {
        return try allocator.dupe(u8,
            \\const std = @import("std");
            \\const raylib = @import("raylib");
            \\
            \\const SCREEN_WIDTH = 800;
            \\const SCREEN_HEIGHT = 450;
            \\
            \\pub fn main() !void {
            \\    raylib.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Zig Game");
            \\    defer raylib.CloseWindow();
            \\
            \\    raylib.SetTargetFPS(60);
            \\
            \\    var ball_position = raylib.Vector2{ .x = SCREEN_WIDTH / 2.0, .y = SCREEN_HEIGHT / 2.0 };
            \\    var ball_velocity = raylib.Vector2{ .x = 200.0, .y = 150.0 };
            \\    const ball_radius = 20.0;
            \\
            \\    while (!raylib.WindowShouldClose()) {
            \\        const delta_time = raylib.GetFrameTime();
            \\
            \\        // Update
            \\        ball_position.x += ball_velocity.x * delta_time;
            \\        ball_position.y += ball_velocity.y * delta_time;
            \\
            \\        // Bounce off walls
            \\        if (ball_position.x <= ball_radius or ball_position.x >= SCREEN_WIDTH - ball_radius) {
            \\            ball_velocity.x *= -1;
            \\        }
            \\        if (ball_position.y <= ball_radius or ball_position.y >= SCREEN_HEIGHT - ball_radius) {
            \\            ball_velocity.y *= -1;
            \\        }
            \\
            \\        // Draw
            \\        raylib.BeginDrawing();
            \\        defer raylib.EndDrawing();
            \\
            \\        raylib.ClearBackground(raylib.RAYWHITE);
            \\        raylib.DrawCircleV(ball_position, ball_radius, raylib.RED);
            \\        raylib.DrawText("Bouncing Ball Game!", 190, 200, 20, raylib.LIGHTGRAY);
            \\        raylib.DrawFPS(10, 10);
            \\    }
            \\}
            \\
        );
    } else {
        // Default: simple library
        return try allocator.dupe(u8,
            \\const std = @import("std");
            \\
            \\pub fn main() !void {
            \\    std.debug.print("Hello from Zig library!\n");
            \\}
            \\
            \\pub fn add(a: i32, b: i32) i32 {
            \\    return a + b;
            \\}
            \\
            \\test "basic addition" {
            \\    const result = add(2, 3);
            \\    try std.testing.expect(result == 5);
            \\}
            \\
        );
    }
}

/// Generate build.zig content
fn generateBuildZig(allocator: Allocator, tmpl_info: TemplateInfo, project_name: []const u8) ![]const u8 {
    if (std.mem.eql(u8, tmpl_info.name, "lib")) {
        return try std.fmt.allocPrint(allocator,
            \\const std = @import("std");
            \\
            \\pub fn build(b: *std.Build) void {{
            \\    const target = b.standardTargetOptions(.{{}});
            \\    const optimize = b.standardOptimizeOption(.{{}});
            \\
            \\    // zion:deps - dependencies will be added below this line
            \\
            \\    const lib = b.addStaticLibrary(.{{
            \\        .name = "{s}",
            \\        .root_source_file = b.path("src/main.zig"),
            \\        .target = target,
            \\        .optimize = optimize,
            \\    }});
            \\
            \\    b.installArtifact(lib);
            \\
            \\    const main_tests = b.addTest(.{{
            \\        .root_source_file = b.path("src/main.zig"),
            \\        .target = target,
            \\        .optimize = optimize,
            \\    }});
            \\
            \\    const run_main_tests = b.addRunArtifact(main_tests);
            \\    const test_step = b.step("test", "Run library tests");
            \\    test_step.dependOn(&run_main_tests.step);
            \\}}
            \\
        , .{project_name});
    } else {
        return try std.fmt.allocPrint(allocator,
            \\const std = @import("std");
            \\
            \\pub fn build(b: *std.Build) void {{
            \\    const target = b.standardTargetOptions(.{{}});
            \\    const optimize = b.standardOptimizeOption(.{{}});
            \\
            \\    // zion:deps - dependencies will be added below this line
            \\
            \\    const exe = b.addExecutable(.{{
            \\        .name = "{s}",
            \\        .root_source_file = b.path("src/main.zig"),
            \\        .target = target,
            \\        .optimize = optimize,
            \\    }});
            \\
            \\    b.installArtifact(exe);
            \\
            \\    const run_cmd = b.addRunArtifact(exe);
            \\    run_cmd.step.dependOn(b.getInstallStep());
            \\
            \\    if (b.args) |args| {{
            \\        run_cmd.addArgs(args);
            \\    }}
            \\
            \\    const run_step = b.step("run", "Run the app");
            \\    run_step.dependOn(&run_cmd.step);
            \\
            \\    const unit_tests = b.addTest(.{{
            \\        .root_source_file = b.path("src/main.zig"),
            \\        .target = target,
            \\        .optimize = optimize,
            \\    }});
            \\
            \\    const run_unit_tests = b.addRunArtifact(unit_tests);
            \\    const test_step = b.step("test", "Run unit tests");
            \\    test_step.dependOn(&run_unit_tests.step);
            \\}}
            \\
        , .{project_name});
    }
}

/// Generate build.zig.zon content
fn generateZonFile(allocator: Allocator, tmpl_info: TemplateInfo, project_name: []const u8) ![]const u8 {
    _ = tmpl_info; // Template info reserved for future template-specific dependencies
    return try std.fmt.allocPrint(allocator,
        \\.{{
        \\    .name = "{s}",
        \\    .version = "0.1.0",
        \\    .dependencies = .{{
        \\    }},
        \\}}
        \\
    , .{project_name});
}

/// Generate README.md content
fn generateReadme(allocator: Allocator, tmpl_info: TemplateInfo, project_name: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator,
        \\# {s}
        \\
        \\{s}
        \\
        \\## Getting Started
        \\
        \\```bash
        \\# Build the project
        \\zig build
        \\
        \\# Run the project
        \\zig build run
        \\
        \\# Run tests
        \\zig build test
        \\```
        \\
        \\## Dependencies
        \\
        \\{s}
        \\
        \\## Features
        \\
        \\{s}
        \\
        \\## Development
        \\
        \\This project was created using the Zion Zig tool:
        \\
        \\```bash
        \\# Add dependencies
        \\zion add <author>/<package>
        \\
        \\# Remove dependencies  
        \\zion remove <package>
        \\
        \\# List dependencies
        \\zion list
        \\
        \\# Search for packages
        \\zion search <term>
        \\```
        \\
        \\## License
        \\
        \\MIT
        \\
    , .{ project_name, tmpl_info.description, tmpl_info.dependencies, try formatFeatures(allocator, tmpl_info.features) });
}

/// Format features list for README
fn formatFeatures(allocator: Allocator, features: []const []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);

    for (features) |feature| {
        try result.writer().print("- {s}\n", .{feature});
    }

    return result.toOwnedSlice();
}

/// Get available templates
fn getAvailableTemplates() []const TemplateInfo {
    return &[_]TemplateInfo{
        .{
            .name = "cli",
            .description = "Command-line application with argument parsing",
            .use_case = "Building CLI tools, command-line utilities, system scripts",
            .dependencies = "zig-clap (command line parsing)",
            .structure = &[_][]const u8{
                "src/main.zig      # CLI entry point with clap integration",
                "build.zig         # Build configuration",
                "build.zig.zon     # Package manifest",
                "README.md         # Documentation",
            },
            .features = &[_][]const u8{
                "Argument parsing with zig-clap",
                "Help and version flags",
                "File processing example",
                "Error handling",
            },
        },
        .{
            .name = "web-server",
            .description = "HTTP web server with routing and API endpoints",
            .use_case = "REST APIs, web services, microservices, backend development",
            .dependencies = "httpz (HTTP server framework)",
            .structure = &[_][]const u8{
                "src/main.zig      # HTTP server with routes",
                "build.zig         # Build configuration",
                "build.zig.zon     # Package manifest",
                "README.md         # Documentation",
            },
            .features = &[_][]const u8{
                "HTTP server with httpz",
                "Route handling (GET /api/*)",
                "JSON responses",
                "Health check endpoint",
                "Parameter extraction",
            },
        },
        .{
            .name = "game",
            .description = "2D game with graphics and input handling",
            .use_case = "Game development, graphics programming, interactive applications",
            .dependencies = "raylib-zig (game development framework)",
            .structure = &[_][]const u8{
                "src/main.zig      # Game loop with raylib",
                "assets/           # Game assets directory",
                "build.zig         # Build configuration",
                "build.zig.zon     # Package manifest",
                "README.md         # Documentation",
            },
            .features = &[_][]const u8{
                "Raylib integration",
                "Game loop with 60 FPS",
                "Bouncing ball physics",
                "Input handling",
                "Graphics rendering",
            },
        },
        .{
            .name = "lib",
            .description = "Reusable library with tests",
            .use_case = "Creating libraries, shared code, packages for others",
            .dependencies = "None",
            .structure = &[_][]const u8{
                "src/main.zig      # Library implementation",
                "build.zig         # Build configuration for library",
                "build.zig.zon     # Package manifest",
                "README.md         # Documentation",
            },
            .features = &[_][]const u8{
                "Static library target",
                "Unit tests included",
                "Example functions",
                "Test runner setup",
            },
        },
    };
}

const TemplateInfo = struct {
    name: []const u8,
    description: []const u8,
    use_case: []const u8,
    dependencies: []const u8,
    structure: []const []const u8,
    features: []const []const u8,
};
