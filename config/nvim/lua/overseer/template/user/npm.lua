-- Custom npm template with pnpm monorepo support:
-- - Uses user.util.workspace.pnpm for workspace info
-- - Prioritizes focused workspace package scripts

local Path = require 'plenary.path'
local files = require 'overseer.files'
local pnpm = require 'user.util.workspace.pnpm'

---@type { [string]: string[] }
local lockfiles = {
  npm = { 'package-lock.json' },
  pnpm = { 'pnpm-lock.yaml' },
  yarn = { 'yarn.lock' },
  bun = { 'bun.lock', 'bun.lockb' },
}

---@param _opts overseer.SearchParams
---@diagnostic disable-next-line: unused-local
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
      if files.exists(vim.fs.joinpath(package_dir, lockfile)) then
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
            focused = p.focused,
            name = p.name,
          }
        end,
        info.packages
      )
    end
  end
  return vim.tbl_map(function(p) return { path = p } end, package_json.workspaces or {})
end

---@type overseer.TemplateFileProvider
return {
  cache_key = function(opts) return opts.dir end,
  generator = function(opts, cb)
    local package = get_package_file(opts)
    if not package then
      cb 'No package.json file found'
      return
    end
    local bin = pick_package_manager(package)
    if vim.fn.executable(bin) == 0 then
      cb(string.format("Could not find command '%s'", bin))
      return
    end

    local data = files.load_json_file(package)
    local ret = {}
    local cwd = vim.fs.dirname(package)

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
              diagnostics = {
                { 'extract', { regex = true }, '\\v^(error|warning|info):\\s+(.*)$', 'type', 'text' },
              },
            },
          })
          table.insert(components, { 'on_result_notify', on_change = false })
        end

        table.insert(ret, {
          name = string.format('%s run %s', bin, k),
          builder = function()
            return {
              cmd = { bin, 'run', k },
              cwd = cwd,
              components = components,
            }
          end,
        })
      end
    end

    -- Load tasks from workspaces
    for _, workspace in ipairs(get_workspaces(bin, data)) do
      local workspace_path = vim.fs.joinpath(cwd, workspace.path)
      local workspace_package_file = vim.fs.joinpath(workspace_path, 'package.json')
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
          local task_name = string.format('[%s] %s %s', workspace.name or workspace.path, bin, k)
          local task_bin = v.bin or bin
          local task_cwd = v.cwd or workspace_path
          local task_args = v.args
          local task = {
            name = task_name,
            builder = function()
              return {
                cmd = { task_bin },
                args = task_args,
                cwd = task_cwd,
              }
            end,
          }

          if workspace.focused then
            table.insert(ret, 1, task)
          else
            table.insert(ret, task)
          end
        end
      end
    end

    -- Add bare package manager command
    table.insert(ret, {
      name = bin,
      builder = function()
        return {
          cmd = { bin },
          cwd = cwd,
        }
      end,
    })

    cb(ret)
  end,
}
