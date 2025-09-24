-- Re-export Path from plenary.path with fixed type annotations

---@class Path
---@field new fun(self: Path, path: string|Path): Path
local Path = require 'plenary.path'

return Path
