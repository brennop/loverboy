local ffi = require "ffi"

local cpu = require "cpu"
local memory = require "memory"
local graphics = require "graphics"
local instructions = require "instructions"

local emulator = {
  rom = nil,
}

function emulator:init(filename, args)
  -- TODO: add arg parsing
  trace = args[2] == "-t"

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
  local cpu_step, gpu_step = cpu.step, graphics.step

  while cycles_this_update < 70224 do
    cycles = cpu_step(cpu)
    gpu_step(graphics, cycles)

    cycles_this_update = cycles_this_update + cycles
  end

end

return emulator
