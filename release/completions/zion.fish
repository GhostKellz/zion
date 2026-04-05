# Fish completion for Zion

complete -c zion -f

for cmd in init add remove rm update list ls info fetch pin unpin repair check build clean lock hash run test tree why policy target doc outdated nvim config security performance debug zig search registry template fmt analyze version publish search-interactive verify cache tui status setup zls workspace keyring help
    complete -c zion -n '__fish_use_subcommand' -a "$cmd"
end

complete -c zion -n '__fish_seen_subcommand_from test' -a 'bootstrap scaffold run bench ci report info docs'
complete -c zion -n '__fish_seen_subcommand_from registry' -a 'list add remove test health auth'
complete -c zion -n '__fish_seen_subcommand_from zig' -a 'install list use current'
complete -c zion -n '__fish_seen_subcommand_from zls' -a 'install doctor config'
complete -c zion -n '__fish_seen_subcommand_from workspace' -a 'init add build'
complete -c zion -n '__fish_seen_subcommand_from policy' -a 'init audit show add-allow add-deny'
complete -c zion -n '__fish_seen_subcommand_from target' -a 'list add remove available'

complete -c zion -n '__fish_seen_subcommand_from clean' -l all
complete -c zion -n '__fish_seen_subcommand_from tree' -l check-cycles
complete -c zion -n '__fish_seen_subcommand_from tree' -s c
complete -c zion -n '__fish_seen_subcommand_from tree' -l depth -r
complete -c zion -n '__fish_seen_subcommand_from tree' -l duplicates
complete -c zion -n '__fish_seen_subcommand_from tree' -l no-versions
complete -c zion -n '__fish_seen_subcommand_from unpin' -l to-main
complete -c zion -n '__fish_seen_subcommand_from test' -l seed -r
complete -c zion -n '__fish_seen_subcommand_from test' -l cases -r
complete -c zion -n '__fish_seen_subcommand_from test' -l time-budget -r
complete -c zion -n '__fish_seen_subcommand_from test' -l include -r
complete -c zion -n '__fish_seen_subcommand_from test' -l exclude -r
complete -c zion -n '__fish_seen_subcommand_from test' -l failed-only
complete -c zion -n '__fish_seen_subcommand_from test' -l ci-profile -r
