very_lazy(function()
  local fn = require 'user.fn'
  local maputil = require 'user.util.map'
  local recent_wins = lazy_require 'user.util.recent-wins'
  local fyler = lazy_require 'fyler'
  local xk = require('user.keys').xk

  local map = maputil.map
  local ft = maputil.ft

  map('n', xk '<C-S-\\>', function()
    local cur = require('fyler.views.finder')._current
    if cur and cur.win:is_visible() then
      fyler.close()
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

  ft('fyler', function(bufmap)
    local parser = require 'fyler.views.finder.parser'
    local finder = require('fyler.views.finder')._current
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
      finder:dispatch_refresh()
    end

    bufmap('n', '<Tab>', function()
      local entry, ref_id = get_selected()
      if not entry or not entry:isdir() then
        return
      end
      toggle_dir(entry, ref_id)
    end, 'Fyler: Toggle expanded')
  end)
end)

---@type LazySpec[]
return {
  {
    'A7Lavinraj/fyler.nvim',
    -- dev = true,
    dependencies = { 'nvim-mini/mini.icons' },
    cmd = 'Fyler',
    opts = {
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
          watcher = {
            enabled = true,
          },
        },
      },
    },
  },
}
