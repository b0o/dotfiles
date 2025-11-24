---- Auto-resize
--- Provides window auto-resizing and collapsing functionality
---@class AutoResize
---@field enabled boolean Whether auto-resize is currently enabled
---@field auto_resize_group number|nil Augroup ID for auto-resize events
local M = {
  enabled = false,
  auto_resize_group = nil,
}

---Disables automatic window resizing
---@return nil
M.disable_autoresize = function()
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
  M.auto_resize_group = vim.api.nvim_create_augroup('auto_resize', { clear = true })
  vim.api.nvim_create_autocmd({ 'VimResized', 'WinNew', 'WinClosed' }, {
    group = M.auto_resize_group,
    callback = vim.schedule_wrap(function() vim.cmd 'wincmd =' end),
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

return M
