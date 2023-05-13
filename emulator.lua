local ffi = require "ffi"

local memory = require "memory"
local cpu = require "cpu"
local instructions = require "instructions"

local emulator = {
  rom = nil,
}

function emulator:init(filename)
  self.rom = ffi.new("uint8_t[?]", 0x8000)

  local file = io.open(filename, "rb")

  for i = 0, 0x7fff do
    self.rom[i] = file:read(1):byte()
  end
  
  memory:init(self.rom)
  cpu:init(memory)
  instructions:init(cpu, memory)

  file:close()
end

function emulator:step()
  local cycles_this_update = 0
  local cpu_step = cpu.step

  while cycles_this_update < 70224 do
    cycles = cpu_step(cpu)
  end
end

return emulator
