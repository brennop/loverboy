local ffi = require "ffi"

local rshift, lshift = bit.rshift, bit.lshift
local bnot, band, bor = bit.bnot, bit.band, bit.bor
local is_down = love.keyboard.isDown
local max = math.max

local memory = {
  data = nil,
  rom = nil,
  banks = nil,
  rom_bank = 0,
  ram_bank = 0,
  ram_enable = false,
  bank_mode = "rom"
}

local mappers = {
  [0x00] = "rom",
  [0x01] = "mbc1",
  [0x02] = "mbc1",
  [0x03] = "mbc1",
  [0x05] = "mbc2",
  [0x06] = "mbc2",
  [0x11] = "mbc3",
  [0x12] = "mbc3",
  [0x13] = "mbc3",
  [0x19] = "mbc5",
  [0x1A] = "mbc5",
}

local bank_size = {
  [0x00] = 0,
  [0x02] = 1,
  [0x03] = 4,
  [0x04] = 16,
  [0x05] = 8,
}

local io_set = {
  [0xff46]  = memory.dma,
}

local io_get = {
  [0xff00] = memory.get_input,
}

function memory:get(address)
  local range = rshift(address, 12)
  if range < 0x4 then
    return self.rom[address]
  elseif range < 0x8 then
    local addr = bor(lshift(band(self.rom_bank, self.rom_banks - 1), 14), band(address, 0x3FFF))
    return self.rom[addr]
  elseif range < 0xA then
  elseif range < 0xC then
    if self.ram_enable then
      if self.mapper == "mbc1" then
        local addr = band(address, 0x1FFF)
        if self.bank_mode == "ram" and self.ram_bank < self.ram_banks then
          addr = bor(lshift(self.ram_bank, 13), addr)
        end
        return self.banks[addr]
      elseif self.mapper == "mbc3" then
        return self.banks[address - 0xA000 + self.ram_bank * 0x2000]
      end
    else
      return 0xff
    end
  elseif range < 0xE then
    -- wram
  elseif range < 0xF then
    return self.data[address - 0x2000]
  elseif range < 0x10 then
    if address < 0xfe00 then
      return self.data[address - 0x2000]
    elseif address == 0xff00 then
      return self:get_input()
    elseif address == 0xff0f then
      return self.data[address] + 0xe0
    end
  end

  return self.data[address]
end

function memory:set(address, value)
  local range = rshift(address, 12)
  if range < 0x02 then
    self.ram_enable = band(value, 0x0f) == 0x0A
  elseif range < 0x04 then
    local mask = ({ mbc1 = 0x1f, mbc3 = 0x7f })[self.mapper]
    self.rom_bank = max(1, band(value, mask))
  elseif range < 0x06 then
    self.ram_bank = band(value, 0x3)
  elseif range < 0x08 then
    if band(value, 0x01) == 0x01 then
      self.bank_mode = "ram"
    else
      self.bank_mode = "rom"
    end
  elseif range < 0xA then -- 0x08, 0x09
    -- vram
  elseif range < 0xC then -- 0xA, 0xB
    if self.ram_enable then
      if self.mapper == "mbc1" then
        local addr = band(address, 0x1FFF)
        if self.bank_mode == "ram" and self.ram_bank < self.ram_banks then
          addr = bor(lshift(self.ram_bank, 13), addr)
        end
        self.banks[addr] = value
      elseif self.mapper == "mbc3" then
        self.banks[address - 0xA000 + self.ram_bank * 0x2000] = value
      end
    end
  elseif range < 0xE then -- 0xC, 0xD
  elseif range < 0xF then -- 0xE
    self.data[address - 0x2000] = value
  elseif range < 0x10 then
    if address < 0xfe00 then
      self.data[address - 0x2000] = value
    elseif address == 0xFF46 then
      self:dma(value)
    end
  end

  self.data[address] = value
end

function memory:init(rom, save)
  self.rom = rom
  self.data = ffi.new("uint8_t[?]", 0x10000)
  self.banks = ffi.new("uint8_t[?]", 0x8000)

  if save then
    ffi.copy(self.banks, save, 0x8000)
  end

  -- TODO: move to boot.lua
  -- https://gbdev.io/pandocs/Power_Up_Sequence.html#hardware-registers
  self.data[0xFF00] = 0xCF
  self.data[0xFF01] = 0x00
  self.data[0xFF02] = 0x7E
  self.data[0xFF04] = 0xAC
  self.data[0xFF05] = 0x00
  self.data[0xFF06] = 0x00
  self.data[0xFF07] = 0xF8
  self.data[0xFF0F] = 0xE1
  self.data[0xFF10] = 0x80
  self.data[0xFF11] = 0xBF
  self.data[0xFF12] = 0xF3
  self.data[0xFF13] = 0xFF
  self.data[0xFF14] = 0xBF
  self.data[0xFF16] = 0x3F
  self.data[0xFF17] = 0x00
  self.data[0xFF18] = 0xFF
  self.data[0xFF19] = 0xBF
  self.data[0xFF1A] = 0x7F
  self.data[0xFF1B] = 0xFF
  self.data[0xFF1C] = 0x9F
  self.data[0xFF1D] = 0xFF
  self.data[0xFF1E] = 0xBF
  self.data[0xFF20] = 0xFF
  self.data[0xFF21] = 0x00
  self.data[0xFF22] = 0x00
  self.data[0xFF23] = 0xBF
  self.data[0xFF24] = 0x77
  self.data[0xFF25] = 0xF3
  self.data[0xFF26] = 0xF1
  self.data[0xFF40] = 0x91
  self.data[0xFF41] = 0x85
  self.data[0xFF42] = 0x00
  self.data[0xFF43] = 0x00
  self.data[0xFF44] = 0x00
  self.data[0xFF45] = 0x00
  self.data[0xFF46] = 0xFF
  self.data[0xFF47] = 0xFC
  self.data[0xFF4A] = 0x00
  self.data[0xFF4B] = 0x00
  self.data[0xFF4D] = 0xFF
  self.data[0xFF4F] = 0xFF
  self.data[0xFF51] = 0xFF
  self.data[0xFF52] = 0xFF
  self.data[0xFF53] = 0xFF
  self.data[0xFF54] = 0xFF
  self.data[0xFF55] = 0xFF
  self.data[0xFF56] = 0xFF
  self.data[0xFF68] = 0xFF
  self.data[0xFF69] = 0xFF
  self.data[0xFF6A] = 0xFF
  self.data[0xFF6B] = 0xFF
  self.data[0xFF70] = 0xFF
  self.data[0xFFFF] = 0x00

  self.rom_bank = 1
  self.ram_bank = 0
  self.ram_enable = false
  self.bank_mode = "rom"
  self.ram_banks = bank_size[rom[0x149]]
  self.rom_banks = lshift(1, rom[0x148] + 1)

  self.mapper = mappers[rom[0x147]]

  if self.mapper == nil then
    error "unsupported cartridge type"
  end
end

function memory:dma(value)
  local source = 0x100 * math.min(value, 0xF1)
  for i = 0, 0x9F do
    self.data[0xFE00 + i] = self:get(source + i)
  end
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
