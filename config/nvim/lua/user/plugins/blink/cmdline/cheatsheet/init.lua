--- Cmdline cheatsheet for substitute/global commands
--- Shows context-aware help based on cursor position in :s/, :g/, etc.
---
--- REDRAW HACK EXPLANATION:
--- In cmdline mode, Neovim doesn't automatically redraw floating windows when they're
--- created or updated. The normal `nvim__redraw({ win = id, flush = true })` doesn't
--- force an immediate visual update - it only queues a redraw for the next event cycle.
---
--- The workaround (borrowed from noice.nvim) is to feed a character followed by backspace
--- via `nvim_feedkeys('Þ' .. '<BS>', 'n', true)`. This tricks Neovim into processing a
--- full event cycle (including screen redraws) without actually modifying the cmdline
--- content. The special character Þ (thorn) is used because it's unlikely to conflict
--- with user input or abbreviations.
---
--- A `forcing_redraw` guard prevents infinite loops since CmdlineChanged fires again
--- when we feed the keys.

local parser = require 'user.plugins.blink.cmdline.cheatsheet.parser'
local window = require 'user.plugins.blink.cmdline.cheatsheet.window'
local cheatsheets = require 'user.plugins.blink.cmdline.cheatsheet.cheatsheets'

local M = {}

local function update_cheatsheet()
  if window.is_forcing_redraw() then
    return
  end
  if vim.fn.getcmdtype() ~= ':' then
    M.hide()
    return
  end

  local cmdline = vim.fn.getcmdline()
  local pos = vim.fn.getcmdpos()
  local context = parser.parse(cmdline, pos)

  local sheet = cheatsheets[context]
  if sheet then
    window.show(sheet)
  else
    M.hide()
  end
end

function M.hide(skip_redraw)
  window.hide(skip_redraw)
end

function M.setup()
  local group = vim.api.nvim_create_augroup('blink-cmdline-cheatsheet', { clear = true })

  -- Pre-create buffer only (window creation during cmdline mode causes conceal issues)
  vim.schedule(window.ensure_buf)

  vim.api.nvim_create_autocmd('CmdlineChanged', {
    group = group,
    callback = function()
      if vim.fn.getcmdtype() == ':' then
        update_cheatsheet()
      end
    end,
  })

  vim.api.nvim_create_autocmd('CmdlineLeave', {
    group = group,
    callback = M.hide,
  })

  -- Hide when blink shows completions (they take priority)
  -- Skip force_redraw to avoid interfering with blink's documentation rendering
  local ok, menu = pcall(require, 'blink.cmp.completion.windows.menu')
  if ok and menu.open_emitter then
    menu.open_emitter:on(function()
      M.hide(true)
    end)
  end
end

return M
