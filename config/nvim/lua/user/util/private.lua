local ok, private = pcall(require, 'user.private')
if not ok then
  vim.defer_fn(
    function() vim.notify_once('[nvim-conf] Failed to load `lua/user/private.lua`', vim.log.levels.WARN) end,
    100
  )
  private = {}
end

---@cast private PrivateConfig
return private
