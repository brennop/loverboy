local ffi = require "ffi"

local rshift, lshift = bit.rshift, bit.lshift
local bnot, band, bor = bit.bnot, bit.band, bit.bor
local is_down = love.keyboard.isDown

local memory = {
  data = nil,
  rom = nil,
  rom_bank = 0,
}

function memory:init(rom)
  self.rom = rom
  self.data = ffi.new("uint8_t[?]", 0x10000)

  -- https://gbdev.io/pandocs/Power_Up_Sequence.html#hardware-registers
  self.data[0xFF00] = 0xCF;
  self.data[0xFF04] = 0xAB;
  self.data[0xFF05] = 0x00;
  self.data[0xFF40] = 0x91;
  self.data[0xFF41] = 0x85;
  self.data[0xFF42] = 0x00;
  self.data[0xFF43] = 0x00;
  self.data[0xFF45] = 0x00;
  self.data[0xFF46] = 0xFF;
  self.data[0xFF47] = 0xFC;

  self.rom_bank = 1
end

function memory:get(address)
  local range = rshift(address, 12)

  if range < 0x04 then
    return self.rom[address]
  elseif range < 0x08 then
    return self.rom[address - 0x4000 + self.rom_bank * 0x4000]
  elseif range < 0x10 then
    if address == 0xff00 then
      return self:get_input()
    end
  end

  return self.data[address]
end

function memory:set(address, value)
  local range = rshift(address, 12)

  if range < 0x04 then
    return
  elseif range < 0x08 then
    -- TODO
  elseif range < 0x10 then
    if address == 0xff46 then
      local source = lshift(value, 8)
      for i = 0, 0x9F do
        self.data[0xFE00 + i] = self.data[source + i]
      end
    end
  end

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
    if is_down "z" then joypad = bor(joypad, 0x01) end
    if is_down "x" then joypad = bor(joypad, 0x02) end
    if is_down "backspace" then joypad = bor(joypad, 0x04) end
    if is_down "return" then joypad = bor(joypad, 0x08) end
  end

  return bor(0xC0, band(0x3F, bnot(joypad)))
end

return memory
