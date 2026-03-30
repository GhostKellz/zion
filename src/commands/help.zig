const std = @import("std");

/// Per-command help texts
const command_help = struct {
    const unpin =
        \\Unpin a dependency to track the latest version
        \\
        \\USAGE:
        \\    zion unpin <package> [OPTIONS]
        \\
        \\OPTIONS:
        \\    --to-main, -m    Track the repository's default branch instead of releases
        \\
        \\EXAMPLES:
        \\    zion unpin libxev              # Update to latest release/tag
        \\    zion unpin libxev --to-main    # Track default branch directly
        \\
    ;

    const pin =
        \\Pin a dependency to a specific version
        \\
        \\USAGE:
        \\    zion pin <package>@<version>
        \\
        \\EXAMPLES:
        \\    zion pin libxev@0.1.5          # Pin to specific version
        \\    zion pin httpz@1.0.0           # Pin httpz to 1.0.0
        \\
    ;

    const add =
        \\Add a dependency to your project
        \\
        \\USAGE:
        \\    zion add <package> [<package2> ...]
        \\
        \\EXAMPLES:
        \\    zion add mitchellh/libxev              # Add from GitHub
        \\    zion add mitchellh/libxev karlseguin/httpz  # Add multiple
        \\
    ;

    const remove =
        \\Remove a dependency from your project
        \\
        \\USAGE:
        \\    zion remove <package>
        \\    zion rm <package>
        \\
        \\EXAMPLES:
        \\    zion remove libxev             # Remove libxev
        \\    zion rm httpz                  # Remove httpz (alias)
        \\
    ;

    const tree =
        \\Show dependency tree visualization
        \\
        \\USAGE:
        \\    zion tree [OPTIONS]
        \\
        \\OPTIONS:
        \\    --check-cycles, -c    Detect circular dependencies
        \\    --depth=N             Limit tree display depth
        \\    --duplicates          Highlight duplicate dependencies
        \\    --no-versions         Hide version information
        \\
        \\EXAMPLES:
        \\    zion tree                      # Show full tree
        \\    zion tree --check-cycles       # Check for circular deps
        \\    zion tree --depth=2            # Limit to 2 levels
        \\
    ;

    const hash =
        \\Generate, verify, and manage package hashes
        \\
        \\USAGE:
        \\    zion hash <subcommand> [OPTIONS]
        \\
        \\SUBCOMMANDS:
        \\    update <package>       Re-download and update hash
        \\    update --all           Update all dependency hashes
        \\    check                  Verify cached packages match ZON hashes
        \\
        \\EXAMPLES:
        \\    zion hash update libxev        # Update hash for libxev
        \\    zion hash update --all         # Update all hashes
        \\    zion hash check                # Verify all hashes
        \\
    ;

    const search =
        \\Search for Zig packages
        \\
        \\USAGE:
        \\    zion search <query>
        \\
        \\EXAMPLES:
        \\    zion search http               # Search for HTTP packages
        \\    zion search json               # Search for JSON packages
        \\
    ;

    const zig =
        \\Zig version manager
        \\
        \\USAGE:
        \\    zion zig <subcommand> [VERSION]
        \\
        \\SUBCOMMANDS:
        \\    install <version>      Install a Zig version
        \\    use <version>          Switch to a Zig version
        \\    use system             Use system-installed Zig
        \\    list                   List installed versions
        \\    list --remote          List available versions
        \\    current                Show current version
        \\
        \\EXAMPLES:
        \\    zion zig install 0.14.1        # Install stable
        \\    zion zig use system            # Use pacman Zig
        \\
    ;

    const zls =
        \\ZLS (Zig Language Server) integration
        \\
        \\USAGE:
        \\    zion zls <subcommand>
        \\
        \\SUBCOMMANDS:
        \\    install                Installation guidance
        \\    update                 Update ZLS
        \\    doctor                 Health check and diagnostics
        \\    config                 Generate optimal configuration
        \\
        \\EXAMPLES:
        \\    zion zls doctor                # Check ZLS health
        \\    zion zls config                # Generate config
        \\
    ;

    const clean =
        \\Clean build artifacts and caches
        \\
        \\USAGE:
        \\    zion clean [OPTIONS]
        \\
        \\OPTIONS:
        \\    --all                  Remove everything including lock file
        \\    --cache                Remove only cached files
        \\
        \\EXAMPLES:
        \\    zion clean                     # Clean build artifacts
        \\    zion clean --all               # Full cleanup
        \\
    ;
};

