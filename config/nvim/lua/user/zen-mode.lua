local zen_view = require 'zen-mode.view'

local M = {}

local last_buf
local augroup

function M.unset_keymaps(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  for _, dir in ipairs { 'h', 'j', 'k', 'l' } do
    pcall(vim.keymap.del, 'n', '<M-' .. dir .. '>', { buffer = buf })
  end
  pcall(vim.keymap.del, 'n', '<M-a>', { buffer = buf })
end

function M.setup_keymaps(buf)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  for _, dir in ipairs { 'h', 'j', 'k', 'l' } do
    vim.keymap.set('n', '<M-' .. dir .. '>', function()
      M.move(dir)
    end, { buffer = buf })
  end
  vim.keymap.set('n', '<M-a>', function()
    M.move 'a'
  end, { buffer = buf })
end

---@param dir 'h' | 'j' | 'k' | 'l' | 'a' | { win: number } | { buf: number }
function M.move(dir)
  if not zen_view.is_open() then
    vim.notify_once('Zen: Move: Not in Zen Mode', vim.log.levels.WARN)
    return
  end
  if not zen_view.parent or not vim.api.nvim_win_is_valid(zen_view.parent) then
    return
  end

  local target_win
  if type(dir) == 'table' then
    if dir.buf then
      vim.api.nvim_win_set_buf(zen_view.parent, dir.buf)
      target_win = zen_view.parent
    else
      target_win = dir.win
    end
  elseif dir == 'a' then
    target_win = require('user.util.recent-wins').get_most_recent_any(zen_view.parent)
  else
    target_win = vim.api.nvim_win_call(zen_view.parent, function()
      return vim.fn.win_getid(vim.fn.winnr(dir))
    end)
  end
  if not target_win or not vim.api.nvim_win_is_valid(target_win) then
    return
  end
  local target_buf = vim.api.nvim_win_get_buf(target_win)
  if not target_buf or not vim.api.nvim_buf_is_valid(target_buf) or not vim.bo[target_buf].buflisted then
    return
  end

  -- update the cursor position in the parent window, so it's saved for if we return to it
  if zen_view.parent and vim.api.nvim_win_is_valid(zen_view.parent) then
    vim.api.nvim_win_set_cursor(zen_view.parent, vim.api.nvim_win_get_cursor(zen_view.win))
  end

  -- switch to the target buffer
  vim.api.nvim_win_set_buf(zen_view.win, target_buf)

  -- sync the cursor position from the parent window to the floating window
  vim.api.nvim_win_set_cursor(zen_view.win, vim.api.nvim_win_get_cursor(target_win))

  if last_buf and vim.api.nvim_buf_is_valid(last_buf) then
    M.unset_keymaps(last_buf)
  end

  -- set the previous parent window as the most recent
  require('user.util.recent-wins').update(target_win)

  last_buf = target_buf
  zen_view.parent = target_win
  M.setup_keymaps(target_buf)
end

function M.on_open()
  augroup = vim.api.nvim_create_augroup('user.zen-mode', { clear = true })

  vim.api.nvim_create_autocmd('WinClosed', {
    group = augroup,
    pattern = tostring(zen_view.win),
    once = true,
    callback = function()
      local target = zen_view.parent
      vim.defer_fn(function()
        if target and vim.api.nvim_win_is_valid(target) then
          vim.api.nvim_set_current_win(target)
        end
      end, 0)
      M.unset_keymaps(vim.api.nvim_get_current_buf())
    end,
  })

  M.setup_keymaps(vim.api.nvim_get_current_buf())
end

return M
