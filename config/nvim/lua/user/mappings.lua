local fn = require 'user.fn'
local lazy = require 'user.util.lazy'
local xk = require('user.keys').xk
local recent_wins = lazy_require 'user.util.recent-wins'
local maputil = require 'user.util.map'
local map, ft, wrap = maputil.map, maputil.ft, maputil.wrap

-- Disable C-z suspend
map('nvo', '<C-z>', '<Nop>')
map('nvo', '<C-\\>', '<Nop>')

-- Disable Ex mode
map('n', 'Q', '<Nop>')
map('n', 'gQ', '<Nop>')

-- Disable command-line window
map('n', 'q:', '<Nop>')
map('n', 'q/', '<Nop>')
map('n', 'q?', '<Nop>')

for _, key in ipairs { 'j', 'k' } do
  -- Jumping more than 2 lines at a time sets the ' mark so you can jump back to the previous position
  map('n', key, function()
    local mark = vim.v.count > 2 and ("m'" .. tostring(vim.v.count)) or ''
    local prefix = vim.v.count == 0 and 'g' or ''
    return mark .. prefix .. key
  end, { expr = true, desc = 'Line ' .. (key == 'j' and 'down' or 'up') })
end

map('nx', 'J', '5j', 'Jump down')
map('nx', 'K', '5k', 'Jump up')
map('nx', '<C-d>', '25j', 'Page down')
map('nx', '<C-u>', '25k', 'Page up')

-- If on a blank line, start insert mode properly indented
map('n', 'i', function()
  if not vim.bo.buftype == 'terminal' and string.match(vim.api.nvim_get_current_line(), '^%s*$') then
    return '"_S'
  else
    return 'i'
  end
end, { expr = true, desc = 'Insert' })

map('nx', '<M-Down>', '<C-e>', 'Scroll view down 1')
map('nx', '<M-Up>', '<C-y>', 'Scroll view up 1')
map('nx', '<M-S-Down>', '5<C-e>', 'Scroll view down 5')
map('nx', '<M-S-Up>', '5<C-y>', 'Scroll view up 5')

map('i', '<M-Down>', '<C-o><C-e>', 'Scroll view down 1')
map('i', '<M-Up>', '<C-o><C-y>', 'Scroll view up 1')
map('i', '<M-S-Down>', '<C-o>5<C-e>', 'Scroll view down 5')
map('i', '<M-S-Up>', '<C-o>5<C-y>', 'Scroll view up 5')

map('n', { 'Q', '<F29>' }, function()
  local most_recent_win = require('user.util.recent-wins').get_most_recent_smart()
  vim.cmd 'confirm q'
  if most_recent_win then
    vim.api.nvim_set_current_win(most_recent_win)
  end
end, 'Close window')
map('n', 'ZQ', '<Cmd>confirm qall<Cr>', { silent = false, desc = 'Quit all' })
map('n', xk '<C-S-w>', '<Cmd>tabclose<Cr>', 'Close tab (except last one)')
map('n', '<leader>H', '<Cmd>hide<Cr>', 'Hide buffer')
map('n', '<C-s>', '<Cmd>w<Cr>', 'Write buffer')
map('n', '<C-M-s>', '<Cmd>noa w<Cr>', 'Write buffer (no autocommands)')

-- quickly enter command mode with substitution commands prefilled
map('n', '<leader>/', ':%s/', { silent = false, desc = 'Substitute' })
map('n', '<leader>?', ':%S/', { silent = false, desc = 'Substitute (rev)' })
map('x', '<leader>/', ':s/', { silent = false, desc = 'Substitute' })
map('x', '<leader>?', ':S/', { silent = false, desc = 'Substitute (rev)' })

-- Buffer-local option toggles
---@param keys string|string[]
---@param opts string|string[]
---@param vals? any|any[]
local function map_toggle_locals(keys, opts, vals)
  keys = type(keys) == 'table' and keys or { keys }
  opts = type(opts) == 'table' and opts or { opts }
  vals = vals or { true, false }

  local lhs = vim.tbl_map(function(k) return [[<localleader><localleader>]] .. k end, keys)

  local rhs = function()
    vim.tbl_map(function(opt)
      local cur = vim.opt_local[opt]:get()
      local target = vals[1]
      for i, v in ipairs(vals) do
        if v == cur then
          if vals[i + 1] ~= nil then
            target = vals[i + 1]
          end
          break
        end
      end
      local msg
      if type(target) == 'boolean' then
        msg = (target and 'Enable ' or 'Disable ') .. opt
      else
        msg = 'Set ' .. opt .. '=' .. target
      end
      vim.notify(msg)
      vim.opt_local[opt] = target
    end, opts)
  end

  map('n', lhs, rhs, 'Toggle ' .. table.concat(opts, ', '))
