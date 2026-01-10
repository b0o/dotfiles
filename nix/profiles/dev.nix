{
  inputs,
  pkgs,
  ...
}: let
  packageGroups = import ../package-groups/default.nix {
    inherit inputs pkgs;
  };
in
  inputs.flakey-profile.lib.mkProfile {
    inherit pkgs;

    pinned = {nixpkgs = toString inputs.nixpkgs;};

    paths =
      packageGroups.base
      ++ packageGroups.javascript
      ++ packageGroups.neovim
      ++ packageGroups.niri
      ++ packageGroups.shell;
  }
