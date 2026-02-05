#!/usr/bin/env -S nu --stdin

export const indexes = [
  "nixos"
  "nixpkgs"
  "home-manager"
  "darwin"
  "nur"
]

def complete-indexes [context: string position: int] {
  use nushell/completion.nu *
  complete-comma-separated-options $context $position $indexes
}

export module _main {
  export def indexes [] { $indexes }

  def complete-open-mode [] { ["source" "homepage"] }

  # Open package in browser
  export def open-pkg [
    --index (-i): string@indexes # Package index
    --mode (-m): string@complete-open-mode = "source" # Either "source" or "homepage"
    package: string # Package name
  ] {
    let result = ^nix-search-tv $mode $"--indexes=($index)" $package | complete
    if ($result.exit_code != 0) {
      error make -u $"Failed to get package ($mode) URL"
    }
    let url = $result.stdout | str trim
    ^xdg-open $url
  }

  export alias open = open-pkg

  # Parse nix-search-tv selection to extract index and package name
  # Format varies:
  # - No indexes or multiple indexes: "index/ package"
  # - Single index: "package" (use provided index)
  def parse-selection [selection: string fallback_index: string] {
    if ($selection | str contains "/ ") {
      let parts = ($selection | split row "/ " --number 2)
      {index: ($parts | get 0) package: ($parts | get 1)}
    } else {
      {index: $fallback_index package: $selection}
    }
  }

  export def docs [
    --indexes (-i): string@complete-indexes # Search indexes (comma-separated)
    package: string # Package name
  ] {
    let ns_opts = if ($indexes | is-not-empty) {
      [$"--indexes=($indexes)"]
    } else {
      []
    }
    ^nix-search-tv preview ...$ns_opts $package
  }

  # Search nix packages
  export def main [
    --indexes (-i): string@complete-indexes # Search indexes (comma-separated)
    --filter-mode (-f) # Return matches for initial query without interactive TUI
    ...query: string # Search query
  ] {
    let ns_opts = if ($indexes | is-not-empty) {
      [$"--indexes=($indexes)"]
    } else {
      []
    }

    let icons = {homepage: "󰖟 " source: " "}

    mut current_query = $query | str join " "

    loop {
      let interactive = not $filter_mode and (is-terminal --stdin) and (is-terminal --stdout)
      let sel = (
        ^nix-search-tv print ...$ns_opts
        | (
          if $interactive {
            (
              lines
              | sk --reverse
              --query $current_query
              --prompt "^o open  ^c copy  ^d exit > "
              --preview { ^nix-search-tv preview ...$ns_opts $in }
              --expect [ctrl-o ctrl-c]
              --bind {ctrl-d: abort}
            )
          } else {
            ^sk --exact --filter $current_query
          }
        )
      )
      if not $interactive {
        return $sel
      }

      if ($sel | is-empty) or ($sel.selected? | is-empty) {
        return null
      }

      let action = $sel.action? | default ""
      let selection = $sel.selected

      let parsed = parse-selection $selection ($indexes | default "")

      if $action == "ctrl-c" {
        $parsed.package | xc
        continue
      }

      if $action == "ctrl-o" {
        # Open picker for homepage or source
        let homepage_url = ^nix-search-tv homepage $"--indexes=($parsed.index)" $parsed.package | str trim
        let source_url = ^nix-search-tv source $"--indexes=($parsed.index)" $parsed.package | str trim

        let open_sel = (
          [
            {label: $"($icons.source)source" mode: source url: $source_url}
            {label: $"($icons.homepage)homepage" mode: homepage url: $homepage_url}
          ]
          | sk
          --reverse
          --prompt $"($parsed.index)/ ($parsed.package) > "
          --format { $in.label }
          --preview { $in.url }
        )

        if ($open_sel | is-not-empty) {
          open-pkg --index $parsed.index --mode $open_sel.mode $parsed.package
        }

        return null
      }

      # Normal selection - return the package name
      return $selection
    }
  }

  export alias home-manager = main --indexes=home-manager
  export alias nixpkgs = main --indexes=nixpkgs
  export alias nixos = main --indexes=nixos
  export alias nur = main --indexes=nur
  export alias darwin = main --indexes=darwin

  export alias h = main --indexes=home-manager
  export alias p = main --indexes=nixpkgs
  export alias o = main --indexes=nixos
  export alias u = main --indexes=nur
  export alias d = main --indexes=darwin
}

export module ns {
  export use _main *

  # Search nix packages
  export def main [
    --indexes (-i): string@complete-indexes # Search indexes (comma-separated)
    --filter-mode (-f) # Return matches for initial query without interactive TUI
    ...query: string # Search query
  ] {
    _main --indexes=$indexes --filter-mode=$filter_mode ...$query
  }
}

# Search nix packages
def main [
  --indexes (-i): string # Search indexes (comma-separated)
  --filter-mode (-f) # Return matches for initial query without interactive TUI
  ...query: string # Search query
] {
  use _main
  _main --indexes=$indexes --filter-mode=$filter_mode ...$query
}

# Open package in browser
def "main open" [
  --index (-i): string # Package index
  --mode (-m): string = "source" # Either "source" or "homepage"
  package: string
] {
  use _main open-pkg
  open-pkg --index=$index --mode=$mode $package
}

# List available indexes
def "main indexes" [] {
  use _main indexes
  indexes
}

# Show package documentation
def "main docs" [
  --indexes (-i): string # Search indexes (comma-separated)
  package: string # Package name
] {
  use _main docs
  docs --indexes=$indexes $package
}
