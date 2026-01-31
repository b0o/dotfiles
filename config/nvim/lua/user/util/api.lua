-- Helpers and utilities for vim.api
local api = vim.api

local M = {}

---@param bufnr? number @the buffer number to resolve (defaults to current buffer)
---@return number|nil @the resolved buffer number or nil if the buffer is invalid
function M.resolve_bufnr(bufnr)
  local resolved = bufnr ~= 0 and bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(resolved) then
    return nil
  end
  return resolved
end

---@param winnr? number @the window number to resolve
---@return number|nil @the resolved window number or nil if the window is invalid
function M.resolve_winnr(winnr)
  local resolved = winnr ~= 0 and winnr or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(resolved) then
    return nil
  end
  return resolved
end

---@param tabnr? number @the tabpage number to resolve
---@return number|nil @the resolved tabpage number or nil if the tabpage is invalid
function M.resolve_tabnr(tabnr)
  local resolved = tabnr ~= 0 and tabnr or vim.api.nvim_get_current_tabpage()
  if not vim.api.nvim_tabpage_is_valid(resolved) then
    return nil
  end
  return resolved
end

---@param win? number @the window number
---@param name string @the buffer option name
---@return any @the option value or nil if the window/option is invalid
function M.win_get_buf_option(win, name)
  win = M.resolve_winnr(win)
  if not win then
    return nil
  end
  local buf = api.nvim_win_get_buf(win)
  if not buf then
    return nil
  end
  return vim.bo[buf][name]
end

---@param win? number @the window number
---@param name string @the buffer option name
---@return any @the option value or nil if the window/option is invalid
function M.win_get_buf_var(win, name)
  win = M.resolve_winnr(win)
  if not win then
    return nil
  end
  local buf = api.nvim_win_get_buf(win)
  if not buf then
    return nil
  end
  return api.nvim_buf_get_var(buf, name)
end

---@param win? number @the window number
---@return boolean @true if the window is modified
function M.win_is_modified(win)
  win = M.resolve_winnr(win)
  if not win then
    return false
  end
  return M.win_get_buf_option(win, 'modified')
end

---@param win? number @the window number
---@return boolean @true if the window is floating
function M.win_is_floating(win)
  win = M.resolve_winnr(win)
  if not win then
    return false
  end
  local cfg = vim.api.nvim_win_get_config(win)
  if not cfg then
    return false
  end
  return cfg.relative and cfg.relative ~= '' and true or false
end

---@param tabpage? number @the tabpage number
---@return boolean @true if the tabpage is modified
function M.tabpage_is_modified(tabpage)
  tabpage = M.resolve_tabnr(tabpage)
  if not tabpage then
    return false
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if M.win_is_modified(win) then
      return true
    end
  end
  return false
end

---@param tabpage? number @the tabpage number
---@return number[] @the buffer numbers in the tabpage
function M.tabpage_list_bufs(tabpage)
  tabpage = M.resolve_tabnr(tabpage)
  if not tabpage then
    return {}
  end
  local bufs = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if bufs[buf] ~= nil then
      return {}
    end
    bufs[buf] = true
  end
  return vim.tbl_keys(bufs)
end

---@param tabpage? number @the tabpage number
---@return number|nil @the quickfix window number or nil if the tabpage has no quickfix window
function M.tabpage_get_quickfix_win(tabpage)
  tabpage = M.resolve_tabnr(tabpage)
  if not tabpage then
    return nil
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if M.win_get_buf_option(win, 'buftype') == 'quickfix' then
      return win
    end
  end
  return nil
end

---@param tabpage? number @the tabpage number
---@return number[] @the buffer numbers in the tabpage that are modified
function M.tabpage_list_modified_bufs(tabpage)
  tabpage = M.resolve_tabnr(tabpage)
  if not tabpage then
    return {}
  end
  return vim.tbl_filter(function(buf)
    return vim.bo[buf].modified
  end, M.tabpage_list_bufs(tabpage))
end

---@param buf? number @the buffer number
---@return boolean @true if the buffer is empty
function M.buf_is_empty(buf)
  buf = M.resolve_bufnr(buf)
  if not buf then
    return false
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  return #lines == 1 and lines[1] == ''
end

---@param buf? number @the buffer number
---@return number[] @the window numbers in the buffer
function M.buf_get_wins(buf)
  buf = M.resolve_bufnr(buf)
  if not buf then
    return {}
  end
  local wins = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      table.insert(wins, win)
    end
  end
  return wins
end

--- Sends keys to Neovim as if typed by the user
---@param keys string The key sequence to send (e.g. '<CR>', '<Space>', '<C-]><CR>')
function M.feedkeys(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, true, true), 'n', true)
end

return M
