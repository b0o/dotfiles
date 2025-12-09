---@type LazySpec[]
return {
  {
    'nvim-lualine/lualine.nvim',
    event = 'VeryLazy',
    config = function()
      local function pnpm_workspace()
        local focused_path = vim.api.nvim_buf_get_name(0)
        if focused_path == '' then
          return ''
        end
        local workspace_info = require('user.util.workspace.pnpm').get_workspace_info {
          focused_path = focused_path,
          only_cached = true,
        }
        if not workspace_info then
          return ''
        end
        if workspace_info.focused then
          local display = workspace_info.focused.name or workspace_info.focused.relative_path
          if display then
            return '󰏗 ' .. display
          end
          return ''
        end
        if workspace_info.root then
          return workspace_info.root.name or ''
        end
        return ''
      end

      local ok, theme = pcall(require, 'lualine.themes.' .. (vim.env.COLORSCHEME or 'lavi'))
      if not ok then
        theme = require 'lualine.themes.lavi'
      end

      require('lualine').setup {
        options = {
          icons_enabled = true,
          theme = theme,
          component_separators = { left = '', right = '' },
          section_separators = { left = ' ', right = ' ' },
          disabled_filetypes = {
            statusline = {},
            winbar = {},
          },
          ignore_focus = {},
          always_divide_middle = true,
          refresh = {
            statusline = 1000,
          },
        },
        sections = {
          lualine_a = {
            {
              'mode',
              fmt = function(str) return str:sub(1, 1) end,
            },
          },
          lualine_b = {
            'branch',
            pnpm_workspace,
            'diff',
            'diagnostics',
          },
          lualine_c = {
            { 'filename', path = 1 },
            'aerial',
          },
          lualine_x = {
            {
              'tabs',
              tab_max_length = 40,
              max_length = vim.o.columns / 4,
              mode = 1,
              show_modified_status = false,
              tabs_color = {
                active = theme.normal.a,
                inactive = theme.inactive.c,
              },
              section_separators = {
                left = '',
                right = '',
              },
              padding = 1,
              fmt = function(_, context)
                local tabpage = context.tabId
                local buf = require('user.util.tabs').get_most_recent_buf(tabpage)
                local mod = vim
                  .iter(vim.api.nvim_tabpage_list_wins(tabpage))
                  :map(function(winnr) return vim.api.nvim_win_get_buf(winnr) end)
                  :any(function(bufnr) return vim.bo[bufnr].modified end)
                local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t')
                return vim
                  .iter({
                    context.tabnr,
                    ' ',
                    name,
                    mod and ' *',
                  })
                  :filter(function(v) return v and v ~= '' end)
                  :join ''
              end,
            },
            '%S', -- showcmd, requires showcmdloc=statusline
            'filetype',
            'progress',
          },
          lualine_y = {
            'overseer',
            require('opencode').statusline,
          },
          lualine_z = { 'location' },
        },
      }

      --- Workaround to make lualine work with tpipeline
      if vim.env.TMUX ~= nil then
        local Debounce = require 'user.util.debounce'
        local lualine_nvim_opts = require 'lualine.utils.nvim_opts'
        local base_set = lualine_nvim_opts.set

        local tpipeline_update = Debounce(function() vim.cmd 'silent! call tpipeline#update()' end, {
          threshold = 20,
        })

        ---@diagnostic disable-next-line: duplicate-set-field
        lualine_nvim_opts.set = function(name, val, scope)
          if name == 'statusline' then
            if scope and scope.window == vim.api.nvim_get_current_win() then
              vim.g.tpipeline_statusline = val
              tpipeline_update()
            end
            return
          end
          return base_set(name, val, scope)
        end
      end
    end,
  },
  {
    'vimpostor/vim-tpipeline',
    event = 'VeryLazy',
    init = function()
      vim.g.tpipeline_autoembed = 0
      vim.g.tpipeline_statusline = ''
    end,
    config = function()
      vim.cmd.hi { 'link', 'StatusLine', 'WinSeparator' }
      vim.g.tpipeline_statusline = ''
      vim.o.laststatus = 0
      vim.defer_fn(function() vim.o.laststatus = 0 end, 0)
      vim.o.fillchars = 'stl:─,stlnc:─'
      vim.api.nvim_create_autocmd('OptionSet', {
        pattern = 'laststatus',
        callback = function()
          if vim.o.laststatus ~= 0 then
            vim.notify 'Auto-setting laststatus to 0'
            vim.o.laststatus = 0
          end
        end,
      })
    end,
    cond = function() return vim.env.TMUX ~= nil end,
    dependencies = {
      'nvim-lualine/lualine.nvim',
    },
  },
}
