# 🚀 Zion Development Roadmap - v0.8.0+

> **Vision**: Make Zion the definitive, all-encompassing Zig development tool - combining package management, version management, project tooling, and ecosystem integration into one powerful CLI.

**Current Status**: v0.3.0 (Basic package manager with security/performance)  
**Next Major Release**: v0.8.0 (The "Cargo for Zig" release)  
**Ultimate Goal**: The **only tool** Zig developers need

---

## 🎯 **v0.8.0 - "The Cargo Release"**

### 🔧 **1. Zig Version Management (AnyZig-like)**
Review the Anyzig project here if needed: 
https://github.com/marler8997/anyzig 

**Goal**: Built-in Zig version management like `rustup` for Rust

#### **Features**:
```bash
# Install and manage Zig versions
zion zig install 0.15.0        # Install specific version
zion zig install master        # Install latest master build
zion zig install 0.15.0-dev.123 # Install specific dev build
zion zig list                   # List installed versions
zion zig use 0.15.0            # Switch global default
zion zig use 0.15.0 --project  # Set project-specific version
zion zig uninstall 0.14.0      # Remove old version
zion zig update                 # Update to latest stable
zion zig update --master       # Update to latest master

# Project-specific version (like .nvmrc)
echo "0.15.0" > .zigversion     # Pin project to specific version
zion zig auto                   # Auto-switch based on .zigversion

# Advanced features
zion zig doctor                 # Check installation health
zion zig which                  # Show current Zig path
zion zig env                    # Show Zig environment info
zion zig cache                  # Manage Zig cache directories
```

#### **Implementation**:
- **File**: `src/zig_manager.zig` (expand existing)
- **Download Management**: Multi-source (official releases, CI builds)
- **Version Detection**: Parse `zig version` output
- **Symlink Management**: Global and project-specific switching
- **Cache Management**: Shared cache across versions
- **Build Integration**: Automatic version detection in projects
- **ZLS Integration**: Auto-install compatible ZLS with each Zig version

### 🚀 **One Nation Under Zig - Complete Environment Setup**

#### **Zero-to-Hero Zig Development Setup**
```bash


# The "One Nation Under Zig" experience:
# 1. Install latest Zig version
# 2. Install compatible ZLS
# 3. Setup shell integration (PATH, completions)
# 4. Configure preferred IDE/editor
# 5. Install essential Zig tools
# 6. Create sample project
# 7. Verify everything works

# Modular setup options
zion setup zig                 # Install and configure Zig versions
zion setup zls                 # Install and configure ZLS
zion setup shell               # Setup shell - zsh + bash integration

zion setup tools               # Install additional tools (zig-test, etc.)

# Professional development setup
zion setup team                # Team/company environment setup
zion setup ci                  # CI/CD environment setup
zion setup docker              # Containerized development setup
```

#### **Setup Wizard Features**:
- **Interactive prompts**: Choose Zig version, editor, tools
- **Environment detection**: Auto-detect existing tools and configurations
- **Conflict resolution**: Handle existing installations gracefully
- **Progress tracking**: Visual progress with detailed steps
- **Rollback support**: Undo setup if something goes wrong
- **Team templates**: Predefined setups for teams/organizations

---

### 📦 **2. Advanced Package Management**

#### **2.1 Workspace Management**
```bash
# Cargo-style workspaces
zion workspace init             # Initialize workspace
zion workspace add mylib        # Add package to workspace
zion workspace build            # Build all packages
zion workspace test             # Test all packages
zion workspace check            # Check all packages

# Workspace structure
workspace/
├── zion-workspace.toml        # Workspace configuration
├── packages/
│   ├── mylib/
│   ├── mytool/
│   └── myapp/
└── target/                    # Shared build output
```

#### **2.2 Development Dependencies**
```bash
# Development vs runtime dependencies
zion add std.testing --dev      # Development-only dependency
zion add benchmark --dev        # Build tools and benchmarks
zion remove --dev std.testing   # Remove dev dependency

# Build.zig.zon enhancement
.{
    .name = "myproject",
    .version = "0.1.0",
    .dependencies = .{
        .mylibrary = .{ .url = "...", .hash = "..." },
    },
    .dev_dependencies = .{        # New section
        .benchmark = .{ .url = "...", .hash = "..." },
        .testing_utils = .{ .url = "...", .hash = "..." },
    },
}
```

