local smart_splits = lazy_require 'smart-splits'
local zellij_nav = lazy_require 'zellij-nav'
local wrap = require('user.util.map').wrap

---@type LazySpec[]
return {
  {
    'sindrets/winshift.nvim',
    cmd = 'WinShift',
    keys = {
      { '<Leader>M', '<Cmd>WinShift<Cr>', desc = 'WinShift: Start' },
      { '<Leader>mm', '<Cmd>WinShift<Cr>', desc = 'WinShift: Start' },
      { '<Leader>ws', '<Cmd>WinShift swap<Cr>', desc = 'WinShift: Swap' },
    },
    opts = {
      highlight_moving_win = true,
      focused_hl_group = 'Visual',
      moving_win_options = {
        wrap = false,
        cursorline = false,
        cursorcolumn = false,
        colorcolumn = '',
      },
    },
  },
  {
    'mrjones2014/smart-splits.nvim',
    cond = function() return vim.env.ZELLIJ == nil end,
    event = 'VeryLazy',
    keys = {
      { '<M-h>', wrap(smart_splits.move_cursor_left), desc = 'Goto window/pane left' },
      { '<M-j>', wrap(smart_splits.move_cursor_down), desc = 'Goto window/pane down' },
      { '<M-k>', wrap(smart_splits.move_cursor_up), desc = 'Goto window/pane up' },
      { '<M-l>', wrap(smart_splits.move_cursor_right), desc = 'Goto window/pane right' },
    },
  },
  {
    'swaits/zellij-nav.nvim',
    cond = function() return vim.env.ZELLIJ ~= nil end,
    event = 'VeryLazy',
    keys = {
      { '<M-h>', wrap(zellij_nav.left), { desc = 'Goto window/pane left' } },
      { '<M-j>', wrap(zellij_nav.down), { desc = 'Goto window/pane down' } },
      { '<M-k>', wrap(zellij_nav.up), { desc = 'Goto window/pane up' } },
      { '<M-l>', wrap(zellij_nav.right), { desc = 'Goto window/pane right' } },
    },
    opts = {},
  },
}
