very_lazy(function()
  local map = require('user.util.map').map
  local xk = require('user.keys').xk

  local comment = lazy_require 'Comment.api'
  local todo_comments = lazy_require 'todo-comments'

  map('n', '<M-/>', comment.toggle.linewise, 'Comment: Toggle')
  map('x', '<M-/>', function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<ESC>', true, false, true), 'nx', false)
    comment.toggle.linewise(vim.fn.visualmode())
  end, 'Comment: Toggle')

  local function dial(dir, mode)
    return function()
      require('dial.map').manipulate(dir, mode)
      if mode == 'visual' or mode == 'gvisual' then
        vim.cmd 'normal! gv'
      end
    end
  end

  map('n', '<C-a>', dial('increment', 'normal'), 'Dial: Increment')
  map('n', '<C-x>', dial('decrement', 'normal'), 'Dial: Decrement')
  map('n', 'g<C-a>', dial('increment', 'gnormal'), 'Dial: Increment')
  map('n', 'g<C-x>', dial('decrement', 'gnormal'), 'Dial: Decrement')
  map('v', '<C-a>', dial('increment', 'visual'), 'Dial: Increment')
  map('v', '<C-x>', dial('decrement', 'visual'), 'Dial: Decrement')
  map('v', 'g<C-a>', dial('increment', 'gvisual'), 'Dial: Increment')
  map('v', 'g<C-x>', dial('decrement', 'gvisual'), 'Dial: Decrement')

  map('n', '[t', todo_comments.jump_prev, 'Todo Comments: Previous')
  map('n', ']t', todo_comments.jump_next, 'Todo Comments: Next')

  map('nxo', '<M-s>', function() require('flash').jump() end, { desc = 'Flash' })

  map('nxo', '<M-S-s>', function() require('flash').treesitter() end, { desc = 'Flash Treesitter' })

  map('nxo', xk '<C-M-S-s>', function() require('flash').treesitter_search() end, { desc = 'Flash Treesitter Search' })

  map('ox', 'r', function() require('flash').remote() end, { desc = 'Remote Flash' })

  map('ox', 'R', function() require('flash').treesitter_search() end, { desc = 'Treesitter Search' })

  map('cx', '<C-s>', function() require('flash').toggle() end, { desc = 'Toggle Flash Search' })
end)