#### **2.3 Feature Flags and Optional Dependencies**
```bash
# Conditional compilation features
zion build --features "network,crypto"  # Enable specific features
zion test --no-default-features         # Disable default features
zion check --features "all"             # Enable all optional features

# Build.zig.zon with features
.{
    .name = "myproject",
    .features = .{
        .default = .{"std", "basic"},
        .network = .{"http_client"},
        .crypto = .{"crypto_lib"},
        .all = .{"network", "crypto", "extra"},
    },
    .dependencies = .{
        .http_client = .{ 
            .url = "...", 
            .hash = "...", 
            .optional = true,        # Only if 'network' feature enabled
            .features = .{"client"}  # Enable specific features in dependency
        },
    },
}
```

---

### 🛠️ **3. Project Templates and Scaffolding**

#### **3.1 Advanced Templates**
```bash
# Built-in templates
zion new myapp --template=cli           # CLI application
zion new mylib --template=library       # Library project
zion new myweb --template=web-server    # HTTP server
zion new mygame --template=raylib       # Game with Raylib
zion new mykernel --template=kernel     # Kernel/OS project
zion new myembed --template=embedded    # Embedded system

# Custom templates from registries
zion template add company/enterprise-api # Add custom template
zion template list                       # Show available templates
zion new myapi --template=enterprise-api # Use custom template

# Interactive scaffolding
zion new myproject --interactive        # Guided project creation
```

#### **3.2 Template System**
**File Structure**:
```
templates/
├── cli/
│   ├── template.toml           # Template configuration
│   ├── src/
│   │   └── main.zig.tmpl      # Template files
│   ├── build.zig.tmpl
│   └── README.md.tmpl
└── library/
    ├── template.toml
    ├── src/
    │   └── lib.zig.tmpl
    └── tests/
        └── test.zig.tmpl
```

**Template Configuration**:
```toml
[template]
name = "CLI Application"
description = "Command-line application with argument parsing"
author = "Zion Team"
version = "1.0.0"

[variables]
app_name = { type = "string", prompt = "Application name?" }
author = { type = "string", prompt = "Author name?", default = "Anonymous" }
license = { type = "choice", prompt = "License?", choices = ["MIT", "Apache-2.0", "GPL-3.0"] }
has_config = { type = "bool", prompt = "Include configuration file support?" }

[dependencies]
clap = { version = "0.9.0", condition = "always" }
config = { version = "0.1.0", condition = "has_config" }

[files]
"src/main.zig" = "src/main.zig.tmpl"
"README.md" = "README.md.tmpl"
"LICENSE" = { template = "licenses/{{license}}.tmpl", condition = "license != 'none'" }
```

---

### 🔍 **4. Enhanced Development Tools**

#### **4.1 Integrated Language Server (ZLS)**
```bash
# ZLS management
zion setup zls                  # Complete ZLS setup (install + configure)
zion zls install                # Install/update ZLS
zion zls install --version=0.13.0 # Install specific ZLS version
zion zls uninstall              # Remove ZLS
zion zls doctor                 # Check ZLS health and configuration
zion zls config                 # Generate ZLS configuration
zion zls restart                # Restart ZLS for current project
zion zls which                  # Show current ZLS path
zion zls logs                   # Show ZLS logs for debugging

# Shell integration
zion setup shell                # Setup shell integration (PATH, completions, etc.)
zion setup shell --zsh          # Add to .zshrc specifically
zion setup shell --bash         # Add to .bashrc specifically
zion setup nvim                 # Complete Neovim setup with Zion plugin


 # Full setup (ZLS + IDE + tools)

# Neovim Plugin Management
zion nvim install               # Install Zion Neovim plugin
zion nvim config                # Generate Neovim configuration for Zion
zion nvim update                # Update Zion plugin and dependencies
zion nvim doctor                # Check Neovim setup health
```

#### **Implementation Details**:
- **Automatic ZLS version matching**: Install ZLS version compatible with current Zig
- **Shell integration**: Automatically add to PATH and setup completions
- **IDE configuration**: Generate optimal configurations for each editor
- **Health checking**: Verify ZLS is working correctly with current project
- **Auto-updates**: Keep ZLS in sync with Zig version changes

