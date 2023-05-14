local ffi = require "ffi"

local rshift = bit.rshift
local bnot, band, bor = bit.bnot, bit.band, bit.bor
local is_down = love.keyboard.isDown

local memory = {
  data = nil,
  rom = nil,
}

function memory:init(rom)
  self.rom = rom
  self.data = ffi.new("uint8_t[?]", 0x10000)
end

function memory:get(address)
  local range = rshift(address, 12)

  if range < 0x04 then
    return self.rom[address]
  elseif range < 0x10 then
    if address == 0xff00 then
      return self:get_input()
    end
  end

  return self.data[address]
end

function memory:set(address, value)
  local range = rshift(address, 12)

  self.data[address] = value
end

-- TODO: simplify
function memory:get_input()
  local joypad = band(bnot(self.data[0xff00]), 0x30)

  if band(joypad, 0x10) == 0x10 then
    if is_down "right" then joypad = bor(joypad, 0x01) end
    if is_down "left" then joypad = bor(joypad, 0x02) end
    if is_down "up" then joypad = bor(joypad, 0x04) end
    if is_down "down" then joypad = bor(joypad, 0x08) end
  end

  if band(joypad, 0x20) == 0x20 then
    if is_down "a" then joypad = bor(joypad, 0x01) end
    if is_down "b" then joypad = bor(joypad, 0x02) end
    if is_down "backspace" then joypad = bor(joypad, 0x04) end
    if is_down "return" then joypad = bor(joypad, 0x08) end
  end

  return bor(0xC0, band(0x3F, bnot(joypad)))
end

return memory
