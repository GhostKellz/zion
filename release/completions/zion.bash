# Bash completion for Zion package manager

_zion_completions() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Main commands
    local commands="init add remove rm update list ls info fetch build run test clean lock version help tree pin unpin hash sign keyring zig zls search outdated registry publish doc template workspace config cache status repair analyze fmt check"

    case "${prev}" in
        zion)
            COMPREPLY=( $(compgen -W "${commands}" -- ${cur}) )
            return 0
            ;;
        add|remove|rm|info|pin|unpin)
            # Package name expected
            return 0
            ;;
        list|ls)
            COMPREPLY=( $(compgen -W "--json" -- ${cur}) )
            return 0
            ;;
        clean)
            COMPREPLY=( $(compgen -W "--all --cache" -- ${cur}) )
            return 0
            ;;
        tree)
            COMPREPLY=( $(compgen -W "--check-cycles -c --depth --duplicates --no-versions" -- ${cur}) )
            return 0
            ;;
        hash)
            COMPREPLY=( $(compgen -W "update" -- ${cur}) )
            return 0
            ;;
        zig)
            COMPREPLY=( $(compgen -W "install list use" -- ${cur}) )
            return 0
            ;;
        zls)
            COMPREPLY=( $(compgen -W "install update" -- ${cur}) )
            return 0
            ;;
        keyring)
            COMPREPLY=( $(compgen -W "add list remove" -- ${cur}) )
            return 0
            ;;
        registry)
            COMPREPLY=( $(compgen -W "list add remove health" -- ${cur}) )
            return 0
            ;;
        template)
            COMPREPLY=( $(compgen -W "list create apply" -- ${cur}) )
            return 0
            ;;
        workspace)
            COMPREPLY=( $(compgen -W "init add list" -- ${cur}) )
            return 0
            ;;
        config)
            COMPREPLY=( $(compgen -W "get set list" -- ${cur}) )
            return 0
            ;;
        cache)
            COMPREPLY=( $(compgen -W "clean info" -- ${cur}) )
            return 0
            ;;
        update)
            # Can optionally specify a package
            if [[ ${cur} == -* ]]; then
                COMPREPLY=( $(compgen -W "--branch" -- ${cur}) )
            fi
            return 0
            ;;
        *)
            ;;
    esac

    # Handle --depth= completion
    if [[ ${cur} == --depth=* ]]; then
        return 0
    fi

    # Handle --branch= completion
    if [[ ${cur} == --branch=* ]]; then
        return 0
    fi

    COMPREPLY=( $(compgen -W "${commands}" -- ${cur}) )
    return 0
}

complete -F _zion_completions zion
