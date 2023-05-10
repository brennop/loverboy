local ffi = require "ffi"

local emulator = {
  rom = nil,
}

function emulator:init(filename)
  self.rom = ffi.new("uint8_t[?]", 0x8000)

  local file = io.open(filename, "rb")

  for i = 0, 0x7fff do
    self.rom[i] = file:read(1):byte()
  end

  file:close()
end

return emulator
