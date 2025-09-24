local fn = lazy_require 'user.fn'

local cmd = vim.api.nvim_create_user_command
local cabbrev = function(a, c) vim.cmd(('cabbrev %s %s'):format(a, c)) end

local M = {
  cmp = {},
}

------ User Commands
cmd('Put', function(o)
  ---@type string
  local res
  if o.bang == true then
    local out = vim
      .system({
        vim.o.shell,
        vim.o.shellcmdflag,
        o.args,
      }, {})
      :wait()
    if out.code ~= 0 then
      vim.notify('Command failed with exit code ' .. out.code)
      return
    end
    res = out.stdout or ''
  else
    res = vim.fn.execute(o.args)
  end
  local start_line, end_line
  if o.range > 0 then
    start_line = o.line1 - 1
    end_line = o.line2 or start_line
  else
    start_line = vim.api.nvim_win_get_cursor(0)[1]
    end_line = start_line
  end
  vim.api.nvim_buf_set_lines(0, start_line, end_line, false, vim.split(vim.fn.trim(res), '\n'))
end, {
  bang = true,
  range = true,
  nargs = '+',
  complete = 'command',
  desc = 'Put the result of a vim or shell command into the current buffer',
})

cmd('DiffOrig', 'vert new | set buftype=nofile | read ++edit # | 0d_ | diffthis | wincmd p | diffthis', {
  desc = 'Open a diff of the current buffer with the original buffer',
})

cmd('H', function(o)
  for _, topic in ipairs(o.fargs) do
    if vim.fn.bufname() == '' and vim.api.nvim_buf_line_count(0) == 1 and vim.fn.getline(1) == '' then
      local win = vim.api.nvim_get_current_win()
      vim.cmd 'help'
      vim.api.nvim_win_close(win, false)
    else
      vim.cmd('tab help ' .. topic)
    end
  end
end, {
  nargs = '*',
  complete = 'help',
  desc = 'Open help for the given topic',
})

cmd('HH', 'enew | set buftype=help | help <args>', {
  nargs = '*',
  complete = 'help',
  desc = 'Open help for the given topic the current window',
})

cmd('Man', function(o) require('user.fn').man('', unpack(o.fargs)) end, {
  nargs = '*',
  complete = "customlist,v:lua.require'man'.man_complete",
  desc = 'Open man page for the given topic',
})

cmd('M', function(o) require('user.fn').man('tab', unpack(o.fargs)) end, {
  nargs = '*',
  complete = "customlist,v:lua.require'man'.man_complete",
  desc = 'Open man page for the given topic in a new tab',
})

cmd('SessionSave', function() require('user.util.session').session_save() end, {
  desc = 'Save the current session',
})

cmd('SessionLoad', function() require('user.util.session').session_load() end, {
  desc = 'Load a saved session',
})

cabbrev('SS', 'SessionSave')
cabbrev('SL', 'SessionLoad')

cmd('YankMessages', function(o) require('user.fn').yank_messages('<reg>', o.count) end, {
  count = -1,
  register = true,
  desc = 'Yank messages to the specified register',
})

-- Like :only but don't close non-normal windows like quickfix, file trees, etc.
cmd('Only', function(o)
  local curwin = vim.api.nvim_get_current_win()
  vim.tbl_map(function(w)
    if w ~= curwin then
      vim.api.nvim_win_close(w, o.bang == true)
    end
  end, fn.tabpage_list_normal_wins())
end, {
  bang = true,
  desc = 'Close other normal windows',
})

cmd('Bclean', function(o)
  local bufs = vim
    .iter(vim.api.nvim_list_bufs())
    :filter(function(buf)
      local bo = vim.bo[buf]
      local bang = o.bang == true
      return bo.buftype == '' and bo.buflisted and (bang or not bo.modified) and #vim.fn.win_findbuf(buf) == 0
    end)
    :totable()
  if #bufs == 0 then
    vim.notify 'No unused buffers found'
    return
  end
  vim.notify(string.format('Deleting %d unused buffer%s', #bufs, #bufs == 1 and '' or 's'))
  vim.iter(bufs):each(function(buf) vim.cmd('confirm bdelete ' .. buf) end)
end, {
  bang = true,
  desc = 'Delete all unused buffers',
})

---- Magic file commands
-- More commands with similar behavior to Eunuch

-- Complete magic file paths
M.cmp.copy = function(input)
  vim.g.lastinput = input
  if input:match '^[%%#]' or input:match '^%b<>' then
    if input == '%' then
      input = '%:t'
    elseif input == '%%' then
      input = '%'
    end
    return { vim.fn.expand(input) }
  end
  local sep = fn.get_path_separator()
  local prefix = vim.fn.expand '%:p:h' .. sep
  local files = vim.fn.glob(prefix .. input .. '*', false, true)
  files = vim.tbl_map(
    function(file) return string.sub(file, #prefix + 1) .. (vim.fn.isdirectory(file) == 1 and sep or '') end,
    files
  )
  if #files > 0 then
    table.insert(files, '..' .. sep)
  end
  return files
end

local function magicFileCmd(func, name, edit_cmd)
  cmd(name, function(o) func(0, o.args, o.bang == true, edit_cmd, true) end, {
    nargs = 1,
    bar = true,
    bang = true,
    complete = "customlist,v:lua.require'user.commands'.cmp.copy",
  })
end

magicFileCmd(fn.magic_saveas, 'Copy')
magicFileCmd(fn.magic_saveas, 'Duplicate', 'split')
magicFileCmd(fn.magic_saveas, 'XDuplicate', 'split')
magicFileCmd(fn.magic_saveas, 'VDuplicate', 'vsplit')
magicFileCmd(fn.magic_saveas, 'Vduplicate', 'vsplit')
magicFileCmd(fn.magic_newfile, 'New')
magicFileCmd(fn.magic_newfile, 'Newsplit', 'split')
magicFileCmd(fn.magic_newfile, 'XNew', 'split')
magicFileCmd(fn.magic_newfile, 'VNew', 'vsplit')
magicFileCmd(fn.magic_newfile, 'VNewsplit', 'split')

---- Search

-- Copy matches of a regex to the clipboard.
local function write_matches_to_clipboard(regex, bang)
  local matches = {}
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, line in ipairs(lines) do
    local match = vim.fn.matchlist(line, regex)
    if #match > 0 then
      if bang then
        table.insert(matches, match[0])
      else
        for i = 2, #match do
          table.insert(matches, match[i])
        end
      end
    end
  end
  vim.fn.setreg('+', table.concat(matches, '\n'))
  print('Copied ' .. #matches .. ' matches to clipboard')
end

cmd('CopyMatches', function(o) write_matches_to_clipboard(o.args, o.bang) end, {
  bang = true,
  nargs = 1,
})

------ Plugins
---- tpope/vim-eunuch
cmd('Cx', ':Chmod +x', {})

------ Abbreviations
cabbrev('Cp', 'Copy')
cabbrev('XDu', 'Duplicate')
cabbrev('Du', 'Duplicate')
cabbrev('Vd', 'VDuplicate')

return M
