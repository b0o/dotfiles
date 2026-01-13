---@class user.util.fyler.search.Opts
---@field max_depth number

---@class (partial) user.util.fyler.search.SetupOpts: user.util.fyler.search.Opts

local M = {
  ---@type user.util.fyler.search.Opts
  opts = {
    max_depth = 5,
  },
}

-- Search state for n/N support
local search_state = {
  pattern = nil, ---@type string|nil
  reverse = false, ---@type boolean
  parent_path = nil, ---@type string|nil
}

local function reset_search_state(pattern, reverse, parent_path)
  search_state.pattern = pattern
  search_state.reverse = reverse
  search_state.parent_path = parent_path
end

--- Sort entries the same way fyler does: directories first, then alphabetically
---@param entries table List of fs entries
---@return table Sorted entries
local function sort_entries(entries)
  table.sort(entries, function(x, y)
    local x_is_dir = x.type == 'directory'
    local y_is_dir = y.type == 'directory'
    if x_is_dir and not y_is_dir then
      return true
    elseif not x_is_dir and y_is_dir then
      return false
    else
      local function pad_numbers(str)
        return str:gsub('%d+', function(n) return string.format('%010d', n) end)
      end
      return pad_numbers(x.name) < pad_numbers(y.name)
    end
  end)
  return entries
end

--- Reorder entries to start from cursor_name, wrapping around
--- Mental model: cursor is *between* entries, like [aaa, <cursor>, bbb, ccc]
--- Forward: bbb, ccc, aaa (down from cursor, wrap)
--- Reverse: aaa, ccc, bbb (up from cursor, wrap)
---@param entries table List of fs entries
---@param cursor_name string|nil Name of cursor item
---@param reverse boolean|nil Whether to reverse order (for ? search)
---@return table Reordered entries
local function order_from_cursor(entries, cursor_name, reverse)
  if not cursor_name then
    if reverse then
      local result = {}
      for i = #entries, 1, -1 do
        table.insert(result, entries[i])
      end
      return result
    end
    return entries
  end

  local cursor_idx = 1
  for i, entry in ipairs(entries) do
    if entry.name == cursor_name then
      cursor_idx = i
      break
    end
  end

  local result = {}
  if reverse then
    -- Reverse: before cursor going up, wrap to end going up, cursor last
    for i = cursor_idx - 1, 1, -1 do
      table.insert(result, entries[i])
    end
    for i = #entries, cursor_idx + 1, -1 do
      table.insert(result, entries[i])
    end
    table.insert(result, entries[cursor_idx])
  else
    -- Forward: cursor first, then forwards, wrap to start
    for i = cursor_idx, #entries do
      table.insert(result, entries[i])
    end
    for i = 1, cursor_idx - 1 do
      table.insert(result, entries[i])
    end
  end
  return result
end

--- BFS search with cursor-aware ordering
--- Only searches HIDDEN paths (not currently visible in the tree)
---@param pattern string Vim regex pattern
---@param parent_path string Parent directory to start from
---@param cursor_name string|nil Name of item at cursor (for ordering)
---@param reverse boolean|nil Whether to search in reverse order
---@param visible_paths table<string, boolean>|nil Set of paths visible in tree (to skip)
---@param callback fun(matched_path: string|nil)
local function bfs_search_hidden(pattern, parent_path, cursor_name, reverse, visible_paths, callback)
  local fs = require 'fyler.lib.fs'
  local regex = vim.regex(pattern)
  visible_paths = visible_paths or {}

  fs.ls(parent_path, function(err, entries)
    if err or not entries then
      return callback(nil)
    end

    vim.schedule(function()
      -- Sort entries to match fyler's display order, then reorder from cursor
      entries = sort_entries(entries)
      entries = order_from_cursor(entries, cursor_name, reverse)

      -- First pass: check immediate children (only non-visible)
      for _, entry in ipairs(entries) do
        if regex:match_str(entry.name) and not visible_paths[entry.path] then
          return callback(entry.path)
        end
      end

      -- Second pass: BFS into subdirectories
      local queue = {}
      for _, entry in ipairs(entries) do
        if entry.type == 'directory' then
          table.insert(queue, { path = entry.path, depth = 1 })
        end
      end

      local head = 1

      local function process_next()
        if head > #queue then
          return callback(nil)
        end

        local current = queue[head]
        head = head + 1

        fs.ls(current.path, function(ls_err, children)
          if ls_err or not children then
            return vim.schedule(process_next)
          end

          vim.schedule(function()
            -- Sort children to match fyler's display order
            children = sort_entries(children)
            children = order_from_cursor(children, nil, reverse)

            for _, child in ipairs(children) do
              if regex:match_str(child.name) and not visible_paths[child.path] then
                return callback(child.path)
              end
            end

            if current.depth < M.opts.max_depth then
              for _, child in ipairs(children) do
                if child.type == 'directory' then
                  table.insert(queue, { path = child.path, depth = current.depth + 1 })
                end
              end
            end

            process_next()
          end)
        end)
      end

      process_next()
    end)
  end)
