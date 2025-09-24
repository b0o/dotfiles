local M = {}

---Motion for selecting the best-match named node under the cursor/selection.
---Via https://www.reddit.com/r/neovim/comments/1ckd1rs/helpful_treesitter_node_motion/
M.node_motion = function()
  local bufnr = vim.api.nvim_win_get_buf(0)
  local ok, lang_tree = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not lang_tree then
    return
  end
  local cpos = vim.api.nvim_win_get_cursor(0)
  local vpos = vim.fn.getpos 'v'
  local node = lang_tree:named_node_for_range(
    { vpos[2] - 1, vpos[3] - 1, cpos[1] - 1, cpos[2] + 1 },
    { ignore_injections = false }
  )
  if not node then
    return
  end
  local mode = vim.fn.mode()
  if mode == 'v' or mode == 'V' or mode == vim.api.nvim_replace_termcodes('<C-V>', true, true, true) then
    vim.cmd('normal! ' .. mode)
  end
  local start_row0, start_col0, end_row0, end_col0 = node:range()
  vim.api.nvim_win_set_cursor(0, { start_row0 + 1, start_col0 })
  vim.cmd 'normal! v'
  vim.api.nvim_win_set_cursor(0, { end_row0 + 1, end_col0 - 1 })
end

return M
