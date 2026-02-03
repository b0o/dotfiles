{pkgs, ...}:
with pkgs; {
  # NOTE: Nix-managed niri is broken on non-NixOS with nvidia-open-dkms with nigGl
  # nixGL doesn't work for compositors due to EGL_EXT_device_query incompatibility.
  # SEE: https://github.com/YaLTeR/niri/issues/1780
  niri = [niri];
  niri-unstable = [niri-unstable];

  graphical = [
    # UI
    waybar
    rofi
    wlr-which-key-b0o # modal keybindings (b0o fork)

    # Terminals
    ghostty
  ];

  other = [
    # Utilities
    pinentry-rofi # rofi frontend for pinentry

    # Screenshots
    grim # Wayland screenshot tool
    slurp # Interactively select a region in a Wayland compositor
    still # Freeze screen of Wayland compositor until command exits, for screenshots

    # Clipboard
    # TODO: re-enable once my PR is merged: https://github.com/b0o/wl-clipboard-rs/tree/feat-cli-copy-multi
    # wl-clipboard-rs # wl-clipboard replacement (wl-copy/wl-paste), written in Rust

    # Fonts
    ttf-pragmasevka # Pragmata Pro doppelgänger made of Iosevka SS08
  ];

  all = niri ++ graphical ++ other;
  all-unstable = niri-unstable ++ graphical ++ other;
}
