{pkgs, ...}:
with pkgs; [
  neovim-nightly
  tree-sitter-nightly

  ### Lanugage Servers / Tools
  # Nix
  alejandra # black-inspired formatting
  nil # language server
  nixd # Nix language server, based on nix libraries
  statix # linter

  ## LSPs
  just-lsp # lsp server for just files
  svelte-language-server # svelte language server
  tailwindcss-language-server # tailwindcss language server
  tombi # TOML Formatter / Linter / Language Server
  typescript-go # tsgo - typescript language server (golang re-implementation)
  vscode-langservers-extracted # vscode-{css,eslint,html,json,markdown}-langserver
  yaml-language-server # yaml language server
  lua-language-server # lua language server

  ## Formatters
  dprint # multi-language formatter
  stylua # lua formatter
  pruner # TreeSitter-powered formatter orchestrator
]
