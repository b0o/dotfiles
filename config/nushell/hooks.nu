let config = $env.XDG_CONFIG_HOME? | default ($env.HOME | path join .config)

let hm_session_vars = "~/.nix-profile/etc/profile.d/hm-session-vars.sh" | path expand
let user_dirs = [$config "user-dirs.dirs"] | path join | path expand

hooks use --timeit {
  env: {
    enabled: true
    cmd: {
      hooks serialize env-smart --default {
        EDITOR: "nvim"
        XDG_CONFIG_HOME: $config
        GIT_PROJECTS_DIR: $"($env.HOME)/git"
        XDG_DATA_HOME: $"($env.HOME)/.local/share"
        XDG_CACHE_HOME: $"($env.HOME)/.cache"
        DOTFILES_HOME: $"($config)/dotfiles"
        PATH: [
          $"($env.HOME)/bin" # TODO: remove
          $"($env.HOME)/.config/bin"
          $"($env.HOME)/.nix-profile/bin"
          $"($env.HOME)/.local/bin"
          $"($env.HOME)/.cache/.bun/bin"
          $"($env.HOME)/.cargo/bin"
        ]
      }
    }
    on_load: {
      $env.GPG_TTY = $env.GPG_TTY? | default (^tty | str trim)
    }
  }
  user-dirs: {
    enabled: true
    depends: { (which bash-env-json | is-not-empty) and ($user_dirs | path exists) }
    hash_files: $user_dirs
    cmd: {
      use nushell/env.nu only-env
      hooks serialize env-smart (only-env --std [] {
        bash-env-json $user_dirs | from json | get -o shellvars
      })
    }
  }
  home-manager: {
    enabled: true
    depends: { (which nix home-manager bash-env-json | length) == 3 and ($hm_session_vars | path exists) }
    hash_files: $hm_session_vars
    cmd: {
      use nushell/env.nu only-env
      hooks serialize env-smart (only-env --std [] {
        bash-env-json $hm_session_vars | from json | get -o env
      })
    }
  }
  ssh_auth_sock: {
    enabled: true
    depends: gpgconf
    env: {{
      SSH_AUTH_SOCK: (^gpgconf --list-dirs agent-ssh-socket | str trim)
    }}
  }
  comark: {
    enabled: true
    hash_fn: {
      use comark "comark generate-autoload-hash"
      comark generate-autoload-hash
    }
    cmd: {
      use comark "comark generate-autoload"
      comark generate-autoload
    }
    on_load: {
      $env.config.keybindings ++= [
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
      ]
    }
  }
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
  formats: {
    enabled: true
    plugin: true
    plugin_cmd: nu_plugin_formats
    depends: nu_plugin_formats
  }
  skim: {
    enabled: true
    plugin: true
    plugin_cmd: nu_plugin_skim
    depends: nu_plugin_skim
    env: {{
      SKIM_DEFAULT_OPTIONS: ([
        --layout reverse
        --color ([
          # Lavi colorscheme
          # TODO: generate with lush + shipwright
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
    }}
    cmd: {
      hooks serialize block {
        def _complete_skim [] {
          use completion [commandline-fuzzy-complete-dwim]
          commandline-fuzzy-complete-dwim
        }
      }
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
    env: {{
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
        ] | str join)
        --color ([
          # Lavi colorscheme
          # TODO: generate with lush + shipwright
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
    }}
  }
}
