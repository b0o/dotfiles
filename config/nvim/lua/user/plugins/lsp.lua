local servers = function()
  return {
    'astro',
    {
      'mdx_analyzer',
      filetypes = { 'mdx' },
    },
    'bashls',
    {
      'clangd',
      filetypes = {
        'c',
        'cpp',
        'objc',
        'objcpp',
        'cuda',
      },
    },
    {
      'neocmake',
      formatting = false,
      init_options = {
        format = { enable = false },
        lint = { enable = false },
      },
    },
    {
      'cssls',
      settings = {
        css = { validate = false },
        scss = { validate = false },
        less = { validate = false },
      },
    },
    {
      'dockerls',
      formatting = false,
    },
    'dotls',
    {
      'emmet_language_server',
      filetypes = {
        'css',
        'eruby',
        'html',
        'htmlangular',
        'htmldjango',
        'javascriptreact',
        'less',
        'markdown',
        'mdx',
        'pug',
        'sass',
        'scss',
        'svelte',
        'typescriptreact',
      },
    },
    {
      'eslint',
      root_markers = {
        'eslint.config.js',
        '.eslintrc',
        '.eslintrc.js',
        '.eslintrc.cjs',
        '.eslintrc.yaml',
        '.eslintrc.yml',
        '.eslintrc.json',
        'package.json',
      },
      filetypes = {
        'astro',
        'javascript',
        'javascript.jsx',
        'javascriptreact',
        'mdx',
        'svelte',
        'typescript',
        'typescriptreact',
        'typescript.tsx',
        'vue',
      },
      settings = {
        experimentalUseFlatConfig = true,
        codeAction = {
          disableRuleComment = {
            enable = true,
            location = 'separateLine',
          },
          showDocumentation = {
            enable = true,
          },
        },
        codeActionOnSave = {
          enable = false,
          mode = 'all',
        },
        format = false,
        onIgnoredFiles = 'off',
        packageManager = 'npm',
        quiet = false,
        rulesCustomizations = {},
        run = 'onType',
        validate = 'on',
        workingDirectory = {
          mode = 'location',
        },
      },
    },
    'glsl_analyzer',
    {
      'gopls',
      formatting = false,
    },
    'hie',
    'html',
    {
      'jsonls',
      on_attach = function(client, bufnr)
        local filename = vim.api.nvim_buf_get_name(bufnr)
        if filename:match '%.ts%.snap$' or filename:match '%.js%.snap$' then
          vim.defer_fn(function()
            vim.lsp.buf_detach_client(bufnr, client.id)
            vim.diagnostic.enable(false, { bufnr = bufnr })
          end, 0)
          return false
        end
      end,
      settings = require('user.util.lazy').table(
        function()
          return {
            json = {
              schemas = require('schemastore').json.schemas(),
            },
            validate = { enable = true },
          }
        end
      ),
    },
    {
      'ocamllsp',
      root_markers = {
        '.opam',
        'esy.json',
        'package.json',
        '.git',
        '.merlin',
      },
    },
    {
      'basedpyright',
      formatting = false,
    },
    'cyright',
    'marksman',
    {
      'ruff',
      hover = false,
    },
    'nil_ls',
    {
      'lua_ls',
      settings = {
        Lua = {
          telemetry = {
            enable = false,
          },
        },
      },
    },
    {
      'svelte',
      formatting = false,
    },
    'systemd',
    {
      'tailwindcss',
      root_markers = {
        'tailwind.config.js',
        'tailwind.config.cjs',
        'tailwind.config.mjs',
        'tailwind.config.ts',
        'tailwind.config.cts',
        'tailwind.config.mts',
        'postcss.config.js',
        'postcss.config.ts',
      },
      settings = {
        scss = {
          validate = false,
        },
        editor = {
          quickSuggestions = { strings = true },
          autoClosingQuotes = 'always',
        },
        tailwindCSS = {
          experimental = {
            classRegex = {
              [[[\S]*ClassName="([^"]*)]], -- <MyComponent containerClassName="..." />
              [[[\S]*ClassName={"([^"}]*)]], -- <MyComponent containerClassName={"..."} />
              [[[\S]*ClassName={"([^'}]*)]], -- <MyComponent containerClassName={'...'} />
            },
          },
          includeLanguages = {
            typescript = 'javascript',
            typescriptreact = 'javascript',
            svelte = 'svelte',
          },
        },
      },
    },
    'taplo',
    {
      'tsgo',
      on_attach = function(client, bufnr) require('twoslash-queries').attach(client, bufnr) end,
    },
    {
      'ts_ls',
      enabled = true,
      on_attach = function(client, bufnr) require('twoslash-queries').attach(client, bufnr) end,
    },
    'vimls',
    {
      'yamlls',
      settings = {
        redhat = { telemetry = { enabled = false } },
        yaml = {
          schemaStore = {
            enable = true,
            -- Avoid TypeError: Cannot read properties of undefined (reading 'length')
            url = '',
          },
          schemas = require('schemastore').yaml.schemas(),
        },
      },
    },
    'lemminx', -- XML
    'zls',
  }