#### **4.2 Code Quality Tools**
```bash
# Integrated tools
zion fmt                        # Format code (existing)
zion lint                       # Run linter with project rules
zion clippy                     # Zig-specific suggestions (like Rust clippy)
zion audit                      # Security audit of dependencies
zion outdated                   # Check for outdated dependencies
zion licenses                   # License compliance check

# Code generation
zion generate api               # Generate API code from schema
zion generate bindings          # Generate C bindings
zion generate tests             # Generate test stubs
```

#### **4.3 Performance and Profiling**
```bash
# Performance tools
zion bench                      # Run benchmarks
zion profile                    # Profile application
zion perf build                 # Optimized build with profiling
zion bloat                      # Analyze binary size
zion deps graph                 # Visualize dependency graph
zion deps tree                  # Show dependency tree
zion deps licenses              # Show all dependency licenses
```

---

### 🌐 **5. Cross-Platform and Target Management**

#### **5.1 Multi-Target Builds**
```bash
# Target management
zion target list                # List available targets
zion target add x86_64-linux   # Add build target
zion build --target=wasm32      # Build for specific target
zion build --all-targets        # Build for all configured targets

# Cross-compilation made easy
zion build --target=aarch64-linux --release
zion test --target=x86_64-windows
zion package --all-targets     # Package for all platforms
```

#### **5.2 Docker and Container Integration**
```bash
# Container support
zion docker build              # Build in Docker container
zion docker test               # Test in clean environment
zion docker shell              # Interactive container shell
zion docker clean              # Clean container images

# Multi-stage builds
zion docker build --stage=dev   # Development container
zion docker build --stage=prod  # Production container
```

---

### 📊 **6. CI/CD and Automation**

#### **6.1 CI/CD Templates**
```bash
# Generate CI/CD configurations
zion ci github                 # Generate GitHub Actions
zion ci gitlab                 # Generate GitLab CI
zion ci azure                  # Generate Azure Pipelines
zion ci custom                 # Custom CI template

# Testing matrix generation
zion ci matrix                 # Generate test matrix for multiple Zig versions/targets
```

#### **6.2 Release Management**
```bash
# Automated releases
zion release prepare           # Prepare release (version bump, changelog)
zion release build             # Build release artifacts
zion release publish           # Publish to registries
zion release rollback          # Rollback failed release

# Changelog generation
zion changelog generate        # Generate changelog from commits
zion changelog preview         # Preview next changelog
```

---

### 🔐 **7. Enhanced Security and Trust**

#### **7.1 Supply Chain Security**
```bash
# Advanced security features
zion verify all                # Verify all dependencies
zion audit vulnerabilities    # Check for known vulnerabilities
zion audit licenses           # Audit license compatibility
zion sbom generate            # Generate Software Bill of Materials
zion provenance verify        # Verify build provenance

# Dependency policies
zion policy set license --allow="MIT,Apache-2.0"
zion policy set vulnerability --block="high,critical"
zion policy check              # Check project against policies
```

#### **7.2 Reproducible Builds**
```bash
# Reproducible build support
zion build --reproducible      # Ensure reproducible build
zion verify build              # Verify build reproducibility
zion compare builds            # Compare two builds for differences
```

---

### 🧪 **8. Testing Framework Integration**

#### **8.1 Enhanced Testing**
```bash
# Advanced testing features
zion test                      # Run all tests (existing)
zion test --coverage           # Run with coverage report
zion test --watch              # Watch mode for TDD
zion test --parallel           # Parallel test execution
zion test integration          # Run integration tests only
zion test --filter="crypto*"   # Filter tests by pattern

# Test reporting
zion test --junit              # JUnit XML output
zion test --html               # HTML coverage report
zion test --lcov               # LCOV format for IDEs
```

#### **8.2 Fuzzing and Property Testing**
```bash
# Advanced testing techniques
zion fuzz                      # Run fuzz tests
zion property                  # Property-based testing
zion mutate                    # Mutation testing
zion stress                    # Stress testing
```

---

### 🌌 **9. Analytics and Insights**

#### **9.1 Project Analytics**
```bash
# Project insights
zion stats                     # Project statistics
zion complexity                # Code complexity analysis
zion health                    # Project health score
zion trends                    # Development trends over time

# Team analytics
zion team stats                # Team contribution statistics
zion team velocity             # Development velocity metrics
```

