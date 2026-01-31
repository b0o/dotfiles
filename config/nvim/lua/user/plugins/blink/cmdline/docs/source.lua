--- Monkey-patch for blink.cmp cmdline source to provide :help documentation

local M = {}

--- Monkey-patch cmdline source to provide documentation via :help
function M.patch()
  local cmdline_source = require 'blink.cmp.sources.cmdline'
  local orig_new = cmdline_source.new
  cmdline_source.new = function(...)
    local self = orig_new(...)
    function self:resolve(item, callback)
      -- Skip if item already has documentation (e.g., from LSP)
      if item.documentation then
        return callback(item)
      end

      -- Use textEdit.newText for full context (e.g., "vim.api.nvim_buf_get_lines")
      -- Fall back to label if not available
      local topic = (item.textEdit and item.textEdit.newText) or item.label or item.filterText
      if not topic or topic == '' then
        return callback(item)
      end

      -- Strip leading = from := syntax (and remember we're in lua context)
      local is_lua_expr = topic:match '^='
      if is_lua_expr then
        topic = topic:sub(2)
      end

      -- Check if help exists using getcompletion, then read help content
      vim.schedule(function()
        local ok, result = pcall(function()
          -- Determine if we're completing a command (at start) or an argument
          local is_command_position = item.textEdit
            and item.textEdit.insert
            and item.textEdit.insert.start
            and item.textEdit.insert.start.character == 0

          -- Try different help tag formats, starting with the full topic
          local last_component = topic:match '[^.]+$'
          local candidates = {
            topic, -- full text: vim.api.nvim_buf_get_lines
            topic .. '()', -- full text as function: table.insert()
            topic:gsub('%.', '-'), -- dot to dash: vim.api -> vim-api
            'lua-' .. topic, -- lua prefix: lua-vim
            "'" .. topic .. "'", -- option: 'shiftwidth'
            last_component and (last_component .. '()'), -- function: nvim_buf_get_lines()
            last_component and ('lua-' .. last_component), -- lua prefix on last component
          }

          -- Only add bare last_component for non-lua contexts to avoid matching unrelated help
          if not is_lua_expr and not topic:match '%.' then
            table.insert(candidates, last_component)
          end

          -- Only try :command format if we're at command position (not completing args or lua expr)
          if is_command_position and not is_lua_expr then
            table.insert(candidates, 2, ':' .. topic)
          end

          -- For arguments (not commands/lua), skip simple words that likely aren't vim help topics
          -- (e.g., "help", "left", "right" as args to custom commands)
          if not is_command_position and not is_lua_expr then
            local is_simple_word = topic:match '^%l+$' and not topic:match '_'
            if is_simple_word then
              return nil
            end
          end

          local help_topic = nil
          for _, candidate in ipairs(candidates) do
            if candidate then
              local topics = vim.fn.getcompletion(candidate, 'help')
              -- Filter out :command style results when not at command position
              if not is_command_position then
                topics = vim.tbl_filter(function(t)
                  return not t:match '^:'
                end, topics)
              end
              -- Only accept exact matches to avoid showing unrelated help
              for _, t in ipairs(topics) do
                if t == candidate then
                  help_topic = t
                  break
                end
              end
              if help_topic then
                break
              end
            end
          end

          if not help_topic then
            return nil
          end

          -- Read help tags files to find the file and location
          local tag_files = vim.api.nvim_get_runtime_file('doc/tags', true)
          for _, tag_file in ipairs(tag_files) do
            local lines = vim.fn.readfile(tag_file)
            for _, line in ipairs(lines) do
              local tag, file, pattern = line:match '^([^\t]+)\t([^\t]+)\t(.+)$'
              if tag == help_topic then
                local doc_dir = vim.fn.fnamemodify(tag_file, ':h')
                local help_file = doc_dir .. '/' .. file

                -- Read the help file and find the tag location
                local help_lines = vim.fn.readfile(help_file)
                local search_pattern = pattern:gsub('^/', ''):gsub('/$', ''):gsub('\\*', '*')
                for i, help_line in ipairs(help_lines) do
                  if
                    help_line:find(search_pattern, 1, true) or help_line:find('%*' .. vim.pesc(help_topic) .. '%*')
                  then
                    return {
                      topic = help_topic,
                      file = file,
                      lines = vim.list_slice(help_lines, i, math.min(i + 25, #help_lines)),
                    }
                  end
                end
              end
            end
          end
          return nil
        end)

        if ok and result and result.lines and #result.lines > 0 then
          -- Calculate width based on content, capped at max
          local max_width = 100
          local content_width = 0
          for _, line in ipairs(result.lines) do
            content_width = math.max(content_width, #line)
          end
          local doc_width = math.min(content_width + 2, max_width)
          local hr = string.rep('─', doc_width)
          -- Create header with topic left-aligned and file right-aligned
          local left = ':h ' .. result.topic
          local right = result.file or ''
          -- Account for markdown formatting: ** ** * * = 8 chars
          local padding = doc_width - #left - #right - 8
          local header = '**' .. left .. '**' .. string.rep(' ', math.max(1, padding)) .. '*' .. right .. '*'
          item.documentation = {
            kind = 'markdown',
            value = header .. '\n' .. hr .. '\n```help\n' .. table.concat(result.lines, '\n') .. '\n```',
          }
        end
        callback(item)
      end)
    end
    return self
  end
end

return M
