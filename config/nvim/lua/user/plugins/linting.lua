---@class Linter: lint.Linter
---@field name string

---@alias LinterSpec string|Linter

---@type { [string]: LinterSpec[] }
local linters_by_ft = {
  cpp = {
    -- { name = 'cppcheck', args = { '--enable=all', '--inconclusive' } },
    -- 'cpplint',
  },
  cmake = { 'cmakelint' },
}

---@type LazySpec[]
local spec = {
  {
    'mfussenegger/nvim-lint',
    ft = vim.tbl_keys(linters_by_ft),
    config = function()
      local lint = require 'lint'
      local by_ft = {}
      for ft, linters in pairs(linters_by_ft or {}) do
        for _, linter in ipairs(linters) do
          local linter_name = type(linter) == 'string' and linter or linter.name
          local linter_base = lint.linters[linter_name]
          if not linter_base then
            error('Unknown linter: ' .. linter_name)
          end
          ---@cast linter_base lint.Linter
          local extended = vim.tbl_deep_extend( --
            'force',
            vim.deepcopy(linter_base),
            type(linter) == 'table' and linter or {}
          )
          by_ft[ft] = by_ft[ft] or {}
          table.insert(by_ft[ft], linter_name)
          lint.linters[linter_name] = extended
        end
      end
      lint.linters_by_ft = by_ft

      vim.api.nvim_create_autocmd({ 'BufWritePost', 'BufReadPost', 'TextChanged', 'InsertLeave' }, {
        group = vim.api.nvim_create_augroup('user_lint', { clear = true }),
        callback = function(event)
          local bufnr = event.buf
          local ft = vim.bo[bufnr].filetype
          local linters = by_ft[ft]
          if not linters then
            return
          end
          -- If this is a TextChanged or InsertLeave event, only lint if there
          -- are linters for the filetype that can accept stdin
          if event.event == 'TextChanged' or event.event == 'InsertLeave' then
            local any_stdin = vim.iter(linters):any(function(linter_name)
              local linter = lint.linters[linter_name]
              return linter.stdin
            end)
            if not any_stdin then
              return
            end
          end
          lint.try_lint()
        end,
      })
    end,
  },
}

return spec
