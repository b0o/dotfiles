-- Originally based on https://github.com/lukahartwig/pnpm.nvim
-- Copyright 2023 Maddison Hellstrom
-- Copyright 2023 Luka Hartwig
-- MIT License

local Job = require 'plenary.job'
local Path = require 'user.util.path' ---@module 'plenary.path'
local util = require 'user.util.workspace.util'

---@class user.util.workspace.pnpm.PackageMeta
---@field name string|nil

---@class user.util.workspace.pnpm.PackageInfo
---@field path Path
---@field name string|nil
---@field root boolean
---@field current boolean
---@field relative_path string
---@field focused boolean

---@class user.util.workspace.pnpm.GetPackageInfoOpts
---@field root? string|Path
---@field focused_path? string|Path
---@field only_cached? boolean

---@class user.util.workspace.pnpm.WorkspaceInfo
---@field root user.util.workspace.pnpm.PackageInfo|nil @the root package
---@field focused user.util.workspace.pnpm.PackageInfo|nil @the focused package
---@field packages user.util.workspace.pnpm.PackageInfo[] @all packages

local M = {}

local cache = {
  ---@type table<string, Path|false>
  roots = {},
  ---@type table<string, Path[]>
  workspaces = {},
  ---@type table<string, user.util.workspace.pnpm.PackageMeta>
  package_meta = {},
}

local augroup = vim.api.nvim_create_augroup('pnpm', {})

---Get the paths of all packages in the workspace
---If opts.callback is provided, the function will run asynchronously and call the callback with the result,
---otherwise it will block until the result is available and return it.
---@param root_dir Path
---@param opts? user.util.workspace.GetWorkspacePackagePathsOpts
---@return Path[]|nil
M.get_workspace_package_paths = function(root_dir, opts)
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
      return
    end
    return
  end
  ---@type Path[]
  local res = {}
  ---@diagnostic disable-next-line: missing-fields
  local job = Job:new {
    command = 'pnpm',
    args = { 'ls', '--recursive', '--depth', '-1', '--parseable' },
    cwd = root_dir:absolute(),
    on_stdout = function(_, data) table.insert(res, Path:new(data)) end,
    on_exit = function(_, code)
      if code == 0 then
        cache.workspaces[abs_root] = res
      else
        cache.workspaces[abs_root] = nil
        vim.notify('pnpm ls exited with code ' .. code, vim.log.levels.ERROR)
      end
    end,
  }
  if cb then
    job:after(function()
      vim.schedule(function() cb(cache.workspaces[abs_root]) end)
    end)
    job:start()
    return
  end
  job:sync()
  return vim.deepcopy(cache.workspaces[abs_root])
end

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
    local ws = vim.fs.find('pnpm-workspace.yaml', {
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

---@param path Path
---@param opts? {only_cached?: boolean}
---@return user.util.workspace.pnpm.PackageMeta|nil
local function get_package_meta(path, opts)
  local abs_path = path:absolute()
  if cache.package_meta[abs_path] then
    return cache.package_meta[abs_path]
  end
  if opts and opts.only_cached then
    return
  end
  ---@type Path
  local package_json = path / 'package.json'
  ---@type boolean, string|nil
  local read_ok, package_json_data = pcall(function() return package_json:read() end)
  if not read_ok or not package_json_data or package_json_data == '' then
    return
  end
  ---@type boolean, user.util.workspace.pnpm.PackageMeta|nil
  local decode_ok, package_meta = pcall(vim.fn.json_decode, package_json_data)
  if not decode_ok or not package_meta then
    return
  end
  if type(package_meta) ~= 'table' then
    return
  end
  cache.package_meta[abs_path] = package_meta
  vim.api.nvim_create_autocmd('BufWritePost', {
    pattern = package_json:absolute(),
    group = augroup,
    once = true,
    callback = function()
      cache.package_meta[abs_path] = nil
      get_package_meta(path) -- replace with cached version
    end,
  })
  return package_meta
end

---@param path string|Path
---@param opts? user.util.workspace.pnpm.GetPackageInfoOpts
---@return user.util.workspace.pnpm.PackageInfo|nil
M.get_package_info = function(path, opts)
  opts = opts or {}
  local root = opts.root and Path:new(opts.root) or nil
  local focused_path = opts.focused_path and Path:new(opts.focused_path) or nil
  path = Path:new(path)
  local abs_path = path:absolute()
  local package_meta = get_package_meta(path, { only_cached = opts.only_cached })
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

M.clear_cache = function()
  cache.roots = {}
  cache.workspaces = {}
  cache.package_meta = {}
end

---@param opts? user.util.workspace.GetWorkspaceInfoOpts
---@return user.util.workspace.pnpm.WorkspaceInfo|nil|false
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
  return res
end

return M
