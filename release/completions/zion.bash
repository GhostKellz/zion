# Bash completion for Zion

_zion_completions() {
    local cur prev commands
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    commands="init add remove rm update list ls info fetch pin unpin repair check build clean lock hash run test tree why policy target doc outdated nvim config security performance debug zig search registry template fmt analyze version publish search-interactive interface verify cache tui status setup zls workspace keyring help"

    case "${prev}" in
        zion)
            COMPREPLY=( $(compgen -W "${commands}" -- ${cur}) )
            return 0
            ;;
        test)
            COMPREPLY=( $(compgen -W "bootstrap scaffold run bench ci report info docs" -- ${cur}) )
            return 0
            ;;
        clean)
            COMPREPLY=( $(compgen -W "--all" -- ${cur}) )
            return 0
            ;;
        tree)
            COMPREPLY=( $(compgen -W "--check-cycles -c --depth --duplicates --no-versions" -- ${cur}) )
            return 0
            ;;
        unpin)
            COMPREPLY=( $(compgen -W "--to-main -m" -- ${cur}) )
            return 0
            ;;
        registry)
            COMPREPLY=( $(compgen -W "list add remove test health auth" -- ${cur}) )
            return 0
            ;;
        zig)
            COMPREPLY=( $(compgen -W "install list use current" -- ${cur}) )
            return 0
            ;;
        zls)
            COMPREPLY=( $(compgen -W "install doctor config" -- ${cur}) )
            return 0
            ;;
        workspace)
            COMPREPLY=( $(compgen -W "init add build" -- ${cur}) )
            return 0
            ;;
        policy)
            COMPREPLY=( $(compgen -W "init audit show add-allow add-deny" -- ${cur}) )
            return 0
            ;;
        target)
            COMPREPLY=( $(compgen -W "list add remove available" -- ${cur}) )
            return 0
            ;;
        keyring)
            COMPREPLY=( $(compgen -W "status list archver trust" -- ${cur}) )
            return 0
            ;;
    esac

    COMPREPLY=( $(compgen -W "${commands}" -- ${cur}) )
    return 0
}

complete -F _zion_completions zion
