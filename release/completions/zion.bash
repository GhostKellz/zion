# Bash completion for Zion package manager

_zion_completions() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Main commands
    opts="init add remove rm update list ls info fetch build clean lock version help"

    case "${prev}" in
        zion)
            COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
            return 0
            ;;
        add|remove|rm|info)
            # For add/remove/info commands, we could potentially complete with
            # package names, but for now just return empty
            return 0
            ;;
        list|ls)
            COMPREPLY=( $(compgen -W "--json" -- ${cur}) )
            return 0
            ;;
        clean)
            COMPREPLY=( $(compgen -W "--all" -- ${cur}) )
            return 0
            ;;
        *)
            ;;
    esac

    COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
    return 0
}

complete -F _zion_completions zion