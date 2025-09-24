---@type LazySpec[]
return {
  'kawre/leetcode.nvim',
  config = function()
    local maputil = require 'user.util.map'
    local map = maputil.map
    local xk = require('user.keys').xk

    map('n', '<localleader>lc', '<Cmd>Leet console<Cr>', 'Leet: Console')
    map('n', '<localleader>lr', '<Cmd>Leet run<Cr>', 'Leet: Run')
    map('n', '<localleader>ls', '<Cmd>Leet submit<Cr>', 'Leet: Submit')
    map('n', '<c-f>L', '<Cmd>Leet list<Cr>', 'Leet: Select question (all)')
    map('n', '<c-f>l', '<Cmd>Leet list status=notac<Cr>', 'Leet: Select question (in progress)')

    ---@diagnostic disable-next-line: missing-fields
    require('leetcode').setup {
      storage = {
        home = (vim.env.GIT_PROJECTS_DIR or vim.fn.stdpath 'data') .. '/leetcode',
        cache = vim.fn.stdpath 'cache' .. '/leetcode',
      },
      injector = { ---@type table<lc.lang, lc.inject>
        ['cpp'] = {
          before = { '#include <bits/stdc++.h>', 'using namespace std;' },
          after = 'int main() {}',
        },
      },
      keys = {
        toggle = { 'Q', 'q' },
        confirm = xk '<C-Cr>',
        reset_testcases = xk '<C-S-r>',
        use_testcase = xk '<C-S-u>',
        focus_testcases = '<M-h>',
        focus_result = '<M-l>',
      },
    }
  end,
  cmd = 'Leet',
  event = { 'BufRead leetcode.nvim', 'BufNewFile leetcode.nvim' },
}
