{
  inputs,
  pkgs,
  ...
}: let
  packageGroups = import ../package-groups/default.nix {
    inherit inputs pkgs;
    homeDirectory =
      if pkgs.stdenv.isLinux
      then "/home/maddy"
      else "/Users/maddy";
  };
in
  inputs.flakey-profile.lib.mkProfile {
    inherit pkgs;

    # Specifies things to pin in the flake registry and in NIX_PATH.
    pinned = {nixpkgs = toString inputs.nixpkgs;};

    paths = packageGroups.neovim;
  }
