local M = {}

-- Get the visual selection as a list-like table of lines
M.get_visual_selection = function(mode)
  if mode == nil then
    local mode_info = vim.api.nvim_get_mode()
    mode = mode_info.mode
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local cline, ccol = cursor[1], cursor[2]
  local vline, vcol = vim.fn.line 'v', vim.fn.col 'v'

  local rev = false
  local sline, scol
  local eline, ecol
  if cline == vline then
    if ccol <= vcol then
      sline, scol = cline, ccol
      eline, ecol = vline, vcol
      scol = scol + 1
      rev = true
    else
      sline, scol = vline, vcol
      eline, ecol = cline, ccol
      ecol = ecol + 1
    end
  elseif cline < vline then
    sline, scol = cline, ccol
    eline, ecol = vline, vcol
    scol = scol + 1
    rev = true
  else
    sline, scol = vline, vcol
    eline, ecol = cline, ccol
    ecol = ecol + 1
  end

  if mode == 'V' or mode == 'CTRL-V' or mode == '\22' then
    scol = 1
    ecol = nil
  end

  local result = {
    start = { line = sline, col = scol },
    finish = { line = eline, col = ecol },
    mode = mode,
    lines = {},
    reversed = rev,
  }

  local lines = vim.api.nvim_buf_get_lines(0, sline - 1, eline, 0)

  if #lines > 0 then
    local start_text, end_text
    if #lines == 1 then
      start_text = string.sub(lines[1], scol, ecol)
    else
      start_text = string.sub(lines[1], scol)
      end_text = string.sub(lines[#lines], 1, ecol)
    end

    local selection = { start_text }
    if #lines > 2 then
      vim.list_extend(selection, vim.list_slice(lines, 2, #lines - 1))
    end
    table.insert(selection, end_text)
    result.lines = selection
  end

  return result
end

-- Get the visual selection as a list-like table of lines
M.get_visual_selection_list = function(mode)
  local selection = M.get_visual_selection(mode)
  local lines = selection.lines
  if #lines == 0 then
    return
  end

  local scol = selection.start.col
  local ecol = selection.finish.col

  local start_text, end_text
  if #lines == 1 then
    start_text = string.sub(lines[1], scol, ecol)
  else
    start_text = string.sub(lines[1], scol)
    end_text = string.sub(lines[#lines], 1, ecol)
  end

  local result = { start_text }
  if #lines > 2 then
    vim.list_extend(result, vim.list_slice(lines, 2, #lines - 1))
  end
  table.insert(result, end_text)

  return result
end

--- Sets the visual selection in Neovim based on a given selection object.
--- @param sel { mode: string, start: { line: number, col: number }, finish: { line: number, col: number }, reversed: boolean }
function M.set_visual_selection(sel)
  local start_line = sel.start.line
  local start_col = sel.start.col - 1
  local finish_line = sel.finish.line
  local finish_col = sel.finish.col - 1
  local reversed = sel.reversed

  -- Validate mode: 'v' for character-wise, 'V' for line-wise, '<C-v>' for block-wise
  local mode = sel.mode
  if mode ~= 'v' and mode ~= 'V' and mode ~= '\22' then
    error "Invalid selection mode. Use 'v' for character-wise, 'V' for line-wise, or '<C-v>' for block-wise."
  end

  -- Exit visual mode if it is active
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<esc>', true, false, true), 'n', true)

  vim.schedule(function()
    -- set the "<" mark to the start of the selection
    vim.api.nvim_buf_set_mark(0, '<', start_line, start_col, {})

    -- set the ">" mark to the end of the selection
    vim.api.nvim_buf_set_mark(0, '>', finish_line, finish_col, {})

    -- use `gv` to reselect the last visual selection
    vim.api.nvim_feedkeys('gv', 'n', true)

    -- if the selection is reversed, move the cursor to the start of the selection
    if reversed then
      vim.api.nvim_feedkeys('o', 'n', true)
    end
  end)
end

M.replace_visual_selection = function(str)
  local selection = M.get_visual_selection()
  if selection == nil or vim.tbl_isempty(selection) then
    return
  end
  local replacement = vim
    .iter(type(str) == 'table' and str or { str })
    :map(function(line)
      return vim.split(line, '\n')
    end)
    :flatten()
    :totable()
  if selection.mode == 'V' then
    vim.api.nvim_buf_set_lines( --
      0,
      selection.start.line - 1,
      selection.finish.line,
      false,
      replacement
    )
    M.set_visual_selection {
      mode = selection.mode,
      start = { line = selection.start.line, col = 1 },
      finish = { line = selection.start.line + #replacement - 1, col = #replacement[#replacement] },
      reversed = selection.reversed,
    }
  else
    vim.api.nvim_buf_set_text(
      0,
      selection.start.line - 1,
      selection.start.col - 1,
      selection.finish.line - 1,
      selection.finish.col,
      replacement
    )
    M.set_visual_selection {
      mode = selection.mode,
      start = { line = selection.start.line, col = selection.start.col },
      finish = { line = selection.start.line, col = selection.start.col + #replacement[#replacement] - 1 },
      reversed = selection.reversed,
    }
  end
end

M.transform_visual_selection = function(cmd, preFn, postFn)
  -- Get visual selection, transform it, and replace it
  -- return
  local selection = M.get_visual_selection()
  if selection == nil or vim.tbl_isempty(selection) then
    return
  end
  local final_output = require('user.fn').transform_string {
    str = table.concat(selection.lines, '\n'),
    cmd = cmd,
    preFn = preFn,
    postFn = postFn,
    meta = { selection = selection },
  }
  M.replace_visual_selection(final_output)
end

return M
