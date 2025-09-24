---- github/copilot.vim
local M = {}

local xk = require('user.keys').xk

M.enable = function()
  vim.cmd [[Lazy load copilot.vim]]
  vim.schedule(function()
    vim.cmd [[Copilot status]]
    -- vim.cmd [[call copilot#Command("", "", "", "", "", "start")]]
  end)
  local opts = { expr = true, replace_keycodes = false, silent = true }
  vim.keymap.set('i', xk [[<C-\>]], [[copilot#Accept("\<CR>")]], opts)
  vim.keymap.set('i', [[^\]], [[copilot#Accept("\<CR>")]], opts)
  vim.keymap.set('i', [[<M-\>]], [[copilot#AcceptWord(" ")]], opts)
  vim.keymap.set('i', xk [[<M-S-\>]], [[copilot#AcceptLine("\<CR>")]], opts)
  vim.keymap.set('i', [[<M-[>]], [[copilot#Previous()]], opts)
  vim.keymap.set('i', [[<M-]>]], [[copilot#Next()]], opts)
end

M.disable = function()
  vim.cmd.Copilot 'disable'
  vim.keymap.del('i', xk [[<C-\>]])
  vim.keymap.del('i', [[^\]])
  vim.keymap.del('i', [[<M-\>]])
  vim.keymap.del('i', xk [[<M-S-\>]])
  vim.keymap.del('i', [[<M-[>]])
  vim.keymap.del('i', [[<M-]>]])
end

return M
