local xk = require('user.keys').xk

very_lazy(function()
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
end)

---@type LazySpec[]
return {
  {
    'saghen/blink.cmp',
    dependencies = {
      { 'saghen/blink.compat', opts = {} },
    },
    lazy = false, -- blink handles lazy loading internally
    -- run with `zsh -i` so Mise loads proper Rust toolchain:
    build = 'zsh -ic "cargo build --release"',
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
        [ xk [[<C-S-n>]] ] = { 'select_next', 'show' },
        [ xk [[<C-S-p>]] ] = { 'select_prev', 'show' },
        ['<C-k>'] = { 'scroll_documentation_up', 'fallback' },
        ['<C-j>'] = { 'scroll_documentation_down', 'fallback' },
      },
      cmdline = {
        keymap = {
          ['<CR>'] = {
            function()
              vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-]><Cr>', true, true, true), 'n', true)
              return true
            end,
          },
          [xk '<C-Cr>'] = {
            function(cmp)
              return cmp.select_and_accept {
                callback = function()
                  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, true, true), 'n', true)
                end,
              }
            end,
            'fallback',
          },
          [xk '<C-S-a>'] = { 'show', 'hide' },
          ['<Tab>'] = {
            'show',
            function()
              local cmp = require 'blink.cmp'
              if cmp.is_visible() then
                if require('blink.cmp.completion.list').selected_item_idx == nil then
                  return false
                end
                if cmp.accept() then
                  vim.schedule(
                    function()
                      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Space>', true, true, true), 'n', true)
                    end
                  )
                  return true
                end
              end
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
            -- preselect = false,
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
                  local sym = require('lspkind').symbolic(ctx.kind)
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
          window = {
            max_height = 15,
            border = 'rounded',
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
