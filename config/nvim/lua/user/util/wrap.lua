local M = {}

local emmet_wrap = function(abbreviation)
  local bufnr = vim.api.nvim_get_current_buf()
  local emmet = vim.lsp.get_clients({
    bufnr = bufnr,
    name = 'emmet_language_server',
  })[1]
  if not emmet then
    return
  end
  local response = emmet:request_sync('emmet/expandAbbreviation', {
    abbreviation = abbreviation,
    language = vim.bo.filetype,
    options = {
      text = '${WRAP_TEXT}',
    },
  }, 1000, bufnr)
  if not response or not response.result then
    return
  end
  local split = vim.split(response.result, '${WRAP_TEXT}')
  if split[1] and split[2] then
    return split[1], split[2]
  end
end

-- Selection Wrapping
-- TODO: Support function calls, e.g. "foo(" -> ")"
--
---@param lhs_in string
local function get_wrap_seq(lhs_in)
  local pairings = {
    ['('] = ')',
    ['{'] = '}',
    ['['] = ']',
    ['<'] = '>',
    ['"'] = '"',
    ["'"] = "'",
    ['`'] = '`',
    ['|'] = '|',
    ['/'] = '/',
    ['_'] = '_',
    [' '] = ' ',
    ['*'] = '*',
  }
  local first = lhs_in:sub(1, 1)
  if first == '>' or not pairings[first] then
    local lhs, rhs = emmet_wrap(first == '>' and lhs_in:sub(2) or lhs_in)
    if lhs and rhs then
      return lhs, rhs
    end
  end
  local lhs = ''
  local rhs = ''
  local valid = true
  local i = 1
  while i <= #lhs_in do
    local tag, tag_name = lhs_in:sub(i):match '^(<([^/> ]*)[^>]*>)'
    if tag then
      lhs = lhs .. tag
      rhs = '</' .. tag_name .. '>' .. rhs
      i = i + #tag
    else
      local c = lhs_in:sub(i, i)
      if not pairings[c] then
        valid = false
        break
      end
      lhs = lhs .. c
      rhs = pairings[c] .. rhs
    end
    i = i + 1
  end
  if valid then
    return lhs, rhs
  end
  return lhs_in, lhs_in
end

---@param params? { lhs?: string, rhs?: string }
---@return { lhs: string, rhs: string }|nil
M.wrap_visual_selection = function(params)
  params = params or {}
  local lhs = params.lhs or vim.fn.input { prompt = 'LHS: ', cancelreturn = -1 }
  if lhs == -1 then
    return
  end
  local rhs
  if params.rhs then
    rhs = params.rhs
  else
    lhs, rhs = get_wrap_seq(lhs)
    rhs = vim.fn.input { prompt = 'RHS: ', default = rhs, cancelreturn = -1 }
  end
  if rhs == -1 then
    return
  end
  require('user.util.visual').transform_visual_selection(function(text, meta)
    local mode = meta.selection.mode

    if mode == '' or mode == '<CTRL-V>' then
      -- TODO: implement block-wise
      return text
    end

    if mode == 'v' then
      return lhs .. text .. rhs
    end

    if mode == 'V' then
      local indent = require('user.fn').get_indent_info()
      local lines = vim.split(text, '\n')
      local current_indent = ''
      if #lines > 0 then
        current_indent = lines[1]:match('^' .. indent.char .. '*')
      end
      local new_lines = {}
      table.insert(new_lines, current_indent .. lhs)
      for _, line in ipairs(lines) do
        table.insert(new_lines, indent.char:rep(indent.size) .. line)
      end
      table.insert(new_lines, current_indent .. rhs)
      return new_lines
    end
  end)
  return {
    lhs = lhs,
    rhs = rhs,
  }
end

return M