end

map_toggle_locals({ 'A', 'ar' }, { 'autoread' })
map_toggle_locals({ 'B' }, { 'cursorbind', 'scrollbind' })
map_toggle_locals({ 'bi' }, { 'breakindent' })
map_toggle_locals({ 'C', 'ci' }, { 'copyindent' })
map_toggle_locals({ 'cc' }, { 'concealcursor' }, { '', 'n' })
map_toggle_locals({ 'cl' }, { 'conceallevel' }, { 0, 2 })
map_toggle_locals({ 'cb' }, { 'cursorbind' })
map_toggle_locals({ 'D', 'di' }, { 'diff' })
map_toggle_locals({ 'E', 'et' }, { 'expandtab' })
map_toggle_locals({ 'F', 'fe' }, { 'foldenable' })
map_toggle_locals({ 'L', 'lb' }, { 'linebreak' })
map_toggle_locals({ 'N', 'nn' }, { 'number', 'relativenumber' })
map_toggle_locals({ 'nr', 'rn' }, { 'relativenumber' })
map_toggle_locals({ 'nu' }, { 'number' })
map_toggle_locals({ 'R', 'ru' }, { 'ruler' })
map_toggle_locals({ 'S', 'sg' }, { 'laststatus' }, { 2, 3 })
map_toggle_locals({ 'sp' }, { 'spell' })
map_toggle_locals({ 'sb' }, { 'scrollbind' })
map_toggle_locals({ 'sr' }, { 'shiftround' })
map_toggle_locals({ 'st' }, { 'smarttab' })
map_toggle_locals({ '|' }, { 'cursorcolumn' })
map_toggle_locals({ 'W', 'ww' }, { 'wrap' })

---- Lua helpers
map('n', '+', ':=', { silent = false, desc = 'Lua: Inspect expression' })

---- Cut/Copy Buffers
local cutbuf = lazy.require 'user.util.cutbuf'
map('n', '<localleader>x', cutbuf.cut, 'cutbuf: cut')
map('n', '<localleader>c', cutbuf.copy, 'cutbuf: copy')
map('n', '<localleader>p', cutbuf.paste, 'cutbuf: paste')
map('n', '<localleader>X', cutbuf.swap, 'cutbuf: swap')

---- Window Management
local smart_size = require 'user.util.smart-size'
map('n', '<leader>sa', smart_size.enable_autoresize, 'Smart size: Enable auto-resize')
map('n', '<leader>sA', smart_size.disable_autoresize, 'Smart size: Disable auto-resize')

---- Editing
map('n', 'gi', [[:exec "normal i".nr2char(getchar())."\e"<Cr>]], 'Insert a single character')
map('n', 'ga', [[:exec "normal a".nr2char(getchar())."\e"<Cr>]], 'Insert a single character (append)')

map('x', '>', '>gv', 'Indent')
map('x', '<', '<gv', 'De-Indent')

map('n', 'go', 'o<C-u>', 'Insert on new line without autocomment')
map('n', 'gO', 'O<C-u>', 'Insert on new line above without autocomment')

map('n', 'Y', 'y$', 'Yank until end of line')

map('n', '<leader>yy', '"+yy', 'Yank line to system clipboard')
map('n', '<C-y>', [[pumvisible() ? "\<C-y>" : '"+yy']], { expr = true, desc = 'Yank line to system clipboard' })
map('x', '<C-y>', [[pumvisible() ? "\<C-y>" : '"+y']], { expr = true, desc = 'Yank line to system clipboard' })

local function get_current_file_or_nvim_tree_node()
  ---@type string
  local file
  ---@type string[]
  local lines
  ---@type integer|nil
  local buf
  ---@type string|nil
  local filetype
  if vim.bo.filetype == 'NvimTree' then
    local ok, node = pcall(require('nvim-tree.api').tree.get_node_under_cursor)
    ---@cast node nvim_tree.api.Node
    if ok and node and node.type == 'file' then
      file = vim.fn.fnamemodify(node.absolute_path, ':.')
      filetype = vim.filetype.match { filename = node.absolute_path }
      buf = vim.fn.bufnr(node.absolute_path)
      -- If the file is not loaded, read it from disk
      if buf == -1 then
        lines = vim.fn.readfile(node.absolute_path)
        buf = nil
      end
    else
      return
    end
  else
    buf = 0
  end
  if buf ~= nil then
    file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':.')
    lines = vim.api.nvim_buf_get_lines(buf or 0, 0, -1, false)
    if filetype == nil then
      filetype = vim.fn.expand '%:e'
    end
  end
  if lines == nil then
    return nil
  end
  return {
    relative_path = file,
    lines = lines,
    filetype = filetype,
  }
