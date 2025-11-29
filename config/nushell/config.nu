use hooks
# use completion [commandline-fuzzy-complete-dwim]
use comark *
# use awtrix

$env.config.completions = {
  algorithm: fuzzy
  quick: false
  partial: true
}

$env.config.keybindings ++= [
  # {
  #   name: fuzzy_complete_dwim
  #   modifier: none
  #   keycode: char_á # mapped to ctrl+tab in ghostty
  #   mode: [emacs vi_insert]
  #   event: [
  #     {
  #       send: executehostcommand
  #       cmd: commandline-fuzzy-complete-dwim
  #     }
  #   ]
  # }
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

$env.config.use_kitty_protocol = true

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
      CARAPACE_ENV: 0
      CARAPACE_UNFILTERED: 1
      CARAPACE_MERGEFLAGS: 0
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
}
