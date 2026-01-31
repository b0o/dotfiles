---@type LazySpec[]
return {
  {
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    build = ':TSUpdate',
    lazy = false,
    config = function()
      local parsers = {
        { 'bash', filetypes = { 'sh', 'bash' } },
        'c',
        'capnp',
        'cmake',
        'cpp',
        'css',
        { 'cython', install = false, filetypes = { 'pyx', 'pxd' } },
        'dockerfile',
        'diff',
        'gitcommit',
        'git_rebase',
        'gitignore',
        'glsl',
        'go',
        'graphql',
        'html',
        'javascript',
        'jsdoc',
        { 'json', filetypes = { 'json', 'jsonc' } },
        'just',
        'kdl',
        'lua',
        'make',
        'markdown',
        { 'markdown_inline', filetypes = { 'lsp_markdown' } },
        'nix',
        'nu',
        'python',
        'query',
        { 'regex', filetypes = {} },
        'rust',
        'svelte',
        'swift',
        'toml',
        'typescript',
        { 'tsx', filetypes = { 'typescriptreact', 'javascriptreact' } },
        'vim',
        { 'vimdoc', filetypes = { 'help' } },
        'yaml',
        'zig',
      }

      require('nvim-treesitter').install(
        vim
          .iter(parsers)
          :filter(function(p) return type(p) == 'string' or p.install == nil or p.install == true end)
          :map(function(p) return type(p) == 'string' and p or p[1] end)
          :totable(),
        { summary = true }
      )

      vim.api.nvim_create_autocmd('FileType', {
        pattern = vim
          .iter(parsers)
          :map(function(p) return type(p) == 'string' and p or p.filetypes or { p[1] } end)
          :flatten()
          :totable(),
        callback = function()
          vim.treesitter.start()
          vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })

      -- TODO: install with nix
      vim.treesitter.language.register('markdown', { 'mdx' })
      local cython_parser = vim.fn.stdpath 'cache' .. '/../tree-sitter/lib/cython.so'
      if vim.fn.filereadable(cython_parser) == 1 then
        vim.treesitter.language.add('cython', { path = cython_parser })
        vim.treesitter.language.register('cython', { 'pyx', 'pxd' })
      end
    end,
  },
  {
    'nvim-treesitter/nvim-treesitter-textobjects',
    branch = 'main',
    event = 'VeryLazy',
    config = function()
      require('nvim-treesitter-textobjects').setup {
        select = { lookahead = true },
        move = { set_jumps = true },
      }

      local map = require('user.util.map').map

      ---@param query string
      ---@return function
      ---@return string
      local select = function(query)
        return function() require('nvim-treesitter-textobjects.select').select_textobject(query, 'textobjects') end,
          'Select ' .. query
      end

      map('ox', 'af', select '@function.outer')
      map('ox', 'if', select '@function.inner')
      map('ox', 'ip', select '@parameter.inner')
      map('ox', 'ap', select '@parameter.outer')
      map('ox', 'ib', select '@block.inner')
      map('ox', 'ab', select '@block.outer')
      map('ox', 'im', select '@class.inner')
      map('ox', 'am', select '@class.outer')
      map('ox', 'aa', select '@call.outer')
      map('ox', 'ia', select '@call.inner')
      map('ox', 'a/', select '@comment.outer')
      map('ox', 'i/', select '@comment.outer')

      ---@param dir string
      ---@param dest string
      ---@param query string
      ---@param group? string
      ---@return function
      ---@return string
      local function go_to(dir, dest, query, group)
        return function()
          if dir == 'prev' then
            dir = 'previous'
          end
          require('nvim-treesitter-textobjects.move')['goto_' .. dir .. '_' .. dest](query, group)
        end,
          'Goto ' .. dir .. ' ' .. query .. ' ' .. dest
      end

      map('nox', '[f', go_to('prev', 'start', '@function.outer'))
      map('nox', '[F', go_to('prev', 'end', '@function.outer'))
      map('nox', ']f', go_to('next', 'start', '@function.outer'))
      map('nox', ']F', go_to('next', 'end', '@function.outer'))
      map('nox', '[m', go_to('prev', 'start', '@class.outer'))
      map('nox', '[M', go_to('prev', 'end', '@class.outer'))
      map('nox', ']m', go_to('next', 'start', '@class.outer'))
      map('nox', ']M', go_to('next', 'end', '@class.outer'))
      map('nox', '[p', go_to('prev', 'start', '@parameter.outer'))
      map('nox', '[P', go_to('prev', 'end', '@parameter.outer'))
      map('nox', ']p', go_to('next', 'start', '@parameter.outer'))
      map('nox', ']P', go_to('next', 'end', '@parameter.outer'))
      map('nox', '[b', go_to('prev', 'start', '@block.outer'))
      map('nox', '[B', go_to('prev', 'end', '@block.outer'))
      map('nox', ']b', go_to('next', 'start', '@block.outer'))
      map('nox', ']B', go_to('next', 'end', '@block.outer'))
      map('nox', '[a', go_to('prev', 'start', '@call.outer'))
      map('nox', '[A', go_to('prev', 'end', '@call.outer'))
      map('nox', ']a', go_to('next', 'start', '@call.outer'))
      map('nox', ']A', go_to('next', 'end', '@call.outer'))
      map('nox', '[/', go_to('prev', 'start', '@comment.outer'))
      map('nox', '[?', go_to('prev', 'end', '@comment.outer'))
      map('nox', ']/', go_to('next', 'start', '@comment.outer'))
      map('nox', ']?', go_to('next', 'end', '@comment.outer'))

      -- restore paragraph textobjects
      map('ox', 'aP', 'ap', 'Select paragraph outer')
      map('ox', 'iP', 'ip', 'Select paragraph inner')
    end,
  },
  {
    'nvim-treesitter/nvim-treesitter-context',
    event = 'VeryLazy',
    opts = {
      enable = true,
      max_lines = 4,
    },
  },
  'JoosepAlviste/nvim-ts-context-commentstring',
  {
    'Wansmer/sibling-swap.nvim',
    event = 'VeryLazy',
    config = function()
      local sibling_swap = require 'sibling-swap'
      ---@diagnostic disable-next-line: missing-fields
      sibling_swap.setup {
        use_default_keymaps = false,
        allow_interline_swaps = true,
      }
      local map = require('user.util.map').map
      local xk = require('user.keys').xk
      map('n', xk '<C-.>', sibling_swap.swap_with_right, 'Sibling-Swap: Swap with right')
      map('n', xk '<C-,>', sibling_swap.swap_with_left, 'Sibling-Swap: Swap with left')
    end,
  },
  {
    'Wansmer/treesj',
    event = 'VeryLazy',
    config = function()
      local lang_utils = require 'treesj.langs.utils'
      local treesj = require 'treesj'

      treesj.setup {
        use_default_keymaps = false,
        check_syntax_error = true,
        max_join_length = 2000,
        cursor_behavior = 'hold',
        notify = true,
        langs = {
          zig = {
            initializer_list = lang_utils.set_preset_for_list(),
            arguments = lang_utils.set_preset_for_args(),
            call_expression = lang_utils.set_preset_for_args {
              split = {
                last_separator = true,
              },
              both = {
                shrink_node = { from = '(', to = ')' },
              },
            },
          },
          -- TODO: Remove once https://github.com/Wansmer/treesj/pull/187 is merged
          nu = require 'treesj.langs.nu',
        },
        dot_repeat = true,
      }
      local map = require('user.util.map').map
      map('n', 'gJ', treesj.toggle, 'Treesj: Toggle')
      map('n', 'gsj', treesj.join, 'Treesj: Join')
      map('n', 'gss', treesj.split, 'Treesj: Split')
    end,
  },
  {
    'windwp/nvim-ts-autotag',
    event = 'VeryLazy',
    config = function()
      require('nvim-ts-autotag').setup {
        opts = {
          enable_close = true,
          enable_rename = true,
          enable_close_on_slash = true,
        },
      }
    end,
  },
}
