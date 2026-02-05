# Desktop profile: settings for graphical environments
{ pkgs, ... }:
{
  imports = [
    ../modules/ghostty.nix
  ];

  home.sessionVariables = {
    GIO_EXTRA_MODULES = "${pkgs.dconf.lib}/lib/gio/modules";
  };
}