#### **9.2 Dependency Analytics**
```bash
# Dependency insights
zion deps analyze              # Analyze dependency health
zion deps security             # Security posture of dependencies
zion deps popularity           # Popularity and maintenance status
zion deps alternatives         # Suggest alternative packages
```
Also, we'll have nvim directory for the setup of our zion based nvim plugin. 
---

## 🎯 **v0.9.0 - "The Ecosystem Release"**

### 🌍 **10. Ecosystem Integration**

#### **10.1 Language Interop**
```bash
# C/C++ integration
zion bindgen generate          # Generate Zig bindings from C headers
zion bindgen verify            # Verify binding correctness
zion c-deps add libcurl        # Add C dependency
zion c-deps build              # Build C dependencies

# WebAssembly
zion wasm build                # Build for WebAssembly
zion wasm optimize             # Optimize WASM output
zion wasm test                 # Test WASM modules

# Python/Node.js integration
zion py-bind generate          # Generate Python bindings
zion js-bind generate          # Generate JavaScript bindings
```

#### **10.2 IDE and Editor Deep Integration**
```bash
# Advanced IDE features
zion ide extensions            # Manage IDE extensions
zion ide project               # Generate comprehensive IDE project
zion ide debug                 # Setup debugging configuration
zion ide tasks                 # Generate IDE task configurations

# Neovim Plugin Development
zion nvim plugin create        # Create new Neovim plugin for Zion integration
zion nvim plugin build         # Build and package Neovim plugin
zion nvim plugin test          # Test Neovim plugin functionality
zion nvim plugin publish       # Publish to Neovim plugin registries

# Advanced Neovim Integration
zion nvim workspace            # Setup Neovim workspace for Zig development
zion nvim telescope            # Integrate with Telescope for package searching
zion nvim lsp-config           # Advanced LSP configuration for Neovim
zion nvim treesitter           # Setup Treesitter for Zig syntax highlighting
```

---

### 🤖 **11. AI and Code Generation**

#### **11.1 AI-Powered Features**
```bash
# AI assistance
zion ai suggest                # AI-powered code suggestions
zion ai review                 # AI code review
zion ai docs                   # AI-generated documentation
zion ai tests                  # AI-generated test cases
zion ai optimize               # AI-powered optimization suggestions

# Code understanding
zion explain                   # Explain complex code sections
zion suggest refactor          # Refactoring suggestions
zion find bugs                 # AI-powered bug detection
```

#### **11.2 Documentation Generation**
```bash
# Advanced documentation
zion docs generate             # Generate API documentation
zion docs preview              # Preview documentation locally
zion docs publish              # Publish to docs hosting
zion docs interactive          # Interactive documentation

# Multiple formats
zion docs --format=html        # HTML documentation
zion docs --format=pdf         # PDF documentation
zion docs --format=man         # Manual pages
```

---

## 🚀 **v1.0.0 - "The Stable Release"**

### 🎖️ **12. Production-Ready Features**

#### **12.1 Enterprise Features**
```bash
# Enterprise security
zion enterprise init           # Initialize enterprise features
zion enterprise audit          # Enterprise security audit
zion enterprise policy         # Enterprise policy management
zion enterprise reporting      # Enterprise reporting

# Team collaboration
zion team init                 # Initialize team workspace
zion team sync                 # Synchronize team dependencies
zion team policies             # Team-wide policies
zion team dashboard            # Team dashboard and metrics
```

#### **12.2 Cloud Integration**
```bash
# Cloud deployment
zion cloud deploy              # Deploy to cloud platforms
zion cloud scale               # Auto-scaling configuration
zion cloud monitor             # Cloud monitoring setup
zion cloud logs                # Centralized logging

# Container orchestration
zion k8s deploy                # Kubernetes deployment
zion docker compose            # Docker Compose generation
zion helm chart                # Helm chart generation
```

---

## 🗺️ **Implementation Priority**

### **Phase 1: v0.8.0 Core (3 months)**
1. **"One Nation Under Zig" Setup System** (2 weeks)
2. **Zig Version Management** (4 weeks)
3. **ZLS Integration & Shell Setup** (2 weeks)
4. **Advanced Package Management** (4 weeks)
5. **Project Templates** (2 weeks)

### **Phase 2: v0.8.x Refinements (2 months)**
5. **Cross-Platform Builds** (3 weeks)
6. **CI/CD Integration** (2 weeks)
7. **Enhanced Security** (3 weeks)

