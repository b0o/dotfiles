very_lazy(function()
  local maputil = require 'user.util.map'
  local map = maputil.map

  local neogit = lazy_require 'neogit'
  local git = lazy_require 'neogit.lib.git'
  local git_cli = lazy_require 'neogit.lib.git.cli'

  local neogit_action = function(...)
    local args = { ... }
    return function()
      local neogit_loaded = package.loaded['neogit'] ~= nil
      local action = require('neogit').action(unpack(args))
      if neogit_loaded then
        action()
      else
        require('plenary.async').void(function()
          require('neogit.lib.git').repo:dispatch_refresh {
            source = 'popup',
            callback = function() action() end,
          }
        end)()
      end
    end
  end

  local async_action = function(cmd, ...)
    local arg0 = ...
    local args = { select(2, ...) }
    return function()
      ---@diagnostic disable-next-line: missing-parameter
      require('plenary.async').run(function()
        if type(arg0) == 'function' then
          cmd(arg0(unpack(args)))
        else
          cmd(arg0, unpack(args))
        end
      end)
    end
  end

  local function open_neogit(opts)
    opts = vim.tbl_extend('force', {
      kind = 'vsplit',
      replace = true,
    }, opts or {})
    return function()
      if
        opts.replace
        and vim.bo.buftype == ''
        and vim.bo.filetype == ''
        and vim.bo.modified == false
        and vim.api.nvim_buf_line_count(0) == 1
        and vim.fn.getline '.' == ''
      then
        neogit.open { kind = 'replace' }
      else
        neogit.open { kind = opts.kind }
      end
    end
  end

  map('n', '<leader>gs', open_neogit { kind = 'vsplit' }, 'Neogit')
  map('n', '<leader>gg', open_neogit { kind = 'replace' }, 'Neogit (replace)')
  map('n', '<leader>G', open_neogit { kind = 'tab', replace = false }, 'Neogit (tab)')

  map(
    'n',
    { [[<leader>gA]], [[<leader>gaa]] },
    async_action(function()
      ---@diagnostic disable-next-line: undefined-field
      git_cli.add.args('--all').call()
    end),
    'Git: Add all'
  )
  map('n', [[<leader>gaf]], async_action(git.index.add, function() return { vim.fn.expand '%:p' } end), 'Git: Add file')

  map('n', '<leader>gC', '<Cmd>Neogit commit<Cr>', 'Neogit: Commit popup')
  map('n', '<leader>gcc', neogit_action('commit', 'commit', { '--verbose' }), 'Git: Commit')
  map('n', '<leader>gca', neogit_action('commit', 'commit', { '--verbose', '--all' }), 'Git: Commit (all)')
  map('n', '<leader>gcA', neogit_action('commit', 'commit', { '--verbose', '--amend' }), 'Git: Commit (amend)')

  map('n', '<leader>gl', '<Cmd>Neogit log<Cr>', 'Neogit: Log')

  map('n', '<leader>gp', '<Cmd>Neogit push<Cr>', 'Neogit: Push popup')
  map('n', '<leader>gP', '<Cmd>Neogit pull<Cr>', 'Neogit: Pull popup')

  ---@diagnostic disable-next-line: undefined-field
  map('n', '<leader>gR', async_action(git_cli.reset.call), 'Git: Reset')

  map('n', '<leader>cc', function()
    local actions = {
      GitConflictCurrent = 'ours',
      GitConflictCurrentLabel = 'ours',
      GitConflictAncestor = 'base',
      GitConflictAncestorLabel = 'base',
      GitConflictIncoming = 'theirs',
      GitConflictIncomingLabel = 'theirs',
    }
    local choose = function(which)
      vim.notify('Choosing ' .. which, vim.log.levels.INFO)
      require('git-conflict').choose(which)
    end
    local line = vim.api.nvim_get_current_line()
    if line == '=======' then
      choose 'both'
      return
    end
    local mark = vim
      .iter(vim.inspect_pos().extmarks)
      :find(function(e) return e.ns == 'git-conflict' and actions[e.opts.hl_group] end)
    if not mark then
      vim.notify('No conflict under cursor', vim.log.levels.WARN)
      return
    end
    choose(actions[mark.opts.hl_group])
  end, 'Git Conflict: Choose hunk under cursor')
end)

