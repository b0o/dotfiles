-- groq.lua
local curl = require 'plenary.curl'

local M = {}

local BASE_URL = 'https://api.groq.com/openai/v1/chat/completions'

function M.client(opts)
  local api_key = opts.api_key

  if not api_key then
    error 'API key is required'
  end

  return {
    chat = {
      completions = {
        create = function(params)
          local headers = {
            ['Content-Type'] = 'application/json',
            ['Authorization'] = 'Bearer ' .. api_key,
          }
          local body = vim.json.encode {
            model = params.model,
            messages = params.messages,
          }
          curl.post(BASE_URL, {
            headers = headers,
            body = body,
            on_error = vim.schedule_wrap(function(err)
              vim.notify(vim.inspect(err))
            end),
            callback = vim.schedule_wrap(function(response)
              if response.status == 200 then
                local data = vim.json.decode(response.body)
                params.on_success(data)
              else
                local err = vim.json.decode(response.body)
                params.on_error(err)
              end
            end),
          })
        end,
      },
    },
  }
end

return M
