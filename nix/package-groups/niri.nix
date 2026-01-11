{
  pkgs,
  inputs,
  ...
}:
with pkgs; [
  # Niri Wayland compositor (unstable/nightly)
  # niri-unstable
  wlr-which-key-b0o # modal keybindings (b0o fork)
  # TODO: re-enable once my PR is merged: https://github.com/b0o/wl-clipboard-rs/tree/feat-cli-copy-multi
  # wl-clipboard-rs # wl-clipboard replacement (wl-copy/wl-paste), written in Rust

  # Utilities
  pinentry-rofi # rofi frontend for pinentry

  # UI
  ttf-pragmasevka # Pragmata Pro doppelgänger made of Iosevka SS08
]
