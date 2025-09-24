local curl = require 'plenary.curl'

local M = {}

---@return string?
M.gh_repo_name_with_owner = function()
  local out = vim.system({ 'gh', 'repo', 'view', '--json', 'nameWithOwner' }):wait()
  if out.code ~= 0 or not out.stdout or out.stdout == '' then
    return nil
  end
  local ok, json = pcall(vim.json.decode, out.stdout)
  if
    not ok
    or not json
    or not json.nameWithOwner
    or type(json.nameWithOwner) ~= 'string'
    or json.nameWithOwner == ''
  then
    return nil
  end
  return json.nameWithOwner
end

M.get_gh_token = function()
  local out = vim.system({ 'gh', 'auth', 'token' }):wait()
  if out.code ~= 0 or not out.stdout or out.stdout == '' then
    return nil
  end
  return out.stdout
end

---@param pr_number number
---@return string[]?
M.gh_pr_range = function(pr_number)
  local name_with_owner = M.gh_repo_name_with_owner()
  if not name_with_owner then
    return nil
  end
  local gh_token = M.get_gh_token()
  if not gh_token then
    return nil
  end
  local res = curl.get {
    url = string.format('https://api.github.com/repos/%s/pulls/%s/commits', name_with_owner, pr_number),
    headers = {
      Authorization = 'Bearer ' .. gh_token,
      Accept = 'application/vnd.github.v3+json',
    },
  }
  if res.status ~= 200 then
    return nil
  end
  if not res.body or res.body == '' then
    return nil
  end
  local ok, body = pcall(vim.json.decode, res.body)
  if not ok or not body or not body.base or not body.head then
    return nil
  end
  if not vim.islist(body) then
    return nil
  end
  local head = body[1] -- newest commit
  local tail = body[#body] -- oldest commit
  -- get parent of oldest commit using the API
  local res = curl.get {
    url = string.format('https://api.github.com/repos/%s/pulls/%s/commits/%s', name_with_owner, pr_number, tail.sha),
    headers = {
      Authorization = 'Bearer ' .. gh_token,
      Accept = 'application/vnd.github.v3+json',
    },
  }
  return { base_sha, head_sha }
end

M.branch_exists = function(branch_name)
  local out = vim.system({ 'git', 'branch', '--list', branch_name }):wait()
  if out.code ~= 0 or not out.stdout then
    return false
  end
  return out.stdout:match(branch_name)
end

M.fetch_pr = function(pr_number)
  local branch_name = 'pull/' .. pr_number
  local remote_head = 'refs/pull/' .. pr_number .. '/head'
  local out = vim.system({ 'git', 'fetch', 'origin', remote_head .. ':' .. branch_name }):wait()
  if out.code ~= 0 then
    return nil
  end
  if not M.branch_exists(branch_name) then
    return nil
  end
  return branch_name
end

return M
