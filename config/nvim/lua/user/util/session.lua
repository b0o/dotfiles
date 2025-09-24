-- Session helpers which persist and load additional state with the session,
-- such as whether nvim-tree is open.
local M = {}

M.session_save = function()
  local meta = {
    focused = vim.api.nvim_get_current_win(),
    nvimTreeOpen = false,
    nvimTreeFocused = false,
  }
  if package.loaded['nvim-tree'] and require('nvim-tree.api').tree.is_visible() then
    meta.nvimTreeOpen = true
    meta.nvimTreeFocused = vim.fn.bufname(vim.fn.bufnr()) == 'NvimTree'
    vim.cmd 'NvimTreeClose'
  end

  vim.g.SessionMeta = vim.json.encode(meta)
  require('session_manager').save_current_session()
  vim.g.SessionMeta = nil

  if meta.nvimTreeOpen then
    vim.cmd 'NvimTreeOpen'
    if not meta.nvimTreeFocused and vim.api.nvim_win_is_valid(meta.focused) then
      vim.api.nvim_set_current_win(meta.focused)
    end
  end
end

M.session_load = function()
  vim.api.nvim_create_autocmd('SessionLoadPost', {
    once = true,
    callback = vim.schedule_wrap(function()
      local meta_ok, meta = pcall(vim.json.decode, vim.g.SessionMeta or '{}')
      if not meta_ok then
        vim.notify('session_load: failed to decode metadata: ' .. meta, vim.log.levels.WARN)
        meta = {}
      end
      vim.g.SessionMeta = nil
      if meta.nvimTreeOpen then
        vim.cmd 'NvimTreeOpen'
      end
      if meta.nvimTreeFocused then
        vim.cmd 'NvimTreeFocus'
      elseif meta.focused and vim.api.nvim_win_is_valid(meta.focused) then
        vim.api.nvim_set_current_win(meta.focused)
      end
    end),
  })
  require('session_manager').load_current_dir_session(false)
end

return M
