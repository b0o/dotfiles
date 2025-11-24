---@type LazySpec[]
return {
  {
    'folke/snacks.nvim',
    priority = 1000,
    lazy = false,
    config = function()
      local Snacks = require 'snacks'
      local maputil = require 'user.util.map'
      local map = maputil.map

      Snacks.setup {
        bigfile = {
          enabled = true,
          notify = true,
          size = 1.5 * 1024 * 1024, -- 1.5MB
          -- Enable or disable features when big file detected
          ---@param ctx {buf: number, ft:string}
          setup = function(ctx)
            ---@diagnostic disable-next-line: missing-fields
            Snacks.util.wo(0, {
              foldmethod = 'manual',
              statuscolumn = '',
              conceallevel = 0,
            })
            vim.schedule(function() vim.bo[ctx.buf].syntax = ctx.ft end)
          end,
        },
        notifier = {
          enabled = true,
          margin = { top = 2, right = 1, bottom = 1 },
          style = 'fancy',
          filter = function(notif)
            local ignores = {
              '^No information available$',
              '^client.supports_method is deprecated',
              '^Error requesting document symbols$',
            }
            return not vim.iter(ignores):any(
            ---@param pat string
              function(pat) return string.find(notif.msg, pat) ~= nil end
            )
          end,
        },
        quickfile = { enabled = true },
        statuscolumn = { enabled = true },
        terminal = { enabled = false },
        words = { enabled = true },
        indent = {
          enabled = true,
          indent = { enabled = true },
          animate = { enabled = false },
          scope = { enabled = true, only_current = true },
        },
        scratch = { enabled = true },
        scope = {
          enabled = true,
          keys = {
            ---@type table<string, snacks.scope.TextObject|{desc?:string}>
            textobject = {
              ii = {
                min_size = 2,
                edge = false,
                cursor = true,
                desc = 'inside scope',
              },
              ai = {
                cursor = true,
                edge = true,
                min_size = 2,
                desc = 'around scope',
              },
            },
            ---@type table<string, snacks.scope.Jump|{desc?:string}>
            jump = {
              ['[s'] = {
                min_size = 2,
                bottom = false,
                cursor = true,
                edge = true,
                desc = 'Scope: start',
              },
              [']s'] = {
                min_size = 2,
                bottom = true,
                cursor = true,
                edge = true,
                desc = 'Scope: end',
              },
            },
          },
        },
      }

      vim.api.nvim_create_user_command(
        'Bdelete',
        function(opts) Snacks.bufdelete.delete { force = opts.bang == true } end,
        { bang = true }
      )

      vim.api.nvim_create_user_command(
        'Gbrowse',
        function() Snacks.gitbrowse() end,
        {}
      )

      vim.api.nvim_create_user_command(
        'Notifications',
        function() Snacks.notifier.show_history() end,
        {}
      )

      vim.api.nvim_create_user_command(
        'Scratch',
        function() Snacks.scratch() end,
        {}
      )

      vim.api.nvim_create_user_command(
        'ScratchSelect',
        function() Snacks.scratch.select() end,
        {}
      )

      map('n', ')', function() Snacks.words.jump(vim.v.count1, true) end, 'Snacks: Jump to next word')

      map('n', '(', function() Snacks.words.jump(-vim.v.count1, true) end, 'Snacks: Jump to prev word')
    end,
  },
}
