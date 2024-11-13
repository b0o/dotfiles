---@type LazySpec[]
local spec = {
  {
    'kyazdani42/nvim-tree.lua',
    branch = '2948-add-user-decorators',
    cmd = { 'NvimTreeOpen', 'NvimTreeFocus' },
    dependencies = {
      {
        'b0o/nvim-tree-preview.lua',
        dev = true,
      },
    },
    config = function()
      local api = require 'nvim-tree.api'
      local preview = require 'nvim-tree-preview'

      local on_attach = function(bufnr)
        local function opts(desc)
          return { desc = 'nvim-tree: ' .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
        end

        vim.keymap.set('n', '<Tab>', function()
          local ok, node = pcall(api.tree.get_node_under_cursor)
          if ok and node then
            if node.type == 'directory' then
              api.node.open.edit()
            else
              preview.node(node, { toggle_focus = true })
            end
          end
        end, opts 'Preview')
        vim.keymap.set('n', 'P', preview.watch, opts 'Preview (Watch)')
        vim.keymap.set('n', '<Esc>', preview.unwatch, opts 'Close Preview/Unwatch')
        vim.keymap.set('n', '<C-j>', function()
          preview.scroll(4)
        end, opts 'Preview: Scroll Down')
        vim.keymap.set('n', '<C-k>', function()
          preview.scroll(-4)
        end, opts 'Preview: Scroll Up')

        local function get_visual_nodes()
          local core = require 'nvim-tree.core'
          local view = require 'nvim-tree.view'
          local utils = require 'nvim-tree.utils'
          if not core.get_explorer() then
            return
          end
          local winnr = view.get_winnr()
          if not winnr then
            return
          end
          local start = vim.api.nvim_buf_get_mark(0, '<')[1]
          local end_ = vim.api.nvim_buf_get_mark(0, '>')[1]
          local nodes = utils.get_nodes_by_line(core.get_explorer().nodes, core.get_nodes_starting_line())
          return vim.list_slice(nodes, start, end_)
        end

        local update_qflist = function(entries)
          local current_qflist = vim.fn.getqflist()
          local filtered = vim
            .iter(entries)
            :filter(function(entry)
              return not vim.iter(current_qflist):any(function(qfl)
                return qfl.bufnr == vim.fn.bufnr(entry.filename)
              end)
            end)
            :totable()
          if #entries > 0 and #filtered == 0 then
            local replace = vim
              .iter(current_qflist)
              :filter(function(qfl)
                return not vim.iter(entries):any(function(entry)
                  return qfl.bufnr == vim.fn.bufnr(entry.filename)
                end)
              end)
              :totable()
            vim.fn.setqflist(replace, 'r')
          else
            vim.fn.setqflist(filtered, 'a')
          end
          require('nvim-tree.api').tree.reload()
        end

        vim.keymap.set('n', '<C-q>', function()
          local ok, node = pcall(api.tree.get_node_under_cursor)
          if ok and node and node.name ~= '..' and node.type ~= 'directory' then
            update_qflist { { filename = node.absolute_path, lnum = 1, col = 1 } }
          end
        end, opts 'Add to Quickfix')

        vim.keymap.set('v', '<C-q>', function()
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<esc>', true, false, true), 'n', false)
          vim.schedule(function()
            local ok, nodes = pcall(get_visual_nodes)
            if ok and nodes then
              local entries = vim
                .iter(nodes)
                :filter(function(node)
                  return node.name ~= '..' and node.type ~= 'directory'
                end)
                :map(function(node)
                  return { filename = node.absolute_path, lnum = 1, col = 1 }
                end)
                :totable()
              update_qflist(entries)
            end
          end)
        end, opts 'Add to Quickfix')

        -- BEGIN_DEFAULT_ON_ATTACH
        vim.keymap.set('n', '<C-]>', api.tree.change_root_to_node, opts 'CD')
        vim.keymap.set('n', '<C-e>', api.node.open.replace_tree_buffer, opts 'Open: In Place')
        -- vim.keymap.set('n', '<C-k>', api.node.show_info_popup, opts 'Info')
        vim.keymap.set('n', '<C-r>', api.fs.rename_sub, opts 'Rename: Omit Filename')
        vim.keymap.set('n', '<C-t>', api.node.open.tab, opts 'Open: New Tab')
        vim.keymap.set('n', '<C-v>', api.node.open.vertical, opts 'Open: Vertical Split')
        vim.keymap.set('n', '<C-x>', api.node.open.horizontal, opts 'Open: Horizontal Split')
        vim.keymap.set('n', '<BS>', api.node.navigate.parent_close, opts 'Close Directory')
        vim.keymap.set('n', '<CR>', api.node.open.edit, opts 'Open')
        -- vim.keymap.set('n', '<Tab>', api.node.open.preview, opts 'Open Preview')
        vim.keymap.set('n', '>', api.node.navigate.sibling.next, opts 'Next Sibling')
        vim.keymap.set('n', '<', api.node.navigate.sibling.prev, opts 'Previous Sibling')
        vim.keymap.set('n', '.', api.node.run.cmd, opts 'Run Command')
        vim.keymap.set('n', '-', api.tree.change_root_to_parent, opts 'Up')
        vim.keymap.set('n', 'a', api.fs.create, opts 'Create File Or Directory')
        -- vim.keymap.set('n', 'bd', api.marks.bulk.delete, opts 'Delete Bookmarked')
        vim.keymap.set('n', 'bt', api.marks.bulk.trash, opts 'Trash Bookmarked')
        vim.keymap.set('n', 'bmv', api.marks.bulk.move, opts 'Move Bookmarked')
        vim.keymap.set('n', 'B', api.tree.toggle_no_buffer_filter, opts 'Toggle Filter: No Buffer')
        vim.keymap.set('n', 'c', api.fs.copy.node, opts 'Copy')
        vim.keymap.set('n', 'C', api.tree.toggle_git_clean_filter, opts 'Toggle Filter: Git Clean')
        vim.keymap.set('n', '[c', api.node.navigate.git.prev, opts 'Prev Git')
        vim.keymap.set('n', ']c', api.node.navigate.git.next, opts 'Next Git')
        vim.keymap.set('n', 'd', api.fs.remove, opts 'Delete')
        vim.keymap.set('n', 'D', api.fs.trash, opts 'Trash')
        vim.keymap.set('n', 'E', api.tree.expand_all, opts 'Expand All')
        vim.keymap.set('n', 'e', api.fs.rename_basename, opts 'Rename: Basename')
        vim.keymap.set('n', ']e', api.node.navigate.diagnostics.next, opts 'Next Diagnostic')
        vim.keymap.set('n', '[e', api.node.navigate.diagnostics.prev, opts 'Prev Diagnostic')
        vim.keymap.set('n', 'F', api.live_filter.clear, opts 'Live Filter: Clear')
        vim.keymap.set('n', 'f', api.live_filter.start, opts 'Live Filter: Start')
        vim.keymap.set('n', 'g?', api.tree.toggle_help, opts 'Help')
        vim.keymap.set('n', 'gy', api.fs.copy.absolute_path, opts 'Copy Absolute Path')
        vim.keymap.set('n', 'H', api.tree.toggle_hidden_filter, opts 'Toggle Filter: Dotfiles')
        vim.keymap.set('n', 'I', api.tree.toggle_gitignore_filter, opts 'Toggle Filter: Git Ignore')
        vim.keymap.set('n', 'J', api.node.navigate.sibling.last, opts 'Last Sibling')
        vim.keymap.set('n', 'K', api.node.navigate.sibling.first, opts 'First Sibling')
        vim.keymap.set('n', 'M', api.tree.toggle_no_bookmark_filter, opts 'Toggle Filter: No Bookmark')
        vim.keymap.set('n', 'm', api.marks.toggle, opts 'Toggle Bookmark')
        vim.keymap.set('n', 'o', api.node.open.edit, opts 'Open')
        vim.keymap.set('n', 'O', api.node.open.no_window_picker, opts 'Open: No Window Picker')
        vim.keymap.set('n', 'p', api.fs.paste, opts 'Paste')
        -- vim.keymap.set('n', 'P', api.node.navigate.parent, opts 'Parent Directory')
        vim.keymap.set('n', 'q', api.tree.close, opts 'Close')
        vim.keymap.set('n', 'r', api.fs.rename, opts 'Rename')
        vim.keymap.set('n', 'R', api.tree.reload, opts 'Refresh')
        vim.keymap.set('n', 's', api.node.run.system, opts 'Run System')
        vim.keymap.set('n', 'S', api.tree.search_node, opts 'Search')
        vim.keymap.set('n', 'u', api.fs.rename_full, opts 'Rename: Full Path')
        vim.keymap.set('n', 'U', api.tree.toggle_custom_filter, opts 'Toggle Filter: Hidden')
        vim.keymap.set('n', 'W', api.tree.collapse_all, opts 'Collapse')
        vim.keymap.set('n', 'x', api.fs.cut, opts 'Cut')
        vim.keymap.set('n', 'y', api.fs.copy.filename, opts 'Copy Name')
        vim.keymap.set('n', 'Y', api.fs.copy.relative_path, opts 'Copy Relative Path')
        vim.keymap.set('n', '<2-LeftMouse>', api.node.open.edit, opts 'Open')
        vim.keymap.set('n', '<2-RightMouse>', api.tree.change_root_to_node, opts 'CD')
        -- END_DEFAULT_ON_ATTACH
      end

      require('nvim-tree').setup {
        actions = {
          open_file = {
            window_picker = {
              enable = true,
              picker = function()
                return require('window-picker').pick_window {
                  filter_rules = {
                    file_path_contains = { 'nvim-tree-preview://' },
                  },
                }
              end,
            },
          },
          file_popup = {
            open_win_config = {
              border = 'rounded',
            },
          },
        },
        open_on_tab = true,
        hijack_cursor = true,
        update_cwd = true,
        respect_buf_cwd = true,
        diagnostics = {
          enable = true,
          icons = { error = '', warning = '', hint = '', info = '' },
        },
        update_focused_file = {
          enable = true,
        },
        system_open = {
          cmd = 'xdg-open',
        },
        filters = {
          custom = {
            '.git',
            'node_modules',
            '.cache',
            '.vscode',
            '.turbo',
            '.bruno',
          },
          exclude = { '[.]env', '[.]env[.].*' },
        },
        renderer = {
          indent_markers = { enable = true },
          highlight_git = 'none',
          highlight_opened_files = 'all',
          add_trailing = true,
          group_empty = true,
          icons = {
            git_placement = 'after',
            glyphs = {
              default = '',
              symlink = '',
              git = {
                deleted = '',
                ignored = '◌',
                renamed = '➜',
                staged = '+',
                unmerged = '',
                unstaged = 'ϟ',
                untracked = '?',
              },
              folder = {
                arrow_open = '',
                arrow_closed = '',
                default = '',
                open = '',
                empty = '',
                empty_open = '',
                symlink = '',
                symlink_open = '',
              },
            },
          },
          user_decorators = {
            {
              class = require 'user.plugins.nvim-tree.decorator-quickfix',
            },
          },
        },
        view = {
          adaptive_size = false,
        },
        on_attach = on_attach,
      }

      require('nvim-tree.commands').setup()
    end,
  },
}

very_lazy(function()
  local fn = require 'user.fn'
  local maputil = require 'user.util.map'
  local recent_wins = lazy_require 'user.util.recent-wins'
  local xk = require('user.keys').xk

  local map = maputil.map
  local ft = maputil.ft
  local wrap = maputil.wrap

  map('n', xk '<C-S-\\>', function()
    if require('nvim-tree.view').is_visible() then
      require('nvim-tree.view').close()
    else
      require('nvim-tree.lib').open()
      recent_wins.focus_most_recent()
    end
  end, 'Nvim-Tree: Toggle')

  map(
    'n',
    xk '<C-\\>',
    fn.filetype_command('NvimTree', recent_wins.focus_most_recent, wrap(vim.cmd, [[NvimTreeFocus]])),
    'Nvim-Tree: Toggle Focus'
  )

  local function nvim_tree_open_oil(enter)
    return function()
      local oil = require 'oil'
      local tree = require('nvim-tree.api').tree
      local node = tree.get_node_under_cursor()
      if not node then
        return
      end
      local path, is_dir
      if node and node.fs_stat then
        local fs_stat = node.fs_stat
        is_dir = fs_stat.type == 'directory'
        path = is_dir and enter and node.absolute_path or node.parent.absolute_path
      else
        ---@type string
        ---@diagnostic disable-next-line: undefined-field
        local base = tree.get_nodes().absolute_path
        is_dir = node.name == '..' or node.name == '.'
        path = enter and node.name == '..' and base .. '/..' or base
      end

      if is_dir and enter then
        oil.toggle_float(path)
        return
      end

      local function bufenter_cb(e, tries)
        if not oil.get_entry_on_line(e.buf, 1) then
          tries = tries or 0
          if tries <= 8 then
            vim.defer_fn(function()
              bufenter_cb(e, tries + 1)
            end, tries * tries)
          end
          return
        end
        for i = 1, vim.api.nvim_buf_line_count(e.buf) do
          local entry = oil.get_entry_on_line(e.buf, i)
          if entry and entry.name == node.name then
            vim.api.nvim_win_set_cursor(0, { i, 0 })
            break
          end
        end
      end

      vim.api.nvim_create_autocmd('BufEnter', {
        once = true,
        pattern = 'oil://*',
        callback = bufenter_cb,
      })

      oil.toggle_float(path)
    end
  end

  ft('NvimTree', function(bufmap)
    local function withSelected(cmd, fmt)
      return function()
        local node = require('nvim-tree.lib').get_node_at_cursor()
        if not node then
          return
        end
        if type(cmd) == 'function' then
          cmd(node)
          return
        end
        local file = node.absolute_path
        vim.cmd(fmt and (cmd):format(file) or ('%s %s'):format(cmd, file))
      end
    end

    bufmap('n', 'ga', withSelected 'Git add', 'Nvim-Tree: Git add')
    bufmap('n', 'gr', withSelected 'Git reset --quiet', 'Nvim-Tree: Git reset')
    bufmap('n', 'gb', withSelected 'tabnew | Git blame', 'Nvim-Tree: Git blame')
    bufmap('n', 'gd', withSelected 'tabnew | Gdiffsplit', 'Nvim-Tree: Git diff')

    bufmap(
      'n',
      'bd',
      withSelected(function(node)
        local bufnr = vim.fn.bufnr(node.absolute_path)
        local wins = require('user.util.api').buf_get_wins(bufnr)
        if #wins > 0 then
          local ok = vim.fn.confirm('Delete buffer ' .. node.name .. '?', '&Yes\n&No', 2) == 1
          if not ok then
            return
          end
        end
        require('bufdelete').bufdelete(bufnr)
      end),
      'Nvim-Tree: Bdelete'
    )

    bufmap('n', 'i', nvim_tree_open_oil(false), 'Nvim-Tree: Open Oil')
    bufmap('n', '<M-i>', nvim_tree_open_oil(true), 'Nvim-Tree: Open Oil (enter dir)')
  end)
end)

return spec
