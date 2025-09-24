---@type LazySpec[]
return {
  {
    'KabbAmine/vCoolor.vim',
    cmd = { 'VCoolIns', 'VCoolor' },
    keys = {
      { '<leader>cO', '<Cmd>VCoolor<Cr>', mode = 'n', desc = 'Open VCooler color picker' },
    },
    config = function()
      vim.g.vcoolor_lowercase = 0
      vim.g.vcoolor_disable_mappings = 1

      -- Use yad as the color picker (Linux)
      if vim.fn.has 'unix' then
        vim.g.vcoolor_custom_picker = table.concat({
          'yad',
          '--title="Color Picker"',
          '--color',
          '--splash',
          '--on-top',
          '--skip-taskbar',
          '--init-color=',
        }, ' ')
      end
    end,
  },
  {
    'NvChad/nvim-colorizer.lua',
    cmd = {
      'Colorize',
      'ColorizerAttachToBuffer',
      'ColorizerDetachFromBuffer',
      'ColorizerToggle',
      'ColorizerReloadAllBuffers',
    },
    config = function()
      require('colorizer').setup {
        user_default_options = {
          --   RGB = true,
          --   RRGGBB = true,
          names = true,
          --   RRGGBBAA = true,
          css = true,
          tailwind = true,
          mode = 'virtualtext',
        },
      }
      vim.api.nvim_create_user_command('Colorize', 'ColorizerToggle', {})
    end,
  },
  {
    'uga-rosa/ccc.nvim',
    cmd = { 'CccPick' },
    keys = {
      { '<leader>co', '<Cmd>CccPick<Cr>', mode = 'n', desc = 'Open CCC color picker' },
    },
    config = function()
      local ccc = require 'ccc'
      local ColorInput = require 'ccc.input'
      local convert = require 'ccc.utils.convert'
      local utils = require 'ccc.utils'

      local mapping = ccc.mapping

      local RgbHslInput = setmetatable({
        name = 'RGB/HSL',
        max = { 1, 1, 1, 360, 1, 1 },
        min = { 0, 0, 0, 0, 0, 0 },
        delta = { 1 / 255, 1 / 255, 1 / 255, 1, 0.01, 0.01 },
        bar_name = { 'R', 'G', 'B', 'H', 'S', 'L' },
      }, { __index = ColorInput })

      ---@diagnostic disable-next-line: duplicate-set-field
      function RgbHslInput.format(n, i)
        if i <= 3 then
          -- RGB
          n = n * 255
        elseif i == 5 or i == 6 then
          -- S or L of HSL
          n = n * 100
        end
        return ('%6d'):format(n)
      end

      function RgbHslInput.from_rgb(RGB)
        local HSL = convert.rgb2hsl(RGB)
        local R, G, B = unpack(RGB)
        local H, S, L = unpack(HSL)
        return { R, G, B, H, S, L }
      end

      function RgbHslInput.to_rgb(value) return { value[1], value[2], value[3] } end

      function RgbHslInput:_set_rgb(RGB)
        self.value[1] = RGB[1]
        self.value[2] = RGB[2]
        self.value[3] = RGB[3]
      end

      function RgbHslInput:_set_hsl(HSL)
        self.value[4] = HSL[1]
        self.value[5] = HSL[2]
        self.value[6] = HSL[3]
      end

      ---@diagnostic disable-next-line: duplicate-set-field
      function RgbHslInput:callback(index, new_value)
        self.value[index] = new_value
        local v = self.value
        if index <= 3 then
          local RGB = { v[1], v[2], v[3] }
          local HSL = convert.rgb2hsl(RGB)
          self:_set_hsl(HSL)
        else
          local HSL = { v[4], v[5], v[6] }
          local RGB = convert.hsl2rgb(HSL)
          self:_set_rgb(RGB)
        end
      end

      local FuncRgbOutput = {
        name = 'FuncRGB',
      }

      function FuncRgbOutput.str(RGB, A)
        local R, G, B = convert.rgb_format(RGB)
        R = utils.round(R)
        G = utils.round(G)
        B = utils.round(B)
        if A then
          A = utils.round(A * 100)
          return ('rgba(%d, %d, %d, %d)'):format(R, G, B, A)
        else
          return ('rgb(%d, %d, %d)'):format(R, G, B)
        end
      end

      ccc.setup {
        inputs = {
          RgbHslInput,
        },
        outputs = {
          ccc.output.hex,
          ccc.output.hex_short,
          ccc.output.css_rgb,
          ccc.output.css_hsl,
          FuncRgbOutput,
        },
        mappings = {
          ['$'] = mapping.set100,
          ['<Esc>'] = mapping.quit,
        },
      }
    end,
  },
}
