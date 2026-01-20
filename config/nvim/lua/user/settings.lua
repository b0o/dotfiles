vim.o.spell = false
vim.o.spellfile = vim.fn.stdpath 'config' .. '/spellfile.utf-8.add'

vim.o.undofile = true
vim.o.undodir = vim.fn.stdpath 'cache' .. '/undo'

vim.o.backup = true
vim.o.backupdir = vim.fn.stdpath 'data' .. '/backup'

vim.wo.number = true
vim.wo.relativenumber = true
vim.wo.numberwidth = 1

vim.o.hidden = true

vim.o.mouse = 'n'

vim.o.breakindent = true

vim.o.ignorecase = true
vim.o.smartcase = true

vim.o.ignorecase = true -- ignore case when searching
vim.o.smartcase = true -- don't ignore case if user types an uppercase letter
vim.o.magic = true -- change set of special search characters

vim.o.hlsearch = true -- keep matches highlighted after searching
vim.o.incsearch = true -- show matches while typing
vim.opt.inccommand = 'split'

vim.opt.complete = ''
vim.opt.completeopt = ''

vim.o.timeout = true
vim.o.timeoutlen = 350
vim.o.matchtime = 2 -- show matching parens/brackets for 200ms

vim.o.updatetime = 500

vim.o.signcolumn = 'auto:1-2'

vim.o.clipboard = 'unnamedplus' -- Enable yanking between vim sessions and system

vim.o.sessionoptions = 'globals,blank,buffers,curdir,folds,help,tabpages,winsize'

vim.o.splitright = true -- default vertical splits to open on right
vim.o.splitbelow = true -- default horizontal splits to open on bottom

vim.o.eadirection = 'hor'

vim.o.wildchar = 9 -- equivalent to 'set wildchar=<Tab>'

vim.o.modeline = true -- always parse modelines when loading files
vim.o.exrc = false -- use jedrzejboczar/exrc.nvim instead

vim.g.mapleader = ' '
vim.g.maplocalleader = ','

vim.o.splitkeep = 'screen' -- keep the text on the same screen line when splitting

vim.opt.shortmess:append 'I' -- Disable intro message

vim.o.title = true
vim.o.titlestring = 'nvim: %f'

vim.o.showtabline = 0

vim.o.cursorline = true

vim.o.showmode = false
vim.o.showcmd = true
vim.o.showcmdloc = 'statusline'
vim.o.ruler = false
vim.o.cmdheight = 0
vim.o.wrap = false

vim.o.laststatus = 3
vim.o.statusline = '%{""}'

vim.o.showmatch = true

vim.o.scrolloff = 5
vim.o.smoothscroll = true -- scroll by screen line rather than by text line when wrap is set

vim.o.winborder = 'rounded'

vim.opt.list = true
vim.opt.listchars = {
  eol = '¬',
  tab = 'ᐧᐧᐧ',
  trail = '~',
  extends = '»',
  precedes = '«',
}
vim.opt.fillchars = {
  diff = '╱',
}

vim.o.termguicolors = true

vim.o.shell = 'nu'
vim.o.shellcmdflag = '-c'

--- Diagnostics
vim.diagnostic.config {
  virtual_text = false,
  float = {
    border = 'rounded',
    prefix = function(diagnostic)
      ---@cast diagnostic vim.Diagnostic
      local source = diagnostic.source
      local replacements = {
        ['Lua Diagnostics.'] = 'LuaLS',
      }
      source = replacements[source] or source
      ---@diagnostic disable-next-line: missing-return-value
      return source and ('[' .. source .. '] ') or ''
    end,
  },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = ' ',
      [vim.diagnostic.severity.WARN] = ' ',
      [vim.diagnostic.severity.HINT] = ' ',
      [vim.diagnostic.severity.INFO] = ' ',
    },
  },
  underline = true,
  update_in_insert = false,
}

vim.g.health = { style = 'float' }

---- Providers
vim.g.loaded_perl_provider = 0

---- Builtin plugins
-- Disable default matchparen plugin
vim.g.loaded_matchparen = 1

---- Filetypes
-- disable default man.vim mappings
vim.g.no_man_maps = 1

-- Disable netrw
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
