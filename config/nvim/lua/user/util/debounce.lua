local Debounce = {}

function Debounce:clear_timer()
  if self.timer then
    self.timer:stop()
    self.timer = nil
  end
end

function Debounce:reset()
  self:clear_timer()
  self.phase = 0
  self.waiting = false
end

function Debounce:call(...)
  local args = { ... }
  if self.phase == 0 then
    self.phase = 1
    self.timer = vim.defer_fn(function() -- 1 -> 2 (rising)
      if self.opts.mode == 'throttle' then
        self:immediate(unpack(args))
        self.phase = 2
      end
      self:clear_timer()
      self.timer = vim.defer_fn(function() -- 2 -> 0 (falling)
        if self.opts.mode == 'rolling' then
          self:immediate(unpack(args))
        else
          if self.waiting then
            self:immediate(unpack(args))
          else
            self:reset()
          end
        end
      end, type(self.opts.threshold) == 'table' and self.opts.threshold.falling or self.opts.threshold)
    end, type(self.opts.threshold) == 'table' and self.opts.threshold.rising or self.opts.threshold)
  elseif self.phase == 2 then
    self.waiting = true
  end
end

function Debounce:immediate(...)
  self:reset()
  self.fn(...)
end

-- ref() returns a normal function which, when called, calls Debounce:call()
-- bound to the original instance.
-- Useful for using Debounce with an API that doesn't accept callable tables.
function Debounce:ref()
  return function(...)
    self:call(...)
  end
end

local function make(fn, opts)
  return setmetatable({
    fn = fn,
    timedout = false,
    waiting = false,
    -- 0: idle
    -- 1: trigger
    -- 1 -> 2: rising
    -- 2: high
    -- 2 -> 0: falling
    phase = 0,
    opts = vim.tbl_extend('force', {
      threshold = {
        rising = 100,
        falling = 100,
      },
      -- throttle: fn will be called at least once every (rising + falling) milliseconds
      -- rolling: fn will be called only once after the falling edge, new triggers will keep extending the timer
      mode = 'throttle',
    }, opts or {}),
  }, {
    __index = Debounce,
    __call = Debounce.call,
  })
end

return make
