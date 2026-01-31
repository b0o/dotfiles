--- Render functions for cheatsheet components

local M = {}

M.CODE_DESC_GAP = 2 -- spaces between code and description
M.COLUMN_GAP = 3 -- spaces between columns

--- Calculate visible width of a cell's code part
---@param c table cell component
---@return number
function M.cell_code_width(c)
  if c.codes then
    local len = 0
    for i, code in ipairs(c.codes) do
      len = len + #code
      if i < #c.codes then
        len = len + #c.join
      end
    end
    return len
  end
  return #(c.code or '')
end

--- Render a cell's code part with backticks
---@param c table cell component
---@return string
function M.cell_render_code(c)
  if c.codes then
    local parts = {}
    for _, code in ipairs(c.codes) do
      table.insert(parts, '`' .. code .. '`')
    end
    return table.concat(parts, c.join)
  end
  local code = c.code or ''
  if c.join and code:find(c.join, 1, true) then
    local parts = vim.split(code, c.join, { plain = true })
    local rendered = {}
    for _, p in ipairs(parts) do
      table.insert(rendered, '`' .. p .. '`')
    end
    return table.concat(rendered, c.join)
  end
  return '`' .. code .. '`'
end

--- Calculate max column widths for a section
---@param sect table section component
---@return table max_code, table max_desc
function M.section_calc_widths(sect)
  local max_code, max_desc = {}, {}
  for _, r in ipairs(sect.rows) do
    local cells = r.cells or { r }
    for i, c in ipairs(cells) do
      if c._type == 'cell' then
        max_code[i] = math.max(max_code[i] or 0, M.cell_code_width(c))
        max_desc[i] = math.max(max_desc[i] or 0, #(c.desc or ''))
      end
    end
  end
  return max_code, max_desc
end

--- Render a section to lines
---@param sect table section component
---@param base_line number starting line number for tracking code positions
---@return string[] lines, number max_width, table code_spans
function M.section_render(sect, base_line)
  local max_code, max_desc = M.section_calc_widths(sect)
  local lines = {}
  local code_spans = {} -- { line, col_start, col_end, col_index }
  local max_width = 0

  for row_idx, r in ipairs(sect.rows) do
    local cells = r.cells or { r }
    local parts = {}
    local visible_len = 0
    local byte_pos = 0 -- track byte position in line

    for i, c in ipairs(cells) do
      if c._type == 'cell' then
        local code_str = M.cell_render_code(c)
        local code_vis = M.cell_code_width(c)
        local desc = c.desc or ''
        local indent = c.indent or 0
        local is_last = (i == #cells)

        local code_pad = (max_code[i] or 0) - code_vis
        local desc_pad = is_last and 0 or ((max_desc[i] or 0) - #desc)

        -- Track code span position (byte positions for extmarks)
        local code_start = byte_pos + indent
        local code_end = code_start + #code_str
        table.insert(code_spans, {
          line = base_line + row_idx - 1,
          col_start = code_start,
          col_end = code_end,
          col_index = i, -- which column (for color variation)
        })

        local part = string.rep(' ', indent)
          .. code_str
          .. string.rep(' ', code_pad + M.CODE_DESC_GAP)
          .. desc
          .. string.rep(' ', desc_pad + (is_last and 0 or M.COLUMN_GAP))

        table.insert(parts, part)
        byte_pos = byte_pos + #part
        visible_len = visible_len + indent + code_vis + code_pad + M.CODE_DESC_GAP + #desc + desc_pad
        if not is_last then
          visible_len = visible_len + M.COLUMN_GAP
        end
      elseif type(c) == 'string' then
        table.insert(parts, c)
        byte_pos = byte_pos + #c
        visible_len = visible_len + #c
      end
    end

    table.insert(lines, table.concat(parts))
    max_width = math.max(max_width, visible_len)
  end

  return lines, max_width, code_spans
end

--- Render a text component
---@param comp table text component
---@return string[], number
function M.text_render(comp)
  return { comp.text }, #comp.text
end

--- Render a header component
---@param comp table header component
---@return string[], number
function M.header_render(comp)
  return { '**' .. comp.text .. '**' }, #comp.text
end

return M
