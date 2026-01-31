--- Monkey-patches for blink.cmp cmdline documentation support
--- Provides :help documentation for cmdline completions and fixes positioning with noice

local source = require 'user.plugins.blink.cmdline.docs.source'
local positioning = require 'user.plugins.blink.cmdline.docs.positioning'

local M = {}

function M.setup()
  source.patch()
  positioning.patch()
end

return M
