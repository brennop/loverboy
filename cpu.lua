local instructions = require "instructions"
local memory = nil

local bor, band, lshift = bit.bor, bit.band, bit.lshift

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

local interrupts = {
  vblank = 0x01,
  stat   = 0x02,
  timer  = 0x04,
  serial = 0x08,
  joypad = 0x10,
}

local index = {
  ["(hl)"] = function(self)
    return memory:get(bor(lshift(self.h, 8), self.l))
  end,
  ["nn"] = function(self)
    return memory:get(self.pc - 1)
  end
}

local newindex = {
  ["(hl)"] = function(self, value)
    memory:set(bor(lshift(self.h, 8), self.l), value)
  end
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

  setmetatable(self, {
    __index = function(tbl, key) return index[key](tbl) end,
    __newindex = function(table, key, value)
      newindex[key](table, value)
    end
  })
end

function cpu:step()
  local opcode = memory:get(self.pc)
  local instr = instructions[opcode + 1]

  local bytes, cycles, handler, params = instr[3], instr[4], instr[5], instr[6]

  if handler == nil then
    print(string.format("unknown instruction: 0x%02x, %s at PC:0x%04x", opcode, instr[2], self.pc))
    os.exit(1)
  end

  if trace then self:trace(instr) end

  self.pc = self.pc + bytes

  local extra_cycles = handler(params) or 0

  return cycles + extra_cycles
end

function cpu:conditional_interrupt(interrupt, value, mask)
  if band(value, mask) ~= 0 then
    self:interrupt(interrupt)
  end
end

function cpu:interrupt(interrupt)
  local interrupt_flag = memory:get(0xFF0F)
  
  memory:set(0xFF0F, bor(interrupt_flag, interrupts[interrupt]))

  self.halt = false
end

function cpu:trace(instruction)
 -- A:00 F:Z-H- BC:0000 DE:0393 HL:ffa8 SP:cfff PC:02f0
  local z = band(cpu.f, 0x80) == 0x80 and "Z" or "-"
  local s = band(cpu.f, 0x40) == 0x40 and "N" or "-"
  local h = band(cpu.f, 0x20) == 0x20 and "H" or "-"
  local c = band(cpu.f, 0x10) == 0x10 and "C" or "-"
  local flags = z .. s .. h .. c

  local opcode = memory:get(self.pc)
  print(string.format("A:%02X F:%s BC:%02X%02X DE:%02X%02X HL:%02X%02X SP:%04X PC:%04X | %s",
    cpu.a, flags, cpu.b, cpu.c, cpu.d, cpu.e, cpu.h, cpu.l, cpu.sp, cpu.pc, instruction[2]
  ))
end

return cpu
