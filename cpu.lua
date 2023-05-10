local instructions = require "instructions"
local memory = nil

local cpu = {
  -- registers
  a = 0,
  f = 0,
  b = 0,
  c = 0,
  d = 0,
  e = 0,
  h = 0,
  l = 0,
  pc = 0,
  sp = 0,

  ime = true,
  halt = false,
  cycles = 0,

  memory = nil,
}

function cpu:init(_memory)
  self.pc = 0x0100
  self.sp = 0xfffe

  self.a = 0x01
  self.f = 0xb0
  self.b = 0x00
  self.c = 0x13
  self.d = 0x00
  self.e = 0xd8
  self.h = 0x01
  self.l = 0x4d

  memory = _memory
end

function cpu:step()
  local opcode = memory:get(self.pc)
  local instruction = instructions[opcode]

  if instruction == nil then
    print(string.format("unknown instruction: 0x%02x at PC:0x%04x", opcode, self.pc))
    os.exit(1)
  end

  self.pc = self.pc + instruction.bytes

  local extra_cycles = instruction.handler(instruction.params) or 0
  local cycles = instruction.cycles + extra_cycles

  return cycles
end

return cpu
