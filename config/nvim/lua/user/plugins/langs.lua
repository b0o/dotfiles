very_lazy(function()
  local maputil = require 'user.util.map'
  local map = maputil.map

  map('n', { '<leader>O', '<leader>oo' }, '<Cmd>Other<Cr>', 'Other: Switch to other file')
  map('n', { '<leader>os', '<leader>ox' }, '<Cmd>OtherSplit<Cr>', 'Other: Open other in split')
  map('n', '<leader>ov', '<Cmd>OtherVSplit<Cr>', 'Other: Open other in vsplit')
end)

---@type LazySpec[]
return {
  {
    'aouelete/sway-vim-syntax',
    ft = 'sway',
  },
  {
    'fatih/vim-go',
    ft = 'go',
    config = function() vim.g.go_doc_keywordprg_enabled = 0 end,
  },
  {
    'rgroli/other.nvim',
    -- dev = true,
    cmd = { 'Other', 'OtherTabNew', 'OtherSplit', 'OtherVSplit' },
    config = function()
      local other = require 'other-nvim'

      other.setup {
        mappings = {
          ---- Typescript
          {
            pattern = '(.*).ts$',
            context = 'test',
            target = '%1.test.ts',
          },
          {
            pattern = '(.*).test.ts$',
            context = 'implementation',
            target = '%1.ts',
          },
          {
            pattern = '(.*).d.ts$',
            context = 'declaration-test',
            target = '%1.test-d.ts',
          },
          {
            pattern = '(.*).test%-d.ts$',
            target = {
              {
                context = 'declaration',
                target = '%1.d.ts',
              },
              {
                context = 'implementation',
                target = '%1.ts',
              },
            },
          },
          ---- TSX
          {
            pattern = '(.*).tsx$',
            context = 'test',
            target = '%1.test.tsx',
          },
          {
            pattern = '(.*).test.tsx$',
            context = 'implementation',
            target = '%1.tsx',
          },
          ---- Javascript
          {
            pattern = '(.*).js$',
            context = 'test',
            target = '%1.test.js',
          },
          {
            pattern = '(.*).test.js$',
            context = 'implementation',
            target = '%1.js',
          },
          ---- JSX
          {
            pattern = '(.*).jsx$',
            context = 'test',
            target = '%1.test.jsx',
          },
          {
            pattern = '(.*).test.jsx$',
            context = 'implementation',
            target = '%1.jsx',
          },
          ---- C++
          {
            pattern = '(.*).cpp$',
            context = 'header',
            target = '%1.h',
          },
          {
            pattern = '(.*).h$',
            context = 'implementation',
            target = '%1.cpp',
          },
          ---- C
          {
            pattern = '(.*).c$',
            context = 'header',
            target = '%1.h',
          },
          {
            pattern = '(.*).h$',
            context = 'implementation',
            target = '%1.c',
          },
        },
        keybindings = {
          ['<Cr>'] = 'open_file()',
          ['<Esc>'] = 'close_window()',
          q = 'close_window()',
          o = 'open_file()',
          t = 'open_file_tabnew()',
          v = 'open_file_vs()',
          s = 'open_file_sp()',
          ['<C-t>'] = 'open_file_tabnew()',
          ['<C-v>'] = 'open_file_vs()',
          ['<C-x>'] = 'open_file_sp()',
        },
        hooks = {
          ---@param files { filename: string, context: string, exists: boolean }[]
          onFindOtherFiles = function(files)
            local existing = vim.iter(files):filter(function(file) return file.exists end):totable()
            if #existing > 0 then
              return existing
            end
            return files
          end,
          onOpenFile = function(filename, exists)
            if exists then
              local bufnr = vim.fn.bufnr(filename)
              if bufnr > 0 then
                local target_win
                local wins = vim.api.nvim_tabpage_list_wins(0)
                for _, win in ipairs(wins) do
                  if vim.api.nvim_win_get_buf(win) == bufnr then
                    target_win = win
                    break
                  end
                end
                local zen_view = package.loaded['zen-mode.view']
                if zen_view and zen_view.is_open() then
                  if target_win then
                    require('user.zen-mode').move { win = target_win }
                  else
                    require('user.zen-mode').move { buf = bufnr }
                  end
                  return false
                end
                if target_win then
                  vim.api.nvim_set_current_win(target_win)
                  return false
                end
              end
            end
            return true
          end,
        },
        style = {
          border = 'rounded',
          seperator = '│',
          newFileIndicator = '[NEW]',
        },
      }
    end,
  },
  {
    'b0o/blender.nvim',
    dev = true,
    opts = {
      notify = {
        verbosity = 'TRACE',
      },
    },
    cmd = {
      'Blender',
      'BlenderLaunch',
      'BlenderManage',
      'BlenderTest',
    },
    dependencies = {
      'MunifTanjim/nui.nvim',
      { 'grapp-dev/nui-components.nvim', dev = false },
      'mfussenegger/nvim-dap',
      'LiadOz/nvim-dap-repl-highlights',
    },
  },
  {
    'mrcjkb/rustaceanvim',
    version = '^5',
    ft = 'rust',
    dependencies = {
      {
        'Joakker/lua-json5',
        build = './install.sh',
        config = function()
          local vim_json_decode = vim.json.decode
          -- Support JSON5 syntax in .vscode/settings.json
          ---@diagnostic disable-next-line: duplicate-set-field
          vim.json.decode = function(str, opts)
            -- Try builtin JSON parser
            local ok, json = pcall(vim_json_decode, str, opts or {})
            if ok then
              return json
            end
            -- Try JSON5 parser
            return require('json5').parse(str)
          end
        end,
      },
    },
    config = function()
      local maputil = require 'user.util.map'
      local ft = maputil.ft
      ---@module 'rustaceanvim'
      ---@type rustaceanvim.Config
      vim.g.rustaceanvim = {
        tools = {
          enable_clippy = true,
          float_win_config = {
            border = 'rounded',
          },
        },
        server = {
          standalone = true,
          on_attach = function(client, bufnr) require('user.util.lsp').on_attach(client, bufnr) end,
          settings = {
            ['rust-analyzer'] = {
              diagnostics = {
                disabled = { 'inactive-code' },
              },
              imports = {
                granularity = {
                  group = 'module',
                },
                prefix = 'self',
              },
              cargo = {
                features = 'all',
                buildScripts = {
                  enable = true,
                },
              },
              procMacro = {
                enable = true,
              },
              checkOnSave = true,
              check = {
                command = 'clippy',
                features = 'all',
                invocationLocation = 'workspace',
                extraArgs = { '--tests' },
              },
              files = {
                excludeDirs = { '.direnv' },
              },
            },
          },
        },
      }

      ft('rust', function(bufmap)
        bufmap('n', '<localleader>rA', '<cmd>RustLsp codeAction<Cr>', { silent = true, desc = 'Rust: Code action' })
        bufmap(
          'n',
          '<localleader>re',
          '<cmd>RustLsp explainError current<Cr>',
          { silent = true, desc = 'Rust: Explain error' }
        )
        bufmap('n', '<localleader>ri', function()
          require('user.util.lsp').hover(function() vim.cmd.RustLsp { 'hover', 'actions' } end)
        end, { silent = true, desc = 'Rust: Hover actions' })
        bufmap(
          'v',
          '<M-i>',
          function() vim.cmd.RustLsp { 'hover', 'range' } end,
          { silent = true, desc = 'Rust: Hover range' }
        )
        bufmap(
          'n',
          '<localleader>rd',
          '<cmd>RustLsp renderDiagnostic current<Cr>',
          { silent = true, desc = 'Rust: Cycle diagnostics' }
        )
        bufmap('n', '<localleader>rI', '<cmd>RustLsp openDocs<Cr>', { silent = true, desc = 'Rust: Open docs' })
      end)
    end,
  },
  {
    'SUSTech-data/neopyter',
    dependencies = { 'AbaoFromCUG/websocket.nvim' },
    event = { 'BufRead *.ju.*', 'BufNewFile *.ju.*' },
    ---@module 'neopyter'
    ---@type neopyter.Option
    opts = {
      mode = 'direct',
      remote_address = '127.0.0.1:8889',
      file_pattern = { '*.ju.*' },
      parser = {
        trim_whitespace = true,
      },
      highlight = {
        mode = 'zen',
        enable = false,
        shortsighted = false,
      },
      on_attach = function(bufnr)
        local bufmap = require('user.util.map').buf(bufnr)
        local xk = require('user.keys').xk
        bufmap('n', xk '<C-Cr>', '<cmd>Neopyter execute notebook:run-cell<Cr>', 'Jupyter: Run selected')
        bufmap('n', '<Leader>jX', '<cmd>Neopyter execute notebook:run-all-above<Cr>', 'Jupyter: Run all above cell')
        bufmap('n', '<Leader>jr', '<cmd>Neopyter kernel restart<Cr>', 'Jupyter: Restart kernel')
        bufmap('n', '<Leader>jR', '<cmd>Neopyter kernel restartRunAll<Cr>', 'Jupyter: Restart kernel and run all')
        bufmap('n', '<S-Cr>', '<cmd>Neopyter execute runmenu:run<Cr>', 'Jupyter: Run selected and select next')
        bufmap(
          'n',
          '<M-Cr>',
          '<cmd>Neopyter execute run-cell-and-insert-below<Cr>',
          'Jupyter: Run selected and insert below'
        )
      end,
    },
  },
  {
    'MeanderingProgrammer/render-markdown.nvim',
    config = function()
      require('render-markdown').setup {
        debounce = 50,
        render_modes = { 'n', 'i', 'v', 'V', 'c', 't' },
        file_types = { 'markdown', 'mdx' },
        code = { language_name = false },
        anti_conceal = { enabled = false },
        win_options = {
          concealcursor = { rendered = 'n' },
        },
        heading = {
          icons = {
            '  󰼏  ',
            '  󰼐  ',
            '  󰼑  ',
            '󰼒  ',
            '󰼓  ',
            '󰼔  ',
          },
          position = 'overlay',
          border = true,
        },
        checkbox = {
          unchecked = { icon = ' 󰄱 ' },
          checked = { icon = ' 󰄵 ' },
        },
        link = {
          wiki = { icon = '󰌹 ' },
        },
      }
      local maputil = require 'user.util.map'
      local ft = maputil.ft

      ft({ 'markdown', 'mdx' }, function(bufmap)
        vim.o.wrap = false

        bufmap('n', '<localleader>C', function()
          ---@diagnostic disable-next-line: invisible
          local config = require('render-markdown.state').config
          pcall(
            require('render-markdown').setup,
            vim.tbl_deep_extend('force', config, config.anti_conceal.enabled and {
              anti_conceal = { enabled = false },
              win_options = {
                concealcursor = { rendered = 'n' },
              },
            } or {
              anti_conceal = { enabled = true },
              win_options = {
                concealcursor = { rendered = '' },
              },
            })
          )
        end, 'Markdown: Toggle concealcursor')

        bufmap('n', '<localleader>M', '<cmd>RenderMarkdown toggle<Cr>', 'Markdown: Toggle')
      end)
    end,
    ft = { 'markdown', 'mdx' },
  },
  {
    '3rd/image.nvim',
    opts = {
      backend = 'kitty',
      processor = 'magick_cli',
      integrations = {
        markdown = {
          enabled = true,
          clear_in_insert_mode = false,
          download_remote_images = true,
          only_render_image_at_cursor = false,
          floating_windows = true,
          filetypes = { 'markdown', 'noice', 'cmp_docs' },
        },
        neorg = { enabled = false },
        typst = { enabled = false },
        html = { enabled = false },
        css = { enabled = false },
      },
      max_width = 80,
      max_height = nil,
      max_width_window_percentage = nil,
      max_height_window_percentage = 50,
      window_overlap_clear_enabled = false, -- toggles images when windows are overlapped
      window_overlap_clear_ft_ignore = {
        'cmp_menu',
        'cmp_docs',
        '',
      },
      editor_only_render_when_focused = false, -- auto show/hide images when the editor gains/looses focus
      tmux_show_only_in_active_window = false, -- auto show/hide images in the correct Tmux window (needs visual-activity off)
      hijack_file_patterns = {
        '*.png',
        '*.bmp',
        '*.jpg',
        '*.jpeg',
        '*.gif',
        '*.webp',
        '*.avif',
        '*.heic',
        '*.xpm',
        '*.ico',
        '*.pdf',
      },
    },
    ft = { 'markdown', 'noice', 'cmp_docs' },
  },
  {
    '3rd/diagram.nvim',
    dependencies = {
      '3rd/image.nvim',
    },
    ft = { 'markdown' },
    opts = {
      renderer_options = {
        mermaid = {
          background = 'transparent',
          theme = 'dark',
        },
        gnuplot = {
          theme = 'dark',
        },
      },
    },
  },
  {
    'lervag/vimtex',
    ft = { 'tex', 'bib' },
    init = function()
      vim.g.vimtex_imaps_enabled = 0
      vim.g.vimtex_view_method = 'zathura_simple'
      vim.g.vimtex_quickfix_ignore_filters = {
        'Underfull \\\\hbox',
        'Underfull \\\\vbox',
        'Overfull \\\\hbox',
        'Overfull \\\\vbox',
        'LaTeX Warning: .\\+ float specifier changed to',
        'LaTeX hooks Warning',
        'Package hyperref Warning: Token not allowed in a PDF string',
      }
    end,
  },
}