end

--- Collect all visible paths from the tree
---@param node table Tree node from files:totable()
---@param paths table<string, boolean> Accumulator
local function collect_visible_paths(node, paths)
  paths[node.path] = true
  if node.open and node.children then
    for _, child in ipairs(node.children) do
      collect_visible_paths(child, paths)
    end
  end
end

--- Navigate to match and expand the tree path
---@param finder table Fyler finder instance
---@param path string Path to navigate to
local function navigate_to_match(finder, path)
  finder.files:navigate(path, function(err, ref_id)
    if err or not ref_id then
      return
    end
    vim.schedule(function()
      finder:dispatch_refresh {
        force_update = true,
        onrender = function()
          vim.api.nvim_win_call(finder.win.winid, function() vim.fn.search(string.format('/%05d ', ref_id)) end)
        end,
      }
    end)
  end)
end

--- Compare two paths to determine which comes first in tree order from cursor
--- Returns true if path_a comes before path_b in the search direction
---@param path_a string
---@param path_b string
---@param cursor_path string
---@param parent_path string
---@param reverse? boolean
---@return boolean
local function path_comes_before(path_a, path_b, cursor_path, parent_path, reverse)
  -- Get the relative paths within parent_path
  local function get_sort_key(path)
    if not vim.startswith(path, parent_path) then
      return path
    end
    local rel = path:sub(#parent_path + 2) -- +2 for the trailing /
    -- Pad numbers for natural sort
    return rel:gsub('%d+', function(n) return string.format('%010d', n) end)
  end

  local key_a = get_sort_key(path_a)
  local key_b = get_sort_key(path_b)
  local key_cursor = get_sort_key(cursor_path)

  -- Determine if each path is "after" cursor in forward direction
  local a_after_cursor = key_a > key_cursor
  local b_after_cursor = key_b > key_cursor

  if reverse then
    -- Reverse: prefer paths before cursor, then wrap to after
    if a_after_cursor ~= b_after_cursor then
      return not a_after_cursor -- path before cursor comes first
    end
    return key_a > key_b -- later paths come first in reverse
  else
    -- Forward: prefer paths after cursor, then wrap to before
    if a_after_cursor ~= b_after_cursor then
      return a_after_cursor -- path after cursor comes first
    end
    return key_a < key_b -- earlier paths come first in forward
  end
end

--- Main search handler
---@param search_pattern string The search pattern from cmdline
---@param finder table Fyler finder instance
---@param cursor_before number[] Cursor position before search
---@param reverse boolean|nil Whether this is a reverse search (?)
local function on_search_submit(search_pattern, finder, cursor_before, reverse)
  if not search_pattern or search_pattern == '' then
    return
  end

  -- Ensure window is still valid
  if not finder.win or not vim.api.nvim_win_is_valid(finder.win.winid) then
    return
  end

  -- Get cursor context (before vim's native search may have moved it)
  -- We need to restore cursor first to get the original context
  local cursor_after_native = vim.api.nvim_win_get_cursor(finder.win.winid)
  vim.api.nvim_win_set_cursor(finder.win.winid, cursor_before)

  local cursor_entry = finder:cursor_node_entry()
  local cursor_path = cursor_entry and cursor_entry.path
  local parent_path = cursor_path and vim.fn.fnamemodify(cursor_path, ':h') or finder.files.root_path
  local cursor_name = cursor_path and vim.fn.fnamemodify(cursor_path, ':t')

  -- Reset search state for new search
  reset_search_state(search_pattern, reverse, parent_path)

  -- Get visible paths to skip
  local visible_paths = {}
  collect_visible_paths(finder.files:totable(), visible_paths)

  -- Find next hidden match via BFS
  bfs_search_hidden(search_pattern, parent_path, cursor_name, reverse, visible_paths, function(hidden_match)
    -- Check if native search found a visible match
    local vim_moved = cursor_after_native[1] ~= cursor_before[1]

    local visible_match = nil
    if vim_moved then
      -- Restore cursor to where native search left it to get that entry
      vim.api.nvim_win_set_cursor(finder.win.winid, cursor_after_native)
      local new_entry = finder:cursor_node_entry()
      visible_match = new_entry and new_entry.path
    end

    -- Decide which match to use
    if hidden_match and visible_match then
      -- Both found - pick whichever comes first
      if path_comes_before(hidden_match, visible_match, cursor_path, parent_path, reverse) then
        -- Hidden match is closer - navigate to it
        vim.api.nvim_win_set_cursor(finder.win.winid, cursor_before)
        navigate_to_match(finder, hidden_match)
      end
      -- else: visible match is closer, cursor already there
    elseif hidden_match then
      -- Only hidden match - navigate to it
      vim.api.nvim_win_set_cursor(finder.win.winid, cursor_before)
      navigate_to_match(finder, hidden_match)
    elseif not visible_match then
      -- No match at all
      vim.api.nvim_win_set_cursor(finder.win.winid, cursor_before)
      vim.notify('Pattern not found: ' .. search_pattern, vim.log.levels.WARN)
    end
    -- else: only visible match, cursor already there from native search
  end)
end

--- Handle n/N to find next/previous match
---@param finder table Fyler finder instance
---@param reverse_direction boolean Whether to reverse the original search direction
local function search(finder, reverse_direction)
  if not search_state.pattern or not search_state.parent_path then
    return
  end

  -- Ensure window is still valid
  if not finder.win or not vim.api.nvim_win_is_valid(finder.win.winid) then
    return
  end

  -- Get current cursor context
  local cursor_entry = finder:cursor_node_entry()
  local cursor_path = cursor_entry and cursor_entry.path
  local cursor_name = cursor_path and vim.fn.fnamemodify(cursor_path, ':t')

  -- Determine effective direction: N reverses the original direction
  local reverse = search_state.reverse
  if reverse_direction then
    reverse = not reverse
  end

  -- Get visible paths
  local visible_paths = {}
  collect_visible_paths(finder.files:totable(), visible_paths)

  -- Find next hidden match
  bfs_search_hidden(
    search_state.pattern,
    search_state.parent_path,
    cursor_name,
    reverse,
    visible_paths,
    function(hidden_match)
      -- Try native n/N to find visible match
      local cursor_before = vim.api.nvim_win_get_cursor(finder.win.winid)
      local ok = pcall(function() vim.cmd(reverse_direction and 'normal! N' or 'normal! n') end)
      local cursor_after = vim.api.nvim_win_get_cursor(finder.win.winid)
      local vim_moved = ok and cursor_after[1] ~= cursor_before[1]

      local visible_match = nil
      if vim_moved then
        local new_entry = finder:cursor_node_entry()
        visible_match = new_entry and new_entry.path
      end

      -- Decide which match to use
      if hidden_match and visible_match then
        -- Both found - pick whichever comes first
        if path_comes_before(hidden_match, visible_match, cursor_path, search_state.parent_path, reverse) then
          -- Hidden match is closer - move cursor back and navigate to hidden
          vim.api.nvim_win_set_cursor(finder.win.winid, cursor_before)
          navigate_to_match(finder, hidden_match)
        end
      -- else: visible match is closer, cursor already there
      elseif hidden_match then
        -- Only hidden match - navigate to it
        navigate_to_match(finder, hidden_match)
      elseif not visible_match then
        -- No match at all
        vim.notify('Pattern not found: ' .. search_state.pattern, vim.log.levels.WARN)
      end
      -- else: only visible match, cursor already there from native n/N
    end
  )
end

--- Set up BFS search for fyler buffers
---@param opts? user.util.fyler.search.SetupOpts
function M.setup(opts)
  M.opts = vim.tbl_deep_extend('force', M.opts, opts or {})

  -- Autocommand to hook into search
  vim.api.nvim_create_autocmd('CmdlineEnter', {
    pattern = { '/', '?' },
    callback = function(event_enter)
      if event_enter.file ~= '/' and event_enter.file ~= '?' then
        return
      end
      local buf = vim.api.nvim_get_current_buf()
      if vim.bo[buf].filetype ~= 'fyler' then
        return
      end

      local finder_mod = require 'fyler.views.finder'
      local finder = finder_mod.instance()
      if not finder or not finder.win or not finder.win.winid then
        return
      end

      local cursor_before = vim.api.nvim_win_get_cursor(finder.win.winid)
      local is_reverse = vim.fn.getcmdtype() == '?'

      local group = vim.api.nvim_create_augroup('FylerSearchLeave', { clear = true })
      vim.api.nvim_create_autocmd('CmdlineLeave', {
        group = group,
        pattern = { '/', '?' },
        once = true,
        callback = function(event_leave)
          if vim.v.event.abort or not (event_leave.file == '/' or event_leave.file == '?') then
            return
          end

          local cmdline = vim.fn.getcmdline()
          vim.schedule(function() on_search_submit(cmdline, finder, cursor_before, is_reverse) end)
        end,
      })
    end,
  })

  require('user.util.map').ft('fyler', function(bufmap)
    ---@param reverse_direction boolean
    local function search_finder(reverse_direction)
      return function()
        local finder = require('fyler.views.finder').instance()
        if finder then
          search(finder, reverse_direction)
        end
      end
    end
    bufmap('n', 'n', search_finder(false), 'Fyler: Next search match')
    bufmap('n', 'N', search_finder(true), 'Fyler: Previous search match')
  end)
end

return M
