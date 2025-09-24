vim.filetype.add {
  extension = {
    astro = 'astro',
    mdx = 'mdx',
    pyx = 'cython',
    pxd = 'cython',
  },
  pattern = {
    ['**/__snapshots__/*.ts.snap'] = { 'jsonc' },
    ['**/__snapshots__/*.js.snap'] = { 'jsonc' },
  },
}