end

local fn = require 'user.fn'
local maputil = require 'user.util.map'
local recent_wins = require 'user.util.recent-wins'

local user_lsp = lazy_require 'user.util.lsp'
local trouble = lazy_require 'trouble'

local map = maputil.map
local wrap = maputil.wrap

local conform = lazy_require 'conform'
local user_conform = lazy_require 'user.plugins.conform.internal'

very_lazy(function()
  map('n', '<leader>lif', '<Cmd>LspInfo<Cr>', 'LSP: Show LSP information')
  map('n', '<leader>lr', '<Cmd>LspRestart<Cr>', 'LSP: Restart LSP')
  map('n', '<leader>ls', '<Cmd>LspStart<Cr>', 'LSP: Start LSP')
  map('n', '<leader>lS', '<Cmd>LspStop<Cr>', 'LSP: Stop LSP')
end)

local on_first_attach = function()
  local function get_trouble_win()
    for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local bufnr = vim.api.nvim_win_get_buf(winid)
      if vim.bo[bufnr].filetype == 'trouble' then
        return winid
      end
    end
  end

  map('n', '<M-S-t>', function()
    local winid = get_trouble_win()
    if winid then
      trouble.close { mode = 'diagnostics' }
    else
      trouble.open { mode = 'diagnostics' }
      recent_wins.focus_most_recent()
    end
  end, { desc = 'Trouble: Toggle' })

  map(
    'n',
    '<M-t>',
    fn.if_filetype('trouble', recent_wins.focus_most_recent, wrap(trouble.open, { mode = 'diagnostics', focus = true })),
    'Trouble: Toggle Focus'
  )

  map('n', '<leader>lii', user_lsp.set_inlay_hints_global, 'LSP: Toggle inlay hints')
  map('n', '<leader>lie', wrap(user_lsp.set_inlay_hints_global, true), 'LSP: Enable inlay hints')
  map('n', '<leader>lid', wrap(user_lsp.set_inlay_hints_global, false), 'LSP: Disable inlay hints')

  map('nx', '<localleader>F', wrap(conform.format, { lsp_fallback = true }), 'LSP: Format')

  map(
    'n',
    { '<localleader>S', '<localleader>ss' },
    user_conform.toggle_format_on_save,
    'Conform: Toggle format on save'
  )
  map('n', '<localleader>se', wrap(user_conform.set_format_on_save, true), 'Conform: Enable format on save')
  map('n', '<localleader>sd', wrap(user_conform.set_format_on_save, false), 'Conform: Disable format on save')
end

