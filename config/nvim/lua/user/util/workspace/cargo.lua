-- Originally based on https://github.com/lukahartwig/pnpm.nvim and ./pnpm.lua
-- Copyright 2023-2025 Maddison Hellstrom
-- Copyright 2023 Luka Hartwig
-- MIT License

local Path = require 'user.util.path' ---@module 'plenary.path'
local util = require 'user.util.workspace.util'

---@class user.util.workspace.cargo.PackageMeta
---@field id string
---@field name string|nil
---@field version string|nil
---@field manifest_path string|nil

---@class user.util.workspace.cargo.WorkspaceMeta
---@field packages user.util.workspace.cargo.PackageMeta[]
---@field workspace_members string[]
---@field workspace_root string

---@class user.util.workspace.cargo.PackageInfo
---@field path Path
---@field name string|nil
---@field root boolean
---@field current boolean
---@field relative_path string
---@field focused boolean

---@class user.util.workspace.cargo.GetPackageInfoOpts
---@field root? string|Path
---@field focused_path? string|Path
---@field only_cached? boolean

---@class user.util.workspace.cargo.WorkspaceInfo
---@field root user.util.workspace.cargo.PackageInfo|nil @the root package
---@field focused user.util.workspace.cargo.PackageInfo|nil @the focused package
---@field packages user.util.workspace.cargo.PackageInfo[] @all packages

---@class user.util.workspace.cargo.GetWorkspaceMetadataOpts
---@field only_cached? boolean @whether to only use cached data
---@field callback? fun(paths: user.util.workspace.cargo.WorkspaceMeta|nil) @the callback to call when the paths are found (get_workspace_package_paths will run asynchronously)

local M = {}

local cache = {
  ---@type table<string, Path|false>
  roots = {},
  ---@type table<string, user.util.workspace.cargo.WorkspaceMeta>
  workspaces = {},
}

---Get the paths of all packages in the workspace
---If opts.callback is provided, the function will run asynchronously and call the callback with the result,
---otherwise it will block until the result is available and return it.
---@param root_dir Path
---@param opts? user.util.workspace.cargo.GetWorkspaceMetadataOpts
---@return user.util.workspace.cargo.WorkspaceMeta|nil
M.get_workspace_metadata = function(root_dir, opts)
  root_dir = root_dir or util.cwd()
  local abs_root = root_dir:absolute()
  local cb = opts and opts.callback
  if cache.workspaces[abs_root] then
    local res = vim.deepcopy(cache.workspaces[abs_root])
    if cb then
      cb(res)
      return
    end
    return res
  end
  if opts and opts.only_cached then
    if cb then
      cb(nil)
    end
    return
  end
  local stdout = ''

  local on_complete = function(out)
    if out.code ~= 0 then
      vim.notify('cargo metadata exited with code ' .. tostring(out.code), vim.log.levels.ERROR)
      cache.workspaces[abs_root] = nil
      return nil
    end
    local data = vim.json.decode(stdout, { luanil = { object = true, array = true } })
    cache.workspaces[abs_root] = data
    return data
  end

  local job = vim.system({ 'cargo', 'metadata', '--format-version=1', '--no-deps', '--locked', '--offline' }, {
    cwd = abs_root,
    text = true,
    stdout = function(_, data)
      if data then
        stdout = stdout .. data
      end
    end,
    stderr = false,
  }, function(out)
    if cb then
      cb(on_complete(out))
    end
  end)
  if cb then
    return
  end
  local res = on_complete(job:wait())
  if not res then
    return nil
  end
  return vim.deepcopy(res)
end

---@param meta user.util.workspace.cargo.WorkspaceMeta
---@return Path[]
local function get_workspace_package_paths(meta)
  local paths = {}
  ---@type table<string, user.util.workspace.cargo.PackageMeta>
  local pkg_id_to_meta = {}
  for _, pkg in ipairs(meta.packages) do
    pkg_id_to_meta[pkg.id] = pkg
  end
  for _, id in ipairs(meta.workspace_members) do
    local package = pkg_id_to_meta[id]
    if package then
      local path = Path:new(package.manifest_path):parent()
      table.insert(paths, path)
    end
  end
  return paths
end

---Get the paths of all packages in the workspace
---If opts.callback is provided, the function will run asynchronously and call the callback with the result,
---otherwise it will block until the result is available and return it.
---@param root_dir? Path
---@param opts? user.util.workspace.GetWorkspacePackagePathsOpts
---@return Path[]|nil
M.get_workspace_package_paths = function(root_dir, opts)
  opts = opts or {}
  root_dir = root_dir or util.cwd()
  if opts.callback then
    return M.get_workspace_metadata(root_dir, {
      only_cached = opts.only_cached,
      callback = function(data) opts.callback(data and get_workspace_package_paths(data) or nil) end,
    })
  end
  local meta = M.get_workspace_metadata(root_dir, { only_cached = opts.only_cached })
  if not meta then
    return nil
  end
  return get_workspace_package_paths(meta)
