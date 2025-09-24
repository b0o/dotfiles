---@type LazySpec[]
return {
  {
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    lazy = false,
  },
  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    event = 'VeryLazy',
    config = function() require 'user.treesitter' end,
  },
  {
    'nvim-treesitter/nvim-treesitter-context',
    event = 'VeryLazy',
    opts = {
      enable = true,
      max_lines = 4,
    },
  },
  'JoosepAlviste/nvim-ts-context-commentstring',
  'Wansmer/sibling-swap.nvim',
  'Wansmer/treesj',
  'windwp/nvim-ts-autotag',
}
