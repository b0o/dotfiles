local M = {
  state = { prev_win = {} },
}

local function is_ignored_buf(bufnr)
  bufnr = bufnr or 0
  if not vim.bo[bufnr].buflisted then
    return true
  end
  if vim.api.nvim_buf_get_name(bufnr) == '' then
    return true
  end
  if vim.bo[bufnr].buftype ~= '' then
    return true
  end
  return false
end

function M.is_ignored_win(winid)
  winid = winid or 0
  if is_ignored_buf(vim.api.nvim_win_get_buf(winid)) then
    return true
  end
  if vim.fn.win_gettype(winid) ~= '' then
    return true
  end
  return false
end

function M.get_most_recent_win(tabpage)
  local win = vim.api.nvim_tabpage_get_win(tabpage)
  if
    M.is_ignored_win(win)
    and M.state.prev_win[tabpage] ~= nil
    and vim.api.nvim_win_is_valid(M.state.prev_win[tabpage])
  then
    win = M.state.prev_win[tabpage]
  end
  M.state.prev_win[tabpage] = win
  return win
end

function M.get_most_recent_buf(tabpage)
  return vim.api.nvim_win_get_buf(M.get_most_recent_win(tabpage))
end

return M
