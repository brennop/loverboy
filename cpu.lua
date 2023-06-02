local instructions = require "instructions"
local memory = nil

local bor, band, lshift, rshift = bit.bor, bit.band, bit.lshift, bit.rshift
local bxor = bit.bxor

local IE = 0xFFFF
local IF = 0xFF0F

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

  -- current opcode, used in some instructions
  opcode = 0,

  memory = nil,
}

local interrupts = {
  vblank = 0x01,
  stat = 0x02,
  timer = 0x04,
  serial = 0x08,
  joypad = 0x10,
}

local index = {
  ["(hl)"] = function(self)
    return memory:get(bor(lshift(self.h, 8), self.l))
  end,
  ["nn"] = function(self)
    return memory:get(self.pc - 1)
  end,
}

local newindex = {
  ["(hl)"] = function(self, value)
    memory:set(bor(lshift(self.h, 8), self.l), value)
  end,
  ["hl"] = function(self, value)
    self.h = rshift(value, 8)
    self.l = band(value, 0xff)
  end,
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
    __index = function(tbl, key)
      return index[key](tbl)
    end,
    __newindex = function(table, key, value)
      newindex[key](table, value)
    end,
  })
end

function cpu:step()
  self:check_interrupts()

  if self.halt then
    return 4
  end

  cpu.opcode = memory:get(self.pc)
  local instr = instructions[cpu.opcode + 1]

  local bytes, cycles, handler, params = instr[3], instr[4], instr[5], instr[6]

  self.pc = band(self.pc + bytes, 0xffff)

  local extra_cycles = handler(params) or 0

  self.cycles = self.cycles + cycles + extra_cycles

  return cycles + extra_cycles
end

local interrupt_handlers = { 0x40, 0x48, 0x50, 0x58, 0x60 }

function cpu:check_interrupts()
  if self.ime then
    local flags = memory:get(IF)
    local interrupt = band(memory:get(IE), flags)

    if interrupt ~= 0 then
      -- no nested interrupts
      self.ime = false

      -- save pc
      self:push(self.pc)

      for index = 1, 5 do
        local mask = lshift(1, index - 1)
        if band(interrupt, mask) ~= 0 then
          self.pc = interrupt_handlers[index]
          memory:set(IF, band(flags, bxor(mask, 0xff)))
          break
        end
      end
    end
  end
end

function cpu:conditional_interrupt(interrupt, value, mask)
  if band(value, mask) ~= 0 then
    self:interrupt(interrupt)
  end
end

function cpu:push(value)
  cpu.sp = cpu.sp - 2

  memory:set(cpu.sp, band(value, 0xff))
  memory:set(cpu.sp + 1, rshift(value, 0x8))
end

function cpu:pop()
  local value = bor(memory:get(cpu.sp), lshift(memory:get(cpu.sp + 1), 8))
  cpu.sp = cpu.sp + 2

  return value
end

function cpu:interrupt(interrupt)
  local interrupt_flag = memory:get(0xFF0F)

  memory:set(0xFF0F, bor(interrupt_flag, interrupts[interrupt]))

  self.halt = false
end

return cpu
