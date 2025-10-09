$env.EDITOR = "nvim"

$env.GIT_PROJECTS_DIR = $"($nu.home-path)/git"
$env.XDG_CONFIG_HOME = $"($nu.home-path)/.config"
$env.XDG_DATA_HOME = $"($nu.home-path)/.local/share"
$env.XDG_CACHE_HOME = $"($nu.home-path)/.cache"

$env.DOTFILES_HOME = $"($env.XDG_CONFIG_HOME)/dotfiles"

$env.PATH = (
  $env.PATH
  | split row (char esep)
  | append $"($nu.home-path)/.nix-profile/bin"
  | append $"($nu.home-path)/.local/bin"
  | append $"($nu.home-path)/bin"
)

$env.config.show_banner = false
$env.config.completions = {
  algorithm: fuzzy
  quick: false
  partial: true
}
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

# SSH Agent configuration
$env.SSH_AGENT_PID = ($env.SSH_AGENT_PID? | default "")

if ($env.SSH_AUTH_SOCK? | is-empty) or (not ($env.SSH_AUTH_SOCK? | path exists)) {
  try {
    $env.SSH_AUTH_SOCK = (^gpgconf --list-dirs agent-ssh-socket | str trim)
  } catch {
    print -e "Failed getting SSH auth socket path from gpgconf"
  }
}

# GPG TTY configuration
$env.GPG_TTY = (^tty | str trim)

$env.FZF_DEFAULT_COMMAND = 'fd --type f --hidden --exclude=.git'

$env.FZF_DEFAULT_OPTS = ([
    "--preview='bat --color=always {} 2>/dev/null || eza -algF --git --group-directories-first -TL1 --color=always {}'"
    "--bind=ctrl-p:up"
    "--bind=ctrl-n:down"
    "--bind=alt-p:up"
    "--bind=alt-n:down"
    "--bind=btab:up"
    "--bind=tab:down"
    "--bind=ctrl-j:preview-down"
    "--bind=ctrl-k:preview-up"
    "--bind=alt-j:preview-half-page-down"
    "--bind=alt-k:preview-half-page-up"
] | str join ' ')

use hooks.nu

hooks use {
  # TODO: use atuin daemon
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
      CARAPACE_BRIDGES: 'zsh,fish,bash'
    }
  },
  starship: {
    enabled: true
    depends: starship
    cmd: [starship init nu]
  }
  mise: {
    enabled: true
    module: true
    overlay: true
    depends: mise
    cmd: [mise activate nu]
  }
  ls_colors: {
    enabled: true
    depends: vivid
    cmd: { || $"$env.LS_COLORS = '(vivid generate lavi)'" }
  }
}
