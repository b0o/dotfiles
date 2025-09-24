local M = {}

--- Processes the given options and returns a table of processed options
--- If the given options is a string, it's used as the description
--- If the given options is nil, the base options are used
--- The base are merged with the given options, with the given options taking precedence
---@param opts? string|table The options to process
---@param base? table The base options to merge with the given options
local process_opts = function(opts, base)
  opts = opts or {}
  if type(opts) == 'string' then
    opts = { desc = opts }
  elseif type(opts) ~= 'table' then
    error 'map: opts must be a string or table'
  end
  if base then
    opts = vim.tbl_extend('force', vim.deepcopy(base), opts)
  end
  return opts
end

---@param mode string|string[]  The mode(s) to map the key to, multi-char strings like 'nx' are allowed
---@param lhs string|string[]   The key to map, can be a single string or a list of strings for multiple keys
---@param rhs string|function   The rhs of the mapping
---@param opts? string|table    The options for the mapping, if string, it's the description, otherwise it's a table of options
M.map = function(mode, lhs, rhs, opts)
  mode = type(mode) == 'string' and vim.split(mode, '') or mode
  lhs = type(lhs) == 'table' and lhs or { lhs }
  opts = process_opts(opts, { silent = true })
  local args = opts.args or false -- include extra args when calling the rhs
  opts.args = nil

  -- wrap callable tables in a function
  if type(rhs) == 'table' then
    local meta = getmetatable(rhs)
    if not meta or not meta.__call then
      error 'map: rhs must be a function or callable table'
    end
    local orig_rhs = rhs
    rhs = function(...) return orig_rhs(...) end
  end

  for _, l in ipairs(lhs) do
    ---@cast l string
    if args then
      if type(rhs) ~= 'function' then
        error 'map: args can only be used with function rhs'
      end
      vim.keymap.set(mode, l, M.wrap(rhs, { lhs = l }), opts)
    else
      vim.keymap.set(mode, l, rhs, opts)
    end
  end
end

local ft_augroup = vim.api.nvim_create_augroup('user_mappings_ft', { clear = true })

--- Given a filetype and a function, creates an autocmd to call the function
--- when the FileType event is triggered. The function is called with a function
--- to create buffer mappings for the given filetype. It has the same signature
--- as map.map()
---@param ft string|string[] The filetype(s) to create the mapping for
---@param callback fun(bufmap: fun(mode: string|string[], lhs: string|string[], rhs: string|function, opts?: string|table), buf: number) The function to call to create the mappings
M.ft = function(ft, callback)
  ft = type(ft) == 'string' and { ft } or ft
  ---@cast ft string[]
  local cb = function(buf)
    callback(
      vim.schedule_wrap(
        function(mode, lhs, rhs, opts) return M.map(mode, lhs, rhs, process_opts(opts, { buffer = buf })) end
      ),
      buf
    )
  end
  vim.api.nvim_create_autocmd('FileType', {
    group = ft_augroup,
    pattern = ft,
    callback = function(event) cb(event.buf) end,
  })
  -- Iterate over open buffers and check if their filetype matches the given filetype,
  -- since that indicates their FileType event has already been triggered and we missed it
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local buf_ft = vim.bo[buf].filetype
    if vim.tbl_contains(ft, buf_ft) then
      cb(buf)
    end
  end
end

--- Given a buffer number, returns a function to create mappings for that buffer
--- The returned function has the same signature as map.map()
---@param bufnr number|nil The buffer number to create the mapping for
M.buf = function(bufnr)
  --- @param mode string|string[]  The mode(s) to map the key to, multi-char strings like 'nx' are allowed
  --- @param lhs string|string[]   The key to map, can be a single string or a list of strings for multiple keys
  --- @param rhs string|function   The rhs of the mapping
  --- @param opts? string|table    The options for the mapping, if string, it's the description, otherwise it's a table of options
  local function bufmap(mode, lhs, rhs, opts) return M.map(mode, lhs, rhs, process_opts(opts, { buffer = bufnr })) end
  return bufmap
end

--- Returns a function that calls func with the given arguments
--- If the returned function is called with arguments, they are passed after the given arguments
---@param func Callable The function to wrap
---@param ... any The arguments to pass to func
M.wrap = function(func, ...)
  local args = { ... }
  return function(...) return func(unpack(vim.list_extend(vim.list_extend({}, args), { ... }))) end
end

return M
