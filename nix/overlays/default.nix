{inputs, ...}: let
  additions = final: _prev:
    import ../pkgs {
      inherit inputs;
      pkgs = final;
    };

  modifications = final: prev: {
    wlr-which-key-b0o = inputs.wlr-which-key-b0o.packages.${final.stdenv.hostPlatform.system}.default;
    ghostty = inputs.ghostty.packages.${final.stdenv.hostPlatform.system}.default;
  };
in
  inputs.nixpkgs.lib.composeManyExtensions [
    additions
    modifications
    (import ./charles.nix)
    (import ./opencode.nix {inherit inputs;})
  ]
