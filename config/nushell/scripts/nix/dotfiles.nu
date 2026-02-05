def --env init [
  --force # Force override of existing profile
] {
  use ./lib.nu is-using-flakey-profile
  if (is-using-flakey-profile) and not $force {
    error make -u {msg: $"Error: flakey-profile is currently active. Use --force to override"}
  }
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

def complete-main [spans: list<string>] {
  use nushell/completion.nu carapace-complete
  init --force
  carapace-complete $spans home-manager
}

# TODO: nixos support
module _main {
  # Dotfiles / Home Manager
  @complete complete-main
  export def --wrapped main [
    --force (-f) # Force override of existing profile
    ...args: string
  ] {
    let home_flake = init --force=$force
    ^home-manager --flake $".#($home_flake)" ...$args
  }

  def complete-update [spans: list<string>] {
    use nushell/completion.nu carapace-complete
    init
    carapace-complete --skip=1 $spans nix flake update
  }

  # Update dotfiles flake.lock
  @complete complete-update
  export def --wrapped update [
    --force (-f) # Force override of existing profile
    ...args: string
  ] {
    init --force=$force
    ^nix flake update ...$args
  }

  def complete-secrets [spans: list<string>] {
    use nushell/completion.nu carapace-complete
    init --force
    carapace-complete --skip=1 $spans sops edit
  }

  # Edit sops-nix managed secrets in $env.EDITOR
  @complete complete-secrets
  export def --wrapped secrets [
    ...args: string
  ] {
    init --force # This is safe because this doesn't change the profile
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
  export use _main *

  @complete complete-main
  export def --wrapped main [...args: string] {
    _main ...$args
  }
}

export use _main *
