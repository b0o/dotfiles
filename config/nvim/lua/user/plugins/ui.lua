---@type LazySpec[]
return {
  'MunifTanjim/nui.nvim',
  {
    'b0o/lavi.nvim',
    dev = true,
    lazy = false,
    config = function()
      if (vim.env.COLORSCHEME or 'lavi') == 'lavi' then
        vim.cmd.colorscheme 'lavi'
      elseif vim.env.COLORSCHEME == 'lavi-light' then
        vim.cmd.colorscheme 'lavi-light'
      end
    end,
    cond = function()
      return vim.env.COLORSCHEME == nil or vim.env.COLORSCHEME == 'lavi' or vim.env.COLORSCHEME == 'lavi-light'
    end,
  },
  {
    'rktjmp/lush.nvim',
    cmd = 'Lushify',
  },
  {
    'folke/tokyonight.nvim',
    lazy = false,
    config = function()
      require('tokyonight').setup {
        on_highlights = function(hl, c)
          hl.CmpSel = { bg = c.bg_visual }

          hl.RenderMarkdownH1Bg = { fg = '#1abc9c', bg = '#003c4b' }
          hl.RenderMarkdownH2Bg = { fg = '#829bff', bg = '#252d50' }
          hl.RenderMarkdownH3Bg = { fg = '#829bff', bg = '#1f2435' }
          hl.RenderMarkdownH4Bg = { fg = '#6b8cbc', bg = '#1f2435' }
          hl.RenderMarkdownH5Bg = { fg = '#6b8cbc', bg = '#1f2435' }
          hl.RenderMarkdownH6Bg = { fg = '#6b8cbc', bg = '#1f2435' }
          hl.RenderMarkdownH1 = { fg = hl.RenderMarkdownH1Bg.fg }
          hl.RenderMarkdownH2 = { fg = hl.RenderMarkdownH2Bg.fg }
          hl.RenderMarkdownH3 = { fg = hl.RenderMarkdownH3Bg.fg }
          hl.RenderMarkdownH4 = { fg = hl.RenderMarkdownH4Bg.fg }
          hl.RenderMarkdownH5 = { fg = hl.RenderMarkdownH5Bg.fg }
          hl.RenderMarkdownH6 = { fg = hl.RenderMarkdownH6Bg.fg }

          hl.RenderMarkdownCode = { bg = '#2d324a' }
          hl.RenderMarkdownCodeInline = { bg = '#373d5a' }
          hl.RenderMarkdownInlineHighlight = { link = 'RenderMarkdownCodeInline' }

          hl.RenderMarkdownChecked = { fg = '#b3f6c0' }
          hl.RenderMarkdownUnchecked = { fg = '#7aa2f7' }
          hl.RenderMarkdownTodo = { fg = '#bb9af7' }

          hl.RenderMarkdownLink = { fg = '#7aa2f7' }
          hl.RenderMarkdownWikiLink = { link = 'RenderMarkdownLink' }

          hl.RenderMarkdownError = { fg = '#db4b4b' }
          hl.RenderMarkdownWarn = { fg = '#e0af68' }
          hl.RenderMarkdownInfo = { fg = '#1abc9c' }
          hl.RenderMarkdownHint = { fg = '#565f89' }
          hl.RenderMarkdownSuccess = { fg = '#b3f6c0' }

          hl.RenderMarkdownQuote = { fg = '#565f89' }
          hl.RenderMarkdownSign = { fg = '#565f89' }
          hl.RenderMarkdownDash = { fg = '#565f89' }
          hl.RenderMarkdownBullet = { link = 'Normal' }

          hl.RenderMarkdownTableHead = { fg = '#0db9d7' }
          hl.RenderMarkdownTableRow = { link = 'Normal' }
          hl.RenderMarkdownTableFill = { link = 'Conceal' }

          hl.RenderMarkdownHtmlComment = { fg = '#565f89' }
          hl.RenderMarkdownMath = { fg = '#a39880', italic = true }

          hl.NoiceCmdlinePopup = { link = 'NormalFloat' }
          hl.BlinkCmpMenuBorder = { link = 'FloatBorder' }
        end,
      }
      vim.cmd.colorscheme 'tokyonight-storm'
    end,
    cond = function() return vim.env.COLORSCHEME == 'tokyonight' end,
  },
  {
    'nvim-tree/nvim-web-devicons',
    opts = {
      override = {
        ['kdl'] = {
          icon = '',
          color = '#7aa2f7',
          cterm_color = '65',
          name = 'kdl',
        },
      },
    },
  },
  {
    'stevearc/dressing.nvim',
    opts = {},
    event = 'VeryLazy',
  },
  {
    'folke/noice.nvim',
    event = 'VeryLazy',
    keys = {
      { '<leader>L', '<Cmd>NoiceHistory<cr>', desc = 'Noice: History log' },
    },
    opts = {
      lsp = {
        -- override markdown rendering so that **cmp** and other plugins use **Treesitter**
        override = {
          ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
          ['vim.lsp.util.stylize_markdown'] = true,
          ['cmp.entry.get_documentation'] = true,
        },
        hover = {
          enabled = true,
          opts = {
            zindex = 200,
          },
        },
        signature = {
          enabled = false,
        },
      },
      -- you can enable a preset for easier configuration
      presets = {
        bottom_search = true, -- use a classic bottom cmdline for search
        command_palette = true, -- position the cmdline and popupmenu together
        long_message_to_split = true, -- long messages will be sent to a split
        inc_rename = true, -- enables an input dialog for inc-rename.nvim
        lsp_doc_border = true, -- add a border to hover docs and signature help
      },
    },
    dependencies = {
      'MunifTanjim/nui.nvim',
    },
  },
  {
    'folke/which-key.nvim',
    event = 'VeryLazy',
    config = function()
      require('which-key.plugins.presets').operators['v'] = nil
      require('which-key').setup {}
    end,
  },
  {
    'folke/zen-mode.nvim',
    config = function()
      require('zen-mode').setup {
        window = {
          backdrop = 0.8,
          width = function()
            local min = 60
            local max = 160
            local target = 0.5
            return math.floor(math.max(min, math.min(max, vim.o.columns * target)))
          end,
        },
        on_open = function() require('user.zen-mode').on_open() end,
      }
    end,
    cmd = 'ZenMode',
    keys = {
      { '<leader>Z', '<Cmd>ZenMode<Cr>', desc = 'Zen: Toggle' },
    },
  },
  {
    's1n7ax/nvim-window-picker',
    keys = {
      {
        '<M-w>',
        function()
          local win = require('window-picker').pick_window()
          if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_set_current_win(win)
          end
        end,
        desc = 'Window Picker: Pick',
      },
    },
    config = function()
      local colors = require 'user.colors'
      -- Generate fonts with the following shell function:
      -- genfont() {
      --   font="${1:-slant}"
      --   echo -e "-- Font: $font\nreturn {"
      --   for l in {a..z} {0..9} ';'; do
      --     echo "['$l'] = [[\n$(figlet -f "$font" "${l}" | awk NF)]],\n"
      --   done
      --   echo "}"
      -- }
      -- Place them in lua/window-picker/hints/data/<font>.lua
      require('window-picker').setup {
        hint = 'floating-big-letter',
        selection_chars = 'FJDKSLACMRUEIWOQPHTGYVBNZX',
        filter_rules = {
          autoselect_one = false,
          bo = {
            filetype = { 'notify', 'incline' },
            buftype = { 'quickfix' },
          },
        },
        picker_config = {
          floating_big_letter = {
            font = 'slant',
          },
        },
        fg_color = colors.hydrangea,
        show_prompt = false,
      }
    end,
  },
}