---@type LazySpec[]
return {
  {
    'lewis6991/gitsigns.nvim',
    cmd = { 'Gitsigns' },
    event = 'VeryLazy',
    config = function()
      local maputil = require 'user.util.map'
      local wrap = maputil.wrap

      require('gitsigns').setup {
        on_attach = function(bufnr)
          local function gitsigns_visual_op(op)
            return function() return require('gitsigns')[op] { vim.fn.line '.', vim.fn.line 'v' } end
          end
          local bufmap = maputil.buf(bufnr)
          local gs = require 'gitsigns'
          bufmap('n', '<leader>hs', gs.stage_hunk, 'Gitsigns: Stage hunk')
          bufmap('n', '<leader>hr', gs.reset_hunk, 'Gitsigns: Reset hunk')
          bufmap('n', '<leader>hu', gs.undo_stage_hunk, 'Gitsigns: Undo stage hunk')
          bufmap('x', '<leader>hs', gitsigns_visual_op 'stage_hunk', 'Gitsigns: Stage selected hunk(s)')
          bufmap('x', '<leader>hr', gitsigns_visual_op 'reset_hunk', 'Gitsigns: Reset selected hunk(s)')
          bufmap('x', '<leader>hu', gitsigns_visual_op 'undo_stage_hunk', 'Gitsigns: Undo stage hunk')
          bufmap('n', '<leader>hS', gs.stage_buffer, 'Gitsigns: Stage buffer')
          bufmap('n', '<leader>hR', gs.reset_buffer, 'Gitsigns: Reset buffer')
          bufmap('n', '<leader>hp', gs.preview_hunk, 'Gitsigns: Preview hunk')
          bufmap('n', '<leader>hb', wrap(gs.blame_line, { full = true }), 'Gitsigns: Blame hunk')
          bufmap('n', '<leader>htb', gs.toggle_current_line_blame, 'Gitsigns: Toggle current line blame')
          bufmap('n', '<leader>hd', gs.diffthis, 'Gitsigns: Diff this')
          bufmap('n', '<leader>htd', gs.toggle_deleted, 'Gitsigns: Toggle deleted')
          bufmap('n', '<leader>hD', wrap(gs.diffthis, '~'), 'Gitsigns: Diff this against last commit')
          bufmap('n', ']c', gs.next_hunk, 'Gitsigns: Next hunk')
          bufmap('n', '[c', gs.prev_hunk, 'Gitsigns: Prev hunk')
          bufmap('xo', 'ih', '<Cmd><C-U>Gitsigns select_hunk<Cr>', '[TextObj] Gitsigns: Inner hunk')
        end,
        signs = {
          add = { text = '│' },
          change = { text = '│' },
          delete = { text = '_' },
          topdelete = { text = '‾' },
          changedelete = { text = '~' },
          untracked = { text = '┆' },
        },
        attach_to_untracked = true,
        sign_priority = 100,
        preview_config = {
          border = 'rounded',
        },
      }
    end,
  },
  {
    'ruifm/gitlinker.nvim',
    cmd = { 'GitLink' },
    otps = {},
    keys = {
      {
        '<leader>gb',
        '<cmd>lua require"gitlinker".get_buf_range_url("n", {action_callback = require"gitlinker.actions".open_in_browser})<cr>',
        mode = 'n',
        desc = 'GitLinker: Open in browser',
      },
      {
        '<leader>gb',
        '<cmd>lua require"gitlinker".get_buf_range_url("v", {action_callback = require"gitlinker.actions".open_in_browser})<cr>',
        mode = 'v',
        desc = 'GitLinker: Open in browser',
      },
      {
        '<leader>gy',
        '<cmd>lua require"gitlinker".get_buf_range_url("n")<cr>',
        mode = 'n',
        desc = 'GitLinker: Copy URL',
      },
      {
        '<leader>gy',
        '<cmd>lua require"gitlinker".get_buf_range_url("v")<cr>',
        mode = 'v',
        desc = 'GitLinker: Copy URL',
      },
    },
  },
  {
    'NeogitOrg/neogit',
    cmd = 'Neogit',
    config = function()
      local maputil = require 'user.util.map'
      local ft = maputil.ft

      local neogit = require 'neogit'
      neogit.setup {
        disable_builtin_notifications = true,
        disable_insert_on_commit = true,
        console_timeout = math.huge,
        auto_show_console = false,
        commit_editor = {
          kind = 'floating',
          show_staged_diff = false,
        },
        signs = {
          hunk = { '', '' },
          item = { '', '' },
          section = { '', '' },
        },
        mappings = {
          popup = {
            ['Z'] = false,
            ['<M-s>'] = 'StashPopup',
          },
          finder = {
            ['<esc>'] = false,
          },
          status = {
            ['q'] = 'Close',
            ['K'] = false,
            ['<C-K>'] = 'Untrack',
            ['<cr>'] = false,
            ['<C-Cr>'] = 'GoToFile',
          },
        },
      }

      ft('NeogitStatus', function(bufmap)
        local function neogit_status_buf_item()
          local status = require('neogit.buffers.status').instance()
          if not status then
            return
          end
          local sel = status.buffer.ui:get_item_under_cursor()
          if not sel or not sel.absolute_path then
            return
          end
          return sel
        end
        bufmap('n', '<M-w>', function()
          local item = neogit_status_buf_item()
          if not item then
            return
          end
          local win = require('window-picker').pick_window()
          if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_set_buf(win, vim.fn.bufadd(item.absolute_path))
            vim.api.nvim_set_current_win(win)
          end
        end)
        bufmap('n', '<Cr>', function()
          local item = neogit_status_buf_item()
          if not item then
            return
          end
          local prev_win = require('user.util.recent-wins').get_most_recent()
          if not prev_win or not vim.api.nvim_win_is_valid(prev_win or -1) then
            vim.cmd('vsplit ' .. item.name)
          else
            vim.api.nvim_win_set_buf(prev_win, vim.fn.bufadd(item.absolute_path))
          end
        end)
        bufmap('n', 'Q', function() neogit.close() end, 'Neogit: Close')
        bufmap('n', 'K', '5k', 'Jump up')
      end)

      local augroup = vim.api.nvim_create_augroup('user.neogit', {})

      -- Neogit uses the filetype `NeogitCommitMessage` for the commit message buffer.
      -- this causes some problems and has no real benefit, so we switch it back to
      -- `gitcommit`.
      -- https://github.com/NeogitOrg/neogit/issues/405#issuecomment-1374652332
      vim.api.nvim_create_autocmd('FileType', {
        group = augroup,
        pattern = 'NeogitCommitMessage',
        command = 'silent! set filetype=gitcommit buflisted',
      })

      -- Unmap <esc> in NeogitLogView
      vim.api.nvim_create_autocmd('FileType', {
        group = augroup,
        pattern = 'NeogitLogView',
        callback = function()
          vim.defer_fn(function() vim.api.nvim_buf_del_keymap(0, 'n', '<esc>') end, 200)
        end,
      })
    end,
  },
  {
    'mattn/gist-vim',
    dependencies = 'mattn/webapi-vim',
    cmd = 'Gist',
  },
  {
    'sindrets/diffview.nvim',
    cmd = {
      'DiffviewClose',
      'DiffviewFileHistory',
      'DiffviewFocusFiles',
      'DiffviewLog',
      'DiffviewOpen',
      'DiffviewRefresh',
      'DiffviewToggleFiles',
      'DiffviewOpenPr',
    },
    config = function()
      local diffview = require 'diffview'
      diffview.setup {}

      -- usage: DiffviewOpenPr [<pr-number>]
      vim.api.nvim_create_user_command('DiffviewOpenPr', function(args)
        local pr_str = args.args
        if pr_str == '' then
          pr_str = vim.fn.input 'PR number: '
        end
        if pr_str == '' then
          vim.notify('No PR number provided', vim.log.levels.WARN)
          return
        end
        local pr_number = tonumber(pr_str)
        if not pr_number then
          vim.notify('Invalid PR number: ' .. pr_str, vim.log.levels.WARN)
          return
        end
        local range = require('user.util.git').gh_pr_range(pr_number)
        if not range then
          vim.notify('Failed to get PR range', vim.log.levels.WARN)
          return
        end
        local range_str = table.concat(range, '..')
        diffview.open { range_str }
        vim.notify(string.format('Opening Diffview for PR #%d (%s)', pr_number, range_str))
      end, {
        nargs = '?',
      })
    end,
  },
  {
    'akinsho/git-conflict.nvim',
    opts = {
      default_commands = true,
      disable_diagnostics = true,
      list_opener = 'botright copen',
      default_mappings = {
        next = ']C',
        prev = '[C',
      },
    },
    event = 'VeryLazy',
  },
  {
    'moyiz/git-dev.nvim',
    cmd = { 'GitDevOpen', 'GitDevCleanAll' },
    opts = {
      ephemeral = false,
      read_only = false,
    },
  },
}
