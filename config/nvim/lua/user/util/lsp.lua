local M = {
  setup_called = false,
  config = {},
  servers = {},
  fmt_on_save_enabled = false,
  on_attach_called = false,
  inlay_hints_enabled_global = false,
  inlay_hints_enabled = {},
}

---If a diagnostic float is open, focus it
---Otherwise, hover over the symbol under the cursor
---@param cb? fun()
function M.hover(cb)
  cb = cb or vim.lsp.buf.hover
  local fn = require 'user.fn'
  local map = require('user.util.map').map
  local win = vim.api.nvim_get_current_win()
  local diag_win = fn.find_diagnostic_float(win)
  if diag_win then
    map(
      'n',
      '<M-i>',
      function() vim.api.nvim_win_close(diag_win, true) end,
      { buffer = vim.api.nvim_win_get_buf(diag_win) }
    )
    vim.api.nvim_set_current_win(diag_win)
    return
  end
  local dapui_win = fn.find_dapui_float()
  if dapui_win then
    map('n', '<M-i>', function() vim.cmd [[noautocmd wincmd p]] end, { buffer = vim.api.nvim_win_get_buf(dapui_win) })
    vim.api.nvim_set_current_win(dapui_win)
    return
  end
  cb()
end

function M.peek_definition()
  local params = vim.lsp.util.make_position_params(0, 'utf-8')
  return vim.lsp.buf_request(0, 'textDocument/definition', params, function(_, results)
    ---@type lsp.Location|lsp.LocationLink|nil
    local location = results and results[1]
    if not location then
      return
    end
    local range = location.range or location.targetRange
    if range then
      local lines = range['end'].line - range['start'].line + 1
      if lines < 20 then
        range['end'].line = range['start'].line + 20
        range['end'].character = 0
      end
    end
    vim.lsp.util.preview_location(location, { border = 'rounded' })
  end)
end

function M.set_inlay_hints_global(status)
  if status == nil then
    status = not M.inlay_hints_enabled_global
  end
  M.inlay_hints_enabled_global = status
  for bufnr, _ in pairs(M.inlay_hints_enabled) do
    M.set_inlay_hints(bufnr, status)
  end
end

---@param bufnr? number @the buffer number
---@param status? boolean @whether to enable inlay hints
function M.set_inlay_hints(bufnr, status)
  bufnr = require('user.util.api').resolve_bufnr(bufnr)
  if not bufnr then
    return
  end
  if status == nil then
    status = not M.inlay_hints_enabled[bufnr]
  end
  M.inlay_hints_enabled[bufnr] = status
  vim.lsp.inlay_hint.enable(status, { bufnr = bufnr })
end

M.on_attach = function(client, bufnr)
  if not M.setup_called then
    vim.notify('Error: user.lsp.on_attach: user.lsp.setup() has not been called yet', vim.log.levels.ERROR)
    return
  end
  if not M.on_attach_called then
    if M.config.on_first_attach then
      M.config.on_first_attach(client, bufnr)
    end
    M.on_attach_called = true
  end
  if M.config.on_attach then
    M.config.on_attach(client, bufnr)
  end
  vim.bo[bufnr].omnifunc = 'v:lua.vim.lsp.omnifunc'
  require('user.util.lsp_status').on_attach(client, bufnr)

  -- Disable default `K` keymap
  pcall(vim.keymap.del, 'n', 'K', { buffer = bufnr })

  -- Enable inlay hints if the client supports it.
  -- Credit @MariaSolOs:
  -- https://github.com/MariaSolOs/dotfiles/blob/8607ace4af5eb2e9001b3f14870c2ffc937f4dcd/.config/nvim/lua/lsp.lua#L118
  local methods = vim.lsp.protocol.Methods
  if methods and client.supports_method(methods.textDocument_inlayHint) then
    local inlay_hints_group = vim.api.nvim_create_augroup('InlayHints', { clear = true })

    -- Initial inlay hint display.
    if M.inlay_hints_enabled[bufnr] == nil then
      M.inlay_hints_enabled[bufnr] = M.inlay_hints_enabled_global
    end
    vim.lsp.inlay_hint.enable(M.inlay_hints_enabled[bufnr], { bufnr = bufnr })

    vim.api.nvim_create_autocmd('InsertEnter', {
      group = inlay_hints_group,
      buffer = bufnr,
      callback = function()
        if M.inlay_hints_enabled[bufnr] then
          vim.lsp.inlay_hint.enable(false, { bufnr = bufnr })
        end
      end,
    })
    vim.api.nvim_create_autocmd('InsertLeave', {
      group = inlay_hints_group,
      buffer = bufnr,
      callback = function()
        if M.inlay_hints_enabled[bufnr] then
          vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
        end
      end,
    })
  end
