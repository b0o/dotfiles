-- Custom overseer lualine component with diagnostic counts for running tasks

---@class LualineOverseerComponent
---@field super { init: function }
---@field options { label?: string, colored?: boolean }
---@field format_hl fun(self: LualineOverseerComponent, hl: string): string
---@field create_hl fun(self: LualineOverseerComponent, color: table|string, text: string): string
local M = require('lualine.component'):extend()

local diagnostic_type_to_severity = {
  e = vim.diagnostic.severity.ERROR,
  E = vim.diagnostic.severity.ERROR,
  w = vim.diagnostic.severity.WARN,
  W = vim.diagnostic.severity.WARN,
  n = vim.diagnostic.severity.INFO,
  N = vim.diagnostic.severity.INFO,
  i = vim.diagnostic.severity.INFO,
  I = vim.diagnostic.severity.INFO,
}

local severity_to_icon = {
  [vim.diagnostic.severity.ERROR] = '',
  [vim.diagnostic.severity.WARN] = '',
  [vim.diagnostic.severity.INFO] = '',
}

---@param options? { label?: string, colored?: boolean }
function M:init(options)
  M.super.init(self, options)
  self.options.label = self.options.label or ''
  if self.options.colored == nil then
    self.options.colored = true
  end
  self.symbols = {
    ['FAILURE'] = '󰅚',
    ['CANCELED'] = '',
    ['SUCCESS'] = '󰄴',
    ['RUNNING'] = '󰑮',
  }
end

function M:update_colors()
  local constants = require 'overseer.constants'
  local STATUS = constants.STATUS
  local extract_color_from_hllist = require('lualine.utils.utils').extract_color_from_hllist
  self.highlight_groups = {}
  for _, status in ipairs(STATUS.values) do
    local hl = 'Overseer' .. status
    local color = { fg = extract_color_from_hllist('fg', { hl }, 'Normal') }
    self.highlight_groups[status] = self:create_hl(color, status)
  end
  for _, severity in ipairs { 'Error', 'Warn', 'Info' } do
    local hl = 'Diagnostic' .. severity
    local color = { fg = extract_color_from_hllist('fg', { hl }, 'Normal') }
    self.highlight_groups[vim.diagnostic.severity[string.upper(severity)]] = self:create_hl(color, severity)
  end
end

function M:update_status()
  if not package.loaded['overseer'] then
    return ''
  end

  if self.options.colored and not self.highlight_groups then
    self:update_colors()
  end

  local constants = require 'overseer.constants'
  local STATUS = constants.STATUS
  local task_list = require 'overseer.task_list'
  local util = require 'overseer.util'

  local tasks = task_list.list_tasks(self.options)
  ---@type { [string]: overseer.Task[] }
  local tasks_by_status = util.tbl_group_by(tasks, 'status')
  local statuses = {}
  local running_diagnostic_counts = {
    [vim.diagnostic.severity.ERROR] = 0,
    [vim.diagnostic.severity.WARN] = 0,
    [vim.diagnostic.severity.INFO] = 0,
  }
  if self.options.label ~= '' then
    table.insert(statuses, self.options.label)
  end
  for _, status in ipairs(STATUS.values) do
    local status_tasks = tasks_by_status[status]
    if self.symbols[status] and status_tasks then
      if self.options.colored then
        local hl_start = self:format_hl(self.highlight_groups[status])
        table.insert(statuses, string.format(' %s%s %s', hl_start, self.symbols[status], #status_tasks))
      else
        table.insert(statuses, string.format(' %s %s', self.symbols[status], #status_tasks))
      end
      if status == 'RUNNING' then
        for _, task in ipairs(status_tasks) do
          if task.result and task.result.diagnostics then
            for _, diagnostic in ipairs(task.result.diagnostics) do
              if diagnostic.type and diagnostic_type_to_severity[diagnostic.type] then
                local severity = diagnostic_type_to_severity[diagnostic.type]
                if not running_diagnostic_counts[severity] then
                  running_diagnostic_counts[severity] = {}
                end
                running_diagnostic_counts[severity] = running_diagnostic_counts[severity] + 1
              end
            end
          end
        end
      end
    end
  end
  for _, severity in ipairs { vim.diagnostic.severity.ERROR, vim.diagnostic.severity.WARN, vim.diagnostic.severity.INFO } do
    local count = running_diagnostic_counts[severity]
    if count > 0 then
      local hl_start = self:format_hl(self.highlight_groups[severity])
      table.insert(statuses, string.format(' %s%s %s', hl_start, severity_to_icon[severity], count))
    end
  end
  if #statuses > 0 then
    return table.concat(statuses, ' ')
  end
end

return M
