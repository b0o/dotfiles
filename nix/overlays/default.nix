# This file defines two overlays and composes them
{inputs, ...}: let
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev:
    import ../pkgs {
      inherit inputs;
      pkgs = final;
    };

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {
    # example = prev.example.overrideAttrs (oldAttrs: rec {
    # ...
    # });
    wlr-which-key-b0o = inputs.wlr-which-key-b0o.packages.${final.system}.default;
    # FIXME: how to properly add bash-env-nushell?
    # bash-env-nushell = inputs.bash-env-nushell.flakePkgs.bash-env-nushell.${final.system}.default;
  };
in
  inputs.nixpkgs.lib.composeManyExtensions [
    additions
    modifications
    # (import ./foobar.nix) # more overlays if needed
  ]
