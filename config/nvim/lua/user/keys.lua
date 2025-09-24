local M = {}

local utf8 = function(decimal)
  if type(decimal) == 'string' then
    decimal = vim.fn.char2nr(decimal)
  end
  if decimal < 128 then
    return string.char(decimal)
  end
  local charbytes = {}
  for bytes, vals in ipairs { { 0x7FF, 192 }, { 0xFFFF, 224 }, { 0x1FFFFF, 240 } } do
    if decimal <= vals[1] then
      for b = bytes + 1, 2, -1 do
        local mod = decimal % 64
        decimal = (decimal - mod) / 64
        charbytes[b] = string.char(128 + mod)
      end
      charbytes[1] = string.char(vals[2] + decimal)
      break
    end
  end
  return table.concat(charbytes)
end

-- Extra keys
-- Configure your terminal emulator to send the unicode codepoint for each
-- given key sequence
M.xk = setmetatable({
  [ [[<C-S-q>]] ] = utf8(0xff01),
  [ [[<C-M-q>]] ] = utf8(0xff03),
  [ [[<C-M-S-q>]] ] = utf8(0xff04),
  [ [[<C-M-.>]] ] = utf8(0xff05),
  [ [[<C-M-S-.>]] ] = utf8(0xff06),
  [ [[<C-M-j>]] ] = utf8(0x00a7),
  [ [[<C-\>]] ] = utf8(0x00f0),
  [ [[<C-S-\>]] ] = utf8(0x00f1),
  [ [[<M-S-\>]] ] = utf8(0x00f2),
  [ [[<C-M-S-\>]] ] = utf8(0x00ff),
  [ [[<C-`>]] ] = utf8(0x00f3),
  [ [[<C-S-w>]] ] = utf8(0x00f4),
  [ [[<C-S-f>]] ] = utf8(0x00f5),
  [ [[<C-S-t>]] ] = utf8(0x00f6),
  [ [[<C-S-a>]] ] = utf8(0x00f7),
  [ [[<C-'>]] ] = utf8(0x00f8),
  [ [[<C-S-.>]] ] = utf8(0x00fa),
  [ [[<C-.>]] ] = utf8(0x00fb),
  [ [[<C-S-o>]] ] = utf8(0x00fc),
  [ [[<C-S-i>]] ] = utf8(0x00fd),
  [ [[<M-c>]] ] = utf8(0x00fe),
  [ [[<C-/>]] ] = utf8(0x00d4),
  [ [[<C-M-/>]] ] = utf8(0x00d5),
  [ [[<C-S-/>]] ] = utf8(0x00d6),
  [ [[<M-S-/>]] ] = utf8(0x00d7),
  [ [[<C-M-S-/>]] ] = utf8(0x00d8),
  [ [[<M-Space>]] ] = utf8(0x00d9),
  [ [[<C-M-S-s>]] ] = utf8(0x00da),
  [ [[<C-S-u>]] ] = utf8(0x00db),
  [ [[<C-S-r>]] ] = utf8(0x00dc),
  [ [[<C-S-h>]] ] = utf8(0x00d0),
  [ [[<C-S-j>]] ] = utf8(0x00d1),
  [ [[<C-S-k>]] ] = utf8(0x00d2),
  [ [[<C-S-l>]] ] = utf8(0x00d3),
  [ [[<M-S-,>]] ] = utf8(0x00db),

  [ [[<C-Cr>]] ] = '<F12>',
  [ [[<C-S-p>]] ] = '<S-F1>',
  [ [[<C-S-n>]] ] = '<S-F2>',
  [ [[<C-,>]] ] = '<F34>',
}, {
  __index = function(self, k) return rawget(self, k) end,
  __call = function(self, k) return self[k] end,
})

return M
