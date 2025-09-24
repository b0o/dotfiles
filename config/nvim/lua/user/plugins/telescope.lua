local xk = require('user.keys').xk

---@type LazySpec[]
local spec = {
  {
    'nvim-telescope/telescope.nvim',
    cmd = 'Telescope',
    dependencies = {},
    config = function()
      vim.schedule(function() require 'user.telescope' end)
    end,
  },
  'nvim-lua/popup.nvim',
  'kyoh86/telescope-windows.nvim',
  'nvim-telescope/telescope-github.nvim',
  'natecraddock/telescope-zf-native.nvim',
  'nvim-telescope/telescope-live-grep-args.nvim',
  {
    'axkirillov/easypick.nvim',
    cmd = { 'Easypick' },
    conf = function()
      local easypick = require 'easypick'
      local actions = require 'telescope.actions'
      local action_state = require 'telescope.actions.state'

      local find_first_include = function(bufnr)
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        for i, line in ipairs(lines) do
          if line:find '^#include' then
            return i
          end
        end
        return nil
      end

      local insert_action = function(current_line)
        return function(prompt_bufnr)
          local picker = action_state.get_current_picker(prompt_bufnr)
          local orig_win_id = picker.original_win_id
          local orig_bufnr = vim.api.nvim_win_get_buf(orig_win_id)

          local entry = action_state.get_selected_entry()
          local include = entry.include
          if include == nil then
            return
          end

          local target_line = not current_line and find_first_include(orig_bufnr) or nil
          if target_line ~= nil then
            target_line = target_line - 1
          else
            target_line = vim.api.nvim_win_get_cursor(orig_win_id)[1] - 1
          end

          actions.close(prompt_bufnr)

          vim.api.nvim_buf_set_lines(orig_bufnr, target_line, target_line, false, { include })
        end
      end

      easypick.setup {
        pickers = {
          {
            name = 'headers',
            command = vim.fn.stdpath 'config' .. '/scripts/findheaders.py -f json',
            previewer = easypick.previewers.default(),
            action = function(_, bufmap)
              bufmap({ 'n', 'i' }, '<C-a>', insert_action(false))
              bufmap({ 'n', 'i' }, xk [[<C-S-a>]], insert_action(true))
              bufmap({ 'n', 'i' }, '<C-y>', function(prompt_bufnr)
                local entry = action_state.get_selected_entry()
                local include = entry.include
                if include == nil then
                  return
                end
                actions.close(prompt_bufnr)
                vim.fn.setreg('+', include)
                vim.notify('Copied' .. include, vim.log.levels.INFO)
              end)
              return true
            end,

            entry_maker = function(line)
              local entry = vim.fn.json_decode(line)
              if entry == nil or type(entry) ~= 'table' or entry.include_dir == nil or entry.header_file == nil then
                return {
                  value = line,
                  ordinal = line,
                  display = line,
                }
              end
              local full_path = entry.include_dir .. '/' .. entry.header_file
              return {
                value = full_path,
                ordinal = full_path,
                display = entry.header_file,
                path = full_path,
                include = '#include <' .. entry.header_file .. '>',
              }
            end,
          },
        },
      }
    end,
  },
  {
    '2kabhishek/nerdy.nvim',
    dependencies = { 'stevearc/dressing.nvim' },
    cmd = 'Nerdy',
    opts = {
      use_new_command = true,
    },
  },
  {
    'Allaman/emoji.nvim',
    dependencies = { 'stevearc/dressing.nvim' },
    opts = {},
    cmd = 'Emoji',
  },
}

very_lazy(function()
  local maputil = require 'user.util.map'
  local map = maputil.map
  local wrap = maputil.wrap

  local tu = lazy_require 'user.telescope'
  local tc = tu.cmds

  map('n', xk '<C-S-f>', tc.builtin, 'Telescope: Builtins')
  map('n', '<C-f>b', tc.buffers, 'Telescope: Buffers')
  map('n', { '<C-f>h', '<C-f><C-h>' }, tc.help_tags, 'Telescope: Help tags')

  map('n', { '<C-f>a', '<C-f><C-a>' }, tc.live_grep_args, 'Telescope: Live grep')

  map('n', '<C-f>F', tc.any_files, 'Telescope: Any Files')
  map('n', { '<C-f>o', '<C-f><C-o>' }, tc.oldfiles, 'Telescope: Old files')

  map('n', {
    '<C-f>f',
      -- Don't override Obsidian <C-f><C-f> mapping
    not package.loaded.obsidian and '<C-f><C-f>' or nil,
  }, tc.smart_files, 'Telescope: Files (Smart)')

  map('n', { '<C-f>d', '<C-f><C-d>' }, tc.dir_files, 'Telescope: Files (Dir)')
  map('n', '<C-f>D', tc.dir_grep, 'Telescope: Live Grep (Dir)')
  map('n', { '<C-f>w', '<C-f><C-w>' }, wrap(tc.windows, {}), 'Telescope: Windows')
  map('n', { '<C-f>i', '<C-f><C-i>' }, '<Cmd>Easypick headers<Cr>', 'Telescope: Includes (headers)')

  map('n', { '<C-f>m', '<C-f><C-m>' }, tc.workspace.workspace_package_files, 'Telescope: Workspace package files')
  map('n', { '<C-f>nf', '<C-f>nn' }, tc.workspace.workspace_package_files, 'Telescope: Workspace package files')
  map('n', { '<C-f>M', '<C-f>np' }, tc.workspace.workspace_packages, 'Telescope: Workspace package')
  map('n', { '<C-f>na' }, tc.workspace.workspace_package_grep, 'Telescope: Workspace package files grep')

  map('n', { '<C-f>t', '<C-f><C-t>' }, tc['todo-comments'], 'Telescope: Todo Comments')

  map('n', { '<C-f>r', '<C-f><C-r>' }, tc.resume, 'Telescope: Resume last picker')

  map('n', '<C-f>gf', tc.git_files, 'Telescope-Git: Files')

  map('n', { '<M-f><M-f>', '<M-f>f' }, tc.current_buffer_fuzzy_find, 'Telescope-Buffer: Fuzzy find')
  map('n', '<M-f>t', tc.tags, 'Telescope-Buffer: Tags')

  map('n', '<C-f>A', tc.aerial, 'Telescope-Workspace: Aerial')

  local function gf_telescope(cmd)
    local file = vim.fn.expand '<cfile>'
    if not file or file == '' then
      return
    end
    ---@diagnostic disable-next-line: param-type-mismatch
    if not vim.uv.fs_stat(file) then
      require('telescope.builtin').find_files { default_text = file }
      return
    end
    vim.cmd((cmd or 'edit') .. ' ' .. file)
  end

  map('n', 'gf', gf_telescope, 'Go to file under cursor')
  map('n', 'gF', gf_telescope, 'Go to file under cursor (new tab)')
end)

return spec
