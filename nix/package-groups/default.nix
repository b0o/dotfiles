{
  inputs,
  pkgs,
  ...
}: {
  base = import ./base.nix {inherit inputs pkgs;};
  javascript = import ./javascript.nix {inherit inputs pkgs;};
  neovim = import ./neovim.nix {inherit inputs pkgs;};
  niri = import ./niri.nix {inherit inputs pkgs;};
  shell = import ./shell.nix {inherit inputs pkgs;};
}
