---@type LazySpec[]
local spec = {
  'stevearc/aerial.nvim',
  cmd = {
    'AerialClose',
    'AerialCloseAll',
    'AerialGo',
    'AerialInfo',
    'AerialNavClose',
    'AerialNavOpen',
    'AerialNavToggle',
    'AerialNext',
    'AerialOpen',
    'AerialOpenAll',
    'AerialPrev',
    'AerialToggle',
  },
  config = function()
    require('aerial').setup {
      backends = { 'treesitter', 'lsp', 'markdown', 'man' },
      attach_mode = 'global',
      disable_max_lines = 5000,
      filter_kind = {
        'Class',
        'Constructor',
        'Enum',
        'Function',
        'Interface',
        'Module',
        'Method',
        'Struct',
        'Type',
      },
      highlight_on_hover = true,
      ignore = { filetypes = { 'gomod' } },
      layout = {
        min_width = 30,
        default_direction = 'right',
        placement = 'edge',
      },
      update_events = 'TextChanged,InsertLeave',
      lsp = {
        update_when_errors = true,
        -- diagnostics_trigger_update = false,
        update_delay = 500,
      },
      treesitter = {
        update_delay = 500,
      },
      markdown = {
        update_delay = 500,
      },
      keymaps = {
        ['?'] = false,
      },
    }
  end,
}

very_lazy(function()
  local maputil = require 'user.util.map'
  local recent_wins = require 'user.util.recent-wins'
  local smart_size = require 'user.util.smart-size'
  local fn = require 'user.fn'
  local xk = require('user.keys').xk

  local aerial = lazy_require 'aerial'
  local aerial_util = lazy_require 'aerial.util'

  local map = maputil.map
  local ft = maputil.ft
  local wrap = maputil.wrap

  local function aerial_get_win()
    local active_bufnr = aerial_util.get_aerial_buffer()
    if active_bufnr ~= -1 then
      local active_winid = aerial_util.buf_first_win_in_tabpage(active_bufnr)
      if active_winid then
        return active_winid
      end
    end
    for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local winbuf = vim.api.nvim_win_get_buf(winid)
      if aerial_util.is_aerial_buffer(winbuf) then
        return winid
      end
    end
  end

  local function aerial_open(focus)
    if not package.loaded.aerial then
      require 'aerial' -- force load aerial
      aerial.close() -- force aerial setup
    end
    local winid = aerial_get_win()
    if winid then
      vim.api.nvim_set_current_win(winid)
      return
    end
    if not pcall(require('aerial.backends').get) then
      aerial.open()
      if not focus then
        recent_wins.focus_most_recent()
      end
      return
    end

    aerial.refetch_symbols()
    aerial.open { focus = focus or false }
    smart_size.update()
  end

  map('n', xk '<M-S-\\>', function()
    if package.loaded.aerial and aerial_get_win() then
      local foc = require('aerial.util').is_aerial_buffer()
      aerial.close()
      if foc then
        recent_wins.focus_most_recent()
      end
    else
      aerial_open()
    end
  end, 'Aerial: Toggle')

  map(
    'n',
    '<M-\\>',
    fn.if_filetype('aerial', recent_wins.focus_most_recent, wrap(aerial_open, true)),
    'Aerial: Toggle Focus'
  )

  map(
    'n',
    xk '<C-M-S-\\>',
    fn.if_filetype('aerial', function() vim.cmd.AerialClose() end, function()
      require('aerial').refetch_symbols()
      vim.cmd.AerialOpen 'float'
    end),
    'Aerial: Open Float'
  )

  ft('aerial', function(bufmap)
    local function aerial_select(opts)
      local winid = recent_wins.get_most_recent_smart()
      if not vim.api.nvim_win_is_valid(winid or -1) then
        winid = nil
      end
      require('aerial.navigation').select(vim.tbl_extend('force', {
        winid = winid,
      }, opts or {}))
    end

    local function aerial_view(cmd)
      vim.schedule(wrap(aerial_select, { jump = false }))
      return cmd or '\\<Nop>'
    end

    bufmap('n', '<Cr>', aerial_select, 'Aerial: Select item')
    bufmap('n', '<Tab>', aerial_view, 'Aerial: Bring item into view')
    bufmap('n', 'J', wrap(aerial_view, 'j'), 'Aerial: Bring next item into view')
    bufmap('n', 'K', wrap(aerial_view, 'k'), 'Aerial: Bring previous item into view')
  end)
end)

return spec
