{pkgs, ...}:
with pkgs; [
  # Give neovim access to a C compiler for tree-sitter grammars
  (neovim.overrideAttrs (old: {
    propagatedBuildInputs =
      (old.propagatedBuildInputs or []) ++ [stdenv.cc.cc];
  }))

  # Tree Sitter + Node for installing Treesitter Grammars
  inputs.neovim-nightly-overlay.packages.${pkgs.stdenv.hostPlatform.system}.tree-sitter

  ### Lanugage Servers / Tools
  # Nix
  alejandra # black-inspired formatting
  nil # language server
  statix # linter

  ## LSPs
  just-lsp # lsp server for just files
  tombi # TOML Formatter / Linter / Language Server
  vscode-langservers-extracted # vscode-{css,eslint,html,json,markdown}-langserver
  svelte-language-server # svelte language server
  tailwindcss-language-server # tailwindcss language server
  typescript-go # tsgo - typescript language server (golang re-implementation)
  yaml-language-server # yaml language server

  ## Formatters
  dprint # multi-language formatter
  stylua # lua formatter
]
