---- user.fn: General utility functions
local apiutil = require 'user.util.api'

local M = {}

-- print + vim.inspect
M.inspect = function(...)
  for _, v in ipairs { ... } do
    print(vim.inspect(v, { depth = math.huge }))
  end
end

-- Make inspect global for convenience
_G.inspect = M.inspect

-- Execute the visual selection or cursor line as a sequence of lua expressions
M.luarun = function(file)
  local mode_info = vim.api.nvim_get_mode()
  if mode_info.blocking then
    return
  end
  local mode = mode_info.mode

  local text
  if file then
    text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  else
    if mode == 'n' then
      text = vim.api.nvim_get_current_line()
    elseif mode == 'v' or mode == 'V' or mode == 'CTRL-V' or mode == '\22' then
      local selection = require('user.util.visual').get_visual_selection_list(mode)
      if selection ~= nil then
        text = table.concat(selection, '\n')
      end
    else
      return
    end
  end

  local loadok, expr = pcall(loadstring, 'return ' .. text)
  if loadok and expr then
    local msg = 'luarun (expr)'
    local evalok, eval_result = pcall(expr)
    if not evalok then
      error(msg .. ' (failed): ' .. eval_result)
    end
    print(msg .. ': ' .. text)
    print(vim.inspect(eval_result))
    return
  end

  local lines = vim.split(text, '\n')
  lines[#lines] = 'return ' .. lines[#lines]

  local blockexpr
  loadok, blockexpr = pcall(loadstring, table.concat(lines, '\n'))
  if loadok and blockexpr then
    local msg = 'luarun (block-expr)'
    local evalok, blockexpr_result = pcall(blockexpr)
    if not evalok then
      error(msg .. ' (failed): ' .. blockexpr_result)
    end
    print(msg .. ': ' .. text)
    print(vim.inspect(blockexpr_result))
    return
  end

  local block, errmsg
  loadok, block, errmsg = pcall(loadstring, text)
  if not loadok or block == nil then
    error(errmsg or 'luarun: failed to load block')
  end

  local msg = 'luarun (block)'
  local blockok, block_result = pcall(block)
  if not blockok then
    error(msg .. ' failed: ' .. block_result)
  end

  print(msg .. ': ' .. text)
  print(vim.inspect(block_result))
end

-- Gets all of the Lua runtime paths
M.get_runtime_path = function()
  local runtime_path = vim.split(package.path, ';')
  table.insert(runtime_path, 'lua/?.lua')
  table.insert(runtime_path, 'lua/?/init.lua')
  return runtime_path
end

M.tbl_reduce = function(tbl, fn, acc)
  for k, v in pairs(tbl) do
    acc = fn(acc, v, k)
  end
  return acc
end

-- Like vim.tbl_keys, but also includes all list-like elements
M.tbl_listkeys = function(tbl)
  return M.tbl_reduce(tbl, function(acc, v, k)
    if type(k) == 'number' then
      table.insert(acc, v)
    else
      table.insert(acc, k)
    end
    return acc
  end, {})
end

-- Like vim.tbl_values, but also includes all list-like elements
M.tbl_listvalues = function(tbl)
  return M.tbl_reduce(tbl, function(acc, v)
    table.insert(acc, v)
    return acc
  end, {})
end

-- Like vim.tbl_map, but fn is called with (k, v) pairs and returns (k, v) pairs
M.tbl_map_entries = function(fn, tbl)
  local res = {}
  for k, v in pairs(tbl) do
    local nk, nv = fn(k, v)
    res[nk] = nv
  end
  return res
end

-- Open one or more man pages
-- Accepts a string representing how to open the man pages, one of:
--   - ''        - current window
--   - 'split'   - new horizontal split
--   - 'vsplit'  - new vertical split
--   - 'tab'     - new tab
-- Varargs should be strings of the format
--   <manpage>
-- or
--   <section> <manpage>
M.man = function(dest, ...)
  if dest == 'tab' then
    dest = 'tabnew'
  end
  if dest ~= '' then
    dest = dest .. ' | '
  end
  for _, page in ipairs { ... } do
    if vim.regex('^\\d\\+p\\? \\w\\+$'):match_str(page) ~= nil then
      local s = vim.split(page, ' ')
      page = ('%s(%s)'):format(s[2], s[1])
    end
    local prefix = dest
    if vim.fn.bufname(0) == '' and vim.fn.line '$' == 1 and vim.fn.getline(1) == '' then
      prefix = ''
    end
    vim.cmd(prefix .. 'file ' .. page)
    require('man').read_page(page)
  end
end

M.close_float_wins = function(opts)
  opts = opts or {}
  local fts = opts.fts or {}
  local exclude = opts.exclude or {}
  local noft = opts.noft == nil and true or opts.noft
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local ok, config, bufnr
    ok, config = pcall(vim.api.nvim_win_get_config, win)
    if ok then
      ok, bufnr = pcall(vim.api.nvim_win_get_buf, win)
      if ok and config.relative ~= '' then
        local ft = vim.bo[bufnr].filetype
        if (ft == '' and noft) or (vim.tbl_contains(fts, ft) and not vim.tbl_contains(exclude, ft)) then
          -- for some reason, vim.api.nvim_win_close() causes issues with some plugins, but win_execute('close') works fine
          vim.fn.win_execute(win, 'close')
        end
      end
    end
  end
end

-- Jump to prev/next buffer in jumplist
M.jumplist_jump_buf = function(dir)
  local jumplist, jumppos = unpack(vim.fn.getjumplist())
  local initial = dir > 0 and (jumppos + 1) or jumppos
  initial = math.max(1, math.min(initial, #jumplist))
  local bufnr = vim.api.nvim_get_current_buf()
  local target = { bufnr = bufnr }
  local i = initial
  -- search for the first jumplist entry that is not the current buffer
  while i > 0 and i <= #jumplist do
    local j = jumplist[i]
    if j.bufnr ~= target.bufnr then
      target = j
      break
    end
    i = i + dir
  end
  if target.bufnr == bufnr then
    return
  end
  local dist = i - initial
  if jumppos == #jumplist then
    dist = dist - 1
  end
  local keys = vim.api.nvim_replace_termcodes(('%d<C-%s>')
    :format(math.abs(dist), dir > 0 and 'i' or 'o'), true, false, true)
  vim.api.nvim_feedkeys(keys, 'n', false)
end

-- Replace occurrences of ${k} with v in tmpl for each { k = v } in data
M.template = function(tmpl, data)
  local fn = function(_data)
    local res = tmpl
    for k, v in pairs(_data) do
      res = res:gsub('${' .. k .. '}', v)
    end
    return res
  end
  if data then
    return fn(data)
  end
  return fn
end

M.tmpl_cmd = function(...) return vim.cmd(M.template(...)) end

M.tmpl_hi = function(tmpl, colors)
  colors = colors or require 'user.colors'
  return M.tmpl_cmd(tmpl, colors)
end

---- memoization

-- memotable gets an index from target and caches the result, returning the
-- cached version on future lookups.
--
-- Setting an index on memotable passes the value through to target and
-- updates the cache.
--
-- This only makes sense for targets who themselves have metatables that do
-- work on __index; if target is a plain table, this is unnecessary overhead.
M.memotable = function(target)
  return setmetatable({}, {
    __index = function(self, k)
      local v = target[k]
      rawset(self, k, v)
      return v
    end,
    __newindex = function(self, k, v)
      rawset(self, k, v)
      target[k] = v
    end,
  })
end

-- returns true if val is a function or callable table
M.is_callable = function(val)
  local t = type(val)
  if t == 'function' then
    return true
  end
  if t == 'table' then
    local mt = getmetatable(val)
    return mt and M.is_callable(mt.__call)
  end
  return false
end

---@param ft string|string[]
---@param if_match fun()
---@param if_not_match? fun()
M.if_filetype = function(ft, if_match, if_not_match)
  local fts = type(ft) == 'table' and ft or { ft }
  return function()
    if vim.tbl_contains(fts, vim.bo.filetype) then
      if_match()
    else
      if if_not_match and M.is_callable(if_not_match) then
        if_not_match()
      end
    end
  end
end

M.get_latest_messages = function(count)
  local messages = vim.fn.execute 'messages'
  local lines = vim.split(messages, '\n')
  lines = vim.tbl_filter(function(line) return line ~= '' end, lines)
  count = count and tonumber(count) or nil
  count = (count ~= nil and count >= 0) and count - 1 or #lines
  return table.concat(vim.list_slice(lines, #lines - count), '\n')
end

M.yank_messages = function(register, count)
  register = (register and register ~= '') and register or '+'
  vim.fn.setreg(register, M.get_latest_messages(count), 'l')
end

M.get_path_separator = function()
  if vim.fn.exists '+shellslash' == 1 and vim.o.shellslash then
    return [[\]]
  end
  return '/'
end

M.resolve_bufnr = apiutil.resolve_bufnr
M.resolve_winnr = apiutil.resolve_winnr

M.get_wins_of_type = function(wintype)
  return vim.tbl_filter(function(winid) return vim.fn.win_gettype(winid) == wintype end, vim.api.nvim_list_wins())
end

M.is_normal_win = function(winid)
  if vim.fn.win_gettype(winid) ~= '' then
    return false
  end
  local bufid = vim.api.nvim_win_get_buf(winid)
  if vim.bo[bufid].buftype ~= '' then
    return false
  end
  if
      vim.tbl_contains({
        'NvimTree',
        'Trouble',
        'aerial',
      }, vim.bo[bufid].filetype)
  then
    return false
  end
  return true
end

M.tabpage_list_normal_wins = function(tabpage)
  local wins = vim.api.nvim_tabpage_list_wins(tabpage or 0)
  return vim.tbl_filter(M.is_normal_win, wins)
end

---- Magic file functions
-- Get a magic file path based on the current buffer path and new_name.
-- Behaves kinda like paths in tpope/vim-eunuch.
M.magic_file_path = function(winnr, new_name, add_ext)
  assert(new_name ~= '', 'magic_file_path: no name specified')
  winnr = M.resolve_winnr(winnr)
  if winnr == nil then
    return
  end
  add_ext = add_ext ~= nil and add_ext or false

  local bufnr = vim.api.nvim_win_get_buf(winnr)
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local file_name = vim.fn.fnamemodify(file_path, ':t')
  local path_is_absolute = new_name:match '^/'

  local dest_path
  if path_is_absolute then
    if vim.fn.isdirectory(new_name) then
      dest_path = new_name .. '/' .. file_name
    else
      dest_path = new_name
    end
  else
    local dest_dir
    if vim.bo[bufnr].buftype == '' then
      dest_dir = vim.fn.fnamemodify(file_path, ':p:h')
    else
      dest_dir = vim.fn.getcwd(winnr)
    end
    dest_path = dest_dir .. '/' .. new_name
  end

  if add_ext and vim.fn.fnamemodify(dest_path, ':e') == '' then
    local ext = vim.fn.fnamemodify(file_name, ':e')
    if ext ~= '' then
      dest_path = dest_path .. '.' .. ext
    end
  end

  return vim.fn.resolve(dest_path)
end

-- Create and edit a new file with a magic path
M.magic_newfile = function(winnr, new_name, force, edit_cmd, add_ext, lines)
  assert(new_name ~= '', 'saveas: no name specified')
  winnr = M.resolve_winnr(winnr)
  lines = lines or {}
  force = force ~= nil and force or false
  edit_cmd = edit_cmd or 'edit!'

  if add_ext and new_name:match '[.]$' then
    add_ext = false
    new_name = new_name:sub(1, #new_name - 1)
  end

  local dest_path = M.magic_file_path(winnr, new_name, add_ext)
  if dest_path == nil then
    return
  end

  assert(force or vim.fn.filereadable(dest_path) == 0, 'File exists: ' .. dest_path)
  local ok, msg = pcall(vim.fn.writefile, lines, dest_path, '')
  assert(ok == true, 'newfile: write failed: ' .. msg)

  vim.cmd(([[%s %s]]):format(edit_cmd, dest_path))
end

-- Saveas and edit a new file with a magic path
M.magic_saveas = function(winnr, new_name, force, edit_cmd, add_ext)
  winnr = M.resolve_winnr(winnr)
  if winnr == nil then
    return
  end
  local bufnr = vim.api.nvim_win_get_buf(winnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return M.magic_newfile(winnr, new_name, force, edit_cmd or 'edit!', add_ext, lines)
end

M.hex_to_rgb = function(hex)
  hex = hex:gsub('#', '')
  return {
    r = tonumber(hex:sub(1, 2), 16) / 255,
    g = tonumber(hex:sub(3, 4), 16) / 255,
    b = tonumber(hex:sub(5, 6), 16) / 255,
  }
end

M.relative_luminance = function(color)
  local r, g, b = color.r, color.g, color.b
  local function adjust(channel)
    if channel <= 0.03928 then
      return channel / 12.92
    else
      return ((channel + 0.055) / 1.055) ^ 2.4
    end
  end
  r, g, b = adjust(r), adjust(g), adjust(b)
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

M.contrast_color = function(bg_hex)
  local bg_color = M.hex_to_rgb(bg_hex)
  local bg_luminance = M.relative_luminance(bg_color)
  -- The W3C recommendation states that if the relative luminance
  -- is more than 0.179, the text should be black; otherwise, it should be white.
  if bg_luminance > 0.179 then
    return 'black'
  else
    return 'white'
  end
end

-- Function to transform string
-- preFn can return a second value, `ctx`, which will be passed to postFn as the second argument
-- M.transform_string = function(str, cmd, preFn, postFn, meta)
M.transform_string = function(opts)
  local str = opts.str
  local cmd = opts.cmd
  local preFn = opts.preFn
  local postFn = opts.postFn
  local meta = opts.meta

  ---@diagnostic disable-next-line: unused-vararg
  local function identityFn(x, ...) return x end
  -- If preFn or postFn are not provided, default to identityFn
  preFn = preFn or identityFn
  postFn = postFn or identityFn

  -- Transform the string
  local transformed, ctx = preFn(str, meta)

  -- Pass the result to cmd and then to postFn
  local cmd_output
  if type(cmd) == 'function' then
    cmd_output = cmd(transformed, meta)
  else
    cmd_output = vim.fn.system(cmd, transformed)
  end
  return postFn(cmd_output, ctx, meta)
end

--- @param bufnr number | nil
--- @return { char: string, size: number }
M.get_indent_info = function(bufnr)
  bufnr = bufnr or 0
  local expandtab = vim.bo[bufnr].expandtab
  local tabstop = vim.bo[bufnr].tabstop
  local shiftwidth = vim.bo[bufnr].shiftwidth
  if expandtab then
    return { char = ' ', size = shiftwidth }
  else
    return { char = '	', size = tabstop }
  end
end

--- Find a floating window that matches a predicate
---@param predicate fun(win: number): boolean
---@return number|nil @the floating window, or nil if none is found
M.find_float = function(predicate)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local winconfig = vim.api.nvim_win_get_config(win)
    if winconfig.relative ~= '' and predicate(win) then
      return win
    end
  end
end

---Find the noice float window for the current window
---@return number|nil @the hover float window, or nil if none is found
M.find_noice_float = function()
  return M.find_float(function(win)
    local buf = vim.api.nvim_win_get_buf(win)
    return vim.bo[buf].filetype == 'noice'
  end)
end

---Find the diagnostic float window for the current window
---@param source_win? number @the window to use as the source window, or nil for the current window
---@return number|nil @the diagnostic float window, or nil if none is found
M.find_diagnostic_float = function(source_win)
  source_win = require('user.util.api').resolve_winnr(source_win)
  return M.find_float(function(win)
    local winconfig = vim.api.nvim_win_get_config(win)
    local w = vim.w[win]
    return (w.line or w.cursor or w.buffer) and (source_win == nil or winconfig.win == source_win)
  end)
end

M.find_dapui_float = function()
  return M.find_float(function(win)
    local buf = vim.api.nvim_win_get_buf(win)
    return vim.bo[buf].filetype:match '^dapui_'
  end)
end

---@param reg string
---@param lines (string|string[])[]
---@param force? boolean  @if true, always send osc52 sequence even if a clipboard tool is available
M.osc52_smart_copy = function(reg, lines, force)
  lines = vim.iter({ lines, '' }):flatten(math.huge):totable()
  if reg and reg ~= '' then
    vim.fn.setreg(reg, vim.iter(lines):join('\n'))
  end
  -- Only send the OSC 52 if connected via SSH
  if not force and vim.env.SSH_CONNECTION == nil then
    return
  end
  require('vim.ui.clipboard.osc52').copy(reg)(lines)
end

return M
