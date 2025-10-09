{
  pkgs,
  inputs,
  ...
}:
with pkgs; [
  # Niri Wayland compositor (unstable/nightly)
  # niri-unstable
  wlr-which-key-b0o # modal keybindings (b0o fork)
  wl-clipboard-rs # wl-clipboard replacement (wl-copy/wl-paste), written in Rust
]
