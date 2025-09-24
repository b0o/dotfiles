---@type LazySpec[]
local spec = {
  {
    'nvim-neotest/neotest',
    cmd = { 'Neotest' },
    opts = {
      adapters = {
        lazy_require 'neotest-vitest',
        lazy_require 'rustaceanvim.neotest',
      },
      quickfix = {
        enabled = false,
        open = false,
      },
      summary = {
        open = [[botright vsplit +set\ nowrap | vertical resize 50]],
      },
      icons = {
        running_animated = {
          '⠋',
          '⠙',
          '⠹',
          '⠸',
          '⠼',
          '⠴',
          '⠦',
          '⠧',
          '⠇',
          '⠏',
        },
      },
    },
  },
  'marilari88/neotest-vitest',
}

very_lazy(function()
  local maputil = require 'user.util.map'
  local map = maputil.map
  local wrap = maputil.wrap

  local neotest = lazy_require 'neotest'
  local neotest_summary = lazy_require 'neotest.consumers.summary'

  map('n', '<leader>nn', neotest.run.run, 'Neotest: Run Nearest Test')
  map('n', { '<leader>N', '<leader>nf' }, function() neotest.run.run(vim.fn.expand '%') end, 'Neotest: Run File')

  map('n', '[n', wrap(neotest.jump.prev, { status = 'failed' }), 'Neotest: Jump Prev Failed')
  map('n', ']n', wrap(neotest.jump.next, { status = 'failed' }), 'Neotest: Jump Next Failed')

  map('n', '<M-n>', function()
    neotest_summary.open()
    if vim.bo.filetype == 'neotest-summary' then
      vim.cmd 'wincmd p'
    else
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'neotest-summary' then
          vim.api.nvim_set_current_win(win)
          return
        end
      end
    end
  end, 'Neotest: Open or Focus Summary')

  map('n', '<M-S-n>', neotest.summary.toggle, 'Neotest: Toggle Summary')
end)

return spec
