local dap = require 'dap'

local M = {
  launchers = {},
  closers = {},
}

local signs = {
  DapBreakpoint = '󰍟',
  DapBreakpointCondition = '󰅂',
  DapLogPoint = '',
  DapStopped = '',
  DapBreakpointRejected = '󱈸',
}

for k, v in pairs(signs) do
  vim.fn.sign_define(k, { text = v, texthl = k, priority = 50 })
end

---- Lua
-- local lua_conf = {
--   host = '127.0.0.1',
--   port = 57801,
--   log = false,
-- }
-- dap.configurations.lua = {
--   {
--     type = 'nlua',
--     request = 'attach',
--     name = 'Attach to running Neovim instance',
--     host = lua_conf.host,
--     port = lua_conf.port,
--   },
-- }
-- dap.adapters.nlua = function(callback, config)
--   callback { type = 'server', host = config.host, port = config.port }
-- end
-- M.nlua_launch = function()
--   require('osv').launch(lua_conf)
-- end
-- M.launchers.nlua = function()
--   --   require('osv').launch(lua_conf)
--   local terminal = (os.getenv 'TERMINAL') or 'alacritty'
--   local cmd = {
--     terminal,
--     '-e',
--     'nvim',
--     '--cmd',
--     'set noswapfile',
--     '-c',
--     'lua require"user.dap".nlua_launch()',
--     '+' .. vim.fn.getcurpos()[2],
--     vim.fn.expand '%:p',
--   }
--   M.job = vim.fn.jobstart(cmd)
--   vim.wait(500, function()
--     vim.fn.system(('nc -z %s %d'):format(lua_conf.host, lua_conf.port))
--     return vim.v.shell_error == 0
--   end)
--   vim.cmd 'sleep 500m'
-- end
-- M.closers.nlua = function()
--   require('osv').stop()
-- end

dap.adapters['local-lua'] = {
  type = 'executable',
  command = 'local-lua-dbg',
  enrich_config = function(config, on_config)
    if not config['extensionPath'] then
      local c = vim.deepcopy(config)
      c.extensionPath = '/usr/lib/node_modules/local-lua-debugger-vscode'
      on_config(c)
    else
      on_config(config)
    end
  end,
}
dap.configurations.lua = {
  {
    name = 'Current file (local-lua-dbg, lua)',
    type = 'local-lua',
    repl_lang = 'lua',
    request = 'launch',
    cwd = '${workspaceFolder}',
    program = {
      lua = 'luajit',
      file = '${file}',
    },
    args = {},
  },
  {
    name = 'Current file (local-lua-dbg, neovim lua interpreter with nlua)',
    type = 'local-lua',
    repl_lang = 'lua',
    request = 'launch',
    cwd = '${workspaceFolder}',
    program = {
      lua = 'nlua',
      file = '${file}',
    },
    args = {},
  },
}

-- Python
require('dap-python').setup()

-- Chrome
local js_chrome_conf = {
  port = 9222,
}
dap.adapters.chrome = {
  type = 'executable',
  command = 'node',
  args = { os.getenv 'GIT_PROJECTS_DIR' .. '/vscode-chrome-debug/out/src/chromeDebug.js' },
}
dap.configurations.javascript = {
  {
    name = 'Chrome',
    type = 'chrome',
    request = 'attach',
    program = '${file}',
    cwd = vim.fn.getcwd(),
    sourceMaps = true,
    protocol = 'inspector',
    port = js_chrome_conf.port,
    webRoot = '${workspaceFolder}',
  },
}
M.launchers.chrome = function()
  vim.fn.system('lsof -i :' .. js_chrome_conf.port)
  if vim.v.shell_error == 0 then
    print 'Already started'
    return
  end
  local cmd = {
    'chromium',
    '--user-data-dir=$XDG_CONFIG_HOME/chromium-dap',
    '--remote-debugging-port=' .. js_chrome_conf.port,
    '--auto-open-devtools-for-tabs ',
  }
  if os.getenv 'WAYLAND_DISPLAY' then
    vim.list_extend(cmd, {
      '--enable-features=UseOzonePlatform',
      '--ozone-platform=wayland',
    })
  end

  local html = [[
    <html>
      <head>
        <title>Debug Adapter</title>
        <style>
          body{
            color: #ffffff;
            background: #111111;
          }
        </style>
      </head>
      <body>
        <h1>Debug Adapter</h1>
        <script src="http://localhost:19222/const-try.js"></script>
      </body>
    </html>
  ]]

  table.insert(cmd, ('"data:text/html;base64,%s"'):format(require('base64').encode(html)))
  M.job = vim.fn.jobstart(cmd)
end

require('nvim-dap-virtual-text').setup { virt_text_pos = 'eol', clear_on_continue = true }

function M.launch(ft)
  if not dap.configurations[ft] then
    vim.notify('No DAP configurations found for ' .. ft, vim.log.levels.ERROR)
    return
  end
  for _, config in ipairs(dap.configurations[ft]) do
    if config.type and M.launchers[config.type] then
      M.launchers[config.type]()
    end
    dap.run(config)
  end
end

function M.close(ft)
  if not dap.configurations[ft] then
    vim.notify('No DAP configurations found for ' .. ft, vim.log.levels.ERROR)
    return
  end
  for _, config in ipairs(dap.configurations[ft]) do
    if config.type and M.launchers[config.type] then
      M.closers[config.type]()
    end
  end
  dap.disconnect { restart = false, terminateDebuggee = false }
  dap.close()
  if M.job then
    vim.fn.jobstop(M.job)
  end
end

local dapui = lazy_require 'dapui'

require('dapui').setup {
  select_window = lazy_require('window-picker').pick_window,
}

dap.listeners.before.attach.dapui_config = function()
  dapui.open()
end
dap.listeners.before.launch.dapui_config = function()
  dapui.open()
end
dap.listeners.before.event_terminated.dapui_config = function()
  dapui.close()
end
dap.listeners.before.event_exited.dapui_config = function()
  dapui.close()
end

return M
