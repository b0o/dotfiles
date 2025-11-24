---@alias user.util.lsp_status.client_id integer

---@class user.util.lsp_status.ClientExitResult
---@field status 'exited'
---@field name string
---@field code integer
---@field signal integer
---@field attached_buffers integer[]

local M = {
  clients = {
    ---@type table<user.util.lsp_status.client_id, vim.lsp.Client>
    attached = {},
    ---@type table<user.util.lsp_status.client_id, user.util.lsp_status.ClientExitResult>
    exited = {},
  },
}

function M.on_attach(client, _)
  M.clients.attached[client.id] = client
  M.clients.exited[client.id] = nil
  for id, exitedClient in pairs(M.clients.exited) do
    if client.name == exitedClient.name then
      M.clients.exited[id] = nil
    end
  end
end

function M.on_exit(code, signal, id)
  local client = M.clients.attached[id]
  M.clients.exited[id] = {
    status = 'exited',
    name = client.name,
    code = code,
    signal = signal,
    attached_buffers = vim.deepcopy(client.attached_buffers),
  }
  M.clients.attached[id] = nil
  vim.notify(
    'LSP client ' .. client.name .. ' (' .. id .. ') exited with code ' .. code .. ' and signal ' .. signal
  )
end

---@param bufnr integer
---@param clients? table<integer, vim.lsp.Client|user.util.lsp_status.ClientExitResult>
---@return (vim.lsp.Client|user.util.lsp_status.ClientExitResult)[]
local function buf_clients(bufnr, clients)
  return vim.iter(clients and { clients } or { M.clients.exited, M.clients.attached })
      :flatten()
      :filter(
        function(client) ---@param client vim.lsp.Client|user.util.lsp_status.ClientExitResult
          return client.attached_buffers[bufnr] == true
        end)
      :totable()
end

function M.status_clients_count(status, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local clients = {}
  if status == 'exited' or status == 'exited_ok' or status == 'exited_err' then
    clients = buf_clients(bufnr, M.clients.exited)
  elseif status == 'running' or status == 'starting' then
    clients = buf_clients(bufnr, M.clients.attached)
  else
    error('Invalid status: ' .. status)
  end
  local count = 0
  for _, c in pairs(clients) do
    local skip = false
    if c.status == 'exited' then
      skip = skip or status == 'exited_ok' and c.signal ~= 0
      skip = skip or status == 'exited_err' and c.signal == 0
    else
      local initialized = c.initialized == true
      skip = skip or status == 'starting' and initialized
      skip = skip or status == 'running' and not initialized
    end
    count = skip and count or count + 1
  end
  return count
end

return M
