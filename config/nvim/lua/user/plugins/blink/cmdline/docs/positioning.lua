--- Monkey-patch for blink.cmp documentation window positioning (noice compatibility)

local M = {}

--- Monkey-patch documentation window to force east/west positioning in cmdline mode
function M.patch()
  local docs = require 'blink.cmp.completion.windows.documentation'
  local menu = require 'blink.cmp.completion.windows.menu'
  local config = require('blink.cmp.config').completion.documentation
  local win_config = config.window

  ---@diagnostic disable-next-line: duplicate-set-field
  docs.update_position = function()
    if not docs.win:is_open() or not menu.win:is_open() then
      return
    end

    docs.win:update_size()

    local menu_winnr = menu.win:get_win()
    if not menu_winnr then
      return
    end
    local menu_win_config = vim.api.nvim_win_get_config(menu_winnr)
    local menu_win_height = menu.win:get_height()
    local menu_border_size = menu.win:get_border_size()

    -- In cmdline mode, force east/west priority
    local direction_priority
    if vim.api.nvim_get_mode().mode == 'c' then
      direction_priority = { 'e', 'w' }
    else
      local cursor_win_row = vim.fn.winline()
      local menu_win_is_up = menu_win_config.row - cursor_win_row < 0
      direction_priority = menu_win_is_up and win_config.direction_priority.menu_north
        or win_config.direction_priority.menu_south

      -- remove the direction priority of the signature window if it's open
      local signature = require 'blink.cmp.signature.window'
      if signature.win and signature.win:is_open() then
        direction_priority = vim.tbl_filter(
          function(dir) return dir ~= (menu_win_is_up and 's' or 'n') end,
          direction_priority
        )
      end
    end

    -- In cmdline mode, skip broken constraint calculation and use content-based dimensions
    local pos
    if vim.api.nvim_get_mode().mode == 'c' then
      local buf = docs.win:get_buf()
      local line_count = buf and vim.api.nvim_buf_line_count(buf) or 0
      local max_height = win_config.max_height or 20
      local max_width = 100
      local doc_height = math.min(line_count, max_height)

      -- Calculate width based on content (excluding HR and header lines)
      local content_width = 0
      if buf then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        for _, line in ipairs(lines) do
          -- Skip HR lines and markdown header lines
          if not line:match '^─' and not line:match '^%*%*' then
            content_width = math.max(content_width, #line)
          end
        end
      end
      local doc_width = math.min(content_width + 2, max_width)

      pos = { direction = 'e', height = doc_height, width = doc_width }
      docs.win:set_height(doc_height)
      docs.win:set_width(doc_width)
    else
      pos = docs.win:get_direction_with_window_constraints(menu.win, direction_priority, {
        width = win_config.desired_min_width or win_config.min_width or 10,
        height = win_config.desired_min_height or 10,
      })

      -- couldn't find anywhere to place the window
      if not pos then
        docs.win:close()
        return
      end

      -- set width and height based on available space
      docs.win:set_height(pos.height)
      docs.win:set_width(pos.width)
    end

    -- set position based on provided direction
    local height = docs.win:get_height()
    local width = docs.win:get_width()

    local menu_win_is_up = menu_win_config.row - (vim.fn.winline()) < 0

    local function set_config(opts)
      docs.win:set_win_config { relative = 'win', win = menu_winnr, row = opts.row, col = opts.col }
    end
    if pos.direction == 'n' then
      if menu_win_is_up then
        set_config { row = -height - menu_border_size.top, col = -menu_border_size.left }
      else
        set_config { row = -1 - height - menu_border_size.top, col = -menu_border_size.left }
      end
    elseif pos.direction == 's' then
      if menu_win_is_up then
        set_config { row = 1 + menu_win_height - menu_border_size.top, col = -menu_border_size.left }
      else
        set_config { row = menu_win_height - menu_border_size.top, col = -menu_border_size.left }
      end
    elseif pos.direction == 'e' then
      -- In cmdline mode, use simpler positioning that works with noice
      if vim.api.nvim_get_mode().mode == 'c' then
        set_config { row = 0, col = menu_win_config.width + 1 }
      elseif menu_win_is_up and menu_win_height < height then
        set_config {
          row = menu_win_height - menu_border_size.top - height,
          col = menu_win_config.width + menu_border_size.right,
        }
      else
        set_config { row = -menu_border_size.top, col = menu_win_config.width + menu_border_size.right }
      end
    elseif pos.direction == 'w' then
      -- In cmdline mode, use simpler positioning that works with noice
      if vim.api.nvim_get_mode().mode == 'c' then
        set_config { row = 0, col = -width }
      elseif menu_win_is_up and menu_win_height < height then
        set_config {
          row = menu_win_height - menu_border_size.top - height,
          col = -width - menu_border_size.left,
        }
      else
        set_config { row = -menu_border_size.top, col = -width - menu_border_size.left }
      end
    end
  end
end

return M
