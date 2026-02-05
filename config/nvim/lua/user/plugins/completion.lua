local xk = require('user.keys').xk
local feedkeys = lazy_require('user.util.api').feedkeys

very_lazy(function()
  require('user.plugins.blink.cmdline.docs').setup()
  require('user.plugins.blink.cmdline.cheatsheet').setup()
  -- TODO:: move to `user.plugins.blink.cmdline.noice-ui`
  local autocmd = vim.api.nvim_create_autocmd
  local group = vim.api.nvim_create_augroup('user-cmp', { clear = true })
  local orig_menu_border
  autocmd('CmdlineEnter', {
    group = group,
    callback = function(ev)
      --- HACK: Make the menu border blend with noice's cmdline border
      local win = require('blink.cmp.completion.windows.menu').win
      orig_menu_border = win.config.border
      if ev.match == ':' then
        win.config.border = {
          '┐',
          ' ',
          '┌',
          '│',
          '╯',
          '─',
          '╰',
          '│',
        }
      end
    end,
  })
  autocmd('CmdlineLeave', {
    group = group,
    callback = function()
      if orig_menu_border then
        local win = require('blink.cmp.completion.windows.menu').win
        win.config.border = orig_menu_border
        orig_menu_border = nil
      end
    end,
  })
  -- /TODO
end)

local blink_nix_dir = require('user.util.lazy').nix_plugin_dir 'blink.cmp'

---@type LazySpec[]
return {
  {
    'saghen/blink.cmp',
    dir = blink_nix_dir,
    version = blink_nix_dir == nil and '1.*' or nil, -- Use release version if not available in nix store
    dependencies = {
      { 'saghen/blink.compat', opts = {} },
    },
    lazy = false, -- blink handles lazy loading internally
    opts = { ---@type blink.cmp.Config
      keymap = {
        preset = 'default',
        [xk '<C-S-a>'] = { 'show', 'hide' },
        ['<CR>'] = { 'accept', 'fallback' },
        ['<Tab>'] = { 'snippet_forward', 'fallback' },
        ['<S-Tab>'] = { 'snippet_backward', 'fallback' },
        ['<Up>'] = { 'select_prev', 'fallback' },
        ['<Down>'] = { 'select_next', 'fallback' },
        ['<C-p>'] = { 'select_prev', 'show' },
        ['<C-n>'] = { 'select_next', 'show' },
        [xk '<C-S-n>'] = { 'select_next', 'show' },
        [xk '<C-S-p>'] = { 'select_prev', 'show' },
        ['<C-k>'] = { 'scroll_documentation_up', 'fallback' },
        ['<C-j>'] = { 'scroll_documentation_down', 'fallback' },
        [xk '<C-S-k>'] = { 'scroll_documentation_up', 'fallback' },
        [xk '<C-S-j>'] = { 'scroll_documentation_down', 'fallback' },
      },
      cmdline = {
        keymap = {
          ['<CR>'] = {
            function()
              feedkeys '<C-]><CR>'
              return true
            end,
          },
          [xk '<C-Cr>'] = {
            function(cmp)
              return cmp.select_and_accept {
                callback = function() feedkeys '<CR>' end,
              }
            end,
            'fallback',
          },
          [xk '<C-S-a>'] = { 'show', 'hide' },
          ['<Tab>'] = {
            'show',
            function()
              local cmp = require 'blink.cmp'
              if not cmp.is_visible() then
                feedkeys '<Space>'
                return true
              end
              if require('blink.cmp.completion.list').selected_item_idx == nil then
                return false -- Fall through to select_next
              end
              local text_before = vim.fn.getcmdline()
              if not cmp.accept() then
                return
              end
              vim.schedule(function()
                local text_after = vim.fn.getcmdline()
                local text_changed = text_after ~= text_before
                local is_partial_path = text_after:match '/$'
                if text_changed or is_partial_path then
                  cmp.show()
                else
                  feedkeys '<Space>'
                end
              end)
              return true
            end,
            'select_next',
            'fallback',
          },
          ['<S-Tab>'] = { 'show', 'select_prev', 'fallback' },
          ['<C-p>'] = {
            'select_prev',
            'show',
            'fallback',
          },
          ['<C-n>'] = {
            'select_next',
            'show',
            'fallback',
          },
          [xk '<C-S-k>'] = { 'scroll_documentation_up', 'fallback' },
          [xk '<C-S-j>'] = { 'scroll_documentation_down', 'fallback' },
        },
        completion = {
          menu = {
            auto_show = true,
          },
        },
      },
      completion = {
        list = {
          selection = {
            preselect = false,
            auto_insert = true,
          },
        },
        menu = {
          border = 'rounded',
          draw = {
            components = {
              kind_icon = {
                ellipsis = false,
                text = function(ctx)
                  if ctx.kind == 'Color' then
                    return '███'
                  end
                  local sym = require('lspkind').symbol_map[ctx.kind]
                  if sym == nil or sym == '' then
                    sym = ctx.kind_icon
                  end
                  return ' ' .. sym .. ' '
                end,
              },
            },
          },
          cmdline_position = function()
            if vim.g.ui_cmdline_pos ~= nil then
              local pos = vim.g.ui_cmdline_pos -- (1, 0)-indexed
              return { pos[1] - 1, pos[2] + 3 }
            end
            local height = (vim.o.cmdheight == 0) and 1 or vim.o.cmdheight
            return { vim.o.lines - height, 0 }
          end,
        },
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 100,
          update_delay_ms = 85,
          treesitter_highlighting = true,
          window = {
            max_height = 15,
            border = 'rounded',
            direction_priority = {
              menu_north = { 'e', 'w', 'n', 's' },
              menu_south = { 'e', 'w', 's', 'n' },
            },
          },
        },
      },
      signature = {
        enabled = true,
        window = {
          border = 'rounded',
          scrollbar = true,
          direction_priority = { 'n', 's' },
        },
      },
      appearance = {
        nerd_font_variant = 'mono',
      },
      sources = {
        default = {
          'lsp',
          'path',
          'snippets',
          'buffer',
          'lazydev',
        },
        providers = {
          lazydev = {
            name = 'LazyDev',
            module = 'lazydev.integrations.blink',
            fallbacks = { 'lsp' },
          },
        },
      },
    },
  },
}
