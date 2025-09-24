{
  inputs,
  pkgs,
  ...
}: {
  neovim = import ../package-groups/neovim.nix {inherit inputs pkgs;};
}
