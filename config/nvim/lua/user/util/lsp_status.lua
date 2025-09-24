local M = {
  clients = { running = {}, exited = {} },
}

local function getClientData(client)
  return {
    client = client,
    buffers = vim.lsp.get_buffers_by_client_id(client.id),
  }
end

function M.on_attach(client, _)
  local clientData = getClientData(client)
  M.clients.running[client.id] = clientData
  M.clients.exited[client.id] = nil
  for id, exitedClientData in pairs(M.clients.exited) do
    if client.name == exitedClientData.client.name then
      M.clients.exited[id] = nil
    end
  end
end

function M.on_exit(code, signal, id)
  local data = M.clients.running[id]
  data.code = code
  data.signal = signal
  M.clients.exited[id] = data
  M.clients.running[id] = nil
  vim.notify(
    'LSP client ' .. data.client.name .. ' (' .. id .. ') exited with code ' .. code .. ' and signal ' .. signal
  )
end

local function getBufClients(bufnr, clients)
  local attached = {}
  for _, client in pairs(vim.lsp.get_clients { bufnr = bufnr }) do
    if clients[client.id] then
      table.insert(attached, clients[client.id])
    end
  end
  return attached
end

function M.getBufClients(bufnr)
  return getBufClients(bufnr, vim.list_extend(vim.list_extend({}, M.clients.running), M.clients.exited))
end

function M.getRunningBufClients(bufnr) return getBufClients(bufnr, M.clients.running) end

function M.getExitedBufClients(bufnr) return getBufClients(bufnr, M.clients.exited) end

function M.status_clients_count(status, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local clients = {}
  if status == 'exited' or status == 'exited_ok' or status == 'exited_err' then
    clients = M.getExitedBufClients(bufnr)
  elseif status == 'running' then
    clients = M.getRunningBufClients(bufnr)
  else
    clients = M.getBufClients(bufnr)
  end
  local count = 0
  for _, c in pairs(clients) do
    local skip = false
    skip = skip or status == 'exited_ok' and c.signal ~= 0
    skip = skip or status == 'exited_err' and c.signal == 0
    skip = skip or status == 'starting' and c.client.initialized
    skip = skip or status == 'running' and not c.client.initialized
    count = skip and count or count + 1
  end
  return count
end

return M
