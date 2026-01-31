--- Cheatsheet definitions for substitute/global commands

local b = require 'user.plugins.blink.cmdline.cheatsheet.builder'

local hr = b.hr
local header = b.header
local cell = b.cell
local codes = b.codes
local row = b.row
local section = b.section
local cheatsheet = b.cheatsheet

local M = {}

M.search = cheatsheet('Search Pattern', {
  hr(),
  section {
    row(cell('.', 'any char'), cell('\\s', 'whitespace'), cell('\\d', 'digit')),
    row(cell('*', '0+ greedy'), cell('\\S', 'non-ws'), cell('\\D', 'non-digit')),
    row(cell('\\+', '1+ greedy'), cell('\\w', 'word char'), cell('\\a', 'alpha')),
    row(cell('\\?', '0 or 1'), cell('\\W', 'non-word'), cell('\\l', 'lowercase')),
    row(cell('\\{n,m}', 'n to m'), cell('\\<', 'word start'), cell('\\u', 'uppercase')),
  },
  hr(),
  section {
    row(cell('^', 'line start'), cell('$', 'line end'), cell('\\_^', 'file start')),
    row(cell('\\zs', 'match start'), cell('\\ze', 'match end'), cell('\\_$', 'file end')),
  },
  hr(),
  section {
    row(cell('[abc]', 'any of'), cell('[^abc]', 'not any'), cell('[a-z]', 'range')),
    row(cell('\\(pat\\)', 'group'), cell('\\|', 'or'), cell('\\%(pat\\)', 'no-cap')),
    row(cell('\\1-\\9', 'backref', { join = '-' }), cell('\\c', 'ignore case'), cell('\\C', 'match case')),
  },
  hr(),
  section {
    row(cell('\\v', 'very magic (perl-like)'), cell('\\V', 'very nomagic (literal)')),
  },
})

M.replace = cheatsheet('Replacement String', {
  hr(),
  section {
    row(codes({ '&', '\\0' }, ' or ', 'whole match')),
    row(cell('\\1-\\9', 'captured group 1-9', { join = '-' })),
    row(cell('~', 'previous replacement string')),
  },
  hr(),
  section {
    row(cell('\\r', 'newline'), cell('\\t', 'tab')),
    row(cell('\\u', 'next char upper'), cell('\\U', 'rest upper')),
    row(cell('\\l', 'next char lower'), cell('\\L', 'rest lower')),
    row(codes({ '\\e', '\\E' }, ' or ', 'end case conversion')),
  },
  hr(),
  section {
    row(cell('\\=expr', 'evaluate vimscript expression')),
    row(cell('\\=submatch(0)', 'whole match')),
    row(cell('\\=submatch(1)', 'group 1')),
    row(cell("\\=line('.')", 'current line number')),
  },
})

M.flags = cheatsheet('Substitute Flags', {
  hr(),
  section {
    row(cell('g', 'all occurrences (not just first)')),
    row(cell('c', 'confirm each substitution')),
    row(cell('i', 'ignore case')),
    row(cell('I', "don't ignore case")),
    row(cell('n', 'count matches only (no substitute)')),
    row(cell('e', 'no error if pattern not found')),
    row(cell('p', 'print last changed line')),
    row(cell('l', 'print last line like :list')),
    row(cell('#', 'print last line with line number')),
  },
  hr(),
  section {
    row(cell(':s/pat/rep/gc', 'Combine: all + confirm')),
  },
})

M.global = cheatsheet('Global Command', {
  hr(),
  section {
    row(cell(':g/pattern/cmd', 'execute cmd on matching lines')),
    row(cell(':g!/pattern/cmd', 'execute cmd on NON-matching lines')),
    row(cell(':v/pattern/cmd', 'same as :g!')),
  },
  hr(),
  header 'Common commands:',
  section {
    row(cell('d', 'delete line'), cell('y', 'yank line')),
    row(cell('p', 'print line'), cell('m$', 'move to end')),
    row(cell('t.', 'copy to here'), cell('j', 'join with next')),
    row(cell('s/x/y/g', 'substitute'), cell('norm @q', 'run macro')),
  },
  hr(),
  section {
    row(cell(':g/pat/t$', 'copy all matches to end')),
    row(cell(':g/^$/d', 'delete empty lines')),
    row(cell(':g/pat/m0', 'reverse matching lines')),
    row(cell(':v/pat/d', 'keep only matching lines')),
  },
})

M.global_cmd = cheatsheet('Command after :g/pattern/', {
  hr(),
  section {
    row(cell('d', 'delete matching lines')),
    row(cell('y', 'yank matching lines')),
    row(cell('p', 'print matching lines')),
    row(cell('m{addr}', 'move lines to {addr}')),
    row(cell('t{addr}', 'copy lines to {addr}')),
    row(cell('j', 'join with next line')),
    row(cell('norm {x}', 'execute normal mode {x}')),
    row(cell('s/x/y/g', 'substitute on matching lines')),
  },
  hr(),
  header 'Examples:',
  section {
    row(cell(':g/TODO/p', 'print TODOs')),
    row(cell(':g/^#/d', 'delete comments')),
    row(cell(':g/./t$', 'copy non-empty to end')),
    row(cell(':g/pat/norm @q', 'run macro q on matches')),
  },
})

return M
