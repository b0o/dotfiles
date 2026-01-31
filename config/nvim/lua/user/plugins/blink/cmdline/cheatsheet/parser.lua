--- Cmdline context parser for substitute/global commands

local M = {}

--- Parse cmdline to determine command type and cursor context
---@param cmdline string
---@param pos number cursor position (1-indexed)
---@return string|nil context: 'search', 'replace', 'flags', 'global', 'global_cmd', or nil
function M.parse(cmdline, pos)
  -- Match substitute command: [range]s[ubstitute]/pattern/replacement/[flags]
  local sub_match = cmdline:match "^[%%'<,>%.%$%d]*s[ubstitute]*/"
  if sub_match then
    local delim_start = #sub_match
    local delim = cmdline:sub(delim_start, delim_start)

    -- Find delimiter positions (accounting for escapes)
    local delim_positions = { delim_start }
    local i = delim_start + 1
    local escaped = false
    while i <= #cmdline do
      local c = cmdline:sub(i, i)
      if escaped then
        escaped = false
      elseif c == '\\' then
        escaped = true
      elseif c == delim then
        table.insert(delim_positions, i)
      end
      i = i + 1
    end

    -- Determine section based on cursor position
    if pos <= delim_positions[1] then
      return nil -- Before the first delimiter
    elseif #delim_positions >= 3 and pos > delim_positions[3] then
      return 'flags'
    elseif #delim_positions >= 2 and pos > delim_positions[2] then
      return 'replace'
    elseif pos > delim_positions[1] then
      return 'search'
    end
    return nil
  end

  -- Match global command: [range]g[lobal][!]/pattern/[cmd] or :v/pattern/[cmd]
  local g_match = cmdline:match "^[%%'<,>%.%$%d]*g[lobal]?!?/" or cmdline:match "^[%%'<,>%.%$%d]*v/"
  if g_match then
    local delim_start = #g_match
    local delim = cmdline:sub(delim_start, delim_start)

    -- Find second delimiter
    local second_delim = nil
    local i = delim_start + 1
    local escaped = false
    while i <= #cmdline do
      local c = cmdline:sub(i, i)
      if escaped then
        escaped = false
      elseif c == '\\' then
        escaped = true
      elseif c == delim then
        second_delim = i
        break
      end
      i = i + 1
    end

    if pos <= delim_start then
      return nil
    elseif second_delim and pos > second_delim then
      return 'global_cmd'
    else
      return 'global'
    end
  end

  return nil
end

return M
