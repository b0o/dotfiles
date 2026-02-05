{
  pkgs,
  inputs,
  ...
}: let
  nvimLib = import ../lib/neovim.nix {inherit pkgs;};
in
  with pkgs; [
    neovim-nightly
    tree-sitter-nightly

    # Nix-managed plugins (installed to ~/.nix-profile/share/nvim/lazy/)
    (nvimLib.mkLazyPlugin "blink.cmp" inputs.blink-cmp.packages.${pkgs.system}.default)

    ### Lanugage Servers / Tools
    # Nix
    alejandra # black-inspired formatting
    nil # language server
    nixd # Nix language server, based on nix libraries
    nixfmt # nix formatter
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
    pruner # tree-sitter formatter orchestrator supporting injected code blocks
    dprint # fast multi-language formatter
    stylua # lua formatter
    nufmt # nushell formatter (TODO: use nufmt flake)

    ## Topiary
    topiary # tree-sitter based generic formatter
    inputs.topiary-nushell.packages.${pkgs.system}.topiary-nushell # topairy nushell formatter
  ]