/// Get help text for a specific command
fn getCommandHelp(cmd: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, cmd, "unpin")) return command_help.unpin;
    if (std.mem.eql(u8, cmd, "pin")) return command_help.pin;
    if (std.mem.eql(u8, cmd, "add")) return command_help.add;
    if (std.mem.eql(u8, cmd, "remove") or std.mem.eql(u8, cmd, "rm")) return command_help.remove;
    if (std.mem.eql(u8, cmd, "tree")) return command_help.tree;
    if (std.mem.eql(u8, cmd, "hash")) return command_help.hash;
    if (std.mem.eql(u8, cmd, "search")) return command_help.search;
    if (std.mem.eql(u8, cmd, "zig")) return command_help.zig;
    if (std.mem.eql(u8, cmd, "zls")) return command_help.zls;
    if (std.mem.eql(u8, cmd, "clean")) return command_help.clean;
    return null;
}

/// Display help information
pub fn help(allocator: std.mem.Allocator, args: []const [:0]const u8) !void {
    _ = allocator;

    // Check for per-command help: zion help <command>
    if (args.len >= 3) {
        const cmd = args[2];
        if (getCommandHelp(cmd)) |cmd_help| {
            std.debug.print("{s}\n", .{cmd_help});
            return;
        } else {
            std.debug.print("No detailed help for '{s}'. Showing general help.\n\n", .{cmd});
        }
    }

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
        \\    ghostspec   GhostSpec testing workflows (install, run, report)
        \\    search      Search for Zig packages
        \\    registry    Manage package registries and test connectivity
        \\    template    Create projects from templates
        \\    debug       Debug build errors and analyze project
        \\    fmt         Format code with enhanced project-wide features
        \\    analyze     Analyze dependencies and project structure
        \\    version     Show version information
        \\    zig         Zig version manager (install, list, use, etc.)
        \\    zls         ZLS (Zig Language Server) integration
        \\    workspace   Cargo-style workspace management
        \\    setup       One Nation Under Zig - complete setup wizard
        \\    keyring     GPG keyring management and signature verification
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
        \\    zion setup all              # Complete development environment setup
        \\    zion setup zig              # Install and configure Zig
        \\    zion setup verify           # Verify setup completion
        \\    zion zls install            # Get ZLS installation guidance
        \\    zion zls doctor             # Check ZLS health and setup
        \\    zion zls config             # Create optimal ZLS configuration
        \\    zion ghostspec bootstrap    # Install and wire GhostSpec into the project
        \\    zion ghostspec run          # Execute GhostSpec suites
        \\    zion workspace init         # Initialize Cargo-style workspace
        \\    zion workspace add mylib    # Add package to workspace
        \\    zion workspace build        # Build all workspace packages
        \\    zion zig list --remote      # List available Zig versions
        \\    zion registry list          # List configured registries
        \\    zion registry test          # Test all registry connections
        \\    zion keyring status         # Show GPG keyring status and health
        \\    zion keyring list           # List all available GPG keys
        \\    zion keyring archver        # Verify Arch Linux system keyrings
        \\    zion publish --registry=zigistry --sign    # Publish with signing
        \\    zion add crypto --verify-signatures        # Add with security checks
        \\    zion search http --filter=web,network      # Advanced search
        \\    zion search-interactive                     # Interactive search mode
        \\    zion registry add https://my-reg.com       # Add custom registry
        \\    zion registry health                       # Check registry health
        \\
        \\ZIGISTRY EXAMPLES:
        \\    zion zigistry search json           # Search Zigistry packages
        \\    zion zigistry trending              # Show trending packages
        \\    zion zigistry info zig-clap         # Package details
        \\    zion add zig-clap --registry zigistry  # Add from Zigistry
        \\    zion search http --registry zigistry   # Search Zigistry only
        \\
        \\COMMAND ALIASES:
        \\    s -> search          i -> info         a -> add
        \\    r -> remove          u -> update       l -> list
        \\    c -> check           b -> build        t -> test
        \\    h -> help            v -> version      f -> fetch
        \\    gs -> ghostspec      si -> interface   reg -> registry
        \\    kr -> keyring        tui -> interface
        \\
        \\ENVIRONMENT VARIABLES:
        \\    NO_COLOR=1           Disable colored output (accessibility)
        \\    ZION_REGISTRY_URL    Custom registry URL
        \\    ZION_REGISTRY_TOKEN  Registry authentication token
        \\    ZIGISTRY_TOKEN       Zigistry authentication token
        \\
        \\For more information, see the documentation at:
        \\https://github.com/ghostkellz/zion
        \\
    ;

    std.debug.print("{s}", .{help_text});
}
