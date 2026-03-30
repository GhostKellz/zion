# Fish completion for Zion package manager

# Disable file completion by default
complete -c zion -f

# Main commands
complete -c zion -n '__fish_use_subcommand' -a 'init' -d 'Initialize a new Zig project'
complete -c zion -n '__fish_use_subcommand' -a 'add' -d 'Add a dependency to your project'
complete -c zion -n '__fish_use_subcommand' -a 'remove' -d 'Remove a dependency from your project'
complete -c zion -n '__fish_use_subcommand' -a 'rm' -d 'Remove a dependency from your project'
complete -c zion -n '__fish_use_subcommand' -a 'update' -d 'Update all dependencies to latest versions'
complete -c zion -n '__fish_use_subcommand' -a 'list' -d 'List all dependencies with their status'
complete -c zion -n '__fish_use_subcommand' -a 'ls' -d 'List all dependencies with their status'
complete -c zion -n '__fish_use_subcommand' -a 'info' -d 'Show detailed information about a package'
complete -c zion -n '__fish_use_subcommand' -a 'fetch' -d 'Fetch all dependencies'
complete -c zion -n '__fish_use_subcommand' -a 'build' -d 'Build the project'
complete -c zion -n '__fish_use_subcommand' -a 'run' -d 'Build and run the project'
complete -c zion -n '__fish_use_subcommand' -a 'test' -d 'Run project tests'
complete -c zion -n '__fish_use_subcommand' -a 'clean' -d 'Clean build artifacts and caches'
complete -c zion -n '__fish_use_subcommand' -a 'lock' -d 'Update or create the lock file'
complete -c zion -n '__fish_use_subcommand' -a 'version' -d 'Show version information'
complete -c zion -n '__fish_use_subcommand' -a 'help' -d 'Show help message'
complete -c zion -n '__fish_use_subcommand' -a 'tree' -d 'Display dependency tree'
complete -c zion -n '__fish_use_subcommand' -a 'pin' -d 'Pin a dependency to a specific version'
complete -c zion -n '__fish_use_subcommand' -a 'unpin' -d 'Unpin a dependency to allow updates'
complete -c zion -n '__fish_use_subcommand' -a 'hash' -d 'Manage package hashes'
complete -c zion -n '__fish_use_subcommand' -a 'sign' -d 'Sign a package with Ed25519'
complete -c zion -n '__fish_use_subcommand' -a 'keyring' -d 'Manage trusted public keys'
complete -c zion -n '__fish_use_subcommand' -a 'zig' -d 'Manage Zig versions'
complete -c zion -n '__fish_use_subcommand' -a 'zls' -d 'Install or update Zig Language Server'
complete -c zion -n '__fish_use_subcommand' -a 'search' -d 'Search for packages'
complete -c zion -n '__fish_use_subcommand' -a 'outdated' -d 'Check for outdated dependencies'
complete -c zion -n '__fish_use_subcommand' -a 'registry' -d 'Manage package registries'
complete -c zion -n '__fish_use_subcommand' -a 'publish' -d 'Publish a package to a registry'
complete -c zion -n '__fish_use_subcommand' -a 'doc' -d 'Generate documentation'
complete -c zion -n '__fish_use_subcommand' -a 'template' -d 'Manage project templates'
complete -c zion -n '__fish_use_subcommand' -a 'workspace' -d 'Manage multi-project workspaces'
complete -c zion -n '__fish_use_subcommand' -a 'config' -d 'View or modify configuration'
complete -c zion -n '__fish_use_subcommand' -a 'cache' -d 'Manage package cache'
complete -c zion -n '__fish_use_subcommand' -a 'status' -d 'Show project status'
complete -c zion -n '__fish_use_subcommand' -a 'repair' -d 'Attempt to repair project issues'
complete -c zion -n '__fish_use_subcommand' -a 'analyze' -d 'Analyze project dependencies'
complete -c zion -n '__fish_use_subcommand' -a 'fmt' -d 'Format project source files'
complete -c zion -n '__fish_use_subcommand' -a 'check' -d 'Check project for issues'

