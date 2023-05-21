local ffi = require "ffi"

local cpu = require "cpu"
local graphics = require "graphics"
local instructions = require "instructions"
local memory = require "memory"

local band, bor = bit.band, bit.bor
local lshift, rshift = bit.lshift, bit.rshift

local freqs = { 1024, 16, 64, 256 }

local emulator = {
  rom = nil,

  div = 0,
  tima = 0,
}

function emulator:init(filename)
  local file = io.open(filename, "rb")
  local size = file:seek("end")
  file:seek("set")

  self.rom = ffi.new("uint8_t[?]", size)

  for i = 0, size - 1 do
    self.rom[i] = file:read(1):byte()
  end

  file:close()

  memory:init(self.rom)
  cpu:init(memory)
  instructions:init(cpu, memory)
  graphics:init()

  self.image = love.graphics.newImage(graphics.framebuffer)
end

function emulator:step()
  local cycles_this_update = 0

  while cycles_this_update < 70224 do
    cycles = cpu:step()
    self:update_timers(cycles)
    graphics:step(cycles)

    cycles_this_update = cycles_this_update + cycles
  end

  self.image:replacePixels(graphics.framebuffer)
end

function emulator:draw()
  love.graphics.draw(self.image, 0, 0, 0, 2, 2)

  love.graphics.setColor(0, 0, 0)
  love.graphics.rectangle("fill", 0, 0, 60, 20)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print(string.format("FPS: %d", love.timer.getFPS()), 0, 0)
end

function emulator:draw_background()
  local x_offset = 160 * 2 + 8
  local y_offset = 0

  local tiles_per_row = 16

  for tile = 0, 0xff do
    for row = 0, 0xf, 2 do
      local left = memory:get(0x8000 + tile * 16 + row)
      local right = memory:get(0x8000 + tile * 16 + row + 1)

      for col = 0, 7 do
        local c = 1 - band(bor(
          -- (left >> (7 - col)) << 1,
          lshift(rshift(left, 7 - col), 1),
          -- (right >> (7 - col))
          rshift(right, 7 - col)
        ), 0x03) / 3 

        local x = x_offset + (tile % tiles_per_row) * 8 + col
        local y = y_offset + math.floor(tile / tiles_per_row) * 8 + row / 2

        love.graphics.setColor(c, c, c)
        love.graphics.points(x, y)
        love.graphics.setColor(1, 1, 1)
      end
    end
  end

end

-- TODO: maybe create timers object
function emulator:update_timers(cycles)
  local div = memory:get(0xFF04)
  local tima = memory:get(0xFF05)
  local tma = memory:get(0xFF06)
  local attributes = memory:get(0xFF07)

  self.div = self.div + cycles
  if self.div >= 256 then
    self.div = 0
    memory:set(0xFF04, div + 1)
  end

  if band(attributes, 0x04) == 0x04 then
    self.tima = self.tima + cycles

    local freq = band(attributes, 0x03)
    local clock_speed = freqs[freq + 1]

    if self.tima >= clock_speed then
      self.tima = 0
      memory:set(0xFF05, band(tima + 1, 0xFF))

      if tima == 0xFF then
        memory:set(0xFF05, tma)
        cpu:interrupt "timer"
      end
    end
  end
end

return emulator
