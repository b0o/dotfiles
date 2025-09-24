{
  inputs,
  pkgs,
  ...
}: {
  base = import ./base.nix {inherit inputs pkgs;};
  shell = import ./shell.nix {inherit inputs pkgs;};
  neovim = import ./neovim.nix {inherit inputs pkgs;};
}
