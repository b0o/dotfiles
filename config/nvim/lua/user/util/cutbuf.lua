local lazy = require 'user.util.lazy'
local fn = lazy.require_on_call_rec 'user.fn'

local MODE_NONE = 1
local MODE_CUT = 2
local MODE_COPY = 3

local M = {
  state = {
    buf = nil,
    win = nil,
    mode = MODE_NONE,
  },
}

M.cut = function(win)
  M.state.win = fn.resolve_winnr(win or 0)
  M.state.buf = vim.api.nvim_win_get_buf(M.state.win)
  M.state.mode = MODE_CUT
  vim.notify('cutbuf: cut buffer ' .. M.state.buf)
end

M.copy = function(win)
  M.state.win = nil
  M.state.buf = vim.api.nvim_win_get_buf(fn.resolve_winnr(win or 0))
  M.state.mode = MODE_COPY
  vim.notify('cutbuf: copy buffer ' .. M.state.buf)
end

M.paste = function(win)
  if M.state.mode == MODE_NONE or not vim.api.nvim_buf_is_valid(M.state.buf or -1) then
    vim.notify 'cutbuf: no buffer to paste'
    return
  end

  local target_win = fn.resolve_winnr(win or 0)
  local target_win_buf = vim.api.nvim_win_get_buf(target_win)
  vim.api.nvim_win_set_buf(target_win, M.state.buf)
  vim.notify('cutbuf: paste buffer ' .. M.state.buf)

  if M.state.mode == MODE_CUT and vim.api.nvim_win_is_valid(M.state.win or -1) then
    vim.api.nvim_win_set_buf(M.state.win, target_win_buf)
    M.state.win = nil
    M.state.buf = nil
    M.state.mode = MODE_NONE
  end
end

M.swap = function(win)
  win = fn.resolve_winnr(win or 0)
  local buf = vim.api.nvim_win_get_buf(win)
  local target_win = require('window-picker').pick_window()
  if not target_win or not vim.api.nvim_win_is_valid(target_win) or target_win == win then
    vim.notify 'cutbuf: no target window'
    return
  end
  local target_buf = vim.api.nvim_win_get_buf(target_win)
  vim.api.nvim_win_set_buf(win, target_buf)
  vim.api.nvim_win_set_buf(target_win, buf)
  vim.api.nvim_set_current_win(target_win)
  vim.notify('cutbuf: swap buffers ' .. buf .. ' and ' .. target_buf)
end

return M
