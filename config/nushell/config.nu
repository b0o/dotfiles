use types *
use comark

$env.config.use_kitty_protocol = true
$env.config.show_banner = false
$env.config.completions = {
  algorithm: fuzzy
  quick: false
  partial: true
}
$env.config.keybindings ++= [
  # Remap ctrl+o to ctrl+g
  {
    modifier: control
    keycode: char_o
    mode: [emacs vi_normal vi_insert]
    event: null
  }
  {
    modifier: control
    keycode: char_g
    mode: [emacs vi_normal vi_insert]
    event: {send: OpenEditor}
  }
  # TODO: fix collision with zellij
  {
    name: completion_menu
    modifier: alt
    keycode: tab
    mode: emacs
    event: {send: menu name: ide_completion_menu}
  }
]

# TODO: lazy loading
use nushell/hooks
do --env { source ./hooks.nu }
