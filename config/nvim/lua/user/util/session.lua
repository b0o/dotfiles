-- Session helpers which persist and load additional state with the session,
-- such as whether nvim-tree is open.
local M = {}

---@class user.util.session.SessionMeta
---@field focused number
---@field nvim_tree_open boolean
---@field nvim_tree_focused boolean
---@field fyler_open boolean
---@field fyler_focused boolean

---@return user.util.session.SessionMeta|nil
local function get_session_meta()
  if vim.g.SessionMeta then
    local meta_ok, meta = pcall(vim.json.decode, vim.g.SessionMeta or '{}')
    if not meta_ok then
      vim.notify('session_load: failed to decode metadata: ' .. meta, vim.log.levels.WARN)
      return
    end
    return meta
  end
end

---@param meta user.util.session.SessionMeta|nil
local function set_session_meta(meta) vim.g.SessionMeta = meta ~= nil and vim.json.encode(meta) or nil end

M.session_save = function()
  ---@type user.util.session.SessionMeta
  local meta = {
    focused = vim.api.nvim_get_current_win(),
    nvim_tree_open = false,
    nvim_tree_focused = false,
    fyler_open = false,
    fyler_focused = false,
  }

  if package.loaded['nvim-tree'] and require('nvim-tree.api').tree.is_visible() then
    meta.nvim_tree_open = true
    meta.nvim_tree_focused = vim.fn.bufname(vim.fn.bufnr()) == 'NvimTree'
    vim.cmd 'NvimTreeClose'
  elseif package.loaded['fyler'] then
    local finder = require('fyler.views.finder').instance()
    if finder and finder.win and finder.win:is_visible() then
      meta.fyler_open = true
      meta.fyler_focused = vim.bo[0].filetype == 'fyler'
      finder:close()
    end
  end

  set_session_meta(meta)
  require('session_manager').save_current_session()
  set_session_meta(nil)

  local refocus = function()
    if meta.focused and vim.api.nvim_win_is_valid(meta.focused) then
      vim.api.nvim_set_current_win(meta.focused)
    else
      vim.cmd.wincmd 'p'
    end
  end

  if meta.nvim_tree_open then
    vim.cmd 'NvimTreeOpen'
    if not meta.nvim_tree_focused then
      refocus()
    end
  elseif meta.fyler_open then
    require('fyler').open()
    if not meta.fyler_focused then
      vim.schedule(refocus)
    end
  end
end

M.session_load = function()
  vim.api.nvim_create_autocmd('SessionLoadPost', {
    once = true,
    callback = vim.schedule_wrap(function()
      local meta = get_session_meta()
      set_session_meta(nil)
      if not meta then
        return
      end

      if meta.nvim_tree_open then
        vim.cmd 'NvimTreeOpen'
      elseif meta.fyler_open then
        require('fyler').open()
      end

      local refocus = function()
        if meta.focused and vim.api.nvim_win_is_valid(meta.focused) then
          vim.api.nvim_set_current_win(meta.focused)
        else
          vim.cmd.wincmd 'p'
        end
      end

      if meta.nvim_tree_focused then
        vim.cmd 'NvimTreeFocus'
      elseif meta.fyler_open and not meta.fyler_focused then
        vim.schedule(refocus)
      else
        refocus()
      end
    end),
  })
  require('session_manager').load_current_dir_session(false)
end

return M
