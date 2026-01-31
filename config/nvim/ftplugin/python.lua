-- ty LSP configuration with PEP 723 inline script metadata support
-- For PEP 723 scripts (`# /// script`), starts a specialized ty instance using
-- `uvx --with-requirements` to resolve dependencies from the script itself.
-- TODO: Remove PEP 723 handling once ty supports it natively: https://github.com/astral-sh/ty/issues/691

local filepath = vim.fn.expand '%:p'

--- Check if buffer contains PEP 723 inline script metadata.
--- Uses the canonical regex from the spec, adapted for Lua patterns.
--- @see https://peps.python.org/pep-0723/#specification
--- @return boolean
local function has_pep723_metadata()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local content = table.concat(lines, '\n')
  -- PEP 723 specifies: block starts with `# /// script` and ends with `# ///`
  -- The canonical regex is: (?m)^# /// (?P<type>[a-zA-Z0-9-]+)$\s(?P<content>(^#(| .*)$\s)+)^# ///$
  -- Lua pattern equivalent for detecting the script block:
  return content:match '\n# /// script\n' ~= nil or content:match '^# /// script\n' ~= nil
end

local has_inline_metadata = has_pep723_metadata()

local name, cmd, root_dir

if has_inline_metadata then
  -- PEP 723 script: use uvx to resolve inline dependencies
  local filename = vim.fn.fnamemodify(filepath, ':t')
  name = 'ty-' .. filename
  -- Use absolute path for --with-requirements to avoid cwd issues
  cmd = { 'uvx', '--with-requirements', filepath, 'ty', 'server' }
  root_dir = vim.fn.fnamemodify(filepath, ':h')
else
  -- Regular Python file: use standard ty configuration
  name = 'ty'
  cmd = { 'uvx', 'ty', 'server' }
  root_dir = vim.fs.root(0, { 'ty.toml', 'pyproject.toml', 'setup.py', 'setup.cfg', 'requirements.txt', '.git' })
end

vim.lsp.start {
  name = name,
  cmd = cmd,
  root_dir = root_dir,
}
