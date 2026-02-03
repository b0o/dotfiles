local xk = require('user.keys').xk

---@type LazySpec[]
local spec = {
  {
    'akinsho/nvim-toggleterm.lua',
    cmd = 'ToggleTerm',
    config = function()
      ---@diagnostic disable-next-line: undefined-field
      vim.env.NVIM_LISTEN_ADDRESS_TOGGLETERM = vim.v.servername or nil

      require('toggleterm').setup {
        size = function(term)
          if term.direction == 'horizontal' then
            return math.max(15, math.min(50, math.floor(vim.o.lines * 0.33)))
          elseif term.direction == 'vertical' then
            return math.max(80, math.min(120, math.floor(vim.o.columns * 0.2)))
          end
        end,
        open_mapping = xk [[<C-S-/>]],
        start_in_insert = false,
        direction = 'float',
        persist_size = false,
        shade_terminals = false,
        float_opts = {
          border = 'curved',
          width = function() return math.max(40, math.min(200, math.floor(vim.o.columns * 0.55))) end,
          height = function() return math.max(30, math.min(100, math.floor(vim.o.lines * 0.55))) end,
          zindex = 200,
          winblend = 0,
        },
        highlights = {
          FloatBorder = { link = 'FloatBorder' },
        },
      }
    end,
  },
  {
    'stevearc/overseer.nvim',
    -- conf = 'user.plugin.overseer',
    cmd = {
      'OverseerRun',
      'OverseerShell',
      'OverseerClose',
      'OverseerOpen',
      'OverseerTaskAction',
      'OverseerToggle',
    },
    config = function()
      require('overseer').setup {
        disable_template_modules = {
          'overseer.template.npm', -- using custom template at lua/overseer/template/user/npm.lua
        },
        component_aliases = {
          default = {
            'on_exit_set_status',
            'on_complete_notify',
            -- 'on_complete_dispose', -- keep tasks until manually disposed
          },
        },
        task_list = {
          direction = 'bottom',
          max_width = { 140, 0.4 },
          min_width = { 40, 0.1 },
          max_height = { 60, 0.6 },
          min_height = { 15, 0.2 },
          keymaps = {
            ---@diagnostic disable-next-line: assign-type-mismatch
            ['<C-s>'] = false,
            ['<C-x>'] = { 'keymap.run_action', opts = { action = 'stop' } },
            ['<C-r>'] = { 'keymap.run_action', opts = { action = 'restart' } },
            ['<C-d>'] = { 'keymap.run_action', opts = { action = 'dispose' } },
          },
        },
      }
    end,
  },
  {
    'tpope/vim-eunuch',
    cmd = { 'Chmod', 'Delete', 'Edit', 'Grep', 'Mkdir', 'Move', 'Rename', 'Unlink', 'Wall', 'Write' },
  },
}

very_lazy(function()
  local fn = require 'user.fn'
  local maputils = require 'user.util.map'
  local map = maputils.map
  local wrap = maputils.wrap

  local recent_wins = lazy_require 'user.util.recent-wins'
  local overseer = lazy_require 'overseer'

  vim.api.nvim_create_user_command('OverseerRestartLast', function()
    -- Sort by most recently active (either started or finished)
    local function get_last_active_time(task)
      local start = task.time_start or 0
      local finish = task.time_finish or 0
      return math.max(start, finish)
    end
    local tasks = overseer.list_tasks {
      sort = function(a, b) return get_last_active_time(a) > get_last_active_time(b) end,
    }
    if vim.tbl_isempty(tasks) then
      vim.notify('No tasks found', vim.log.levels.WARN)
    else
      overseer.run_action(tasks[1], 'restart')
    end
  end, {})

  map('n', '<M-S-o>', wrap(overseer.toggle, { enter = false }), 'Overseer: Toggle')

  map(
    'n',
    '<M-o>',
    fn.if_filetype('OverseerList', recent_wins.focus_most_recent, overseer.open),
    'Overseer: Toggle Focus'
  )

  map('n', '<leader>or', '<cmd>OverseerRun<Cr>', 'Overseer: Run')
  map('n', '<leader>oR', '<cmd>OverseerRestartLast<Cr>', 'Overseer: Restart Last')

  local function toggleterm_open(direction, mode)
    mode = mode or 'n'
    return function()
      if mode == 't' then
        return ([[<C-\><C-n>:ToggleTerm direction=%s<Cr>]]):format(direction)
      end
      local cmd = 'ToggleTerm'
      if direction then
        cmd = cmd .. ' direction=' .. direction
      end
      require('user.util.recent-wins').update()
      vim.cmd(cmd)
    end
  end

  local toggleterm_smart_toggle = function()
    local terms = require('toggleterm.terminal').get_all()
    if #terms > 0 then
      local term = terms[1]
      local cur_win = vim.api.nvim_get_current_win()
      if term.window == cur_win then
        require('user.util.recent-wins').focus_most_recent()
        return
      end
      local cur_tab = vim.api.nvim_get_current_tabpage()
      if vim.api.nvim_win_is_valid(term.window) then
        if vim.api.nvim_win_get_tabpage(term.window) == cur_tab then
          vim.api.nvim_set_current_win(term.window)
          return
        end
        vim.api.nvim_win_close(term.window, true)
      end
    end
    toggleterm_open()()
  end

  map('n', xk '<C-M-S-/>', toggleterm_open 'float', 'ToggleTerm: Toggle (float)')
  map('t', xk '<C-M-S-/>', [[<C-\><C-n>:ToggleTerm direction=float<Cr>]], 'ToggleTerm: Toggle (float)')
  map('n', xk '<M-S-/>', toggleterm_open 'vertical', 'ToggleTerm: Toggle (vertical)')
  map('t', xk '<M-S-/>', [[<C-\><C-n>:ToggleTerm direction=vertical<Cr>]], 'ToggleTerm: Toggle (vertical)')
  map('n', xk '<C-M-/>', toggleterm_open 'horizontal', 'ToggleTerm: Toggle (horizontal)')
  map('t', xk '<C-M-/>', [[<C-\><C-n>:ToggleTerm direction=horizontal<Cr>]], 'ToggleTerm: Toggle (horizontal)')
  map('n', xk '<C-/>', toggleterm_smart_toggle, 'ToggleTerm: Smart Toggle')
  map('t', xk '<C-/>', toggleterm_smart_toggle, 'ToggleTerm: Smart Toggle')
end)

return spec
