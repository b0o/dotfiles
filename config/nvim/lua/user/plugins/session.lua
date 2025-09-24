---@type LazySpec[]
return {
  {
    'mbbill/undotree',
    cmd = { 'UndotreeToggle', 'UndotreeHide', 'UndotreeShow', 'UndotreeFocus' },
    keys = {
      { '<leader>ut', '<Cmd>UndotreeToggle<Cr>', desc = 'Undotree: Toggle' },
    },
    config = function()
      vim.g.undotree_SetFocusWhenToggle = 1
    end,
  },
  {
    'Shatur/neovim-session-manager',
    config = function()
      require('session_manager').setup {
        autoload_mode = require('session_manager.config').AutoloadMode.Disabled,
        autosave_last_session = false,
      }
    end,
  },
  {
    'jedrzejboczar/exrc.nvim',
    lazy = false,
    opts = {
      --- IMPORTANT! When you use on_vim_enter=true do not lazy-load
      on_vim_enter = true, -- Load exrc from current directory on start
      use_telescope = false,
    },
  },
}
