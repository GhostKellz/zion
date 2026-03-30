#compdef zion

# Zsh completion for Zion package manager

_zion() {
    local -a commands
    commands=(
        'init:Initialize a new Zig project'
        'add:Add a dependency to your project'
        'remove:Remove a dependency from your project'
        'rm:Remove a dependency from your project'
        'update:Update all dependencies to latest versions'
        'list:List all dependencies with their status'
        'ls:List all dependencies with their status'
        'info:Show detailed information about a package'
        'fetch:Fetch all dependencies'
        'build:Build the project'
        'run:Build and run the project'
        'test:Run project tests'
        'clean:Clean build artifacts and caches'
        'lock:Update or create the lock file'
        'version:Show version information'
        'help:Show help message'
        'tree:Display dependency tree'
        'pin:Pin a dependency to a specific version'
        'unpin:Unpin a dependency to allow updates'
        'hash:Manage package hashes'
        'sign:Sign a package with Ed25519'
        'keyring:Manage trusted public keys'
        'zig:Manage Zig versions'
        'zls:Install or update Zig Language Server'
        'search:Search for packages'
        'outdated:Check for outdated dependencies'
        'registry:Manage package registries'
        'publish:Publish a package to a registry'
        'doc:Generate documentation'
        'template:Manage project templates'
        'workspace:Manage multi-project workspaces'
        'config:View or modify configuration'
        'cache:Manage package cache'
        'status:Show project status'
        'repair:Attempt to repair project issues'
        'analyze:Analyze project dependencies'
        'fmt:Format project source files'
        'check:Check project for issues'
    )

    _arguments -C \
        '1: :->command' \
        '*: :->args'

    case $state in
        command)
            _describe 'commands' commands
            ;;
        args)
            case $words[2] in
                list|ls)
                    _arguments '--json[Output in JSON format]'
                    ;;
                clean)
                    _arguments \
                        '--all[Remove everything including lock files]' \
                        '--cache[Remove only cached files]'
                    ;;
                tree)
                    _arguments \
                        '--check-cycles[Detect circular dependencies]' \
                        '-c[Detect circular dependencies]' \
                        '--depth=[Limit tree display depth]:depth' \
                        '--duplicates[Show duplicate dependencies]' \
                        '--no-versions[Hide version information]'
                    ;;
                unpin)
                    _arguments '--to-main[Track default branch]'
                    ;;
                hash)
                    local -a hash_cmds
                    hash_cmds=('update:Update package hashes')
                    _describe 'hash commands' hash_cmds
                    _arguments '--branch=[Specify branch]:branch'
                    ;;
                zig)
                    local -a zig_cmds
                    zig_cmds=(
                        'install:Install a Zig version'
                        'list:List available versions'
                        'use:Switch to a version'
                    )
                    _describe 'zig commands' zig_cmds
                    ;;
                zls)
                    local -a zls_cmds
                    zls_cmds=(
                        'install:Install ZLS'
                        'update:Update ZLS'
                    )
                    _describe 'zls commands' zls_cmds
                    ;;
                keyring)
                    local -a keyring_cmds
                    keyring_cmds=(
                        'add:Add a public key'
                        'list:List trusted keys'
                        'remove:Remove a key'
                    )
                    _describe 'keyring commands' keyring_cmds
                    ;;
                registry)
                    local -a registry_cmds
                    registry_cmds=(
                        'list:List configured registries'
                        'add:Add a registry'
                        'remove:Remove a registry'
                        'health:Check registry health'
                    )
                    _describe 'registry commands' registry_cmds
                    ;;
                template)
                    local -a template_cmds
                    template_cmds=(
                        'list:List available templates'
                        'create:Create a new template'
                        'apply:Apply a template'
                    )
                    _describe 'template commands' template_cmds
                    ;;
                workspace)
                    local -a workspace_cmds
                    workspace_cmds=(
                        'init:Initialize a workspace'
                        'add:Add a project to workspace'
                        'list:List workspace projects'
                    )
                    _describe 'workspace commands' workspace_cmds
                    ;;
                config)
                    local -a config_cmds
                    config_cmds=(
                        'get:Get a config value'
                        'set:Set a config value'
                        'list:List all config'
                    )
                    _describe 'config commands' config_cmds
                    ;;
                cache)
                    local -a cache_cmds
                    cache_cmds=(
                        'clean:Clean the cache'
                        'info:Show cache info'
                    )
                    _describe 'cache commands' cache_cmds
                    ;;
                add|remove|rm|info|pin|unpin|sign)
                    # Package name completion - could be enhanced
                    ;;
            esac
            ;;
    esac
}

_zion "$@"
