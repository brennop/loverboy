local ffi = require "ffi"

local rshift = bit.rshift

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

  if (range < 4) then
    return self.rom[address]
  end

  return self.data[address]
end

function memory:set(address, value)
  local range = rshift(address, 12)

  self.data[address] = value
end

return memory
