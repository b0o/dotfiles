--- Window management for cmdline cheatsheet

local M = {}

local win_id = nil
local buf_id = nil
local is_visible = false
local forcing_redraw = false

local BS = vim.api.nvim_replace_termcodes('<BS>', true, false, true)
local ns_id = vim.api.nvim_create_namespace 'cmdline-cheatsheet'

function M.is_forcing_redraw()
  return forcing_redraw
end

function M.ensure_buf()
  if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
    buf_id = vim.api.nvim_create_buf(false, true)
    vim.bo[buf_id].buftype = 'nofile'
    vim.bo[buf_id].bufhidden = 'hide'
    vim.bo[buf_id].filetype = 'markdown_inline'
  end
  return buf_id
end

local function ensure_win()
  local buf = M.ensure_buf()
  if not win_id or not vim.api.nvim_win_is_valid(win_id) then
    win_id = vim.api.nvim_open_win(buf, false, {
      relative = 'editor',
      row = 0,
      col = 0,
      width = 1,
      height = 1,
      style = 'minimal',
      border = 'none',
      zindex = 1,
      focusable = false,
      hide = true,
    })
    vim.wo[win_id].wrap = false
    vim.wo[win_id].conceallevel = 2
    -- Disable search highlighting in this window by linking to Normal background
    vim.wo[win_id].winhighlight =
      'Normal:BlinkCmpDoc,FloatBorder:BlinkCmpDocBorder,Search:BlinkCmpDoc,IncSearch:BlinkCmpDoc,CurSearch:BlinkCmpDoc'
    is_visible = false
  end
  return win_id
end

local function force_redraw()
  if win_id and vim.api.nvim_win_is_valid(win_id) then
    vim.api.nvim__redraw { win = win_id, flush = true }
  end
  if not forcing_redraw then
    forcing_redraw = true
    vim.api.nvim_feedkeys('Þ' .. BS, 'n', true)
    vim.defer_fn(function()
      forcing_redraw = false
    end, 50)
  end
end

function M.show(sheet)
  local buf = M.ensure_buf()
  local win = ensure_win()

  -- Set content
  vim.bo[buf].modifiable = true
  local lines = vim.split(sheet.content, '\n')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Apply treesitter highlighting (using blink's method for proper conceal)
  local ok, blink_docs = pcall(require, 'blink.cmp.lib.window.docs')
  if ok and blink_docs.highlight_with_treesitter then
    blink_docs.highlight_with_treesitter(buf, 'markdown_inline', 0, #lines)
  end

  -- Apply custom highlights
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

  -- HR lines (dimmed)
  for _, line_nr in ipairs(sheet.hr_lines or {}) do
    vim.api.nvim_buf_set_extmark(buf, ns_id, line_nr, 0, {
      line_hl_group = 'Comment',
      priority = 1000,
    })
  end

  -- Code spans (colored by column)
  local code_highlights = { 'Function', 'Keyword', 'String' }
  for _, span in ipairs(sheet.code_spans or {}) do
    local hl = code_highlights[((span.col_index - 1) % #code_highlights) + 1]
    vim.api.nvim_buf_set_extmark(buf, ns_id, span.line, span.col_start, {
      end_col = span.col_end,
      hl_group = hl,
      priority = 1001,
    })
  end

  -- Use pre-calculated dimensions (add 2 for border padding)
  local width = math.min(sheet.width + 2, 80)
  local height = math.min(sheet.height, 20)

  -- Calculate position (below cmdline, accounting for noice)
  local row, col
  if vim.g.ui_cmdline_pos then
    row = vim.g.ui_cmdline_pos[1] + 1
    -- Offset to align with cmdline content (border + padding)
    col = vim.g.ui_cmdline_pos[2] - 3
  else
    local cmdheight = (vim.o.cmdheight == 0) and 1 or vim.o.cmdheight
    row = vim.o.lines - cmdheight + 1
    col = 0
  end

  -- Show window
  vim.api.nvim_win_set_config(win, {
    relative = 'editor',
    row = row,
    col = col,
    width = width,
    height = height,
    border = 'rounded',
    zindex = 1000,
    hide = false,
  })
  is_visible = true
  force_redraw()
end

function M.hide(skip_redraw)
  if win_id and vim.api.nvim_win_is_valid(win_id) and is_visible then
    vim.api.nvim_win_set_config(win_id, { hide = true })
    is_visible = false
    if not skip_redraw then
      force_redraw()
    end
  end
end

return M