end

map('n', '<leader>Y', function()
  local file = get_current_file_or_nvim_tree_node()
  if not file then
    vim.notify('No file found', vim.log.levels.WARN)
    return
  end
  local lines = file.lines
  require('user.fn').osc52_smart_copy('+', lines)
  vim.notify('Copied ' .. #lines .. ' lines to clipboard', vim.log.levels.INFO)
end, 'Yank file contents')

map('n', '<leader>ym', function()
  local file = get_current_file_or_nvim_tree_node()
  if not file then
    vim.notify('No file found', vim.log.levels.WARN)
    return
  end
  local lines = file.lines
  local filetype = file.filetype
  local relative_path = file.relative_path
  require('user.fn').osc52_smart_copy('+', {
    '# ' .. relative_path,
    '```' .. (filetype or ''),
    lines,
    '```',
  })
  vim.notify('Copied ' .. relative_path .. ' as markdown code block', vim.log.levels.INFO)
end, 'Yank file as markdown code block')

map('n', '<leader>ypa', function()
  local file = vim.fn.expand '%:p'
  require('user.fn').osc52_smart_copy('+', { file })
  vim.notify('Copied ' .. file, vim.log.levels.INFO)
end, 'Yank file path (absolute)')

map('n', '<leader>ypp', function()
  local file = vim.fn.expand '%:.'
  require('user.fn').osc52_smart_copy('+', { file })
  vim.notify('Copied ' .. file, vim.log.levels.INFO)
end, 'Yank file path (relative)')

map('n', '<leader>ypA', function()
  local line = vim.fn.line '.'
  local file = vim.fn.expand '%'
  require('user.fn').osc52_smart_copy('+', { file .. ':' .. line })
  vim.notify('Copied ' .. file .. ':' .. line, vim.log.levels.INFO)
end, 'Yank file path with line number (absolute)')

map('n', { '<leader>ypP', '<leader>yP' }, function()
  local line = vim.fn.line '.'
  local file = vim.fn.expand '%:.'
  require('user.fn').osc52_smart_copy('+', { file .. ':' .. line })
  vim.notify('Copied ' .. file .. ':' .. line, vim.log.levels.INFO)
end, 'Yank file path with line number (relative)')

-- TODO: use opencode
map('n', '<localleader>aa', function()
  require('user.util.aider').add_buf()
  require('user.util.aider').copy_cmd()
end, 'Aider: /add file')

map('n', { '<localleader>aA', '<localleader>at' }, function()
  require('user.util.aider').add_tabpage()
  require('user.util.aider').copy_cmd()
end, 'Aider: /add all files in tab')

map('n', '<localleader>ac', function() require('user.util.aider').clear_cmd() end, 'Aider: Clear cmd')

map('n', '<leader>y:', function()
  local cmd = vim.fn.getreg '@:'
  require('user.fn').osc52_smart_copy('+', { cmd })
  vim.notify('Copied ' .. cmd, vim.log.levels.INFO)
end, 'Yank last command')

map('nx', '<C-p>', '"+p', 'Paste from system clipboard')

map('n', { '<C-M-j>', xk '<C-M-j>', '<M-Cr>' }, '"dY"dp', 'Duplicate line downwards')
map('n', '<C-M-k>', '"dY"dP', 'Duplicate line upwards')

map('x', { '<C-M-j>', xk '<C-M-j>', '<M-Cr>' }, '"dy`<"dPjgv', 'Duplicate selection downwards')
map('x', '<C-M-k>', '"dy`>"dpgv', 'Duplicate selection upwards')

local wrap_visual_selection_prev = nil
local wrap_visual_selection = function(params)
  local res_params = require('user.util.wrap').wrap_visual_selection(params)
  if res_params then
    wrap_visual_selection_prev = res_params
    vim.cmd [[silent! call repeat#set("\<Plug>WrapVisualSelectionRepeat")]]
  end
end

local wrap_cursor_line_prev = nil
local wrap_cursor_line = function(params)
  vim.cmd [[normal! V]]
  local res_params = require('user.util.wrap').wrap_visual_selection(params)
  if res_params then
    wrap_cursor_line_prev = res_params
    vim.cmd [[silent! call repeat#set("\<Plug>WrapCursorLineRepeat")]]
  end
end

map('x', '<M-w>', wrap_visual_selection, 'Wrap selection')
map('n', '<Plug>WrapVisualSelectionRepeat', function()
  vim.cmd [[normal! gv]]
  wrap_visual_selection(wrap_visual_selection_prev)
end, { desc = 'Wrap visual selection' })

map('n', '<M-S-W>', wrap_cursor_line, 'Wrap line')
map(
  'n',
  '<Plug>WrapCursorLineRepeat',
  function() wrap_cursor_line(wrap_cursor_line_prev) end,
  { desc = 'Wrap cursor line' }
)

---- Treesitter
local node_motion = lazy.require('user.util.treesitter').node_motion
map('xo', 'n', node_motion, 'Smart select node')
map('n', '<C-M-w>', function()
  node_motion()
  wrap_visual_selection()
end, 'Wrap word')

-- match the indentation of the next line
local function match_indent(dir)
  return function()
    local target_line = vim.fn.search([[\S]], 'nW' .. (dir == -1 and 'bz' or ''))
    if target_line == 0 then
      return
    end
    local cur = vim.api.nvim_win_get_cursor(0)
    local indent = vim.fn.indent(cur[1])
    local new_indent = vim.fn.indent(target_line)
    local text = vim.fn.trim(vim.api.nvim_get_current_line())
    ---@diagnostic disable-next-line: param-type-mismatch
    local new_text = string.rep(' ', new_indent) .. text
    vim.api.nvim_set_current_line(new_text)
    vim.api.nvim_win_set_cursor(0, { cur[1], cur[2] + (new_indent - indent) })
  end
end

map('i', '<M-,>', match_indent(-1), 'Match indent of prev line')
map('i', '<M-.>', match_indent(1), 'Match indent of next line')

map('i', xk '<M-Cr>', '<Cr><C-o>O', 'Insert indented new line at cursor')

-- Clear UI state:
-- - Clear search highlight
-- - Clear command-line
-- - Close floating windows
map('n', [[<Esc>]], function()
  local close_noft = true
  vim.cmd 'nohlsearch'
  vim.snippet.stop()
  if package.loaded['nvim-tree'] then
    require('nvim-tree.actions.node.file-popup').close_popup()
  end
  if package.loaded['noice'] then
    vim.cmd 'NoiceDismiss'
  end
  if vim.fn.win_gettype() == 'popup' and vim.bo.filetype == 'leetcode.nvim' then
    close_noft = false
  end
  fn.close_float_wins {
    noft = close_noft,
    fts = {
      'notify',
      'aerial',
      'dap-float',
      'dapui_scopes',
      'dapui_breakpoints',
      'dapui_stacks',
      'dapui_watches',
      'dapui_hover',
    },
    exclude = {
      'leetcode.nvim',
      'markdown',
    },
  }
  vim.cmd "echo ''"
end, 'Clear UI')

-- emacs-style motion & editing in insert mode
map('i', '<C-a>', '<Home>', 'Goto beginning of line')
map('i', '<C-e>', '<End>', 'Goto end of line')
map('i', '<C-b>', '<Left>', 'Goto char backward')
map('i', '<C-f>', '<Right>', 'Goto char forward')
map('i', '<M-b>', '<S-Left>', 'Goto word backward')
map('i', '<M-f>', '<S-Right>', 'Goto word forward')
map('i', '<C-d>', '<Delete>', 'Kill char forward')
map('i', '<M-d>', '<C-o>de', 'Kill word forward')
map('i', '<M-Backspace>', '<C-o>dB', 'Kill word backward')
map('i', '<C-k>', '<C-o>D', 'Kill to end of line')

map('i', '<M-h>', '<Left>', 'Move left')
map('i', '<M-j>', '<Down>', 'Move down')
map('i', '<M-k>', '<Up>', 'Move up')
map('i', '<M-l>', '<Right>', 'Move right')

map('i', '<M-a>', '<C-o>_', 'Move to start of line')

-- unicode stuff
map('i', { xk '<C-S-k>', xk "<C-'>" }, '<C-k>', 'Insert digraph')
map('n', 'gxa', 'ga', 'Show char code in decimal, hexadecimal and octal')

map('n', 'gxG', function()
  local col = vim.fn.col '.'
  local line = vim.api.nvim_get_current_line()
  -- Find username/reponame pattern that contains the cursor position
  local pattern = '[%w_%-%.]+/[%w_%-%.]+'
  local start_pos = 1
  while true do
    local match_start, match_end = line:find(pattern, start_pos)
    if not match_start then
      break
    end
    -- Check if cursor is within or adjacent to this match
    if col >= match_start and col <= match_end then
      local repo = line:sub(match_start, match_end)
      local url = 'https://github.com/' .. repo
      vim.ui.open(url)
      vim.notify('Opening ' .. url, vim.log.levels.INFO)
      return
    end
    start_pos = match_start + 1
  end
  vim.notify('No GitHub repo found under cursor', vim.log.levels.WARN)
end, 'Open GitHub repo under cursor')

map('i', xk '<C-`>', '<C-o>~<Left>', 'Toggle case')

-- emacs-style motion & editing in command mode
map('c', '<C-a>', '<Home>', { silent = false, desc = 'Goto beginning of line' })
map('c', '<C-b>', '<Left>', { silent = false, desc = 'Goto char backward' })
map('c', '<C-d>', '<Delete>', { silent = false, desc = 'Kill char forward' })
map('c', '<C-e>', '<End>', { silent = false, desc = 'Goto end of line' })
map('c', '<C-f>', '<Right>', { silent = false, desc = 'Goto char forward' })
map('c', '<C-g>', '<C-c>', { silent = false, desc = 'Cancel' })
map('c', '<C-k>', [[<C-\>e(" ".getcmdline())[:getcmdpos()-1][1:]<Cr>]], { silent = false, desc = 'Kill to EOL' })
map('c', '<M-f>', [[<C-\>euser#fn#cmdlineMoveWord( 1, 0)<Cr>]], { silent = false, desc = 'Goto word forward' })
map('c', '<M-b>', [[<C-\>euser#fn#cmdlineMoveWord(-1, 0)<Cr>]], { silent = false, desc = 'Goto word backward' })
map('c', '<M-d>', [[<C-\>euser#fn#cmdlineMoveWord( 1, 1)<Cr>]], { silent = false, desc = 'Kill word forward' })
map('c', '<M-Backspace>', [[<C-\>euser#fn#cmdlineMoveWord(-1, 1)<Cr>]], { silent = false, desc = 'Kill word backward' })

map('c', '<M-k>', '<C-k>', 'Insert digraph')

map('c', xk '<C-S-p>', '<Up>', { silent = false, desc = 'History prev (prefix)' })
map('c', xk '<C-S-n>', '<Down>', { silent = false, desc = 'History next (prefix)' })

local function cursor_lock(lock)
  return function()
    local win = vim.api.nvim_get_current_win()
    local augid = vim.api.nvim_create_augroup('user_cursor_lock_' .. win, { clear = true })
    if not lock or vim.w.cursor_lock == lock then
      vim.w.cursor_lock = nil
      vim.notify 'Cursor lock disabled'
      return
    end
    local cb = function()
      if vim.w.cursor_lock then
        vim.cmd('silent normal! z' .. vim.w.cursor_lock)
      end
    end
    vim.w.cursor_lock = lock
    vim.api.nvim_create_autocmd('CursorMoved', {
      desc = 'Cursor lock for window ' .. win,
      buffer = 0,
      group = augid,
      callback = vim.schedule_wrap(cb),
    })
    cb()
    vim.notify 'Cursor lock enabled'
  end
end

map('n', '<leader>zt', cursor_lock 't', 'Toggle cursor lock (top)')
map('n', '<leader>zz', cursor_lock 'z', 'Toggle cursor lock (middle)')
map('n', '<leader>zb', cursor_lock 'b', 'Toggle cursor lock (bottom)')

---- Jumplist
map('n', xk '<C-S-o>', wrap(fn.jumplist_jump_buf, -1), 'Jumplist: Go to last buffer')
map('n', xk '<C-S-i>', wrap(fn.jumplist_jump_buf, 1), 'Jumplist: Go to next buffer')

---- Quickfix
map('n', '<M-S-q>', function()
  local winid = vim.fn.getqflist({ winid = 1 }).winid
  if winid and winid ~= 0 then
    vim.api.nvim_win_close(winid, true)
  else
    vim.cmd 'botright copen'
    vim.cmd.wincmd 'p'
  end
end, 'Quickfix: Toggle')

map(
  'n',
  [[<M-q>]],
  fn.if_filetype('qf', recent_wins.focus_most_recent, wrap(vim.cmd, 'botright copen')),
  'Quickfix: Toggle Focus'
)

map('n', ']q', '<Cmd>cnext<Cr>', 'Quickfix: Next')
map('n', '[q', '<Cmd>cprev<Cr>', 'Quickfix: Prev')

ft('qf', function(bufmap)
  local function is_loclist(winid) return vim.fn.getwininfo(winid)[1].loclist == 1 end

  local function get_list(winid) return is_loclist(winid) and vim.fn.getloclist(winid) or vim.fn.getqflist() end

  local function set_list(winid, list, action)
    if is_loclist(winid) then
      vim.fn.setloclist(winid, list, action)
    else
      vim.fn.setqflist(list, action)
    end
  end

  bufmap('n', 'dd', function()
    local winid = vim.api.nvim_get_current_win()
    local line = vim.fn.line '.'
    set_list(winid, vim.fn.filter(get_list(winid), function(idx) return idx ~= line - 1 end), 'r')
    vim.fn.setpos('.', { 0, line, 1, 0 })
  end, 'Delete item under cursor')

  bufmap('v', 'd', function()
    vim.schedule(function()
      local winid = vim.api.nvim_get_current_win()
      local start = vim.fn.line "'<"
      local finish = vim.fn.line "'>"
      set_list(winid, vim.fn.filter(get_list(winid), function(idx) return idx < start - 1 or idx >= finish end), 'r')
      vim.fn.setpos('.', { 0, start, 1, 0 })
    end)
    vim.cmd [[call feedkeys("\<Esc>", 'n')]]
  end, 'Delete selected items')

  bufmap('n', '<Tab>', function()
    local winid = vim.api.nvim_get_current_win()
    return '<Cr><Cmd>' .. (is_loclist(winid) and 'lopen' or 'copen') .. '<Cr>'
  end, { expr = true, desc = 'Jump to item under cursor' })

  bufmap('n', '<M-w>', function()
    local winid = vim.api.nvim_get_current_win()
    local list = get_list(winid)
    local sel = list[vim.fn.line '.']
    if not sel then
      return
    end
    local win = require('window-picker').pick_window()
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_buf(win, sel.bufnr)
      vim.api.nvim_set_current_win(win)
      vim.api.nvim_win_set_cursor(win, { sel.lnum, sel.col })
    end
  end, 'Jump to item under cursor (pick window)')
end)

---- Location list
map('n', ']z', '<Cmd>lnext<Cr>', 'Loclist: Next')
map('n', '[z', '<Cmd>lprev<Cr>', 'Loclist: Prev')

map('n', '<M-S-z>', function()
  local winid = vim.api.nvim_get_current_win()
  local loclist = vim.fn.getloclist(winid)
  if vim.tbl_isempty(loclist) then
    vim.notify('No location list', vim.log.levels.WARN)
    return
  end
  local loclist_win = vim.fn.getloclist(winid, { winid = 0 }).winid
  if loclist_win == 0 then
    vim.cmd 'lopen'
    vim.cmd.wincmd 'p'
  else
    vim.cmd 'lclose'
  end
end, 'Loclist: Toggle')

map('n', [[<M-z>]], fn.if_filetype('qf', wrap(vim.cmd.wincmd, 'p'), wrap(vim.cmd, 'lopen')), 'Loclist: Toggle Focus')

map('c', { '<C-z>', '<C-q>' }, function(args)
  local cmdtype = vim.fn.getcmdtype()
  if cmdtype ~= '/' and cmdtype ~= '?' then
    return
  end
  local cmdline = vim.fn.getcmdline()
  if cmdline == '' then
    return
  end
  vim.schedule(function()
    vim.cmd.nohlsearch()
    if args.lhs == '<C-q>' then
      vim.cmd('silent! vimgrep /' .. cmdline .. '/ % | botright copen')
    else
      vim.cmd('silent! lvimgrep /' .. cmdline .. '/ % | lopen')
    end
  end)
  return '<Esc>'
end, { expr = true, args = true, desc = 'Add search matches to qflist/loclist' })

---- Tabs
-- Navigate tabs
-- Go to a tab by index; If it doesn't exist, create a new tab
local function tabnm(n)
  return function()
    local tabs = vim.api.nvim_list_tabpages()
    if n > #tabs then
      vim.cmd '$tabnew'
    else
      local tabpage = tabs[n]
      vim.api.nvim_set_current_tabpage(tabpage)
    end
  end
end

local last_tab = function()
  local tabs = vim.api.nvim_list_tabpages()
  local tabpage = tabs[#tabs]
  vim.api.nvim_set_current_tabpage(tabpage)
end

map('n', "<M-'>", '<Cmd>tabn<Cr>', 'Tabs: Goto next')
map('n', '<M-;>', '<Cmd>tabp<Cr>', 'Tabs: Goto prev')
map('t', "<M-'>", '<C-\\><C-n>:tabn<Cr>', 'Tabs: Goto next')
map('t', '<M-;>', '<C-\\><C-n>:tabp<Cr>', 'Tabs: Goto prev')
map('n', '<M-S-a>', ':execute "wincmd g\\<Tab>"<Cr>', 'Tabs: Goto last accessed')

ft('toggleterm', function(bufmap)
  bufmap('n', '<C-n>', 'i<C-n>', 'Goto next')
  bufmap('n', '<C-p>', 'i<C-p>', 'Goto prev')
end)

map('n', '<M-a>', recent_wins.focus_most_recent, 'Panes: Goto previously focused')
map('n', '<M-x>', recent_wins.flip_recents, 'Panes: Flip the last normal wins')
map('n', xk '<C-S-a>', 'g<Tab>', 'Tabs: Goto last accessed')

map('n', '<M-1>', tabnm(1), 'Goto tab 1')
map('n', '<M-2>', tabnm(2), 'Goto tab 2')
map('n', '<M-3>', tabnm(3), 'Goto tab 3')
map('n', '<M-4>', tabnm(4), 'Goto tab 4')
map('n', '<M-5>', tabnm(5), 'Goto tab 5')
map('n', '<M-6>', tabnm(6), 'Goto tab 6')
map('n', '<M-7>', tabnm(7), 'Goto tab 7')
map('n', '<M-8>', tabnm(8), 'Goto tab 8')
map('n', '<M-9>', tabnm(9), 'Goto tab 9')
map('n', '<M-0>', last_tab, 'Goto last tab')

map('n', '<M-">', ':+tabm<Cr>', 'Move tab right')
map('n', '<M-:>', ':-tabm<Cr>', 'Move tab left')

map('n', '<F13>', '<Cmd>tabnew<Cr>', 'Open new tab')

map('t', '<M-h>', '<C-\\><C-n><C-w>h', 'Goto window left')
map('t', '<M-j>', '<C-\\><C-n><C-w>j', 'Goto window down')
map('t', '<M-k>', '<C-\\><C-n><C-w>k', 'Goto window up')
map('t', '<M-l>', '<C-\\><C-n><C-w>l', 'Goto window right')

-- see also the VSplit plugin mappings below
map('n', '<leader>S', '<Cmd>new<Cr>', 'Split (horiz, new)')
map('n', '<leader>sn', '<Cmd>new<Cr>', 'Split (horiz, new)')
map('n', '<leader>V', '<Cmd>vnew<Cr>', 'Split (vert, new)')
map('n', '<leader>vn', '<Cmd>vnew<Cr>', 'Split (vert, new)')
map('n', '<leader>ss', '<Cmd>split<Cr>', 'Split (horiz, cur)')
map('n', '<leader>st', '<Cmd>split<Cr>', 'Split (horiz, cur)')
map('n', '<leader>vv', '<Cmd>vsplit<Cr>', 'Split (vert, cur)')
map('n', '<leader>vt', '<Cmd>vsplit<Cr>', 'Split (vert, cur)')

-- swap p and P
map('v', 'p', 'P', 'paste without overwriting with the original selection')
map('v', 'P', 'p', 'paste')

map('t', xk [[<C-S-n>]], '<C-\\><C-n>', 'Switch to normal mode')
map('t', '<C-n>', '<C-n>', 'Send Ctrl-n')
map('t', '<C-p>', '<C-p>', 'Send Ctrl-p')
map('t', '<M-n>', '<M-n>', 'Send Alt-n')
map('t', '<M-p>', '<M-p>', 'Send Alt-p')

-- TODO: Convert to Lua
map('n', '<Leader>ml', '<Cmd>call AppendModeline()<Cr>', 'Append modeline with current settings')

---- Syntax
map('n', '<leader>hi', '<Cmd>Inspect<Cr>', 'Inspect syntax under cursor')

------ Filetypes
ft('lua', function(bufmap)
  bufmap('nx', '<leader><Enter>', fn.luarun, 'Lua: Eval')
  bufmap('n', '<localleader><Enter>', wrap(fn.luarun, true), 'Lua: Eval file')
  bufmap('nx', '<leader><F12>', "<Cmd>Put lua require'user.fn'.luarun()<Cr>", 'Lua: Eval (Append result to buffer)')
end)

ft({ 'typescriptreact', 'javascriptreact' }, function(bufmap)
  local tailwind_sort = function()
    require('user.util.visual').transform_visual_selection(
      { 'rustywind', '--stdin', '--custom-regex', '(.*)' },
      function(pre)
        -- if the selection includes quotes at the beginning and end, remove them
        local first = pre:sub(0, 1)
        local last = pre:sub(-1)
        if first == last and (first == "'" or first == '"' or first == '`') then
          return pre:sub(2, -2), { first, last }
        end
        return pre
      end,
      function(post, ctx)
        -- if the selection was quoted, re-add the quotes
        if ctx then
          return ctx[1] .. post .. ctx[2]
        end
        return post
      end
    )
  end
  bufmap('x', '<leader>ft', tailwind_sort, 'Tailwind: Sort selection')
  bufmap('n', '<leader>ft', function()
    require('nvim-treesitter.textobjects.select').select_textobject('@string', 'textobjects', 'x')
    tailwind_sort()
  end, 'Tailwind: Sort string under cursor')
end)

ft({ 'typescript', 'javascript', 'typescriptreact', 'javascriptreact' }, function(bufmap)
  bufmap('n', '<leader>ii', '<Cmd>TwoslashQueriesInspect<Cr>', 'TwoSlash: Inspect')
  bufmap('n', '<leader>ir', '<Cmd>TwoslashQueriesRemove<Cr>', 'TwoSlash: Remove')
end)

ft('man', function(bufmap)
  bufmap('n', '<C-]>', function() fn.man('', vim.fn.expand '<cword>') end, 'Man: Open tag in current buffer')

  bufmap('n', '<M-]>', function() fn.man('tab', vim.fn.expand '<cword>') end, 'Man: Open tag in new tab')

  bufmap('n', '}', function() fn.man('split', vim.fn.expand '<cword>') end, 'Man: Open tag in new split')

  -- navigate to next/prev section
  bufmap('n', '[[', ":<C-u>call user#fn#manSectionMove('b', 'n', v:count1)<Cr>", 'Man: Goto prev section')
  bufmap('n', ']]', ":<C-u>call user#fn#manSectionMove('' , 'n', v:count1)<Cr>", 'Man: Goto next section')
  bufmap('x', '[[', ":<C-u>call user#fn#manSectionMove('b', 'v', v:count1)<Cr>", 'Man: Goto prev section')
  bufmap('x', ']]', ":<C-u>call user#fn#manSectionMove('' , 'v', v:count1)<Cr>", 'Man: Goto next section')

  -- navigate to next/prev manpage tag
  bufmap('n', '<Tab>', [[:call search('\(\w\+(\w\+)\)', 's')<Cr>]], 'Man: Goto next tag')
  bufmap('n', '<S-Tab>', [[:call search('\(\w\+(\w\+)\)', 'sb')<Cr>]], 'Man: Goto prev tag')

  -- search from beginning of line (useful for finding command args like -h)
  bufmap('n', 'g/', [[/^\s*\zs]], { silent = false, desc = 'Man: Start BOL search' })
end)

ft('help', function(bufmap)
  -- navigate to next/prev help tag
  bufmap('n', '<Tab>', function() vim.fn.search([[\(|\S\+|\|\*\S\+\*\)]], 's') end, 'Help: Goto next tag')
  bufmap('n', '<S-Tab>', function() vim.fn.search([[\(|\S\+|\|\*\S\+\*\)]], 'sb') end, 'Help: Goto prev tag')
end)

---- folke/noice.nvim
ft('noice', function(bufmap) bufmap('n', 'K', '5k', 'Scroll up 5') end)

---- tpope/vim-repeat
-- make . repeat work from visual mode
map('x', '.', [[<Esc>.]], { remap = true, silent = true, desc = 'Repeat last command' })

---- folke/lazy.nvim
map('n', '<leader>ll', '<Cmd>Lazy<cr>', 'Lazy')
