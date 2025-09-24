local M = {}

M.start = function()
  require('supermaven-nvim').setup {
    disable_keymaps = true,
    ignore_filetypes = {
      ['dap-repl'] = true,
      dapui_scopes = true,
      dapui_breakpoints = true,
      dapui_stacks = true,
      dapui_watches = true,
      dapui_hover = true,
    },
  }

  local c = require 'supermaven-nvim.completion_preview'
  local xk = require('user.keys').xk
  local map = require('user.util.map').map

  map('i', { xk [[<C-\>]], '' }, c.on_accept_suggestion, 'SuperMaven: Accept')
  map('i', { [[<M-\>]] }, c.on_accept_suggestion_word, 'SuperMaven: Accept word')

  map('i', [[<M-right>]], function()
    local smu = require 'supermaven-nvim.util'
    local orig_to_next_word = smu.to_next_word
    ---@diagnostic disable-next-line: duplicate-set-field
    smu.to_next_word = function(str)
      local match = str:match '^.'
      if match ~= nil then
        return match
      end
      return ''
    end
    pcall(c.on_accept_suggestion_word)
    smu.to_next_word = orig_to_next_word
  end, 'SuperMaven: Accept next char')
end

M.stop = function()
  local xk = require('user.keys').xk

  vim.keymap.del('i', xk [[<C-\>]])
  vim.keymap.del('i', '')
  vim.keymap.del('i', [[<M-\>]])

  require('supermaven-nvim.api').stop()
end

return M
