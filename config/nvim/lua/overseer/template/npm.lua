-- Based on https://github.com/stevearc/overseer.nvim/blob/68a2d344cea4a2e11acfb5690dc8ecd1a1ec0ce0/lua/overseer/template/npm.lua
-- Modified to tweak how pnpm monorepos are handled:
-- - Use user.util.workspace.pnpm to get workspace info
-- - Give priority to focused workspace package scripts
-- - Simplify get_candidate_package_files so the nearest package.json from the cwd is used
local Path = require 'plenary.path'
local files = require 'overseer.files'
local overseer = require 'overseer'
local pnpm = require 'user.util.workspace.pnpm'

---@type { [string]: string[] }
local lockfiles = {
  npm = { 'package-lock.json' },
  pnpm = { 'pnpm-lock.yaml' },
  yarn = { 'yarn.lock' },
  bun = { 'bun.lock', 'bun.lockb' },
}

---@type overseer.TemplateFileDefinition
local tmpl = {
  priority = 60,
  params = {
    args = { optional = true, type = 'list', delimiter = ' ' },
    cwd = { optional = true },
    bin = { optional = true, type = 'string' },
    name = { optional = true, type = 'string' },
  },
  builder = function(params)
    return {
      cmd = { params.bin },
      args = params.args,
      cwd = params.cwd,
      name = params.name,
    }
  end,
}

---@param _opts overseer.SearchParams
local function get_candidate_package_files(_opts)
  return vim.fs.find('package.json', {
    upward = true,
    type = 'file',
    path = vim.fn.getcwd(),
  })
end

---@param opts overseer.SearchParams
---@return string|nil
local function get_package_file(opts)
  local candidate_packages = get_candidate_package_files(opts)
  -- go through candidate package files from closest to the file to least close
  for _, package in ipairs(candidate_packages) do
    local data = files.load_json_file(package)
    if data.scripts or data.workspaces then
      return package
    end
  end
  return nil
end

local function pick_package_manager(package_file)
  local package_dir = vim.fs.dirname(package_file)
  for mgr, candidates in pairs(lockfiles) do
    for _, lockfile in ipairs(candidates) do
      if files.exists(files.join(package_dir, lockfile)) then
        return mgr
      end
    end
  end
  return 'npm'
end

local function get_workspaces(package_mgr, package_json)
  if package_mgr == 'pnpm' then
    local info = pnpm.get_workspace_info {
      focused_path = Path:new(vim.api.nvim_buf_get_name(0)),
    }
    if info then
      return vim.tbl_map(
        function(p)
          return {
            path = p.relative_path,
            priority = p.focused and 0 or nil,
            name = p.name,
          }
        end,
        info.packages
      )
    end
  end
  return vim.tbl_map(function(p) return { path = p } end, package_json.workspaces or {})
end

return {
  cache_key = function(opts) return opts.dir end,
  condition = {
    callback = function(opts)
      local package_file = get_package_file(opts)
      if not package_file then
        return false, 'No package.json file found'
      end
      local package_manager = pick_package_manager(package_file)
      if vim.fn.executable(package_manager) == 0 then
        return false, string.format("Could not find command '%s'", package_manager)
      end
      return true
    end,
  },
  generator = function(opts, cb)
    local package = get_package_file(opts)
    if not package then
      cb {}
      return
    end
    local bin = pick_package_manager(package)
    local data = files.load_json_file(package)
    local ret = {}
    if data.scripts then
      for k in pairs(data.scripts) do
        local components = { 'default' }
        if k == 'tsc:watch' then
          table.insert(components, { 'on_output_parse', problem_matcher = '$tsc-watch' })
          table.insert(components, { 'on_result_notify', on_change = false })
        end
        if k == 'dev' then
          table.insert(components, {
            'on_output_parse',
            parser = {
              diagnostics = require('overseer.parser.lib').watcher_output(
                '^build: start',
                '^build: end',
                { 'extract', { regex = true }, '\\v^(error|warning|info):\\s+(.*)$', 'type', 'text' },
                {}
              ),
            },
          })
          table.insert(components, { 'on_result_notify', on_change = false })
        end

        table.insert(
          ret,
          overseer.wrap_template(tmpl, {
            name = string.format('%s run %s', bin, k),
            builder = function(params)
              params = tmpl.builder(params or {})
              params.components = vim.deepcopy(params.components or {})
              vim.list_extend(params.components, components)
              return params
            end,
          }, {
            args = { 'run', k },
            bin = bin,
            cwd = vim.fs.dirname(package),
          })
        )
      end
    end

    -- Load tasks from workspaces
    for _, workspace in ipairs(get_workspaces(bin, data)) do
      local workspace_path = files.join(vim.fs.dirname(package), workspace.path)
      local workspace_package_file = files.join(workspace_path, 'package.json')
      local workspace_data = files.load_json_file(workspace_package_file)
      if workspace_data then
        workspace_data.scripts = workspace_data.scripts or {}
        for k, v in
          pairs(vim.tbl_extend('force', {
            -- base tasks for all workspaces
            install = { args = { 'install' } },
          }, workspace_data.scripts))
        do
          v = v or {}
          if type(v) == 'string' then
            v = { args = { 'run', k } }
          end
          local name = string.format('[%s] %s %s', workspace.name or workspace.path, bin, k)
          table.insert(
            ret,
            overseer.wrap_template(tmpl, {
              name = name,
              priority = workspace.priority,
            }, {
              name = name,
              args = v.args,
              bin = v.bin or bin,
              cwd = v.cwd or workspace_path,
            })
          )
        end
      end
    end
    table.insert(ret, overseer.wrap_template(tmpl, { name = bin }, { bin = bin }))
    cb(ret)
  end,
}
