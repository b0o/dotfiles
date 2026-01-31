--- Component constructors and cheatsheet builder

local render = require 'user.plugins.blink.cmdline.cheatsheet.render'

local M = {}

-------------------------------------------------------------------------------
-- Component Constructors
-------------------------------------------------------------------------------

--- Create a horizontal rule component
function M.hr()
  return { _type = 'hr' }
end

--- Create a bold header component
---@param text string
function M.header(text)
  return { _type = 'header', text = text }
end

--- Create a plain text component
---@param text string
function M.text(text)
  return { _type = 'text', text = text }
end

--- Create a code+description cell
---@param code string the code to display
---@param desc string the description
---@param opts? { join?: string, indent?: number } options for split-join or indentation
function M.cell(code, desc, opts)
  opts = opts or {}
  return {
    _type = 'cell',
    code = code,
    desc = desc,
    join = opts.join,
    indent = opts.indent or 0,
  }
end

--- Create a cell with multiple codes joined by a separator
---@param code_list string[] array of codes
---@param joiner string separator between codes (e.g., " or ")
---@param desc string the description
function M.codes(code_list, joiner, desc)
  return {
    _type = 'cell',
    codes = code_list,
    join = joiner,
    desc = desc,
    indent = 0,
  }
end

--- Create a row of cells
---@param ... table cells
function M.row(...)
  return { _type = 'row', cells = { ... } }
end

--- Create a section (group of rows that share column alignment)
---@param rows table[] array of row components
function M.section(rows)
  return { _type = 'section', rows = rows }
end

-------------------------------------------------------------------------------
-- Cheatsheet Builder
-------------------------------------------------------------------------------

--- Build a cheatsheet from title and components
---@param title string
---@param components table[]
---@return table { content: string, width: number, height: number, hr_lines: table, code_spans: table }
function M.cheatsheet(title, components)
  local rendered = {}
  local max_width = #title
  local current_line = 1 -- start after title (line 0)

  -- First pass: render all components and calculate max width
  for _, comp in ipairs(components) do
    if comp._type == 'hr' then
      table.insert(rendered, { _type = 'hr' })
      current_line = current_line + 1
    elseif comp._type == 'header' then
      local lines, width = render.header_render(comp)
      table.insert(rendered, { _type = 'lines', lines = lines })
      max_width = math.max(max_width, width)
      current_line = current_line + #lines
    elseif comp._type == 'text' then
      local lines, width = render.text_render(comp)
      table.insert(rendered, { _type = 'lines', lines = lines })
      max_width = math.max(max_width, width)
      current_line = current_line + #lines
    elseif comp._type == 'section' then
      local lines, width, code_spans = render.section_render(comp, current_line)
      table.insert(rendered, { _type = 'lines', lines = lines, code_spans = code_spans })
      max_width = math.max(max_width, width)
      current_line = current_line + #lines
    end
  end

  -- Second pass: build output with calculated HR width
  local output = { '**' .. title .. '**' }
  local hr_str = string.rep('─', max_width)
  local hr_lines = {} -- track which lines are HRs for highlighting
  local all_code_spans = {} -- collect all code spans

  for _, r in ipairs(rendered) do
    if r._type == 'hr' then
      table.insert(hr_lines, #output) -- 0-indexed line number
      table.insert(output, hr_str)
    elseif r._type == 'lines' then
      vim.list_extend(output, r.lines)
      if r.code_spans then
        vim.list_extend(all_code_spans, r.code_spans)
      end
    end
  end

  return {
    content = table.concat(output, '\n'),
    width = max_width,
    height = #output,
    hr_lines = hr_lines,
    code_spans = all_code_spans,
  }
end

return M
