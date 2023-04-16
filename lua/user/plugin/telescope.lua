---- nvim-telescope/telescope.nvim
local t = require 'telescope'
local ta = require 'telescope.actions'
local tb = require 'telescope.builtin'

local action_state = require 'telescope.actions.state'

local fn = require 'user.fn'
local m = require 'user.mappings'
local Debounce = require 'user.util.debounce'

local M = {}

local dbounced_show_builtins = Debounce(function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, true, true), 'm', false)
  M.cmds.builtin()
end, { threshold = vim.o.timeoutlen - 1 })

local select_or_show_builtins = function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc><C-f>', true, true, true), 'm', false)
  dbounced_show_builtins()
end

-- Based on https://github.com/nvim-telescope/telescope.nvim/issues/1048#issuecomment-1225975038
local function multiopen(method)
  return function(prompt_bufnr)
    local edit_file_cmd_map = {
      vertical = 'vsplit',
      horizontal = 'split',
      tab = 'tabedit',
      default = 'edit',
    }
    local edit_buf_cmd_map = {
      vertical = 'vert sbuffer',
      horizontal = 'sbuffer',
      tab = 'tab sbuffer',
      default = 'buffer',
    }
    local picker = action_state.get_current_picker(prompt_bufnr)
    local multi_selection = picker:get_multi_selection()

    if #multi_selection > 1 then
      require('telescope.pickers').on_close_prompt(prompt_bufnr)
      pcall(vim.api.nvim_set_current_win, picker.original_win_id)

      for i, entry in ipairs(multi_selection) do
        local filename, row, col

        if entry.path or entry.filename then
          filename = entry.path or entry.filename

          row = entry.row or entry.lnum
          col = vim.F.if_nil(entry.col, 1)
        elseif not entry.bufnr then
          local value = entry.value
          if not value then
            return
          end

          if type(value) == 'table' then
            value = entry.display
          end

          local sections = vim.split(value, ':')

          filename = sections[1]
          row = tonumber(sections[2])
          col = tonumber(sections[3])
        end

        local entry_bufnr = entry.bufnr

        if entry_bufnr then
          if not vim.api.nvim_buf_get_option(entry_bufnr, 'buflisted') then
            vim.api.nvim_buf_set_option(entry_bufnr, 'buflisted', true)
          end
          local command = i == 1 and 'buffer' or edit_buf_cmd_map[method]
          pcall(vim.cmd, string.format('%s %s', command, vim.api.nvim_buf_get_name(entry_bufnr)))
        else
          local command = i == 1 and 'edit' or edit_file_cmd_map[method]
          if vim.api.nvim_buf_get_name(0) ~= filename or command ~= 'edit' then
            filename = require('plenary.path'):new(vim.fn.fnameescape(filename)):normalize(vim.loop.cwd())
            pcall(vim.cmd, string.format('%s %s', command, filename))
          end
        end

        if row and col then
          pcall(vim.api.nvim_win_set_cursor, 0, { row, col - 1 })
        end
      end
    else
      ta['select_' .. method](prompt_bufnr)
    end
  end
end

local function stopinsert(callback)
  return function(prompt_bufnr)
    vim.cmd.stopinsert()
    vim.schedule(function()
      callback(prompt_bufnr)
    end)
  end
end

t.setup {
  defaults = {
    layout_config = {
      scroll_speed = 2,
      preview_cutoff = 50,
      -- preview_width = 0.6, -- TODO: breaks floatwins
    },
    mappings = {
      i = {
        ['<C-x>'] = stopinsert(multiopen 'horizontal'),
        ['<C-v>'] = stopinsert(multiopen 'vertical'),
        ['<C-t>'] = stopinsert(multiopen 'tab'),
        ['<Cr>'] = stopinsert(multiopen 'default'),
        [m.xk['<C-.>']] = ta.toggle_selection,
        [m.xk['<C-S-f>']] = ta.close,
        ['<C-s>'] = select_or_show_builtins,
        ['<M-n>'] = ta.cycle_history_next,
        ['<M-p>'] = ta.cycle_history_prev,
        ['<C-j>'] = ta.preview_scrolling_down,
        ['<C-k>'] = ta.preview_scrolling_up,
        ['<C-d>'] = false,
      },
      n = {
        ['<C-x>'] = multiopen 'horizontal',
        ['<C-v>'] = multiopen 'vertical',
        ['<C-t>'] = multiopen 'tab',
        ['<Cr>'] = multiopen 'default',
        [m.xk['<C-.>']] = ta.toggle_selection,
        [m.xk['<C-S-f>']] = ta.close,
        ['<C-s>'] = dbounced_show_builtins:ref(),
        ['<M-n>'] = ta.cycle_history_next,
        ['<M-p>'] = ta.cycle_history_prev,
        ['<C-n>'] = ta.move_selection_next,
        ['<C-p>'] = ta.move_selection_previous,
        ['<C-j>'] = ta.preview_scrolling_down,
        ['<C-k>'] = ta.preview_scrolling_up,
      },
    },
  },
  extensions = {
    live_grep_args = {
      auto_quoting = true,
    },
  },
}

local extensions_loaded = false
local function load_extensions()
  if extensions_loaded then
    return
  end
  for _, ext in ipairs(require('user.packer').telescope_exts) do
    if not rawget(t.extensions, ext) then
      t.load_extension(ext)
    end
  end
  extensions_loaded = true
end

local _cmds = {}

_cmds.smart_files = function()
  tb.find_files {
    prompt_title = 'Find Files (Smart)',
    hidden = true,
    file_ignore_patterns = {
      '^.git/',
      '^node_modules/',
      '%.jpg$',
      '%.png$',
      '%.gif$',
      '%.mp4$',
      '%.exe$',
      '%.gz$',
      '%.zip$',
      '%.webm$',
      '%.avi$',
      '%.mov$',
    },
  }
end

_cmds.any_files = function()
  tb.find_files {
    prompt_title = 'Find Files (Any)',
    hidden = true,
  }
end

_cmds.tags = function()
  tb.tags { only_current_buffer = true }
end

_cmds.builtin = function()
  load_extensions()
  tb.builtin { include_extensions = true }
end

M.cmds = setmetatable({}, {
  __index = function(self, k)
    local v = rawget(self, k) or _cmds[k] or tb[k]
    if not v then
      t.load_extension(k)
      v = rawget(t.extensions, k)
      if v and v[k] then
        v = v[k]
      end
    end
    -- This convoluted mess allows a call to any property or descendant
    -- property of M.cmds to be wrapped in a function that cancels the
    -- debounced show_builtins function
    if type(v) == 'table' or type(v) == 'function' then
      local cb = function(func, ...)
        dbounced_show_builtins:reset()
        func(...)
      end
      if type(v) == 'table' then
        return fn.on_call_rec(v, cb)
      end
      return function(...)
        return cb(v, ...)
      end
    end
    return v
  end,
})

return M
