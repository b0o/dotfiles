-- Copy this file to lua/user/private.lua and edit it to add your private configuration.
-- lua/user/private.lua is ignored by git.

---@module 'obsidian'

---@class PrivateConfig
---@field obsidian_vault? obsidian.workspace.WorkspaceSpec
local M = {
  obsidian_vault = {
    name = 'name',
    path = '/path/to/obsidian/vault',
  },
}

return M
