---@type LazySpec[]
return {
  {
    'stevearc/conform.nvim',
    config = function() require('user.plugins.conform.internal').setup() end,
    event = 'BufWritePre',
  },
}
