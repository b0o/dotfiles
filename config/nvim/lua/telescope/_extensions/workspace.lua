local Path = require 'plenary.path'

local t = require 'telescope'
local ta = require 'telescope.actions'
local tb = require 'telescope.builtin'
local tf = require 'telescope.finders'
local tp = require 'telescope.pickers'
local ts = require 'telescope.sorters'
local tv = require 'telescope.previewers'

local action_state = require 'telescope.actions.state'

local M = {}

local right_pad = function(s, len) return s .. string.rep(' ', len - #s) end

---@class WorkspacePackageOpts
---@field focused_path? string|Path @the path to use as the focused package
---@field refresh? boolean @whether to refresh the workspace cache
---@field grep? boolean @whether to use grep instead of find

local function get_focused_path(opts)
  if opts.focused_path then
    return Path:new(opts.focused_path)
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname ~= '' then
    return Path:new(bufname)
  end
  local last_focused_win = require('user.util.recent-wins').get_most_recent_smart()
  if last_focused_win and vim.api.nvim_win_is_valid(last_focused_win) then
    local last_focused_buf = vim.api.nvim_win_get_buf(last_focused_win)
    local last_focused_bufname = vim.api.nvim_buf_get_name(last_focused_buf)
    return Path:new(last_focused_bufname)
  end
  local cwd = vim.uv.cwd()
  assert(cwd ~= nil and cwd ~= '', 'Could not determine focused path')
  return Path:new(cwd)
end

---@param opts WorkspacePackageOpts
function M.workspace_packages(opts)
  opts = opts or {}
  local info = require('user.util.workspace').get_workspace_info {
    focused_path = get_focused_path(opts),
    refresh = opts.refresh,
  }
  if not info then
    vim.notify('No workspace detected', vim.log.levels.WARN)
    return
  end
  local max_path_len = 0
  for _, package in ipairs(info.packages) do
    max_path_len = math.max(max_path_len, #package.relative_path)
  end
  tp.new(opts, {
    prompt_title = 'Workspace packages',
    finder = tf.new_table {
      results = info.packages,
      entry_maker = function(entry)
        local status_icon = ' '
        if entry.focused then
          status_icon = ''
        elseif entry.current then
          status_icon = '•'
        end
        local kind_icon = ' '
        if entry.root then
          kind_icon = ''
        end
        return {
          value = entry,
          display = table.concat({
            kind_icon,
            status_icon,
            '/' .. right_pad(entry.relative_path, max_path_len),
            entry.name or vim.fs.basename(entry.relative_path),
          }, ' '),
          ordinal = (entry.name or '') .. ' ' .. entry.relative_path,
          path = entry.path:absolute(),
          name = entry.name or vim.fs.basename(entry.relative_path),
        }
      end,
    },
    previewer = tv.new_termopen_previewer {
      dyn_title = function(_, entry) return 'Package ' .. entry.name end,
      get_command = function(entry)
        return {
          'eza',
          '--color=always',
          '-T',
          '--group-directories-first',
          '--git-ignore',
          '-I',
          '.git',
          '-L2',
          entry.path,
        }
      end,
    },
    sorter = ts.get_fzy_sorter(),
    attach_mappings = function(prompt_bufnr, map)
      -- find files in package
      ta.select_default:replace(function()
        local entry = action_state.get_selected_entry().value
        ta.close(prompt_bufnr)
        vim.schedule(
          function()
            M.workspace_package_files(vim.tbl_extend('force', opts or {}, {
              focused_path = entry.path,
            }))
          end
        )
      end)
      -- reload workspace info
      map({ 'i', 'n' }, '<C-r>', function()
        ta.close(prompt_bufnr)
        vim.schedule(
          function()
            M.workspace_packages(vim.tbl_extend('force', opts or {}, {
              focused_path = info.focused.path,
              refresh = true,
            }))
          end
        )
      end)
      -- grep in package
      map({ 'i', 'n' }, '<M-a>', function()
        local entry = action_state.get_selected_entry().value
        ta.close(prompt_bufnr)
        vim.schedule(
          function()
            M.workspace_package_files(vim.tbl_extend('force', opts or {}, {
              focused_path = entry.path,
              grep = true,
            }))
          end
        )
      end)
      -- cd to package
      map({ 'i', 'n' }, '<C-i>', function()
        local entry = action_state.get_selected_entry().value
        ta.close(prompt_bufnr)
        vim.api.nvim_set_current_dir(entry.path:absolute())
      end)
      return true
    end,
  }):find()
end

---@param opts WorkspacePackageOpts
function M.workspace_package_files(opts)
  opts = opts or {}
  local info = require('user.util.workspace').get_workspace_info {
    focused_path = get_focused_path(opts),
    refresh = opts.refresh,
  }
  if not info then
    vim.notify('No workspace detected', vim.log.levels.WARN)
    return
  end
  local focused = info.focused or info.root
  if not focused then
    vim.notify('No focused package', vim.log.levels.WARN)
    return
  end
  local picker = opts.grep and tb.live_grep or tb.find_files
  local title = 'WS Package' .. (opts.grep and ' Grep' or ' Files')
  return picker(vim.tbl_extend('force', opts or {}, {
    prompt_title = (title .. ' ' .. (focused.name or (focused.relative_path and ('/' .. focused.relative_path) or ''))),
    cwd = focused.path:absolute(),
    attach_mappings = function(_, map)
      -- select a different package
      map({ 'i', 'n' }, '<C-o>', function(prompt_bufnr)
        ta.close(prompt_bufnr)
        vim.schedule(
          function()
            M.workspace_packages(vim.tbl_extend('force', opts or {}, {
              focused_path = focused.path,
            }))
          end
        )
      end)
      -- reload workspace info
      map({ 'i', 'n' }, '<C-r>', function(prompt_bufnr)
        ta.close(prompt_bufnr)
        vim.schedule(
          function()
            M.workspace_package_files(vim.tbl_extend('force', opts or {}, {
              focused_path = focused.path,
              refresh = true,
            }))
          end
        )
      end)
      -- toggle grep
      map({ 'i', 'n' }, '<M-a>', function(prompt_bufnr)
        ta.close(prompt_bufnr)
        vim.schedule(
          function()
            M.workspace_package_files(vim.tbl_extend('force', opts or {}, {
              focused_path = focused.path,
              grep = not opts.grep,
            }))
          end
        )
      end)
      return true
    end,
  }))
end

---@param opts WorkspacePackageOpts
function M.workspace_package_grep(opts)
  opts = opts or {}
  opts.grep = true
  return M.workspace_package_files(opts)
end

return t.register_extension {
  exports = {
    workspace_packages = M.workspace_packages,
    workspace_package_files = M.workspace_package_files,
    workspace_package_grep = M.workspace_package_grep,
  },
}