end

M.setup = function(config)
  if M.setup_called then
    vim.notify('Error: user.lsp.setup: user.lsp.setup() has already been called', vim.log.levels.ERROR)
    return
  end

  config = config or {}
  local servers = config.servers
  if not servers then
    vim.notify('No lsp_servers specified in config', vim.log.levels.WARN)
    return
  end

  M.setup_called = true
  M.config = config
  M.servers = servers

  vim.lsp.log.set_level(vim.log.levels.WARN)

  vim.lsp.handlers['textDocument/definition'] = function(_, result, ctx)
    if result == nil or vim.tbl_isempty(result) then
      vim.notify('Definition not found', vim.log.levels.WARN)
      return
    end
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    if client == nil then
      vim.notify('Client not found: ' .. ctx.client_id, vim.log.levels.WARN)
      return
    end
    local function jumpto(loc)
      local split_cmd = vim.uri_from_bufnr(0) == loc.targetUri and 'split' or 'tabnew'
      vim.cmd(split_cmd)
      vim.lsp.util.show_document(loc, client.offset_encoding, { focus = true })
    end
    if vim.islist(result) then
      jumpto(result[1])
      if #result > 1 then
        vim.fn.setqflist(vim.lsp.util.locations_to_items(result, client.offset_encoding))
        vim.api.nvim_command 'copen'
        vim.api.nvim_command 'wincmd p'
      end
    else
      jumpto(result)
    end
  end

  local capabilities = require('blink.cmp').get_lsp_capabilities()

  local function is_enabled(server)
    if type(server) == 'table' then
      return server.enabled ~= false
    end
    return true
  end

  for _, lsp in ipairs(vim.tbl_filter(is_enabled, servers)) do
    local opts = {
      on_attach = M.on_attach,
      on_exit = function(code, signal, id) require('user.util.lsp_status').on_exit(code, signal, id) end,
      flags = {
        debounce_text_changes = 150,
      },
      capabilities = capabilities,
    }
    local name = lsp
    if type(lsp) == 'table' then
      ---@diagnostic disable-next-line: cast-local-type
      name = lsp[1]
      if lsp.formatting ~= nil then
        local opts_on_attach = opts.on_attach
        opts.on_attach = function(client, bufnr)
          client.server_capabilities.documentFormattingProvider = lsp.formatting
          client.server_capabilities.documentRangeFormattingProvider = lsp.formatting
          return opts_on_attach(client, bufnr)
        end
        lsp.formatting = nil
      end
      if lsp.hover ~= nil then
        local opts_on_attach = opts.on_attach
        opts.on_attach = function(client, bufnr)
          client.server_capabilities.hoverProvider = lsp.hover
          return opts_on_attach(client, bufnr)
        end
        lsp.hover = nil
      end
      if lsp.on_attach ~= nil then
        local lsp_on_attach = lsp.on_attach
        local opts_on_attach = opts.on_attach
        opts.on_attach = function(client, bufnr)
          if lsp_on_attach(client, bufnr) == false then
            return false
          end
          return opts_on_attach(client, bufnr)
        end
        lsp.on_attach = nil
      end
      for k, v in pairs(lsp) do
        if k ~= 1 then
          opts[k] = v
        end
      end
    else
      name = lsp
    end
    vim.lsp.config(name, opts)
    vim.lsp.enable(name)
  end
end

return M
