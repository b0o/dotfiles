---- zbirenbaum/copilot.lua
local M = {}

local copilot = require 'copilot'
local copilot_api = require 'copilot.api'
local copilot_suggestion = require 'copilot.suggestion'
local copilot_panel = require 'copilot.panel'
local xk = require('user.keys').xk

local is_setup = false
local ns = vim.api.nvim_create_namespace 'user.copilot'

local function setup()
  if is_setup then
    return
  end

  copilot.setup {
    panel = {
      enabled = false,
      auto_refresh = true,
      keymap = {
        jump_prev = '[[',
        jump_next = ']]',
        accept = '<CR>',
        refresh = 'gr',
        open = '<M-CR>',
      },
      layout = {
        position = 'bottom', -- | top | left | right
        ratio = 0.4,
      },
    },
    suggestion = {
      enabled = true,
      auto_trigger = true,
      debounce = 75,
      keymap = {
        accept = false,
        accept_word = false,
        accept_line = false,
        next = false,
        prev = false,
        dismiss = false,
        -- accept = '<M-l>',
        -- accept_word = false,
        -- accept_line = false,
        -- next = '<M-]>',
        -- prev = '<M-[>',
        -- dismiss = '<C-]>',
      },
    },
    filetypes = {
      yaml = true,
      markdown = true,
      help = true,
      gitcommit = true,
      gitrebase = true,
      hgcommit = true,
      svn = true,
      cvs = true,
      oil = false,
      ['.'] = true,
    },
    -- Node.js version must be > 16.x
    copilot_node_command = vim.env.HOME .. '/.asdf/shims/node',
    server_opts_overrides = {},
  }

  copilot_api.register_status_notification_handler(function(data)
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
    if vim.fn.mode() == 'i' and data.status == 'InProgress' then
      vim.api.nvim_buf_set_extmark(0, ns, vim.fn.line '.' - 1, 0, {
        virt_text = { { ' 🤖Thinking...', 'Comment' } },
        virt_text_pos = 'eol',
        hl_mode = 'combine',
      })
    end
  end)

  is_setup = true
end

local copilot_accept_or_insert = function(action, fallback)
  return function()
    if copilot_suggestion.is_visible() then
      copilot_suggestion[action]()
    elseif fallback then
      vim.api.nvim_put(vim.split(fallback, '\n'), 'c', false, true)
    end
  end
end

M.enable = function()
  if not is_setup then
    setup()
  else
    require('copilot.command').enable()
  end

  vim.keymap.set('i', xk [[<C-\>]], copilot_accept_or_insert('accept', '\n'), { silent = true })
  vim.keymap.set('i', [[^\]], copilot_accept_or_insert('accept', '\n'), { silent = true })
  vim.keymap.set('i', [[<M-\>]], copilot_accept_or_insert 'accept_word', { silent = true })
  vim.keymap.set('i', xk [[<M-S-\>]], copilot_accept_or_insert('accept_line', '\n'), { silent = true })
  vim.keymap.set('i', [[<M-[>]], copilot_suggestion.prev, { silent = true })
  vim.keymap.set('i', [[<M-]>]], copilot_suggestion.next, { silent = true })
  vim.keymap.set('i', xk [[<C-S-\>]], copilot_panel.open, { silent = true })

  vim.api.nvim_create_autocmd({ 'InsertEnter', 'InsertLeave' }, {
    group = vim.api.nvim_create_augroup('user_copilot', { clear = true }),
    callback = function(state)
      vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
    end,
  })
end

M.disable = function()
  if not is_setup then
    return
  end
  require('copilot.command').disable()
  vim.keymap.del('i', xk [[<C-\>]])
  vim.keymap.del('i', [[^\]])
  vim.keymap.del('i', [[<M-\>]])
  vim.keymap.del('i', xk [[<M-S-\>]])
  vim.keymap.del('i', [[<M-[>]])
  vim.keymap.del('i', [[<M-]>]])
  vim.keymap.del('i', xk [[<C-S-\>]])
end

return M