end

---Get the root path of the cargo workspace
---Note: depends on Cargo.lock being present
---@param start_path? Path
---@param opts? {only_cached?: boolean}
---@return Path|nil|false @the root path, nil if not cached and only_cached is true, false if not found
M.get_root_path = function(start_path, opts)
  opts = opts or {}
  start_path = start_path or util.cwd()
  local abs_path = start_path:absolute()
  if cache.roots[abs_path] == nil then
    if opts.only_cached then
      return nil
    end
    local ws = vim.fs.find('Cargo.lock', {
      path = abs_path,
      upward = true,
      type = 'file',
    })[1]
    local root
    if not ws then
      root = false
    else
      root = Path:new(ws):parent()
    end
    cache.roots[abs_path] = root
  end
  return cache.roots[abs_path]
end

---@param root_path Path
---@param ws_path Path
---@param opts? {only_cached?: boolean}
---@return user.util.workspace.cargo.PackageMeta?
local function get_package_meta(root_path, ws_path, opts)
  opts = opts or {}
  local cargo_toml = Path:new(ws_path / 'Cargo.toml'):absolute()
  local root = root_path:absolute()
  ---@type user.util.workspace.cargo.WorkspaceMeta?
  local ws_meta = cache.workspaces[root]
  if not ws_meta then
    if opts.only_cached then
      return nil
    end
    ws_meta = M.get_workspace_metadata(root_path, { only_cached = false })
    if not ws_meta then
      return nil
    end
  end
  for _, pkg in ipairs(ws_meta.packages) do
    if pkg.manifest_path == cargo_toml then
      return pkg
    end
  end
  return nil
end

---@param path string|Path
---@param opts? user.util.workspace.cargo.GetPackageInfoOpts
---@return user.util.workspace.cargo.PackageInfo|nil
M.get_package_info = function(path, opts)
  opts = opts or {}
  local root = opts.root and Path:new(opts.root) or M.get_root_path()
  if not root then
    return
  end
  local focused_path = opts.focused_path and Path:new(opts.focused_path) or nil
  path = Path:new(path)
  local abs_path = path:absolute()
  local package_meta = get_package_meta(root, path, { only_cached = opts.only_cached })
  if not package_meta then
    return
  end
  local is_root = root ~= nil and abs_path == root:absolute()
  return {
    path = path,
    name = package_meta.name,
    root = is_root,
    current = abs_path == util.cwd():absolute(),
    relative_path = string.sub(abs_path, (root and #root:absolute() or 0) + 2),
    focused = not is_root and focused_path ~= nil and vim.startswith(focused_path:absolute(), abs_path),
  }
end

---@param opts? user.util.workspace.cargo.GetPackageInfoOpts
---@return user.util.workspace.cargo.PackageInfo|nil
M.get_root_package_info = function(opts)
  opts = opts or {}
  local root = M.get_root_path(Path:new(opts.focused_path or util.cwd()), {
    only_cached = opts.only_cached,
  })
  if not root then
    return
  end
  local info = M.get_package_info(root, opts)
  if info ~= nil then
    info.root = true
    return info
  end
  return {
    path = root,
    name = nil,
    root = true,
    current = false,
    relative_path = '',
    focused = false,
  }
end

M.clear_cache = function()
  cache.roots = {}
  cache.workspaces = {}
end

---@param opts? user.util.workspace.GetWorkspaceInfoOpts
---@return user.util.workspace.cargo.WorkspaceInfo|nil|false
M.get_workspace_info = function(opts)
  opts = opts or {}
  if opts.refresh then
    M.clear_cache()
  end
  local focused_path = Path:new(opts.focused_path or util.cwd())
  local root_dir = M.get_root_path(focused_path, {
    only_cached = opts.only_cached,
  })
  if not root_dir then
    -- root dir is either false or nil
    -- false indicates that the root dir was not found, while
    -- nil only indicates that the root dir has not been cached and
    -- that only_cached is true
    return root_dir
  end
  local paths = M.get_workspace_package_paths(root_dir, {
    only_cached = opts.only_cached,
  }) or {}
  local res = {
    root = nil,
    focused = nil,
    packages = {},
  }
  for _, path in ipairs(paths) do
    local package = M.get_package_info(path, {
      focused_path = focused_path,
      root = root_dir,
      only_cached = opts.only_cached,
    })
    if package then
      table.insert(res.packages, package)
      if package.root then
        res.root = package
        if not res.focused then
          res.focused = package
        end
      end
      if package.focused then
        res.focused = package
      end
    end
  end
  if not res.root then
    res.root = M.get_root_package_info {
      focused_path = focused_path,
      only_cached = opts.only_cached,
    }
    if res.root then
      table.insert(res.packages, res.root)
    end
  end
  return res
end

return M
