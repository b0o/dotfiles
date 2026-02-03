; TODO: pruner injected languages for nix: https://github.com/pruner-formatter/pruner/issues/2
; References:
; - https://github.com/search?q=path%3Anix%2Finjections.scm&type=code
; - https://pruner-formatter.github.io/configuration.html
; - https://pruner-formatter.github.io/language-injections.html
; - https://www.reddit.com/r/neovim/comments/1bqz2rs/treesitter_syntax_highlighting_for_injected/
; - https://github.com/nvim-treesitter/nvim-treesitter/blob/main/runtime/queries/nix/injections.scm
; - https://github.com/nix-community/tree-sitter-nix/blob/master/queries/injections.scm
; - https://github.com/zed-extensions/nix/blob/main/languages/nix/injections.scm
; - https://github.com/helix-editor/helix/blob/583dba4cc4c8d9a6963efb74d32159ef1446473d/runtime/queries/nix/injections.scm
;
; ((comment) @injection.language (#offset! @injection.language 0 3 0 -3)
; expression: (indented_string_expression) @injection.content (#offset! @injection.content 0 2 0 -2))
