# Manage Nix user profiles with flakes.
# See: https://github.com/lf-/flakey-profile
export module fp {
  def --env init [
    --profile (-p): string = ""   # Specify the profile name
    --dir (-d): string = ""       # Specify the base directory
  ] {
    let dotfiles_dir = $env.DOTFILES_HOME
    let profile_default = $env.USER
    let profile = if ($profile | is-empty) { $profile_default } else { $profile }
    let base_dir = if ($dir | is-empty) { $dotfiles_dir } else { $dir | path expand }
    if not ($base_dir | path exists) {
      error make {msg: $"Error: Base directory does not exist: ($base_dir)"}
    }
    cd $base_dir
    $profile
  }

  # Build the flakey profile
  export def build [
    --profile (-p): string = ""   # Specify the profile name
    --dir (-d): string = ""       # Specify the base directory
  ] {
    let profile = (init --profile $profile --dir $dir)
    nix build $".#profile.($profile)"
  }

  # Switch (activate) the flakey profile
  export def switch [
    --profile (-p): string = ""   # Specify the profile name
    --dir (-d): string = ""       # Specify the base directory
  ] {
    let profile = (init --profile $profile --dir $dir)
    nix run $".#profile.($profile).switch"
  }

  # Rollback to the previous flakey profile
  export def rollback [
    --profile (-p): string = ""   # Specify the profile name
    --dir (-d): string = ""       # Specify the base directory
  ] {
    let profile = (init --profile $profile --dir $dir)
    nix run $".#profile.($profile).rollback"
  }

  # Enter a development shell
  export def develop [
    --profile (-p): string = ""   # Specify the profile name
    --dir (-d): string = ""       # Specify the base directory
    ...args: string               # Specify additional arguments to pass to nix
  ] {
    init --profile $profile --dir $dir
    nix develop ...$args
  }

  # Enter a shell with the flakey profile's environment
  export def shell [
    --profile (-p): string = ""   # Specify the profile name
    --dir (-d): string = ""       # Specify the base directory
    ...args: string               # Specify additional arguments to pass to nix
  ] {
    init --profile $profile --dir $dir
    nix shell ...$args
  }

  # Update the flake.lock file
  export def update [
    --profile (-p): string = "" # Specify the profile name
    --dir (-d): string = ""     # Specify the base directory
    ...inputs: string           # Specify the inputs to update (e.g. nixpkgs)
  ] {
    init --profile $profile --dir $dir
    nix flake update ...$inputs
    switch --profile $profile --dir $dir
  }

  export alias b = build
  export alias sw = switch
  export alias rb = rollback
  export alias r = rollback
  export alias dev = develop
  export alias d = develop
  export alias sh = shell
  export alias upd = update
  export alias up = update
  export alias u = update
}

use fp