### **Phase 3: v0.9.0 Ecosystem (3 months)**
8. **Testing Framework** (4 weeks)
9. **Analytics** (2 weeks)
10. **Ecosystem Integration** (6 weeks)

### **Phase 4: v1.0.0 Production (3 months)**
11. **AI Features** (6 weeks)
12. **Enterprise Features** (6 weeks)

---

## 🎯 **Success Metrics**

### **Adoption Metrics**
- **10,000+ weekly active users** by v0.8.0
- **100+ packages** in Zepplin registry
- **50+ community templates**
- **Integration with top 10 Zig projects**

### **Feature Completeness**
- **100% Cargo feature parity** for relevant features
- **Zero-config setup** for new Zig developers
- **Sub-second response times** for all commands
- **99.9% uptime** for registry services

### **Ecosystem Impact**
- **Reduce Zig project setup time** from 30min to 30sec
- **Increase Zig package adoption** by 300%
- **Become the default** Zig project management tool
- **Featured in official Zig documentation**

---

## 🛠️ **Technical Architecture Goals**

### **Performance**
- **Cold start**: < 100ms for any command
- **Package resolution**: < 200ms average
- **Build integration**: Zero overhead
- **Memory usage**: < 50MB resident

### **Reliability**
- **Offline operation**: Full functionality without internet
- **Error recovery**: Graceful handling of all failure modes
- **Data integrity**: Cryptographic verification of all operations
- **Backward compatibility**: Never break existing projects

### **Extensibility**
- **Plugin system**: Third-party extensions
- **API stability**: Stable API for tools integration
- **Configuration**: Highly configurable without complexity
- **Cross-platform**: Identical experience on all platforms

---

This roadmap positions Zion to become the **definitive Zig development tool**, comparable to Cargo for Rust, with even more comprehensive features for the modern development workflow. The goal is to make Zion so essential that it becomes the first tool every Zig developer installs.

---

### 🔌 **Neovim Plugin Development**

#### **Zion.nvim - Official Neovim Plugin**

**Goal**: Create a comprehensive Neovim plugin that integrates all Zion functionality directly into the editor.

#### **Plugin Features**:
```lua
-- Package management directly in Neovim
:ZionAdd mitchellh/libxev       -- Add dependency
:ZionRemove libxev              -- Remove dependency  
:ZionUpdate                     -- Update all dependencies
:ZionSearch crypto              -- Search packages with Telescope integration

-- Project management
:ZionInit                       -- Initialize new project
:ZionTemplate cli               -- Create from template
:ZionWorkspace                  -- Manage workspace

-- Development tools
:ZionBuild                      -- Build project
:ZionTest                       -- Run tests
:ZionFmt                        -- Format code
:ZionLint                       -- Run linter

-- Version management
:ZionZigInstall 0.15.0          -- Install Zig version
:ZionZigUse 0.15.0              -- Switch Zig version
:ZionZigList                    -- List installed versions

-- Advanced features
:ZionDeps                       -- Show dependency tree in floating window
:ZionHealth                     -- Project health dashboard
:ZionSecurity                   -- Security audit results
:ZionPerf                       -- Performance metrics
```

#### **Telescope Integration**:
```lua
-- Telescope pickers for Zion
:Telescope zion packages        -- Browse and add packages
:Telescope zion templates       -- Browse project templates
:Telescope zion versions        -- Switch Zig versions
:Telescope zion dependencies    -- Manage project dependencies
:Telescope zion commands        -- Fuzzy find Zion commands
```

#### **Plugin Structure**:
```
lua/zion/
├── init.lua                    -- Main plugin entry point
├── config.lua                  -- Configuration management
├── commands.lua                -- Neovim command definitions
├── telescope/
│   ├── packages.lua           -- Package search picker
│   ├── templates.lua          -- Template picker
│   ├── versions.lua           -- Version picker
│   └── dependencies.lua       -- Dependency picker
├── ui/
│   ├── floating.lua           -- Floating windows for output
│   ├── progress.lua           -- Progress indicators
│   └── health.lua             -- Health check UI
├── utils/
│   ├── zion.lua               -- Zion CLI wrapper
│   ├── project.lua            -- Project detection
│   └── notifications.lua      -- User notifications
└── integrations/
    ├── lsp.lua                -- LSP integration
    ├── treesitter.lua         -- Syntax highlighting
    ├── dap.lua                -- Debug adapter integration
    └── lualine.lua            -- Status line integration
```

