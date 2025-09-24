---@type LazySpec[]
return {
  {
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        { 'lazy.nvim', words = { 'lazy', 'LazySpec' } },
        { path = 'luvit-meta/library', words = { 'vim%.uv' } },
      },
    },
  },
  'Bilal2453/luvit-meta', -- `vim.uv` typings
}
