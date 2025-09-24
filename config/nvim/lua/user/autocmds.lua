local Debounce = require 'user.util.debounce'
local win_is_floating = require('user.util.api').win_is_floating

local group = vim.api.nvim_create_augroup('user', { clear = true })
local autocmd = vim.api.nvim_create_autocmd

-- Set local highlight overrides on non-current windows
autocmd({ 'WinNew', 'WinLeave' }, {
  group = group,
  callback = function(event)
    if win_is_floating(0) or vim.bo.filetype == 'qf' then
      return
    end
    local ft = vim.bo[event.buf].filetype
    if ft == 'NvimTree' then
      return
    end
    vim.cmd [[setlocal winhl=CursorLine:CursorLineNC,CursorLineNr:CursorLineNrNC]]
  end,
})

local other_hl_wins = {}
autocmd('WinEnter', {
  group = group,
  pattern = { '*.c', '*.c++', '*.cc', '*.cpp', '*.cxx', '*.h', '*.h++', '*.hh', '*.hpp', '*.hxx' },
  callback = function(event)
    local curwin = vim.api.nvim_get_current_win()
    local other = require 'other-nvim'
    local bufname = vim.api.nvim_buf_get_name(event.buf)
    local others = other.findOther(bufname)
    for _, other in ipairs(others) do
      ---@cast other { exists: boolean, filename: string }
      if other.exists then
        local bufnr = vim.fn.bufnr(other.filename)
        if bufnr ~= -1 then
          local wins = vim.fn.win_findbuf(bufnr)
          for _, win in ipairs(wins) do
            if win ~= curwin and vim.api.nvim_win_is_valid(win) then
              table.insert(other_hl_wins, win)
              vim.api.nvim_win_call(win, function() vim.cmd [[setlocal winhighlight=NormalNC:Normal]] end)
            end
          end
        end
      end
    end
  end,
})

autocmd('WinEnter', {
  group = group,
  callback = function(event)
    if win_is_floating(0) or vim.bo.filetype == 'qf' then
      return
    end
    local ft = vim.bo[event.buf].filetype
    if ft == 'NvimTree' then
      return
    end
    vim.cmd [[setlocal winhighlight=]]
    vim.b.user_winhl = true
  end,
})

local rwins_cursormoved_autocmd, rwins_modechanged_autocmd
local update_recent_wins = Debounce(function()
  pcall(vim.api.nvim_del_autocmd, rwins_cursormoved_autocmd)
  pcall(vim.api.nvim_del_autocmd, rwins_modechanged_autocmd)
  require('user.util.recent-wins').update()
end, { threshold = 500, mode = 'rolling' })

autocmd('WinLeave', {
  group = group,
  callback = function()
    for _, other in ipairs(other_hl_wins) do
      if vim.api.nvim_win_is_valid(other) then
        vim.api.nvim_win_call(other, function() vim.cmd [[setlocal winhighlight=]] end)
      end
    end
    other_hl_wins = {}
    update_recent_wins()
    pcall(vim.api.nvim_del_autocmd, rwins_cursormoved_autocmd)
    pcall(vim.api.nvim_del_autocmd, rwins_modechanged_autocmd)
    local first = true
    rwins_cursormoved_autocmd = autocmd('CursorMoved', {
      callback = function()
        if first then
          first = false
          return
        end
        update_recent_wins:immediate()
      end,
    })
    rwins_modechanged_autocmd = autocmd('ModeChanged', {
      callback = function() update_recent_wins:immediate() end,
      once = true,
    })
  end,
})

autocmd('FocusGained', {
  group = group,
  callback = function() vim.g.nvim_focused = true end,
})
autocmd('FocusLost', {
  group = group,
  callback = function() vim.g.nvim_focused = false end,
})

autocmd('TextYankPost', {
  group = group,
  callback = function()
    vim.highlight.on_yank()
    -- OSC 52 support
    local ev = vim.v.event
    if
      -- unnamed register
      ev.regname ~= ''
      or ev.operator ~= 'y'
      or not ev.regcontents
    then
      return
    end
    local lines = ev.regcontents --[[@as string[] ]]
    require('user.fn').osc52_copy(ev.regname, lines)
  end,
})
autocmd('TermOpen', {
  group = group,
  command = [[setlocal scrolloff=0]],
})
autocmd('WinEnter', {
  group = group,
  pattern = {
    -- 'term://*',
    '\\[dap-repl-*\\]',
  },
  callback = vim.schedule_wrap(function(event)
    local bufnr = vim.api.nvim_get_current_buf()
    if event.buf ~= bufnr then
      return
    end
    vim.cmd 'normal! $'
    vim.schedule(function() vim.cmd 'startinsert!' end)
  end),
})

------ Filetypes
autocmd('FileType', {
  pattern = 'qf',
  group = group,
  callback = function(event)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == event.buf then
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_call(win, function()
            vim.cmd [[setlocal winfixheight]]
            if vim.fn.getwininfo(win)[1].loclist == 1 then
              -- use setlocal to avoid leaving the winhighlight into newly opened windows
              -- see: https://github.com/neovim/neovim/issues/18283
              vim.cmd [[setlocal winhighlight=Normal:LocListNormal,NormalNC:LocListNormalNC,CursorLine:LocListCursorLine,CursorLineNC:LocListCursorLineNC]]
            else -- qflist
              vim.cmd [[setlocal winhighlight=Normal:QFListNormal,NormalNC:QFListNormalNC,CursorLine:QFListCursorLine,CursorLineNC:QFListCursorLineNC]]
            end
          end)
        end
      end
    end
  end,
})

------ Plugins

---- nvim-tree/nvim-tree.lua
autocmd('BufEnter', {
  group = group,
  nested = true,
  callback = function()
    if
      #vim.api.nvim_tabpage_list_wins(0) == 1
      and vim.fn.bufname() == 'NvimTree_' .. vim.api.nvim_get_current_tabpage()
    then
      vim.api.nvim_win_close(0, false)
    end
  end,
})