#### **Configuration Example**:
```lua
require('zion').setup({
  -- Zion executable path (auto-detected)
  cmd = 'zion',
  
  -- Auto commands
  auto_update = true,           -- Auto-update dependencies on save
  auto_fmt = true,              -- Auto-format on save
  auto_lint = true,             -- Auto-lint on buffer change
  
  -- UI preferences
  floating_window = {
    border = 'rounded',
    width = 0.8,
    height = 0.8,
  },
  
  -- Telescope integration
  telescope = {
    enable = true,
    theme = 'dropdown',
  },
  
  -- Notifications
  notifications = {
    enable = true,
    timeout = 3000,
  },
  
  -- LSP integration
  lsp = {
    auto_setup_zls = true,      -- Auto-configure ZLS
    auto_install_zls = true,    -- Auto-install ZLS if missing
  },
  
  -- Keymaps
  keymaps = {
    add_dependency = '<leader>za',
    remove_dependency = '<leader>zr',
    update_dependencies = '<leader>zu',
    build_project = '<leader>zb',
    test_project = '<leader>zt',
    format_code = '<leader>zf',
    search_packages = '<leader>zs',
    project_health = '<leader>zh',
  },
})
```

#### **Advanced Integrations**:

**1. LSP Integration**:
- Auto-configure ZLS with optimal settings
- Project-specific LSP configurations
- Dependency-aware code completion
- Real-time error checking

**2. Treesitter Integration**:
- Enhanced Zig syntax highlighting
- Dependency declaration highlighting
- Build script syntax support
- Template file highlighting

**3. DAP Integration**:
- Debug configuration generation
- Breakpoint management
- Variable inspection
- Step-through debugging

**4. Status Line Integration**:
```lua
-- Lualine component showing Zion status
require('lualine').setup({
  sections = {
    lualine_x = {
      {
        'zion#status',
        color = { fg = '#7aa2f7' },
        symbols = {
          building = '🔨',
          testing = '🧪',
          updating = '⬇️',
          error = '❌',
          ok = '✅',
        }
      }
    }
  }
})
```

#### **Plugin Installation**:
```lua
-- Using lazy.nvim
{
  'ghostkellz/zion.nvim',
  dependencies = {
    'nvim-telescope/telescope.nvim',
    'nvim-lua/plenary.nvim',
    'nvim-notify/nvim-notify',  -- Optional: for notifications
  },
  config = function()
    require('zion').setup({
      -- your configuration
    })
  end,
  cmd = {
    'ZionAdd', 'ZionRemove', 'ZionUpdate', 'ZionBuild', 
    'ZionTest', 'ZionInit', 'ZionHealth'
  },
  ft = { 'zig' },  -- Load on Zig files
}

-- Using packer.nvim
use {
  'ghostkellz/zion.nvim',
  requires = {
    'nvim-telescope/telescope.nvim',
    'nvim-lua/plenary.nvim',
  },
  config = function()
    require('zion').setup()
  end
}
```

#### **Implementation Timeline**:
- **Phase 1** (2 weeks): Basic plugin structure and commands
- **Phase 2** (2 weeks): Telescope integration and UI
- **Phase 3** (2 weeks): LSP and Treesitter integration
- **Phase 4** (1 week): Advanced features and polish
- **Phase 5** (1 week): Documentation and testing


### CURRENT BUILD ISSUE
 src   build.zig   build.zig.zon   keypair.bin
❯ zion clean --all
🧹 Starting hands-free cleanup...
🗑️  Deleted .zig-cache/
🗑️  Deleted .zion/cache/
🗑️  Deleted zig-out/
🔧 Cleaning up build.zig...
  ℹ️  No orphaned dependencies found in build.zig
🔥 Deep clean mode: removing everything...
🗑️  Deleted .zion/deps/
🗑️  Deleted .zion/
🔄 Resetting build.zig to pristine state...
  ℹ️  build.zig was already clean
🔄 Cleaning dependencies from build.zig.zon...
  ✅ Cleared all dependencies from build.zig.zon
✅ Hands-free cleanup complete! Removed 6 items
🎯 Project is now clean and ready for fresh dependencies
error(gpa): memory address 0x71a8ed1e0004 leaked:

error(gpa): memory address 0x71a8ed220010 leaked:

error(gpa): memory address 0x71a8ed200020 leaked: