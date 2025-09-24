---@meta

---@class CallableTable
---@operator call:any

---@alias Callable fun(...)|CallableTable

---@class AutocmdEvent
---@field id number @the id of the autocommand
---@field event string @the name of the triggered event
---@field group number|nil @the autocommand group id, if any
---@field match string @the expanded value of <amatch>
---@field buf number @the expanded value of <abuf>
---@field file string @the expanded value of <afile>
---@field data any @arbitrary data passed from `nvim_exec_autocmds()`
