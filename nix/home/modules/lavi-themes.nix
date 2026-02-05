# Lavi theme files for tools with externally-managed configs
# Installs theme files to ~/.nix-profile/share/<tool>/themes/
# Symlink from your config dir to the nix profile path to use them.
#
# Other tools that could use lavi themes in the future:
# - fzf: has inline lavi colors in hooks.nu, TODO to generate from lush
# - lazygit: no theme configured
# - nushell: no color_config set
# - zathura: has stale non-lavi colors
# - atuin: theme section commented out
# - rofi, waybar, mako, niri, wlr-which-key: hand-themed with lavi colors
{
  inputs,
  pkgs,
  ...
}: let
  lavi-opencode-theme = pkgs.writeTextDir "share/opencode/themes/lavi.json" inputs.lavi.lib.themes.opencode;
  lavi-zellij-theme = pkgs.writeTextDir "share/zellij/themes/lavi.kdl" inputs.lavi.lib.themes.zellij;
in {
  home.packages = [
    lavi-opencode-theme
    lavi-zellij-theme
  ];
}
