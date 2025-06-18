const std = @import("std");

/// Display help information
pub fn help(allocator: std.mem.Allocator) !void {
    _ = allocator; // unused but required for API consistency

    const help_text =
        \\Zion - A Modern Zig Package Manager
        \\
        \\USAGE:
        \\    zion <COMMAND>
        \\
        \\COMMANDS:
        \\    init        Initialize a new Zig project
        \\    add         Add a dependency to your project
        \\    remove, rm  Remove a dependency from your project
        \\    update      Update all dependencies to latest versions
        \\    list, ls    List all dependencies in the project
        \\    info        Show detailed information about a package
        \\    fetch       Fetch all dependencies
        \\    build       Build the project
        \\    clean       Clean build artifacts and caches
        \\    lock        Update the lock file
        \\    security    Package signing, verification, and trust management
        \\    performance Performance monitoring and optimization
        \\    search      Search for Zig packages
        \\    template    Create projects from templates
        \\    debug       Debug build errors and analyze project
        \\    fmt         Format code with enhanced project-wide features
        \\    analyze     Analyze dependencies and project structure
        \\    version     Show version information
        \\    zig         Zig version manager (install, list, use, etc.)
        \\    help        Show this help message
        \\
        \\EXAMPLES:
        \\    zion init                   # Initialize a new project
        \\    zion add mitchellh/libxev   # Add a dependency
        \\    zion list                   # List dependencies
        \\    zion remove libxev          # Remove a dependency
        \\    zion update                 # Update all dependencies
        \\    zion clean                  # Clean build artifacts
        \\    zion clean --all            # Clean everything including lock file
        \\    zion search json            # Search for JSON packages
        \\    zion template list          # List available templates
        \\    zion template new cli mytool # Create CLI project
        \\    zion debug build            # Analyze build errors
        \\    zion fmt                    # Format entire project
        \\    zion fmt --check            # Check code formatting
        \\    zion analyze deps           # Show dependency tree
        \\    zion zig install 0.15.0     # Install Zig version 0.15.0
        \\    zion zig use 0.15.0         # Switch to Zig version 0.15.0
        \\
        \\For more information, see the documentation at:
        \\https://github.com/ghostkellz/zion
        \\
    ;

    std.debug.print("{s}", .{help_text});
}
