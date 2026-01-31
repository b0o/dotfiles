local xk = require('user.keys').xk

---@type LazySpec[]
return {
  {
    'supermaven-inc/supermaven-nvim',
    event = 'VeryLazy',
    enabled = true,
    config = function()
      require('supermaven-nvim').setup {
        disable_keymaps = true,
        ignore_filetypes = {
          ['dap-repl'] = true,
          dapui_scopes = true,
          dapui_breakpoints = true,
          dapui_stacks = true,
          dapui_watches = true,
          dapui_hover = true,
          Fyler = true,
        },
      }

      local c = require 'supermaven-nvim.completion_preview'
      local map = require('user.util.map').map

      map('i', { xk [[<C-\>]], '' }, c.on_accept_suggestion, 'SuperMaven: Accept')
      map('i', { [[<M-\>]] }, c.on_accept_suggestion_word, 'SuperMaven: Accept word')

      map('i', [[<M-right>]], function()
        local smu = require 'supermaven-nvim.util'
        local orig_to_next_word = smu.to_next_word
        ---@diagnostic disable-next-line: duplicate-set-field
        smu.to_next_word = function(str)
          local match = str:match '^.'
          if match ~= nil then
            return match
          end
          return ''
        end
        pcall(c.on_accept_suggestion_word)
        smu.to_next_word = orig_to_next_word
      end, 'SuperMaven: Accept next char')
    end,
  },
  {
    'NickvanDyke/opencode.nvim',
    event = 'VeryLazy',
    config = function()
      vim.g.opencode_opts = {}

      local cmd = vim.api.nvim_create_user_command
      cmd('OpencodeAsk', function(o) require('opencode').ask(o.args, {}) end, {
        nargs = '?',
        -- complete = 'customlist,v:lua.require"user.util.opencode".complete',
        desc = 'Opencode: Ask for a code snippet',
      })
    end,
  },
  -- {
  --   'milanglacier/minuet-ai.nvim',
  --   event = 'VeryLazy',
  --   config = function()
  --     require('minuet').setup {
  --       virtualtext = {
  --         auto_trigger_ft = { 'python' },
  --         keymap = {
  --           -- accept whole completion
  --           accept = xk [[<C-\>]],
  --           -- accept one line
  --           accept_line = xk [[<C-S-\>]],
  --           -- accept n lines (prompts for number)
  --           -- e.g. "A-z 2 CR" will accept 2 lines
  --           accept_n_lines = nil,
  --           prev = nil,
  --           next = nil,
  --           dismiss = nil,
  --         },
  --       },
  --       provider_options = {
  --         openai_compatible = {
  --           api_key = function() return require('user.private').cerebras_api_key end,
  --           -- model = 'qwen-3-235b-a22b-instruct-2507',
  --           model = 'zai-glm-4.7',
  --           end_point = 'https://api.cerebras.ai/v1/chat/completions',
  --           debounce = 250,
  --           throttle = 750,
  --           -- system = {
  --           --   -- prompt = function() return '/no_think\n' .. require('minuet.config').default_system.prompt end,
  --           --   prompt = function() return require('minuet.config').default_system_prefix_first.prompt end,
  --           -- },
  --           system = require('minuet.config').default_system_prefix_first,
  --           -- few_shots = function() return require('minuet.config').default_few_shots end,
  --           -- chat_input = {},
  --           stream = true,
  --           name = 'cerebras',
  --           optional = {
  --             max_tokens = 256,
  --             disable_reasoning = true,
  --             -- enable_thinking = false,
  --             -- reasoning_effort = 'low',
  --             -- reasoning_format = 'none',
  --           },
  --         },
  --       },
  --       provider = 'openai_compatible',
  --     }
  --   end,
  -- },
}
