use hooks
use comark *

# like load-env, but only sets the environment variable if
# it's not already set
def --env default-env [defaults: record] {
  let unset = $defaults
    | transpose name value
    | where {|it| $env | get -o $it.name | is-empty }
    | transpose -dr
  if ($unset | is-not-empty) {
    $unset | load-env
  }
}

# Add paths to PATH
def --env add-path [paths: list<string>] {
    $env.PATH = ($env.PATH
        | where ($it not-in $paths)
        | append $paths
    )
}

default-env ({
  EDITOR: "nvim"
  GIT_PROJECTS_DIR: $"($nu.home-dir)/git"
  XDG_CONFIG_HOME: $"($nu.home-dir)/.config"
  XDG_DATA_HOME: $"($nu.home-dir)/.local/share"
  XDG_CACHE_HOME: $"($nu.home-dir)/.cache"
  DOTFILES_HOME: $"($env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config))/dotfiles"
  GPG_TTY: (^tty | str trim)
})

add-path ([
  $"($nu.home-dir)/bin"
  $"($nu.home-dir)/.nix-profile/bin"
  $"($nu.home-dir)/.local/bin"
  $"($nu.home-dir)/.cache/.bun/bin"
  $"($nu.home-dir)/.cargo/bin"
])

# See ./autoload/plugins.nu
$env.NU_PLUGINS = [
  # { name: example, cmd?: nu_plugin_example }
  # { name: example, path?: /path/to/plugin }
  { name: skim, cmd: nu_plugin_skim }
]

$env.config.use_kitty_protocol = true
$env.config.show_banner = false
$env.config.completions = {
  algorithm: fuzzy
  quick: false
  partial: true
}
$env.config.keybindings ++= [
  {
    name: completion_menu
    modifier: alt
    keycode: tab
    mode: emacs
    event: { send: menu name: ide_completion_menu }
  }
  {
    name: insert_fzf_result
    modifier: alt
    keycode: char_/
    mode: [emacs vi_normal vi_insert]
    event: {
      send: executehostcommand
      cmd: "fzf,path"
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

if (($env.SSH_AUTH_SOCK? | is-empty) or (not ($env.SSH_AUTH_SOCK? | path exists))) and (which gpgconf | is-not-empty) {
  try {
    $env.SSH_AUTH_SOCK = (^gpgconf --list-dirs agent-ssh-socket | str trim)
  } catch {
    print -e "Failed getting SSH auth socket path from gpgconf"
  }
}

hooks use {
  # TODO: use atuin daemon
  atuin: {
    enabled: true
    depends: atuin
    env: {
      ATUIN_NOBIND: true
    }
    cmd: [atuin init nu]
    on_load: {
      $env.config.keybindings ++= [{
        name: atuin
        modifier: control
        keycode: char_r
        mode: [emacs vi_normal vi_insert]
        event: { send: executehostcommand cmd: (_atuin_search_cmd) }
      }]
    }
  }
  carapace: {
    enabled: true
    depends: carapace
    cmd: [carapace _carapace nushell]
    env: {
      CARAPACE_BRIDGES: 'zsh,fish,bash'
      CARAPACE_ENV: false
      CARAPACE_UNFILTERED: true
      CARAPACE_MERGEFLAGS: false
    }
  }
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
    cmd: { $"$env.LS_COLORS = '(vivid generate lavi)'" }
  }
  direnv: {
    enabled: true
    depends: direnv
    on_load: {
      $env.config.hooks.pre_prompt ++= [{ direnv export json | from json | default {} | load-env }]
    }
  }
  skim: {
    enabled: true
    depends: nu_plugin_skim
    env: {
      SKIM_DEFAULT_OPTIONS: ([
        --layout reverse
        --color ([
          # Lavi colorscheme
          bg:-1
          bg+:-1
          fg+:12
          current:#FFFFFF
          current_bg:#2D2846
          matched:#E2B2F1
          matched_bg:empty
          current_match:#F5D9FD
          current_match_bg:empty
          info:#848FF1
          prompt:#B29EED
          cursor:#9C73FE
          selected:#7CF89C
          spinner:#3FC4C4
          header:#B29EED
          border:#8977A8
        ] | str join ",")
      ] | str join ' ')
    }
    cmd: {
      view source {
        def _complete_skim [] {
          use completion [commandline-fuzzy-complete-dwim]
          commandline-fuzzy-complete-dwim
        }
      } | str trim -lc '{' | str trim -rc '}'
    }
    on_load: {
      $env.config.keybindings ++= [
        {
          name: fuzzy_complete_dwim
          modifier: none
          keycode: char_á # mapped to ctrl+tab in ghostty
          mode: [emacs vi_insert]
          event: [
            {
              send: executehostcommand
              cmd: _complete_skim
            }
          ]
        }
      ]
    }
  }
  fzf: {
    enabled: true
    depends: fzf
    env: {
      FZF_DEFAULT_COMMAND: (
        'fd --type f --hidden --exclude .git'
      )
      FZF_DEFAULT_OPTS: ([
        --layout reverse
        --bind ctrl-p:up
        --bind ctrl-n:down
        --bind alt-p:up
        --bind alt-n:down
        --bind btab:up
        --bind tab:down
        --bind ctrl-j:preview-down
        --bind ctrl-k:preview-up
        --bind alt-j:preview-half-page-down
        --bind alt-k:preview-half-page-up
        --preview-border none
        --separator ─
        --scrollbar ▌
        --preview ([
          '"'
          "bat --decorations=never --color=always {} 2>/dev/null"
          " || "
          "eza -algF --git --group-directories-first -TL1 --color=always {}"
          '"'
        ] | str join '')
        --color ([
          # Lavi colorscheme
          fg:#FFF1E0
          bg:#25213B
          fg+:#FFFFFF
          bg+:#2D2846
          gutter:#25213B
          hl:#E2B2F1
          hl+:#F5D9FD
          query:#FFF1E0
          disabled:#9A9AC0
          info:#848FF1
          prompt:#B29EED
          pointer:#9C73FE
          marker:#7CF89C
          spinner:#3FC4C4
          header:#B29EED
          footer:#B29EED
          border:#8977A8
          scrollbar:#4C435C
          separator:#4C435C
          preview-border:#8977A8
          preview-scrollbar:#4C435C
          label:#EBBBF9
          preview-label:#EBBBF9
          preview-fg:#EEE6FF
          preview-bg:#1D1A2E
        ] | str join ",")
      ] | str join ' ')
    }
  }
}
