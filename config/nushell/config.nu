use hooks
use completion [commandline-fuzzy-complete-dwim]
use comark *
use awtrix

$env.config.completions = {
  algorithm: fuzzy
  quick: false
  partial: true
}

$env.config.keybindings ++= [
  {
      name: fuzzy_complete_dwim
      modifier: none
      keycode: char_á # mapped to ctrl+tab in ghostty
      mode: [emacs vi_insert]
      event: [
        {
          send: executehostcommand
          cmd: commandline-fuzzy-complete-dwim
        }
      ]
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

$env.config.hooks.pre_prompt ++= [
  # Direnv
  {
    if (which direnv | is-empty) {
      return
    }
    direnv export json | from json | default {} | load-env
  }
]

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
