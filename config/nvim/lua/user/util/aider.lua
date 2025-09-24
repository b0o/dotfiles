local apiutil = require 'user.util.api'

local M = {}

local state = {
  ---@type string[]
  cmds = {},
}

---add an aider command to the list
---@param path string
M.add_cmd = function(path)
  if not vim.tbl_contains(state.cmds, path) then
    table.insert(state.cmds, path)
  end
end

---add the current buffer
---@param bufnr? number
M.add_buf = function(bufnr)
  bufnr = apiutil.resolve_bufnr(bufnr)
  if not bufnr then
    return
  end
  if vim.bo[bufnr].buftype ~= '' then
    return
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  if not path then
    return
  end
  path = vim.fn.fnamemodify(path, ':.')
  M.add_cmd(string.format('/add %s', path))
end

---add all files in a tabpage
---@param tabnr? number
M.add_tabpage = function(tabnr)
  tabnr = apiutil.resolve_tabnr(tabnr)
  if not tabnr then
    return
  end
  local wins = vim.api.nvim_tabpage_list_wins(tabnr)
  for _, winnr in ipairs(wins) do
    if vim.api.nvim_win_is_valid(winnr) then
      local bufnr = vim.api.nvim_win_get_buf(winnr)
      if vim.api.nvim_buf_is_valid(bufnr) then
        M.add_buf(bufnr)
      end
    end
  end
end

--- copy the current command list to the clipboard
M.copy_cmd = function()
  local cmd = table.concat(state.cmds, '\n')
  vim.fn.setreg('+', cmd)
  vim.notify('Copied: \n' .. cmd, vim.log.levels.INFO)
end

--- clear the command list
M.clear_cmd = function()
  state.cmds = {}
  vim.notify('Cleared command list', vim.log.levels.INFO)
end

return M
