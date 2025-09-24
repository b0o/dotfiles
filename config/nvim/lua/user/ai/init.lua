---@alias UserAiCopilot "copilot"|"gh_copilot"|"supermaven"

---@class UserAiConfig
---@field default_copilot? UserAiCopilot
---@field autostart? boolean

local M = {
  ---@type UserAiConfig
  config = {
    default_copilot = vim.g.ActiveCopilot,
    autostart = true,
  },
  state = {
    ---@type UserAiCopilot|nil
    active_copilot = nil,
  },
}

local notify = function(...)
  if M.silent then
    return
  end
  vim.notify(...)
end

---@class UserAiCopilotManager
---@field start fun()
---@field stop fun()

---@type {[UserAiCopilot]: UserAiCopilotManager}
local copilots = {
  copilot = {
    start = function()
      require('user.ai.copilot').enable()
    end,
    stop = function()
      require('user.ai.copilot').disable()
    end,
  },
  gh_copilot = {
    start = function()
      require('user.ai.gh_copilot').enable()
    end,
    stop = function()
      require('user.ai.gh_copilot').disable()
    end,
  },
  supermaven = {
    start = function()
      require('user.ai.supermaven').start()
    end,
    stop = function()
      require('user.ai.supermaven').stop()
    end,
  },
}

---@param copilot UserAiCopilot | nil
local set_active_copilot = function(copilot)
  if copilot then
    notify('Started Copilot: ' .. copilot)
  else
    notify('Stopped Copilot: ' .. M.state.active_copilot)
  end
  M.state.active_copilot = copilot
  vim.g.ActiveCopilot = copilot
end

---@param config? UserAiConfig
M.setup = function(config)
  M.config = vim.tbl_deep_extend('force', M.config, config or {})

  vim.api.nvim_create_user_command('CopilotStart', function(o)
    M.start_copilot(o.args and o.args ~= '' and o.args or nil)
  end, {
    nargs = '?',
    complete = function()
      return vim.tbl_keys(copilots)
    end,
  })

  vim.api.nvim_create_user_command('CopilotSelect', function(o)
    M.select_copilot(o.args and o.args ~= '' and o.args or nil)
  end, {
    nargs = 1,
    complete = function()
      return vim.tbl_keys(copilots)
    end,
  })

  vim.api.nvim_create_user_command('CopilotStop', function()
    M.stop_copilot()
  end, {})

  vim.api.nvim_create_user_command('CopilotRestart', function()
    M.stop_copilot()
    M.start_copilot()
  end, {})

  vim.api.nvim_create_user_command('CopilotStatus', function()
    local copilot = M.state.active_copilot or 'None'
    notify('Copilot: ' .. copilot)
  end, {})

  if M.config.autostart then
    local silent = M.silent
    M.silent = true
    M.start_copilot()
    M.silent = silent
  end
end

M.start_copilot = function(copilot_name)
  local selected = copilot_name or M.config.default_copilot
  local copilot = selected and copilots[selected]
  if not copilot then
    notify('Unknown copilot: ' .. selected, vim.log.levels.ERROR)
    return
  end
  if M.state.active_copilot then
    if M.state.active_copilot == selected then
      return
    end
    M.stop_copilot()
  end
  copilot.start()
  set_active_copilot(selected)
end

M.select_copilot = function(copilot_name)
  if not copilots[copilot_name] then
    notify('Unknown copilot: ' .. copilot_name, vim.log.levels.ERROR)
    return
  end
  M.config.default_copilot = copilot_name
  if M.state.active_copilot ~= copilot_name then
    M.start_copilot(copilot_name)
  end
end

M.stop_copilot = function()
  local copilot = M.state.active_copilot and copilots[M.state.active_copilot]
  if not copilot then
    return
  end
  copilot.stop()
  set_active_copilot(nil)
end

return M
