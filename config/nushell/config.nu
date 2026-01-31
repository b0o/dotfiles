use types *

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
]

# TODO: lazy loading
use nushell/hooks
do --env { source ./hooks.nu }
