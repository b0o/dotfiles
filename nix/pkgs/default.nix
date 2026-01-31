{pkgs, ...} @ args: {
  ttf-pragmasevka = pkgs.callPackage ./ttf-pragmasevka.nix args;
  still = pkgs.callPackage ./still.nix args;
  zellij-pr-passthrough = pkgs.callPackage ./zellij-pr-passthrough.nix args;
  pruner = pkgs.callPackage ./pruner.nix args;
}
