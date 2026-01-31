# TODO: move to scripts/ and load with hooks
# TODO: detect if we're currently using home-manager or flakey-profile and warn if attempting to switch to the other

# Manage Nix user profiles with flakes.
# See: https://github.com/lf-/flakey-profile
export module flakey-profile {
  def --env init [
    --profile (-p): string
    --dir (-d): string
  ] {
    let dotfiles_dir = $env | get -o DOTFILES_HOME
    let profile_default = $env | get -o NIX_PROFILE | default "dev"
    let profile = if ($profile | is-empty) { $profile_default } else { $profile }
    let base_dir = if ($dir | is-empty) { $dotfiles_dir } else { $dir | path expand }
    if ($base_dir | is-empty) {
      error make -u {msg: $"Error: Base directory is not set: set DOTFILES_HOME or specify --dir"}
    }
    if not ($base_dir | path exists) {
      error make -u {msg: $"Error: Base directory does not exist: ($base_dir)"}
    }
    cd $base_dir
    $profile
  }

  # Build the flakey profile
  export def --wrapped build [
    --profile (-p): string   # Specify the profile name
    --dir (-d): string       # Specify the base directory
    ...args: string          # Specify additional arguments to pass to nix
  ] {
    let profile = (init --profile=$profile --dir=$dir)
    nix build $".#profile.($profile)" ...$args
  }

  # Switch (activate) the flakey profile
  export def --wrapped switch [
    --profile (-p): string   # Specify the profile name
    --dir (-d): string       # Specify the base directory
    ...args: string          # Specify additional arguments to pass to nix
  ] {
    let profile = (init --profile=$profile --dir=$dir)
    nix run $".#profile.($profile).switch" ...$args
  }

  # Rollback to the previous flakey profile
  export def --wrapped rollback [
    --profile (-p): string   # Specify the profile name
    --dir (-d): string       # Specify the base directory
    ...args: string          # Specify additional arguments to pass to nix
  ] {
    let profile = (init --profile=$profile --dir=$dir)
    nix run $".#profile.($profile).rollback" ...$args
  }

  # Enter a development shell
  export def --wrapped develop [
    --profile (-p): string   # Specify the profile name
    --dir (-d): string       # Specify the base directory
    ...args: string          # Specify additional arguments to pass to nix
  ] {
    init --profile=$profile --dir=$dir
    nix develop ...$args
  }

  # Enter a shell with the flakey profile's environment
  export def --wrapped shell [
    --profile (-p): string   # Specify the profile name
    --dir (-d): string       # Specify the base directory
    ...args: string          # Specify additional arguments to pass to nix
  ] {
    init --profile=$profile --dir=$dir
    nix shell ...$args
  }

  # Update the flake.lock file
  export def --wrapped update [
    --profile (-p): string # Specify the profile name
    --dir (-d): string     # Specify the base directory
    ...inputs: string      # Specify the inputs to update (e.g. nixpkgs)
  ] {
    init --profile=$profile --dir=$dir
    nix flake update ...$inputs
    switch --profile=$profile --dir=$dir
  }

  export alias b = build
  export alias sw = switch
  export alias rb = rollback
  export alias dev = develop
  export alias sh = shell
  export alias up = update
  export alias upd = update
}

export module fp { export use flakey-profile * }

use flakey-profile
use fp

def --wrapped fp [cmd, ...args] {
  print -e "Usage: fp <command> [<args>]"
  print -e "Commands:"
  print -e "  build (b)     Build the flakey profile"
  print -e "  switch (sw)   Switch to the flakey profile"
  print -e "  rollback (rb) Rollback to the previous flakey profile"
  print -e "  develop (dev) Enter a development shell"
  print -e "  shell (sh)    Enter a shell with the flakey profile's environment"
  print -e "  update (up)   Update the flake.lock file"
}

export module dotfiles {
  def --env init [] {
    let dotfiles_dir = $env | get -o DOTFILES_HOME
    if ($dotfiles_dir | is-empty) {
      error make -u {msg: $"Error: DOTFILES_HOME is not set"}
      return
    }
    cd $dotfiles_dir
    # TODO: Don't hardcode this
    let home_flake = "arch-maddy"
    $home_flake
  }

  export def complete-main [spans: list<string>] {
    use nushell/completion.nu carapace-complete
    init
    carapace-complete $spans home-manager
  }

  # Dotfiles / Home Manager
  @complete complete-main
  export def --wrapped main [
    ...args: string
  ] {
    let home_flake = (init)
    ^home-manager --flake $".#($home_flake)" ...$args
  }

  def complete-update [spans: list<string>] {
    use nushell/completion.nu carapace-complete
    init
    carapace-complete --skip=1 $spans nix flake update
  }

  # Update dotfiles flake.lock
  @complete complete-update
  export def --wrapped update [...args: string] {
    init
    ^nix flake update ...$args
  }

  def complete-secrets [spans: list<string>] {
    use nushell/completion.nu carapace-complete
    init
    carapace-complete --skip=1 $spans sops edit
  }

  # Edit sops-nix managed secrets in $env.EDITOR
  @complete complete-secrets
  export def --wrapped secrets [...args: string] {
    init
    # TODO: Don't hardcode this
    let secrets_file = "secrets.yaml"
    ^sops edit ...$args $secrets_file
  }

  export alias sw = main switch
  export alias u = update
  export alias up = update
  export alias upd = update
  export alias sec = secrets
}

export module d {
  export use dotfiles *

  @complete complete-main
  export def --wrapped main [...args: string] {
    dotfiles ...$args
  }
}

use dotfiles
use d

export module nix-search {
  const indexes = [
      "nixos"
      "nixpkgs"
      "home-manager"
      "darwin"
      "nur"
  ]

  export def _complete-indexes [context: string, position: int] {
    use nushell/completion.nu *
    complete-comma-separated-options $context $position $indexes
  }

  def complete-index [] { $indexes }

  def complete-open-mode [] { ["source" "homepage"] }

  # Open package in browser
  export def open-pkg [
    package: string # Package name
    --index (-i): string@complete-index # Package index
    --mode (-m): string@complete-open-mode = "source" # Either "source" or "homepage"
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
  def parse-selection [selection: string, fallback_index: string] {
    if ($selection | str contains "/ ") {
      let parts = ($selection | split row "/ " --number 2)
      { index: ($parts | get 0), package: ($parts | get 1) }
    } else {
      { index: $fallback_index, package: $selection }
    }
  }

  # Search nix packages
  export def main [
    # Search query
    ...query: string
    --indexes (-i): string@_complete-indexes # Search index
  ] {
    let ns_opts = if ($indexes | is-not-empty) {
      [$"--indexes=($indexes)"]
    } else {
      []
    }

    let icons = { homepage: "󰖟 ", source: " " }

    mut current_query = ($query | str join " ")

    loop {
      let sel = (
        ^nix-search-tv print ...$ns_opts
        | lines
        | sk
          --reverse
          --query $current_query
          --prompt "^o open  ^c copy  ^d exit > "
          --preview { ^nix-search-tv preview ...$ns_opts $in }
          --expect [ctrl-o, ctrl-c]
          --bind { ctrl-d: abort }
      )

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
            { label: $"($icons.source)source", mode: source, url: $source_url }
            { label: $"($icons.homepage)homepage", mode: homepage, url: $homepage_url }
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
}

export module ns {
  export use nix-search *

  # Search nix packages
  export def main [
    # Search query
    ...query: string
    --indexes (-i): string@_complete-indexes # Search index
  ] {
    nix-search --indexes=$indexes ...$query
  }
}

use nix-search
use ns
