{inputs, ...}: let
  additions = final: _prev:
    import ../pkgs {
      inherit inputs;
      pkgs = final;
    };

  modifications = final: prev: {
    wlr-which-key-b0o = inputs.wlr-which-key-b0o.packages.${final.system}.default;
    # FIXME: how to properly add bash-env-nushell?
    # bash-env-nushell = inputs.bash-env-nushell.flakePkgs.bash-env-nushell.${final.system}.default;
  };
in
  inputs.nixpkgs.lib.composeManyExtensions [
    additions
    modifications
    (import ./opencode.nix {inherit inputs;})
  ]
