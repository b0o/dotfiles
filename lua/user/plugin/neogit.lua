local neogit = require 'neogit'

neogit.setup {
  -- Hides the hints at the top of the status buffer
  -- disable_hint = false,
  -- Disables changing the buffer highlights based on where the cursor is.
  -- disable_context_highlighting = false,
  -- Disables signs for sections/items/hunks
  -- disable_signs = false,
  -- Do not ask to confirm the commit - just do it when the buffer is closed.
  -- disable_commit_confirmation = false,
  -- Uses `vim.notify` instead of the built-in notification system.
  disable_builtin_notifications = true,
  -- Changes what mode the Commit Editor starts in. `true` will leave nvim in normal mode, `false` will change nvim to insert mode, and `"auto"` will change nvim to insert mode IF the commit message is empty, otherwise leaving it in normal mode.
  disable_insert_on_commit = true,
  -- Allows a different telescope sorter. Defaults to 'fuzzy_with_index_bias'. The example below will use the native fzf
  -- sorter instead. By default, this function returns `nil`.
  -- telescope_sorter = function()
  --   return require('telescope').extensions.fzf.native_fzf_sorter()
  -- end,
  -- Persist the values of switches/options within and across sessions
  -- remember_settings = true,
  -- Scope persisted settings on a per-project basis
  -- use_per_project_settings = true,
  -- Table of settings to never persist. Uses format "Filetype--cli-value"
  -- ignored_settings = {
  --   'NeogitPushPopup--force-with-lease',
  --   'NeogitPushPopup--force',
  --   'NeogitPullPopup--rebase',
  --   'NeogitCommitPopup--allow-empty',
  --   'NeogitRevertPopup--no-edit',
  -- },
  -- Neogit refreshes its internal state after specific events, which can be expensive depending on the repository size.
  -- Disabling `auto_refresh` will make it so you have to manually refresh the status after you open it.
  -- auto_refresh = true,
  -- Value used for `--sort` option for `git branch` command
  -- By default, branches will be sorted by commit date descending
  -- Flag description: https://git-scm.com/docs/git-branch#Documentation/git-branch.txt---sortltkeygt
  -- Sorting keys: https://git-scm.com/docs/git-for-each-ref#_options
  -- sort_branches = '-committerdate',
  -- Change the default way of opening neogit
  -- kind = 'tab',
  -- The time after which an output console is shown for slow running commands
  -- console_timeout = 2000,
  -- Automatically show console if a command takes more than console_timeout milliseconds
  auto_show_console = false, -- disable annoying console window when commiting with fugitive
  -- status = {
  --   recent_commit_count = 10,
  -- },
  -- commit_editor = {
  --   kind = 'floating',
  -- },
  -- commit_select_view = {
  --   kind = 'floating',
  -- },
  -- commit_view = {
  --   kind = 'vsplit',
  -- },
  -- log_view = {
  -- kind = 'floating',
  -- },
  -- rebase_editor = {
  --   kind = 'split',
  -- },
  -- reflog_view = {
  --   kind = 'tab',
  -- },
  -- merge_editor = {
  --   kind = 'split',
  -- },
  -- preview_buffer = {
  --   kind = 'split',
  -- },
  -- popup = {
  --   kind = 'split',
  -- },
  signs = {
    -- { CLOSED, OPENED }
    hunk = { '', '' },
    item = { '', '' },
    section = { '', '' },
  },
  -- Each Integration is auto-detected through plugin presence, however, it can be disabled by setting to `false`
  -- integrations = {
  -- If enabled, use telescope for menu selection rather than vim.ui.select.
  -- Allows multi-select and some things that vim.ui.select doesn't.
  -- telescope = nil,
  -- Neogit only provides inline diffs. If you want a more traditional way to look at diffs, you can use `diffview`.
  -- The diffview integration enables the diff popup.
  --
  -- Requires you to have `sindrets/diffview.nvim` installed.
  -- diffview = false,
  -- },
  -- sections = {
  --   -- Reverting/Cherry Picking
  --   sequencer = {
  --     folded = false,
  --     hidden = false,
  --   },
  --   untracked = {
  --     folded = false,
  --     hidden = false,
  --   },
  --   unstaged = {
  --     folded = false,
  --     hidden = false,
  --   },
  --   staged = {
  --     folded = false,
  --     hidden = false,
  --   },
  --   stashes = {
  --     folded = true,
  --     hidden = false,
  --   },
  --   unpulled_upstream = {
  --     folded = true,
  --     hidden = false,
  --   },
  --   unmerged_upstream = {
  --     folded = false,
  --     hidden = false,
  --   },
  --   unpulled_pushRemote = {
  --     folded = true,
  --     hidden = false,
  --   },
  --   unmerged_pushRemote = {
  --     folded = false,
  --     hidden = false,
  --   },
  --   recent = {
  --     folded = true,
  --     hidden = false,
  --   },
  --   rebase = {
  --     folded = true,
  --     hidden = false,
  --   },
  -- },
  mappings = {
    popup = {
      ['Z'] = false,
      ['<M-s>'] = 'StashPopup',
    },
    finder = {
      --   ['<cr>'] = 'Select',
      --   ['<c-c>'] = 'Close',
      ['<esc>'] = false,
      --   ['<c-n>'] = 'Next',
      --   ['<c-p>'] = 'Previous',
      --   ['<down>'] = 'Next',
      --   ['<up>'] = 'Previous',
      --   ['<tab>'] = 'MultiselectToggleNext',
      --   ['<s-tab>'] = 'MultiselectTogglePrevious',
      --   ['<c-j>'] = 'NOP',
    },
    -- Setting any of these to `false` will disable the mapping.
    status = {
      -- ['q'] = 'Close',
      -- ['I'] = 'InitRepo',
      -- ['1'] = 'Depth1',
      -- ['2'] = 'Depth2',
      -- ['3'] = 'Depth3',
      -- ['4'] = 'Depth4',
      -- ['<tab>'] = 'Toggle',
      -- ['x'] = 'Discard',
      -- ['s'] = 'Stage',
      -- ['S'] = 'StageUnstaged',
      -- ['<c-s>'] = 'StageAll',
      -- ['u'] = 'Unstage',
      -- ['U'] = 'UnstageStaged',
      -- ['d'] = 'DiffAtFile',
      -- ['$'] = 'CommandHistory',
      -- ['#'] = 'Console',
      -- ['<c-r>'] = 'RefreshBuffer',
      -- ['<enter>'] = 'VSplitOpen',
      -- ['<c-v>'] = 'VSplitOpen',
      -- ['<c-x>'] = 'SplitOpen',
      -- ['<c-t>'] = 'TabOpen',
      -- ['?'] = 'HelpPopup',
      -- ['D'] = 'DiffPopup',
      -- ['p'] = 'PullPopup',
      -- ['r'] = 'RebasePopup',
      -- ['m'] = 'MergePopup',
      -- ['P'] = 'PushPopup',
      -- ['c'] = 'CommitPopup',
      -- ['l'] = 'LogPopup',
      -- ['v'] = 'RevertPopup',
      -- ['A'] = 'CherryPickPopup',
      -- ['b'] = 'BranchPopup',
      -- ['f'] = 'FetchPopup',
      -- ['X'] = 'ResetPopup',
      -- ['M'] = 'RemotePopup',
      -- ['{'] = 'GoToPreviousHunkHeader',
      -- ['}'] = 'GoToNextHunkHeader',
    },
  },
}
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
    vim.defer_fn(function()
      vim.api.nvim_buf_del_keymap(0, 'n', '<esc>')
    end, 200)
  end,
})
