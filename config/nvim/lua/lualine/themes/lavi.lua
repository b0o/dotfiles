local lavi = require 'lavi.palette'
local lavi_b = { bg = lavi.bg_bright.hex, fg = lavi.bg.lighten(80).hex }
local lavi_c = { bg = lavi.bg.hex, fg = lavi.bg.lighten(70).hex }
return {
  normal = {
    a = { bg = lavi.bg_bright.lighten(30).hex, fg = lavi.white_bright.hex, gui = 'bold' },
    b = lavi_b,
    c = lavi_c,
  },
  insert = {
    a = { bg = lavi.violet.hex, fg = lavi.white_bright.hex, gui = 'bold' },
    b = lavi_b,
    c = lavi_c,
  },
  visual = {
    a = { bg = lavi.pumpkin.hex, fg = lavi.white_bright.hex, gui = 'bold' },
    b = lavi_b,
    c = lavi_c,
  },
  replace = {
    a = { bg = lavi.red_bright.hex, fg = lavi.white_bright.hex, gui = 'bold' },
    b = lavi_b,
    c = lavi_c,
  },
  command = {
    a = { bg = lavi.blue.hex, fg = lavi.white_bright.hex, gui = 'bold' },
    b = lavi_b,
    c = lavi_c,
  },
  inactive = {
    a = { bg = lavi.bg.hex, fg = lavi.white_bright.hex, gui = 'bold' },
    b = lavi_b,
    c = lavi_c,
  },
}
