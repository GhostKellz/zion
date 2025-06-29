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
        \\    fetch       Fetch dependencies or specific packages with versions
        \\    pin         Pin a dependency to a specific version
        \\    unpin       Unpin a dependency to track latest version
        \\    repair      Fix broken hashes and dependency issues
        \\    check       Check dependency health and project status
        \\    build       Build the project
        \\    clean       Clean build artifacts and caches  
        \\    lock        Update the lock file
        \\    run         Run the project executable
        \\    test        Run project tests with filtering
        \\    doc         Generate and open documentation
        \\    tree        Show dependency tree visualization
        \\    outdated    Check for outdated dependencies
        \\    hash        Generate, verify, and manage package hashes
        \\    config      Configuration management (env vars, Lua, JSON)
        \\    nvim        Neovim integration setup and management
        \\    security    Package signing, verification, and trust management
        \\    performance Performance monitoring and optimization
        \\    search      Search for Zig packages
        \\    registry    Manage package registries and test connectivity
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
        \\    zion fetch ghostkellz/zcrypto@0.2.0  # Fetch specific version
        \\    zion pin libxev@0.1.5       # Pin dependency to version
        \\    zion unpin libxev           # Unpin dependency
        \\    zion repair                 # Fix hash mismatches
        \\    zion check                  # Check project health
        \\    zion list                   # List dependencies
        \\    zion remove libxev          # Remove a dependency
        \\    zion update                 # Update all dependencies
        \\    zion clean                  # Clean build artifacts
        \\    zion clean --all            # Clean everything including lock file
        \\    zion run                    # Run the main executable
        \\    zion run --bin mytool       # Run specific binary
        \\    zion test                   # Run all tests
        \\    zion test --filter "json"   # Run tests matching filter
        \\    zion doc --open             # Generate and open docs
        \\    zion tree --depth 2         # Show dependency tree (max depth 2)
        \\    zion outdated               # Check for outdated dependencies
        \\    zion hash generate file.tar.gz # Generate hash for file
        \\    zion hash verify file.tar.gz abc123... # Verify file hash
        \\    zion config init --lua      # Create Lua config for Neovim
        \\    zion config show            # Show current configuration
        \\    zion nvim setup             # Setup Neovim integration
        \\    zion zig install 0.12.0     # Install Zig version 0.12.0
        \\    zion zig use 0.12.0         # Switch to Zig version 0.12.0
        \\    zion zig list --remote      # List available Zig versions
        \\    zion registry list          # List configured registries
        \\    zion registry test          # Test all registry connections
        \\
        \\For more information, see the documentation at:
        \\https://github.com/ghostkellz/zion
        \\
    ;

    std.debug.print("{s}", .{help_text});
}
