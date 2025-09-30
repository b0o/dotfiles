$env.EDITOR = "nvim"

$env.GIT_PROJECTS_DIR = $"($nu.home-path)/git"
$env.XDG_CONFIG_HOME = $"($nu.home-path)/.config"
$env.XDG_DATA_HOME = $"($nu.home-path)/.local/share"
$env.XDG_CACHE_HOME = $"($nu.home-path)/.cache"

let dotfiles = $"($env.XDG_CONFIG_HOME)/dotfiles"

$env.PATH = (
  $env.PATH
  | split row (char esep)
  | append $"($nu.home-path)/.nix-profile/bin"
  | append $"($nu.home-path)/.local/bin"
  | append $"($nu.home-path)/bin"
  | append $"($dotfiles)/scripts/nix"
)

$env.config.show_banner = false
$env.config.keybindings = $env.config.keybindings ++ [
  {
    name: insert_fzf_result
    modifier: alt
    keycode: char_/
    mode: [emacs vi_normal vi_insert]
    event: {
      send: executehostcommand
      cmd: "fzf-path-complete"
    }
  }
  {
    name: comark_fzf_smart
    modifier: alt
    keycode: "char_,"
    mode: [emacs vi_insert vi_normal]
    event: {
      send: executehostcommand
      cmd: "fzf,smart"
    }
  }
]

# Direnv
$env.config.hooks.pre_prompt = (
  $env.config.hooks.pre_prompt | append ({ ||
    if (which direnv | is-empty) {
      return
    }
    direnv export json | from json | default {} | load-env
  })
)

use hooks.nu

hooks use {
  atuin: {
    enabled: true
    depends: atuin
    cmd: [atuin init nu]
  },
  carapace: {
    enabled: true
    depends: carapace
    cmd: [carapace _carapace nushell]
    env: {
      CARAPACE_BRIDGES: 'zsh,bash'
    }
  },
  starship: {
    enabled: true
    depends: starship
    cmd: [starship init nu]
  }
}