# Options for list/ls
complete -c zion -n '__fish_seen_subcommand_from list ls' -l json -d 'Output in JSON format'

# Options for clean
complete -c zion -n '__fish_seen_subcommand_from clean' -l all -d 'Remove everything including lock files'
complete -c zion -n '__fish_seen_subcommand_from clean' -l cache -d 'Remove only cached files'

# Options for tree
complete -c zion -n '__fish_seen_subcommand_from tree' -l check-cycles -d 'Detect circular dependencies'
complete -c zion -n '__fish_seen_subcommand_from tree' -s c -d 'Detect circular dependencies'
complete -c zion -n '__fish_seen_subcommand_from tree' -l depth -d 'Limit tree display depth' -r
complete -c zion -n '__fish_seen_subcommand_from tree' -l duplicates -d 'Show duplicate dependencies'
complete -c zion -n '__fish_seen_subcommand_from tree' -l no-versions -d 'Hide version information'

# Options for unpin
complete -c zion -n '__fish_seen_subcommand_from unpin' -l to-main -d 'Track default branch'

# Options for hash
complete -c zion -n '__fish_seen_subcommand_from hash' -a 'update' -d 'Update package hashes'
complete -c zion -n '__fish_seen_subcommand_from hash' -l branch -d 'Specify branch' -r

# Subcommands for zig
complete -c zion -n '__fish_seen_subcommand_from zig' -a 'install' -d 'Install a Zig version'
complete -c zion -n '__fish_seen_subcommand_from zig' -a 'list' -d 'List available versions'
complete -c zion -n '__fish_seen_subcommand_from zig' -a 'use' -d 'Switch to a version'

# Subcommands for zls
complete -c zion -n '__fish_seen_subcommand_from zls' -a 'install' -d 'Install ZLS'
complete -c zion -n '__fish_seen_subcommand_from zls' -a 'update' -d 'Update ZLS'

# Subcommands for keyring
complete -c zion -n '__fish_seen_subcommand_from keyring' -a 'add' -d 'Add a public key'
complete -c zion -n '__fish_seen_subcommand_from keyring' -a 'list' -d 'List trusted keys'
complete -c zion -n '__fish_seen_subcommand_from keyring' -a 'remove' -d 'Remove a key'

# Subcommands for registry
complete -c zion -n '__fish_seen_subcommand_from registry' -a 'list' -d 'List configured registries'
complete -c zion -n '__fish_seen_subcommand_from registry' -a 'add' -d 'Add a registry'
complete -c zion -n '__fish_seen_subcommand_from registry' -a 'remove' -d 'Remove a registry'
complete -c zion -n '__fish_seen_subcommand_from registry' -a 'health' -d 'Check registry health'

# Subcommands for template
complete -c zion -n '__fish_seen_subcommand_from template' -a 'list' -d 'List available templates'
complete -c zion -n '__fish_seen_subcommand_from template' -a 'create' -d 'Create a new template'
complete -c zion -n '__fish_seen_subcommand_from template' -a 'apply' -d 'Apply a template'

# Subcommands for workspace
complete -c zion -n '__fish_seen_subcommand_from workspace' -a 'init' -d 'Initialize a workspace'
complete -c zion -n '__fish_seen_subcommand_from workspace' -a 'add' -d 'Add a project to workspace'
complete -c zion -n '__fish_seen_subcommand_from workspace' -a 'list' -d 'List workspace projects'

# Subcommands for config
complete -c zion -n '__fish_seen_subcommand_from config' -a 'get' -d 'Get a config value'
complete -c zion -n '__fish_seen_subcommand_from config' -a 'set' -d 'Set a config value'
complete -c zion -n '__fish_seen_subcommand_from config' -a 'list' -d 'List all config'

# Subcommands for cache
complete -c zion -n '__fish_seen_subcommand_from cache' -a 'clean' -d 'Clean the cache'
complete -c zion -n '__fish_seen_subcommand_from cache' -a 'info' -d 'Show cache info'
