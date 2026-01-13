very_lazy(function()
  local fn = require 'user.fn'
  local maputil = require 'user.util.map'
  local recent_wins = lazy_require 'user.util.recent-wins'
  local fyler = lazy_require 'fyler'
  local xk = require('user.keys').xk

  local map = maputil.map
  local ft = maputil.ft

  -- Custom smart breadth-first recursive search
  -- TODO: Make a Fyler PR adding this once I've tested it thoroughly
  require('user.util.fyler.search').setup {
    max_depth = 5,
  }

  map('n', xk '<C-S-\\>', function()
    local finder = require('fyler.views.finder').instance()
    if finder and finder.win and finder.win:is_visible() then
      finder:close()
    else
      fyler.open()
      vim.schedule(function() recent_wins.focus_most_recent() end)
    end
  end, 'Fyler: Toggle')

  map(
    'n',
    xk [[<C-\>]],
    fn.if_filetype({ 'fyler', 'DiffviewFiles' }, recent_wins.focus_most_recent, function()
      local wins = vim.api.nvim_tabpage_list_wins(0)
      local tree_win, diffview_win
      for _, win in ipairs(wins) do
        local bufnr = vim.api.nvim_win_get_buf(win)
        local filetype = vim.bo[bufnr].filetype
        if filetype == 'fyler' then
          tree_win = win
        elseif filetype == 'DiffviewFiles' then
          diffview_win = win
        end
      end
      -- prefer diffview
      if diffview_win then
        vim.api.nvim_set_current_win(diffview_win)
      elseif tree_win then
        vim.api.nvim_set_current_win(tree_win)
      else
        fyler.open()
      end
    end),
    'Fyler: Toggle Focus'
  )

  map('v', xk [[<C-\>]], '<Cmd>Fyler<Cr>', 'Fyler: Open visual selection')

  ft('fyler', function(bufmap)
    local parser = require 'fyler.views.finder.helper'
    local finder = require('fyler.views.finder').instance()
    if not finder then
      return
    end

    local get_selected = function()
      local ref_id = parser.parse_ref_id(vim.api.nvim_get_current_line())
      if not ref_id then
        return
      end
      local entry = finder.files:node_entry(ref_id)
      if not entry then
        return
      end
      return entry, ref_id
    end

    local function toggle_dir(entry, ref_id)
      if entry.open then
        finder.files:collapse_node(ref_id)
      else
        finder.files:expand_node(ref_id)
      end
      finder:dispatch_refresh { force_update = true }
    end

    bufmap('n', '<Tab>', function()
      local entry, ref_id = get_selected()
      if not entry then
        return
      end
      if entry:is_directory() then
        toggle_dir(entry, ref_id)
      elseif entry.type == 'file' then
        require('overlook.peek').file(entry.path)
      end
    end, 'Fyler: Toggle expanded')
  end)
end)

---@type LazySpec[]
return {
  {
    'A7Lavinraj/fyler.nvim',
    cmd = 'Fyler',
    opts = {
      integrations = {
        icon = 'nvim_web_devicons',
        winpick = 'nvim-window-picker',
      },
      views = {
        finder = {
          close_on_select = false,
          win = {
            kind = 'split_left_most',
            kinds = { split_left_most = { width = '30' } },
            win_opts = {
              cursorline = true,
            },
          },
          mappings = {
            ['<Cr>'] = 'Select',
            ['q'] = 'CloseView',
            ['<C-t>'] = 'SelectTab',
            ['<C-v>'] = 'SelectVSplit',
            ['<C-x>'] = 'SelectSplit',
            ['^'] = 'GotoParent',
            ['='] = 'GotoCwd',
            ['.'] = 'GotoNode',
            ['#'] = 'CollapseAll',
          },
          follow_current_file = true,
          watcher = {
            enabled = true,
          },
        },
      },
    },
  },
}
