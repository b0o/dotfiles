# Manage Nix user profiles with flakes.
# See: https://github.com/lf-/flakey-profile
export module fp {
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

def _complete-hm [spans: list<string>] {
  use nushell/completion.nu carapace-complete
  carapace-complete $spans home-manager
}

def --env _hm_init [] {
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

def _complete-hm-update [spans: list<string>] {
  _hm_init
  use nushell/completion.nu carapace-complete
  carapace-complete $spans nix flake update
}

# Update the $DOTFILES_HOME/flake.lock
@complete _complete-hm-update
def --wrapped "hm update" [...args] {
  _hm_init
  ^nix flake update ...$args
}

@complete _complete-hm
def --wrapped hm [...args] {
  let home_flake = _hm_init
  ^home-manager --flake $".#($home_flake)" ...$args
}

export module ns {
  export def complete-indexes [context: string, position: int] {
    use nushell/completion.nu *
    complete-comma-separated-options $context $position [
      "nixos"
      "nixpkgs"
      "home-manager"
      "darwin"
      "nur"
    ]
  }

  # Search nix packages
  export def main [
    # Search query
    query?: string
    --indexes (-i): string@complete-indexes # Search index
  ] {
    let ns_opts = [
      ...(if ($indexes | is-not-empty) { $indexes | each { ["--indexes" $in] } | flatten })
    ]
    let fzf_opts = [
      --scheme history
      --preview $"nix-search-tv preview ($ns_opts | str join ' ') {}"
      ...(if ($query | is-not-empty) { ["--query" $query] })
    ]

    nix-search-tv print ...$ns_opts | fzf ...$fzf_opts
  }
}

use ns
