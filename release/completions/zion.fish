# Fish completion for Zion package manager

# Main commands
complete -c zion -f -n '__fish_use_subcommand' -a 'init' -d 'Initialize a new Zig project'
complete -c zion -f -n '__fish_use_subcommand' -a 'add' -d 'Add a dependency to your project'
complete -c zion -f -n '__fish_use_subcommand' -a 'remove' -d 'Remove a dependency from your project'
complete -c zion -f -n '__fish_use_subcommand' -a 'rm' -d 'Remove a dependency from your project'
complete -c zion -f -n '__fish_use_subcommand' -a 'update' -d 'Update all dependencies to latest versions'
complete -c zion -f -n '__fish_use_subcommand' -a 'list' -d 'List all dependencies with their status'
complete -c zion -f -n '__fish_use_subcommand' -a 'ls' -d 'List all dependencies with their status'
complete -c zion -f -n '__fish_use_subcommand' -a 'info' -d 'Show detailed information about a package'
complete -c zion -f -n '__fish_use_subcommand' -a 'fetch' -d 'Fetch all dependencies'
complete -c zion -f -n '__fish_use_subcommand' -a 'build' -d 'Build the project'
complete -c zion -f -n '__fish_use_subcommand' -a 'clean' -d 'Clean build artifacts and caches'
complete -c zion -f -n '__fish_use_subcommand' -a 'lock' -d 'Update or create the lock file'
complete -c zion -f -n '__fish_use_subcommand' -a 'version' -d 'Show version information'
complete -c zion -f -n '__fish_use_subcommand' -a 'help' -d 'Show help message'

# Options for specific commands
complete -c zion -f -n '__fish_seen_subcommand_from list ls' -l json -d 'Output in JSON format'
complete -c zion -f -n '__fish_seen_subcommand_from clean' -l all -d 'Remove everything including lock files'