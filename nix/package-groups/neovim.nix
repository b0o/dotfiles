{
  pkgs,
  inputs,
  ...
}:
with pkgs; [
  # Give neovim access to a C compiler for tree-sitter grammars
  (neovim.overrideAttrs (old: {
    propagatedBuildInputs =
      (old.propagatedBuildInputs or []) ++ [stdenv.cc.cc];
  }))

  # Tree Sitter + Node for installing Treesitter Grammars
  inputs.neovim-nightly-overlay.packages.${pkgs.system}.tree-sitter

  ### Lanugage Servers / Tools
  # Nix
  nil # language server
  alejandra # black-inspired formatting
  statix # linter

  # Misc
  just-lsp # lsp server for just files
  tombi # TOML Formatter / Linter / Language Server
  vscode-langservers-extracted # vscode-{css,eslint,html,json,markdown}-langserver
]