local on_attach = function(_, bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.b[bufnr].user_lsp_attached then
    return
  end
  vim.b[bufnr].user_lsp_attached = true

  local bufmap = maputil.buf(bufnr)

  bufmap('n', '<localleader>ii', wrap(user_lsp.set_inlay_hints, 0), 'LSP: Toggle inlay hints for buffer')
  bufmap('n', '<localleader>ie', wrap(user_lsp.set_inlay_hints, 0, true), 'LSP: Enable inlay hints for buffer')
  bufmap('n', '<localleader>id', wrap(user_lsp.set_inlay_hints, 0, false), 'LSP: Disable inlay hints for buffer')

  bufmap('n', '<localleader>gD', vim.lsp.buf.declaration, 'LSP: Goto declaration')
  bufmap('n', { '<localleader>gd', 'gd' }, '<Cmd>Glance definitions<Cr>', 'LSP: Glance definitions')
  bufmap('n', '<localleader>gi', '<Cmd>Glance implementations<Cr>', 'LSP: Glance implementation')
  bufmap('n', '<localleader>gt', '<Cmd>Glance type_definitions<Cr>', 'LSP: Glance type definitions')
  bufmap('n', '<localleader>gr', '<Cmd>Glance references<Cr>', 'LSP: Glance references')

  bufmap('n', '<localleader>wa', vim.lsp.buf.add_workspace_folder, 'LSP: Add workspace folder')
  bufmap('n', '<localleader>wr', vim.lsp.buf.remove_workspace_folder, 'LSP: Rm workspace folder')

  bufmap(
    'n',
    '<localleader>wl',
    function() fn.inspect(vim.lsp.buf.list_workspace_folders()) end,
    'LSP: List workspace folders'
  )

  bufmap('n', '<localleader>R', function()
    require 'inc_rename' -- Force lazy.nvim to load inc_rename
    return ':IncRename ' .. vim.fn.expand '<cword>'
  end, { silent = false, expr = true, desc = 'LSP: Rename' })

  local code_action = lazy_require('tiny-code-action').code_action
  bufmap('nx', { '<localleader>A', '<localleader>ca' }, code_action, 'LSP: Code action')

  local function goto_diag(dir, float)
    return function(sev)
      return function()
        local opts = {
          float = float,
          severity = vim.diagnostic.severity[sev],
        }

        if dir == 'first' or dir == 'last' then
          opts.wrap = false
          if dir == 'first' then
            opts.pos = { 1, -1 }
            opts.count = 1
          else
            opts.pos = { vim.api.nvim_buf_line_count(0) - 1, 99999 }
            opts.count = -1
          end
        elseif dir == 'prev' then
          opts.count = -1
        elseif dir == 'next' then
          opts.count = 1
        else
          error('Invalid direction: ' .. dir)
        end

        if type(vim.diagnostic.jump) == 'function' then
          vim.diagnostic.jump(opts)
        else
          vim.diagnostic['goto_' .. dir](opts)
        end
      end
    end
  end
  local diag_prev = goto_diag('prev', false)
  local diag_next = goto_diag('next', false)
  local diag_first = goto_diag('first', false)
  local diag_last = goto_diag('last', false)

  local diag_prev_float = goto_diag('prev', true)
  local diag_next_float = goto_diag('next', true)
  local diag_first_float = goto_diag('first', true)
  local diag_last_float = goto_diag('last', true)

  bufmap('n', '<localleader>ds', vim.diagnostic.show, 'LSP: Show diagnostics')
  bufmap('n', { '<localleader>dt', '<localleader>T' }, trouble.toggle, 'LSP: Toggle Trouble')

  bufmap('n', '<localleader>dd', function()
    local enabled = vim.diagnostic.is_enabled { bufnr = 0 }
    vim.diagnostic.enable(not enabled, { bufnr = 0 })
    vim.notify('Diagnostics ' .. (enabled and 'disabled' or 'enabled'))
  end, 'LSP: Toggle Diagnostic')

  bufmap('n', '<leader><M-i>', vim.diagnostic.open_float, 'LSP: Float diagnostic under cursor')

  bufmap('n', '[d', diag_prev(), 'LSP: Goto prev diagnostic')
  bufmap('n', ']d', diag_next(), 'LSP: Goto next diagnostic')
  bufmap('n', '[h', diag_prev 'HINT', 'LSP: Goto prev hint')
  bufmap('n', ']h', diag_next 'HINT', 'LSP: Goto next hint')
  bufmap('n', '[i', diag_prev 'INFO', 'LSP: Goto prev info')
  bufmap('n', ']i', diag_next 'INFO', 'LSP: Goto next info')
  bufmap('n', '[w', diag_prev 'WARN', 'LSP: Goto prev warning')
  bufmap('n', ']w', diag_next 'WARN', 'LSP: Goto next warning')
  bufmap('n', '[e', diag_prev 'ERROR', 'LSP: Goto prev error')
  bufmap('n', ']e', diag_next 'ERROR', 'LSP: Goto next error')

  bufmap('n', '[D', diag_first(), 'LSP: Goto first diagnostic')
  bufmap('n', ']D', diag_last(), 'LSP: Goto last diagnostic')
  bufmap('n', '[H', diag_first 'HINT', 'LSP: Goto first hint')
  bufmap('n', ']H', diag_last 'HINT', 'LSP: Goto last hint')
  bufmap('n', '[I', diag_first 'INFO', 'LSP: Goto first info')
  bufmap('n', ']I', diag_last 'INFO', 'LSP: Goto last info')
  bufmap('n', '[W', diag_first 'WARN', 'LSP: Goto first warning')
  bufmap('n', ']W', diag_last 'WARN', 'LSP: Goto last warning')
  bufmap('n', '[E', diag_first 'ERROR', 'LSP: Goto first error')
  bufmap('n', ']E', diag_last 'ERROR', 'LSP: Goto last error')

  bufmap('n', '<leader>[d', diag_prev_float(), 'LSP: Goto prev diagnostic (float)')
  bufmap('n', '<leader>]d', diag_next_float(), 'LSP: Goto next diagnostic (float)')
  bufmap('n', '<leader>[h', diag_prev_float 'HINT', 'LSP: Goto prev hint (float)')
  bufmap('n', '<leader>]h', diag_next_float 'HINT', 'LSP: Goto next hint (float)')
  bufmap('n', '<leader>[i', diag_prev_float 'INFO', 'LSP: Goto prev info (float)')
  bufmap('n', '<leader>]i', diag_next_float 'INFO', 'LSP: Goto next info (float)')
  bufmap('n', '<leader>[w', diag_prev_float 'WARN', 'LSP: Goto prev warning (float)')
  bufmap('n', '<leader>]w', diag_next_float 'WARN', 'LSP: Goto next warning (float)')
  bufmap('n', '<leader>[e', diag_prev_float 'ERROR', 'LSP: Goto prev error (float)')
  bufmap('n', '<leader>]e', diag_next_float 'ERROR', 'LSP: Goto next error (float)')
  bufmap('n', '<leader>[D', diag_first_float(), 'LSP: Goto first diagnostic (float)')
  bufmap('n', '<leader>]D', diag_last_float(), 'LSP: Goto last diagnostic (float)')
  bufmap('n', '<leader>[H', diag_first_float 'HINT', 'LSP: Goto first hint (float)')
  bufmap('n', '<leader>]H', diag_last_float 'HINT', 'LSP: Goto last hint (float)')
  bufmap('n', '<leader>[I', diag_first_float 'INFO', 'LSP: Goto first info (float)')
  bufmap('n', '<leader>]I', diag_last_float 'INFO', 'LSP: Goto last info (float)')
  bufmap('n', '<leader>[W', diag_first_float 'WARN', 'LSP: Goto first warning (float)')
  bufmap('n', '<leader>]W', diag_last_float 'WARN', 'LSP: Goto last warning (float)')
  bufmap('n', '<leader>[E', diag_first_float 'ERROR', 'LSP: Goto first error (float)')
  bufmap('n', '<leader>]E', diag_last_float 'ERROR', 'LSP: Goto last error (flooat)')

  bufmap('n', '<localleader>dr', function() vim.diagnostic.reset(nil, 0) end, 'LSP: Reset diagnostics (buffer)')

  bufmap(
    'n',
    { [[<localleader>so]], [[<leader>so]] },
    lazy_require('user.telescope').cmds.lsp_document_symbols,
    'LSP: Telescope symbol search'
  )

  bufmap('n', '<localleader>hs', vim.lsp.buf.signature_help, 'LSP: Signature help')
  bufmap('n', '<M-S-i>', user_lsp.peek_definition, 'LSP: Peek definition')
  bufmap('ni', '<M-i>', user_lsp.hover, 'LSP: Hover or focus diagnostic')

  -- map('n', '<M-p>', vim.schedule_wrap(lazy_require('seek').trigger), 'Hover: Preview completions for word under cursor')
end

---@type LazySpec[]
return {
  {
    'neovim/nvim-lspconfig',
    cmd = { 'LspInfo', 'LspStart', 'LspStop', 'LspRestart', 'LspLog' },
    lazy = false,
    config = function()
      user_lsp.setup {
        servers = servers(),
        on_attach = on_attach,
        on_first_attach = on_first_attach,
      }
    end,
  },
  {
    'onsails/lspkind-nvim',
    config = function()
      require('lspkind').init {
        symbol_map = {
          Type = '',
          Copilot = '',
          -- Neopyter:
          Magic = '',
          Path = '',
          ['Dict key'] = '',
          Instance = '󰆧',
          Statement = '󱇯',
        },
      }
    end,
  },
  {
    'jmbuhr/otter.nvim',
    enabled = false,
    dependencies = { 'neovim/nvim-lspconfig' },
    config = function()
      -- require('user.otter').setup()
      local otter = require 'otter'
      -- local keeper = require 'otter.keeper'
      ---@type table<string, string> @ Filetype to extension mapping
      local extensions = require 'otter.tools.extensions'

      -- filetype -> extension mappings
      -- If you want to use an injected language that's not in Otter's
      -- default list, you can add it here. If it's not in the list,
      -- and you don't add it here, the lsp_action wrapper won't work for
      -- that language.
      extensions.glsl = 'glsl'
      extensions.json = 'json'
      extensions.lua = 'lua'
      extensions.typescript = 'ts'
      extensions.tsx = 'tsx'
      extensions.jsx = 'jsx'
      extensions.javascript = 'js'

      -- TODO: Update user mappings to use otter lsp_action
      --
      -- -- If you want to ignore a filetype, you can add it here.
      -- -- the table key is the parent filetype, and the table value
      -- -- can be true (to completely ignore the parent filetype) or
      -- -- a list of injected filetypes to ignore for that parent.
      -- local ignore = {
      --   mdx = {
      --     'html',
      --   },
      -- }
      --
      -- -- Wrapper that checks if the current buffer has a tree-sitter parser and
      -- -- has injected languages. If so, it activates the injected languages and
      -- -- then runs the action via otter. Otherwise, it runs the action via vim.lsp.buf.
      -- -- If all the injected languages are already activated, it does not re-activate
      -- -- them.
      -- -- Example usage:
      -- --   vim.api.nvim_set_keymap('n', 'K', function()
      -- --     lsp_action('hover')
      -- --   end)
      -- local lsp_action = function(action_name)
      --   local injected = {}
      --   local bufnr = vim.api.nvim_get_current_buf()
      --   local function do_action()
      --     if #injected > 0 and keeper._otters_attached[bufnr] then
      --       otter['ask_' .. action_name]()
      --     else
      --       vim.lsp.buf[action_name]()
      --     end
      --   end
      --   local ignore_fts = ignore[vim.bo.filetype]
      --   if ignore_fts == true then
      --     do_action()
      --     return
      --   end
      --   local parser = vim.treesitter.get_parser(bufnr)
      --   if not parser then
      --     do_action()
      --     return
      --   end
      --   for _, node in pairs(parser:children()) do
      --     local lang = node:lang()
      --     local ok = true
      --     ok = ok and extensions[lang] ~= nil
      --     ok = ok and not vim.tbl_contains(ignore_fts or {}, lang)
      --     if ok then
      --       table.insert(injected, lang)
      --     end
      --   end
      --   if #injected == 0 then
      --     do_action()
      --     return
      --   end
      --   local langs = keeper._otters_attached[bufnr] and keeper._otters_attached[bufnr].languages or {}
      --   for _, lang in ipairs(injected) do
      --     if not vim.tbl_contains(langs, lang) then
      --       vim.notify('Activating Otter for ' .. table.concat(injected, ', '))
      --       otter.activate(injected)
      --       vim.defer_fn(function() do_action() end, 0)
      --       return
      --     end
      --   end
      --   do_action()
      -- end

      otter.setup {
        buffers = {
          set_filetype = true,
        },
      }
    end,
  },
  'b0o/schemastore.nvim',
  {
    'rachartier/tiny-code-action.nvim',
    event = 'LspAttach',
    opts = {
      backend = 'delta',

      backend_opts = {
        delta = {
          header_lines_to_remove = 6,
          args = { '--line-numbers', '--width', '168' },
        },
      },
      telescope_opts = {
        layout_strategy = 'vertical',
        layout_config = {
          width = 170,
          height = 40,
          preview_cutoff = 1,
          preview_height = function(_, _, max_lines)
            local h = math.floor(max_lines * 0.5)
            return math.max(h, 10)
          end,
        },
      },
    },
  },
  {
    'smjonas/inc-rename.nvim',
    cmd = { 'IncRename' },
    opts = {},
  },
  -- {
  --   'b0o/seek.nvim',
  --   dev = true,
  --   config = function()
  --     require('seek').setup {
  --       debug = vim.g.SeekDebug or false,
  --     }
  --   end,
  -- },
  {
    'DNLHC/glance.nvim',
    config = function()
      local glance = require 'glance'
      local actions = glance.actions
      ---@diagnostic disable-next-line: missing-fields
      glance.setup {
        zindex = 200,
        mappings = {
          list = {
            ['<C-n>'] = actions.next,
            ['<C-p>'] = actions.previous,
            ['<Down>'] = actions.next,
            ['<Up>'] = actions.previous,
            ['<Tab>'] = actions.next_location,
            ['<S-Tab>'] = actions.previous_location,
            ['<C-j>'] = actions.preview_scroll_win(-1),
            ['<C-k>'] = actions.preview_scroll_win(1),
            ['<C-d>'] = actions.preview_scroll_win(-5),
            ['<C-u>'] = actions.preview_scroll_win(5),
            ['<C-v>'] = actions.jump_vsplit,
            ['<C-x>'] = actions.jump_split,
            ['<C-t>'] = actions.jump_tab,
            ['<M-w>'] = function()
              local win = require('window-picker').pick_window()
              if not win or not vim.api.nvim_win_is_valid(win) then
                return
              end
              actions.jump {
                cmd = function() vim.api.nvim_set_current_win(win) end,
              }
            end,
            ['<M-a>'] = actions.enter_win 'preview',
          },
          preview = {
            ['<Esc>'] = actions.close,
            ['<M-a>'] = actions.enter_win 'list',
          },
        },
      }
    end,
    cmd = 'Glance',
  },
  {
    'marilari88/twoslash-queries.nvim',
    dev = true,
    opts = { multi_line = true },
    ft = {
      'typescript',
      'javascript',
      'typescriptreact',
      'javascriptreact',
    },
  },
  {
    'folke/trouble.nvim',
    cmd = { 'Trouble', 'TroubleClose', 'TroubleRefresh', 'TroubleToggle' },
    opts = {},
  },
  {
    'rachartier/tiny-inline-diagnostic.nvim',
    lazy = false,
    priority = 1000,
    opts = {
      options = {
        show_source = true,
        multilines = {
          enabled = true,
          always_show = true,
        },
        show_all_diags_on_cursorline = true,
      },
    },
  },
}
