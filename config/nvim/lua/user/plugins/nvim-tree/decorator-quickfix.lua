---@class (exact) DecoratorQuickfix: nvim_tree.api.decorator.UserDecorator
---@field private qf_icon nvim_tree.api.HighlightedString
local QuickfixDecorator = require('nvim-tree.api').decorator.UserDecorator:extend()

local augroup = vim.api.nvim_create_augroup('nvim-tree-decorator-quickfix', { clear = true })

local autocmds_setup = false
local function setup_autocmds()
  if autocmds_setup then
    return
  end
  autocmds_setup = true
  vim.api.nvim_create_autocmd('QuickfixCmdPost', {
    group = augroup,
    callback = function() require('nvim-tree.api').tree.reload() end,
  })

  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'qf',
    group = augroup,
    callback = function(evt)
      vim.api.nvim_create_autocmd('TextChanged', {
        buffer = evt.buf,
        group = augroup,
        callback = function() require('nvim-tree.api').tree.reload() end,
      })
    end,
  })
end

function QuickfixDecorator:new()
  self.enabled = true
  self.highlight_range = 'none'
  self.icon_placement = 'signcolumn'
  self.qf_icon = { str = '', hl = { 'QuickFixLine' } }
  self:define_sign(self.qf_icon)
  setup_autocmds()
end

---Helper function to check if a node is in quickfix list
---@param node nvim_tree.api.Node
---@return boolean
local function is_qf_item(node)
  if node.name == '..' or node.type == 'directory' then
    return false
  end
  local bufnr = vim.fn.bufnr(node.absolute_path)
  return bufnr ~= -1 and vim.iter(vim.fn.getqflist()):any(function(qf) return qf.bufnr == bufnr end)
end

---Return quickfix icons for the node
---@param node nvim_tree.api.Node
---@return nvim_tree.api.HighlightedString[]? icons
function QuickfixDecorator:icons(node)
  if is_qf_item(node) then
    return { self.qf_icon }
  end
  return nil
end

---Return highlight group for the node
---@param node nvim_tree.api.Node
---@return string? highlight_group
function QuickfixDecorator:highlight_group(node)
  if is_qf_item(node) then
    return 'QuickFixLine'
  end
  return nil
end

return QuickfixDecorator