---@type LazySpec[]
return {
  {
    'smjonas/live-command.nvim',
    main = 'live-command',
    event = 'CmdlineEnter',
    opts = {
      commands = {
        Norm = { cmd = 'norm' },
        S = { cmd = 'Subvert' },
      },
    },
  },
  {
    'benlubas/wrapping-paper.nvim',
    event = 'VeryLazy',
    opts = {},
    keys = {
      { '<M-->', function() require('wrapping-paper').wrap_line() end, mode = { 'n' } },
    },
  },
  {
    'brenton-leighton/multiple-cursors.nvim',
    opts = {},
    cmd = {
      'MultipleCursorsAddDown',
      'MultipleCursorsAddUp',
      'MultipleCursorsMouseAddDelete',
      'MultipleCursorsAddMatches',
      'MultipleCursorsAddMatchesV',
      'MultipleCursorsAddJumpNextMatch',
      'MultipleCursorsJumpNextMatch',
    },
    keys = {
      { '<C-Down>', '<Cmd>MultipleCursorsAddDown<CR>', mode = { 'n', 'i' } },
      { '<C-Up>', '<Cmd>MultipleCursorsAddUp<CR>', mode = { 'n', 'i' } },
      { '<C-LeftMouse>', '<Cmd>MultipleCursorsMouseAddDelete<CR>', mode = { 'n', 'i' } },
      { '<C-n>', '<Cmd>MultipleCursorsAddJumpNextMatch<CR>', mode = { 'n', 'x' } },
      { [[\\A]], '<Cmd>MultipleCursorsAddMatches<CR>', mode = { 'n', 'x' } },
      { [[\\|]], function() require('multiple-cursors').align() end, mode = { 'n', 'x' } },
      { '<C-n>', '<Cmd>MultipleCursorsAddVisualArea<CR>', mode = { 'x' } },
      { '<C-q>', '<Cmd>MultipleCursorsJumpNextMatch<CR>' },
    },
  },
  {
    'numToStr/Comment.nvim',
    config = function()
      local state = {}

      local ts_context_commentstring_pre_hook =
        require('ts_context_commentstring.integrations.comment_nvim').create_pre_hook()

      ---@diagnostic disable-next-line: missing-fields
      require('Comment').setup {
        pre_hook = function(ctx)
          -- If comment was triggered in visual mode, save the visual selection so it can be re-selected in post_hook
          if ctx.cmotion >= 3 and ctx.cmotion <= 5 then
            local c = vim.api.nvim_win_get_cursor(0)
            local m = {
              vim.api.nvim_buf_get_mark(0, '<'),
              vim.api.nvim_buf_get_mark(0, '>'),
            }
            if c[1] == m[1][1] then
              m = { m[2], m[1] }
            end
            state.marks = m
            state.cursor = c
            state.cursor_line_len = #(vim.api.nvim_buf_get_lines(0, c[1] - 1, c[1], true))[1]
          else
            state = {}
          end
          ---@diagnostic disable-next-line: return-type-mismatch
          return ts_context_commentstring_pre_hook(ctx) -- Adds support for JSX comments
        end,
        ---@diagnostic disable-next-line: unused-local
        post_hook = function(_ctx)
          vim.schedule(function()
            if state and state.marks and #state.marks > 0 then
              vim.api.nvim_buf_set_mark(0, '<', state.marks[1][1], state.marks[1][2], {})
              vim.api.nvim_buf_set_mark(0, '>', state.marks[2][1], state.marks[2][2], {})
              vim.cmd [[normal gv]]
              local c = state.cursor
              local diff = #(vim.api.nvim_buf_get_lines(0, c[1] - 1, c[1], true))[1] - state.cursor_line_len
              vim.api.nvim_win_set_cursor(0, { state.cursor[1], state.cursor[2] + diff })
              state = {}
            end
          end)
        end,
      }

      local ft = require 'Comment.ft'
      ft.set('capnp', { '#%s' })
      ft.set('cython', { '#%s' })
      ft.set('dosini', { '#%s' })
      ft.set('jq', { '#%s' })
      ft.set('sway', { '#%s' })
      ft.set('systemd', { '#%s' })
    end,
  },
  {
    'tpope/vim-repeat',
    event = 'VeryLazy',
  },
  {
    'kylechui/nvim-surround',
    event = 'VeryLazy',
    opts = {},
  },
  {
    'monaqa/dial.nvim',
    keys = {
      '<Plug>(dial-increment)',
      '<Plug>(dial-decrement)',
    },
    config = function()
      local augend = require 'dial.augend'
      require('dial.config').augends:register_group {
        default = {
          augend.integer.alias.decimal,
          augend.integer.alias.hex,
          augend.constant.new {
            elements = { 'false', 'true' },
            cyclic = false,
            preserve_case = true,
          },
          augend.constant.new {
            elements = { 'no', 'yes' },
            cyclic = false,
            preserve_case = true,
          },
          augend.constant.new {
            elements = { 'off', 'on' },
            cyclic = false,
            preserve_case = true,
          },
          augend.constant.alias.alpha,
          augend.constant.alias.Alpha,
          augend.semver.alias.semver,
          augend.date.alias['%Y/%m/%d'],
          augend.date.alias['%m/%d/%Y'],
          augend.date.alias['%d/%m/%Y'],
          augend.date.alias['%m/%d/%y'],
          augend.date.alias['%m/%d'],
          augend.date.alias['%Y-%m-%d'],
          augend.date.alias['%H:%M:%S'],
          augend.date.alias['%H:%M'],
          augend.constant.new {
            elements = { 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun' },
            word = true,
            cyclic = true,
          },
          augend.constant.new {
            elements = { 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday' },
            word = true,
            cyclic = true,
          },
        },
      }
    end,
  },
  {
    'WilliamHsieh/overlook.nvim',
    opts = {
      ui = {
        min_width = 100,
        z_index_base = 100,
      },
      adapters = {
        file = {
          get = function(path)
            local buf = vim.fn.bufnr(path, true)
            if buf == -1 then
              vim.notify('Overlook: Failed to get buf for file ' .. path, vim.log.levels.ERROR)
              return
            end
            ---@type OverlookPopupOptions
            return {
              target_bufnr = buf,
              col = 1,
              lnum = 1,
            }
          end,
        },
      },
    },
    keys = {
      {
        '<leader>pp',
        function() require('overlook.api').peek_definition() end,
        desc = 'Overlook: Peek definition',
      },
      {
        '<leader>pc',
        function() require('overlook.api').peek_cursor() end,
        desc = 'Overlook: Peek cursor',
      },
      { '<leader>pu', function() require('overlook.api').restore_popup() end, desc = 'Overlook: Restore' },
      {
        '<leader>pU',
        function() require('overlook.api').restore_all_popups() end,
        desc = 'Overlook: Restore all',
      },
      { '<leader>pq', function() require('overlook.api').close_all() end, desc = 'Overlook: Close all' },
      {
        '<leader>pf',
        function() require('overlook.api').switch_focus() end,
        desc = 'Overlook: Switch focus',
      },
      {
        '<leader>ps',
        function() require('overlook.api').open_in_split() end,
        desc = 'Overlook: Open in split',
      },
      {
        '<leader>pv',
        function() require('overlook.api').open_in_vsplit() end,
        desc = 'Overlook: Open in vsplit',
      },
      {
        '<leader>pt',
        function() require('overlook.api').open_in_tab() end,
        desc = 'Overlook: Open popup in tab',
      },
      { '<leader>po', function() require('overlook.api').open_in_original_window() end, desc = 'Overlook: Orig win' },
    },
  },
  {
    'matze/vim-move',
    init = function() vim.g.move_map_keys = false end,
    event = 'VeryLazy',
    config = function()
      local map = require('user.util.map').map

      ---@param dir 'Down' | 'Up'
      local function move_or_scroll(dir)
        return function()
          local fn = require 'user.fn'
          local win = vim.api.nvim_get_current_win()
          local noice_win = fn.find_noice_float()
          if noice_win then
            if require('noice.lsp').scroll(dir == 'Down' and 4 or -4) then
              return ''
            end
          end
          local diag_win = fn.find_diagnostic_float(win)
          if diag_win then
            -- TODO: scroll diagnostic float
            return ''
          end
          local dapui_win = fn.find_dapui_float()
          if dapui_win then
            -- TODO: scroll dapui float
            return ''
          end
          return '<Plug>MoveLine' .. dir
        end
      end

      map('n', '<C-j>', move_or_scroll 'Down', { remap = true, expr = true, desc = 'Move block down' })
      map('n', '<C-k>', move_or_scroll 'Up', { remap = true, expr = true, desc = 'Move block up' })

      map('n', '<C-h>', '<Plug>MoveCharLeft', { remap = true, desc = 'Move block left' })
      map('n', '<C-l>', '<Plug>MoveCharRight', { remap = true, desc = 'Move block right' })

      map('v', '<C-h>', '<Plug>MoveBlockLeft', { remap = true, desc = 'Move block left' })
      map('v', '<C-j>', '<Plug>MoveBlockDown', { remap = true, desc = 'Move block down' })
      map('v', '<C-k>', '<Plug>MoveBlockUp', { remap = true, desc = 'Move block up' })
      map('v', '<C-l>', '<Plug>MoveBlockRight', { remap = true, desc = 'Move block right' })
    end,
  },
  {
    -- TODO: revert when https://github.com/folke/todo-comments.nvim/pull/381 is merged
    'belltoy/todo-comments.nvim',
    -- 'folke/todo-comments.nvim',
    commit = 'dbe224bc0bd4378425cbd65602386f5846bd7354',
    event = 'VeryLazy',
    opts = {
      keywords = {
        TEST = { icon = ' ', color = 'test', alt = { 'TESTING', 'PASSED', 'FAILED' } },
        WARN = { icon = ' ', color = 'warning', alt = { 'WARNING' } },
        XXX = { icon = ' ', color = 'error' },
      },
      highlight = {
        pattern = { [[.*<(KEYWORDS)\s*(\(.+\))?\s*(:|$)]] },
        multiline = false,
        keyword = 'wide',
        after = 'fg',
      },
      search = {
        pattern = [[\b(KEYWORDS)\b]],
      },
    },
  },
  {
    'folke/flash.nvim',
    event = 'VeryLazy',
    opts = {
      labels = "fjdghksla;eiworuqpcnxmz,vbty'",
      search = {},
      jump = {
        autojump = true,
      },
      label = {
        uppercase = false,
      },
      modes = {
        treesitter = {
          labels = 'abcdefghijklmnopqrstuvwxyz',
          label = {
            uppercase = false,
            rainbow = {
              enabled = true,
              shade = 3,
            },
          },
        },
        treesitter_search = {
          labels = 'abcdefghijklmnopqrstuvwxyz',
          label = {
            uppercase = false,
            rainbow = {
              enabled = true,
              shade = 3,
            },
          },
        },
        char = {
          keys = { 'f', 'F', 't', 'T', [';'] = '<Tab>', [','] = '<S-Tab>' },
        },
      },
    },
  },
}
