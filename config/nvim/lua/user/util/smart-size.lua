---- Auto-resize
--- Provides window auto-resizing and collapsing functionality
local fn = require 'user.fn'

---@class AutoResize
---@field enabled boolean Whether auto-resize is currently enabled
---@field collapsed_windows table<number, boolean> Map of window handles to collapsed state
---@field auto_resize_group number|nil Augroup ID for auto-resize events
---@field collapse_groups table<number, number> Map of window handles to their collapse augroup IDs
---@field window_views table<number, {view: table, cursor: number[]}> Saved window views for collapsed windows
local M = {
  enabled = false,
  collapsed_windows = {},
  auto_resize_group = nil,
  collapse_groups = {},
  window_views = {},
}

---Disables automatic window resizing
---@return nil
M.disable_autoresize = function()
  local msg = fn.capture(fn.set_winfix, true, 'width', 'height')
  table.insert(msg, 'auto-resize disable')
  fn.notify(table.concat(msg, ', '))

  if M.auto_resize_group then
    vim.api.nvim_del_augroup_by_id(M.auto_resize_group)
    M.auto_resize_group = nil
  end
  M.enabled = false
end

---Triggers a window resize if auto-resize is enabled
---@return nil
M.update = function()
  if M.enabled then
    vim.cmd 'wincmd ='
  end
end

---Enables automatic window resizing
---@return nil
M.enable_autoresize = function()
  local msg = fn.capture(fn.set_winfix, false, 'width', 'height')
  table.insert(msg, 'auto-resize enable')
  fn.notify(table.concat(msg, ', '))

  M.auto_resize_group = vim.api.nvim_create_augroup('auto_resize', { clear = true })
  vim.api.nvim_create_autocmd({ 'VimResized', 'WinNew', 'WinClosed' }, {
    group = M.auto_resize_group,
    callback = function() vim.cmd 'wincmd =' end,
  })

  vim.cmd 'wincmd ='
  M.enabled = true
end

---Toggles automatic window resizing on/off
---@return nil
M.toggle = function()
  if M.enabled then
    M.disable_autoresize()
  else
    M.enable_autoresize()
  end
end

local function expand_window(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  vim.wo[win].winfixheight = false
  vim.cmd 'wincmd ='

  if M.window_views[win] then
    vim.api.nvim_win_set_cursor(win, M.window_views[win].cursor)
    vim.fn.winrestview(M.window_views[win].view)
    M.window_views[win] = nil
  end
end

local function collapse_window(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  M.window_views[win] = {
    view = vim.fn.winsaveview(),
    cursor = vim.api.nvim_win_get_cursor(win),
  }

  local target_height = vim.o.scrolloff * 2
  vim.wo[win].winfixheight = true
  vim.api.nvim_win_set_config(win, { height = target_height })
  vim.api.nvim_win_set_cursor(win, M.window_views[win].cursor)
  vim.cmd 'wincmd ='
end

---Toggles collapse state for a specific window
---@param win number|nil Window handle, defaults to current window if nil
---@return nil
M.toggle_collapse = function(win)
  win = fn.resolve_winnr(win or 0)
  if not win then
    return
  end

  if M.collapsed_windows[win] then
    M.collapsed_windows[win] = nil
    M.window_views[win] = nil
    expand_window(win)
    if M.collapse_groups[win] then
      vim.api.nvim_del_augroup_by_id(M.collapse_groups[win])
      M.collapse_groups[win] = nil
    end
  else
    M.collapsed_windows[win] = true
    if vim.api.nvim_get_current_win() ~= win then
      collapse_window(win)
    end
    M.collapse_groups[win] = vim.api.nvim_create_augroup('collapse_win_' .. win, { clear = true })

    vim.api.nvim_create_autocmd('WinEnter', {
      group = M.collapse_groups[win],
      pattern = '*',
      callback = function()
        local current_win = vim.api.nvim_get_current_win()
        if current_win == win then
          expand_window(win)
        end
      end,
    })

    vim.api.nvim_create_autocmd('WinLeave', {
      group = M.collapse_groups[win],
      pattern = '*',
      callback = function()
        local current_win = vim.api.nvim_get_current_win()
        if current_win == win then
          collapse_window(win)
        end
      end,
    })
  end
end

---Handles window enter events for collapsed windows
---@param win number Window handle
---@return nil
M.handle_win_enter = function(win)
  if M.collapsed_windows[win] then
    expand_window(win)
  end
end

---Handles window leave events for collapsed windows
---@param win number Window handle
---@return nil
M.handle_win_leave = function(win)
  if M.collapsed_windows[win] then
    collapse_window(win)
  end
end

---Clears collapse state for all windows
---@return nil
M.clear_all_collapse = function()
  for win, _ in pairs(M.collapsed_windows) do
    if vim.api.nvim_win_is_valid(win) then
      expand_window(win)
      if M.collapse_groups[win] then
        vim.api.nvim_del_augroup_by_id(M.collapse_groups[win])
        M.collapse_groups[win] = nil
      end
    end
  end
  M.collapsed_windows = {}
  M.window_views = {}
  fn.notify 'Cleared collapse mode for all windows'
end

return M
