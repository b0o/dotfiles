local M = {}

local format_on_save = true

function M.set_format_on_save(val)
  format_on_save = val
  vim.notify('Format on save ' .. (val and 'enabled' or 'disabled'))
end

function M.toggle_format_on_save() M.set_format_on_save(not format_on_save) end

---@type table<string, conform.FormatterConfigOverride|fun(bufnr: integer): nil|conform.FormatterConfigOverride>
M.formatters = {
  -- SEE: https://pruner-formatter.github.io/guides/neovim-integration.html
  pruner = {
    command = 'pruner',
    args = function(_, ctx)
      local args = { 'format' }
      local textwidth = vim.api.nvim_get_option_value('textwidth', { buf = ctx.buf })
      if textwidth and textwidth > 0 then
        table.insert(args, '--print-width=' .. textwidth)
      end
      local filetype = vim.api.nvim_get_option_value('filetype', { buf = ctx.buf })
      if filetype then
        table.insert(args, '--lang=' .. filetype)
      end
      return args
    end,
    stdin = true,
  },
}

---@type table<string, conform.FiletypeFormatterInternal|fun(bufnr: integer):conform.FiletypeFormatterInternal>
-- TODO: Migrate language-specific config to Pruner config: ~/.config/pruner/config.toml
M.formatters_by_ft = {
  nix = { 'pruner' },
  nu = { 'pruner' },

  cmake = { 'gersemi' },
  glsl = { 'clang_format' },
  go = { 'gofmt', 'goimports' },
  lua = { 'stylua' },

  javascript = { 'dprint' },
  javascriptreact = { 'dprint' },
  typescript = { 'dprint' },
  typescriptreact = { 'dprint' },
  svelte = { 'dprint' },
  html = { 'dprint' },

  dockerfile = { 'dprint' },
  json = { 'dprint' },
  jsonc = { 'dprint' },
  markdown = { 'pruner' },
  mdx = { 'prettierd' }, -- TODO: Use dprint when MDX is supported: https://github.com/dprint/dprint-plugin-markdown/issues/93
  toml = { 'dprint' },

  css = { 'prettierd', 'stylelint' },
  graphql = { 'prettierd' },
  less = { 'prettierd' },
  scss = { 'prettierd' },
  yaml = { 'prettierd' },
  xml = { 'prettierd' },

  sh = { 'shfmt', 'shellharden' },
  bash = { 'shfmt', 'shellharden' },
  zsh = { 'shfmt', 'shellharden' },
}

---@param name string
---@param tbl conform.FormatterConfigOverride|fun(bufnr: integer): nil|conform.FormatterConfigOverride
---@param setup? boolean
function M.extend_formatter(name, tbl, setup)
  if not M.formatters[name] then
    M.formatters[name] = require('conform.formatters.' .. name)
  end
  ---@diagnostic disable-next-line: param-type-mismatch
  M.formatters[name] = vim.tbl_deep_extend('force', M.formatters[name], tbl)
  if setup == nil or setup == true then
    M.setup()
  end
end

---@param ft string
---@param formatter conform.FormatterConfigOverride|fun(bufnr: integer): nil|conform.FormatterConfigOverride
---@param setup? boolean
function M.set_formatter(ft, formatter, setup)
  M.formatters[ft] = formatter
  if setup == nil or setup == true then
    M.setup()
  end
end

---@param tbl table<string, conform.FormatterConfigOverride|(fun(bufnr: integer): nil|conform.FormatterConfigOverride)>
---@param merge? boolean
---@param setup? boolean
function M.set_formatters_by_ft(tbl, merge, setup)
  merge = merge == nil and true or merge
  if merge then
    M.formatters_by_ft = vim.tbl_deep_extend('force', M.formatters_by_ft, tbl)
  else
    ---@diagnostic disable-next-line: assign-type-mismatch
    M.formatters_by_ft = tbl
  end
  if setup == nil or setup == true then
    M.setup()
  end
end

function M.setup()
  require('conform').setup {
    log_level = vim.log.levels.DEBUG,
    notify_on_error = true,
    format_on_save = function(buf)
      if format_on_save then
        local ft = vim.bo[buf].filetype
        local formatter = M.formatters_by_ft[ft]
        local opts = {
          timeout_ms = 5000,
          lsp_format = 'fallback',
        }
        formatter = type(formatter) == 'function' and formatter(buf) or formatter
        if type(formatter) == 'table' and formatter.lsp_format ~= nil then
          opts.lsp_format = formatter.lsp_format
        end
        return opts
      end
    end,
    formatters = M.formatters,
    formatters_by_ft = M.formatters_by_ft,
  }
end

return M
