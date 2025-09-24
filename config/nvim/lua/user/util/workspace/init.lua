local M = {}

local Path = require 'user.util.path'
local util = require 'user.util.workspace.util'

local cargo = require 'user.util.workspace.cargo'
local pnpm = require 'user.util.workspace.pnpm'

---@alias user.util.workspace.WorkspaceType "pnpm"|"cargo"

---@alias user.util.workspace.WorkspaceInfo user.util.workspace.pnpm.WorkspaceInfo|user.util.workspace.cargo.WorkspaceInfo

---@class user.util.workspace.GetWorkspaceInfoOpts
---@field workspace_type? user.util.workspace.WorkspaceType
---@field focused_path? string|Path @the path to use as the focused package
---@field refresh? boolean @whether to refresh the cache
---@field only_cached? boolean @whether to only use cached data

---@class user.util.workspace.GetWorkspacePackagePathsOpts
---@field workspace_type? user.util.workspace.WorkspaceType
---@field only_cached? boolean @whether to only use cached data
---@field callback? fun(paths: Path[]|nil) @the callback to call when the paths are found (get_workspace_package_paths will run asynchronously)

---@param root_dir? Path
---@return user.util.workspace.WorkspaceType?
M.get_workspace_type = function(root_dir)
  root_dir = root_dir or util.cwd()
  local cargo_root = cargo.get_root_path(root_dir)
  if cargo_root then
    return 'cargo'
  end
  local pnpm_root = pnpm.get_root_path(root_dir)
  if pnpm_root then
    return 'pnpm'
  end
  return nil
end

---@param opts? user.util.workspace.GetWorkspaceInfoOpts
---@return user.util.workspace.WorkspaceInfo|nil|false
M.get_workspace_info = function(opts)
  opts = opts or {}
  local workspace_type = opts.workspace_type
    or M.get_workspace_type(opts.focused_path and Path:new(opts.focused_path) or nil)
  if not workspace_type then
    return
  end
  local workspace_info = function(info)
    return vim.tbl_extend('force', {
      type = workspace_type,
    }, info)
  end
  if workspace_type == 'pnpm' then
    return workspace_info(pnpm.get_workspace_info(opts))
  end
  if workspace_type == 'cargo' then
    return workspace_info(cargo.get_workspace_info(opts))
  end
end

---@param start_path? Path
---@param opts? {only_cached?: boolean, workspace_type?: user.util.workspace.WorkspaceType}
---@return Path|nil|false @the root path, nil if not cached and only_cached is true, false if not found
M.get_root_path = function(start_path, opts)
  opts = opts or {}
  local workspace_type = opts.workspace_type or M.get_workspace_type(start_path)
  if workspace_type == 'pnpm' then
    return pnpm.get_root_path(start_path, opts)
  end
  if workspace_type == 'cargo' then
    return cargo.get_root_path(start_path, opts)
  end
end

---@param root_dir? Path
---@param opts? user.util.workspace.GetWorkspacePackagePathsOpts
---@return Path[]|nil
M.get_workspace_package_paths = function(root_dir, opts)
  opts = opts or {}
  root_dir = root_dir or util.cwd()
  local workspace_type = opts.workspace_type or M.get_workspace_type(root_dir)
  if not workspace_type then
    return
  end
  if workspace_type == 'pnpm' then
    return pnpm.get_workspace_package_paths(root_dir, opts)
  end
  if workspace_type == 'cargo' then
    return cargo.get_workspace_package_paths(root_dir, opts)
  end
end

return M
