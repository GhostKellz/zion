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
        'clean:Clean build artifacts and caches'
        'lock:Update or create the lock file'
        'version:Show version information'
        'help:Show help message'
    )

    case $state in
        commands)
            _describe 'commands' commands
            ;;
        *)
            case $words[2] in
                list|ls)
                    _arguments '--json[Output in JSON format]'
                    ;;
                clean)
                    _arguments '--all[Remove everything including lock files]'
                    ;;
                add|remove|rm|info)
                    # Could complete with package names here
                    ;;
            esac
            ;;
    esac

    _arguments \
        '1: :->commands' \
        '*: :->args'
}

_zion "$@"