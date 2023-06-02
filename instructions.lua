local ffi = require "ffi"

local cpu = nil
local memory = nil

local rshift, lshift, rol, ror = bit.rshift, bit.lshift, bit.rol, bit.ror
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local cast = ffi.cast

local registers = { "b", "c", "d", "e", "h", "l", "(hl)", "a" }

local cb_cycles = {
  2,2,2,2,2,2,4,2,2,2,2,2,2,2,4,2,
	2,2,2,2,2,2,4,2,2,2,2,2,2,2,4,2,
	2,2,2,2,2,2,4,2,2,2,2,2,2,2,4,2,
	2,2,2,2,2,2,4,2,2,2,2,2,2,2,4,2,
	2,2,2,2,2,2,3,2,2,2,2,2,2,2,3,2,
	2,2,2,2,2,2,3,2,2,2,2,2,2,2,3,2,
	2,2,2,2,2,2,3,2,2,2,2,2,2,2,3,2,
	2,2,2,2,2,2,3,2,2,2,2,2,2,2,3,2,
	2,2,2,2,2,2,4,2,2,2,2,2,2,2,4,2,
	2,2,2,2,2,2,4,2,2,2,2,2,2,2,4,2,
	2,2,2,2,2,2,4,2,2,2,2,2,2,2,4,2,
	2,2,2,2,2,2,4,2,2,2,2,2,2,2,4,2,
	2,2,2,2,2,2,4,2,2,2,2,2,2,2,4,2,
	2,2,2,2,2,2,4,2,2,2,2,2,2,2,4,2,
	2,2,2,2,2,2,4,2,2,2,2,2,2,2,4,2,
	2,2,2,2,2,2,4,2,2,2,2,2,2,2,4,2
}

local function compose(high, low)
  return bor(lshift(high, 0x8), low)
end

local function nn()
  return memory:get(cpu.pc - 1)
end

local function nnn()
  return bor(lshift(memory:get(cpu.pc - 1), 0x8), memory:get(cpu.pc - 2))
end

local function c()
  return cpu.c
end

local function bc()
  return bor(lshift(cpu.b, 0x8), cpu.c)
end

local function de()
  return bor(lshift(cpu.d, 0x8), cpu.e)
end

local function hl()
  return bor(lshift(cpu.h, 0x8), cpu.l)
end

local function hli()
  local value = bor(lshift(cpu.h, 0x8), cpu.l)
  cpu.h = band(rshift(value + 1, 0x8), 0xff)
  cpu.l = band(value + 1, 0xff)
  return value
end

local function hld()
  local value = bor(lshift(cpu.h, 0x8), cpu.l)
  cpu.h = band(rshift(value - 1, 0x8), 0xff)
  cpu.l = band(value - 1, 0xff)
  return value
end

local function sp()
  return cpu.sp
end

local function pop()
  return cpu:pop()
end

local function push()
  cpu:push(cpu.pc)
  return nnn()
end

local function set_flags(f, s, h, c)
  cpu.f = bor(f == 0 and 0x80 or 0, s and 0x40 or 0, h and 0x20 or 0, c and 0x10 or 0)
end

local function get_flag_condition()
  local masked = band(cpu.opcode, 0x18)

  if masked == 0x00 then
    return band(cpu.f, 0x80) == 0
  elseif masked == 0x08 then
    return band(cpu.f, 0x80) == 0x80
  elseif masked == 0x10 then
    return band(cpu.f, 0x10) == 0
  elseif masked == 0x18 then
    return band(cpu.f, 0x10) == 0x10
  end
end

--[[
-- Start Instructions handlers
--   each handler can receive additional data
--   each handler can return additional cycles
--]]

local function nop() end

local function jp_hl()
  cpu.pc = hl()
end

local function jp_nnn(save)
  local target = nnn()
  if save then
    cpu:push(cpu.pc)
  end
  cpu.pc = target
end

--- conditional jumps
-- @param target
local function jp_cond(target)
  if get_flag_condition() then
    cpu.pc = target()

    return 12
  end
end

local function jp_cond_4(target)
  if get_flag_condition() then
    cpu.pc = target()

    return 4
  end
end

local function ret(ime)
  cpu.pc = cpu:pop()
  if ime then
    cpu.ime = true
  end
end

local function cpl()
  cpu.a = bxor(cpu.a, 0xff)
  cpu.f = bor(cpu.f, 0x60)
end

local function ld_r16_d16(reg)
  cpu[reg[1]], cpu[reg[2]] = memory:get(cpu.pc - 1), memory:get(cpu.pc - 2)
end

local function ld_sp(getter)
  cpu.sp = getter()
end

local function ld_d16_sp()
  memory:set(nnn(), band(cpu.sp, 0xff))
  memory:set(nnn() + 1, rshift(cpu.sp, 0x8))
end

-- param:
--  data[1] = getter to address
--  data[2] = register to get
local function ld_mem_r8(data)
  memory:set(data[1](), cpu[data[2]])
end

-- param:
--  data[1] = register to set
--  data[2] = getter to address
local function ld_r8_mem(data)
  cpu[data[1]] = memory:get(data[2]())
end

local function add_sp(target)
  local offset = tonumber(cast("int8_t", memory:get(cpu.pc - 1)))
  local result = band(cpu.sp + offset, 0xffff)
  local xor = bxor(cpu.sp, offset, result)

  set_flags(1, false, band(xor, 0x10) == 0x10, band(xor, 0x100) == 0x100)
  cpu[target] = result
end

-- arith

local function add_a_r8(register)
  local value = cpu[register]
  cpu.a = band(cpu.a + value, 0xff)
  set_flags(cpu.a, false, band(cpu.a, 0x0F) < band(value, 0x0F), cpu.a < value)
end

local function adc_a_r8(register)
  local carry_value = rshift(band(cpu.f, 0x10), 4)
  local value = cpu[register]
  local result = cpu.a + value + carry_value

  local half = band(band(cpu.a, 0x0f) + band(value, 0x0f) + carry_value, 0x10) == 0x10
  local carry = band(result, 0x100) == 0x100

  cpu.a = band(result, 0xff)
  set_flags(cpu.a, false, half, carry)
end

local function sub_a_r8(register)
  local value = cpu[register]
  local result = cpu.a - value

  local half = band(band(cpu.a, 0x0f) - band(value, 0x0f), 0x10) == 0x10
  local carry = band(result, 0x100) == 0x100

  cpu.a = band(result, 0xff)
  set_flags(result, true, half, carry)
end

local function sbc_a_r8(register)
  local carry_value = rshift(band(cpu.f, 0x10), 4)
  local value = cpu[register]
  local result = cpu.a - value - carry_value

  local half = band(band(cpu.a, 0x0f) - band(value, 0x0f) - carry_value, 0x10) == 0x10
  local carry = band(result, 0x100) == 0x100

  cpu.a = band(result, 0xff)
  set_flags(band(result, 0xff), true, half, carry)
end

local function and_a_r8(register)
  cpu.a = band(cpu.a, cpu[register])
  cpu.f = bor(cpu.a == 0 and 0x80 or 0, 0x20)
end

local function xor_a_r8(register)
  cpu.a = bxor(cpu.a, cpu[register])
  cpu.f = cpu.a == 0 and 0x80 or 0
end

local function or_a_r8(register)
  cpu.a = bor(cpu.a, cpu[register])
  cpu.f = cpu.a == 0 and 0x80 or 0
end

local function compare(register)
  local value = cpu[register]
  local result = cpu.a - value
  set_flags(result, true, band(cpu.a, 0x0F) < band(value, 0x0F), cpu.a < value)
end

---

local function rlca()
  cpu.f = lshift(rshift(cpu.a, 7), 4)
  cpu.a = bor(band(lshift(cpu.a, 1), 0xff), rshift(band(cpu.f, 0x10), 4))
end

local function rla()
  local carry = band(cpu.f, 0x10)
  cpu.f = lshift(rshift(cpu.a, 7), 4)
  cpu.a = bor(band(lshift(cpu.a, 1), 0xff), rshift(carry, 4))
end

local function rrca()
  cpu.f = lshift(band(cpu.a, 0x01), 4)
  cpu.a = band(bor(rshift(cpu.a, 1), lshift(cpu.a, 7)), 0xff)
end

local function rra()
  local carry = band(cpu.f, 0x10)
  cpu.f = lshift(band(cpu.a, 0x01), 4)
  cpu.a = bor(rshift(cpu.a, 1), lshift(carry, 3))
end

local function ld_r8_r8(registers)
  cpu[registers[1]] = cpu[registers[2]]
end

local function ld_r8_nn(register)
  cpu[register] = memory:get(cpu.pc - 1)
end

local function add_hl_r16(source)
  local value = source()
  local _hl = hl()
  local result = _hl + source()

  local half = band(result, 0x0fff) < band(_hl, 0x0fff)
  local carry = band(result, 0xffff) < band(_hl, 0xffff)
  local zero = bxor(band(cpu.f, 0x80), 0x80)

  set_flags(zero, false, half, carry)

  cpu.l = band(result, 0xff)
  cpu.h = band(rshift(result, 0x08), 0xff)
end

local function dec_sp()
  cpu.sp = band(cpu.sp - 1, 0xffff)
end

local function dec_r16(registers)
  local high, low = registers[1], registers[2]
  cpu[low] = band(cpu[low] - 1, 0xff)
  if cpu[low] == 0xff then
    cpu[high] = band(cpu[high] - 1, 0xff)
  end
end

local function inc_r16(registers)
  local high, low = registers[1], registers[2]
  cpu[low] = band(cpu[low] + 1, 0xff)
  if cpu[low] == 0x00 then
    cpu[high] = band(cpu[high] + 1, 0xff)
  end
end

local function dec_r8(register)
  local result = band(cpu[register] - 1, 0xff)

  cpu[register] = result

  set_flags(result, true, band(result, 0xf) == 0xf, band(cpu.f, 0x10) == 0x10)
end

local function inc_r8(register)
  local result = band(cpu[register] + 1, 0xff)

  cpu[register] = result

  set_flags(result, false, band(result, 0xf) == 0x0, band(cpu.f, 0x10) == 0x10)
end

local function inc_sp()
  cpu.sp = band(cpu.sp + 1, 0xffff)
end

local function jr_flag_r8(data)
  local mask, value = data[1], data[2]
  if band(cpu.f, mask) == value then
    cpu.pc = band(cpu.pc + tonumber(cast("int8_t", memory:get(cpu.pc - 1))), 0xffff)
    return 4
  end
end

local function set_ime(value)
  cpu.ime = value
end

local function write_io(getter)
  memory:set(bor(0xff00, getter()), cpu.a)
end

local function read_io(getter)
  cpu.a = memory:get(bor(0xff00, getter()))
end

local function rst(target)
  cpu:push(cpu.pc)
  cpu.pc = target
end

local function pop_r16(registers)
  cpu[registers[2]] = memory:get(cpu.sp)
  cpu[registers[1]] = memory:get(cpu.sp + 1)
  cpu.sp = cpu.sp + 2
end

local function pop_af()
  cpu.f = band(memory:get(cpu.sp), 0xf0)
  cpu.a = memory:get(cpu.sp + 1)
  cpu.sp = cpu.sp + 2
end

local function push_r16(registers)
  cpu.sp = cpu.sp - 2
  memory:set(cpu.sp, cpu[registers[2]])
  memory:set(cpu.sp + 1, cpu[registers[1]])
end

local function daa()
  local correction = 0
  local set_carry = false

  local half = band(cpu.f, 0x20) == 0x20
  local carry = band(cpu.f, 0x10) == 0x10
  local not_sub = band(cpu.f, 0x40) == 0x00

  if half or (not_sub and band(cpu.a, 0xf) > 9) then
    correction = 6
  end

  if carry or (not_sub and cpu.a > 0x99) then
    correction = correction + 0x60
    set_carry = true
  end

  if not_sub then
    cpu.a = band(cpu.a + correction, 0xff)
  else
    cpu.a = band(cpu.a - correction, 0xff)
  end

  set_flags(cpu.a, not not_sub, false, set_carry)
end

local function halt()
  cpu.halt = true
end

local function op_cf(op)
  local carry = band(op(cpu.f, 0xff), 0x10)
  cpu.f = bor(band(cpu.f, 0x80), carry)
end

--
-- cb
--

local function bit(opcode)
  return lshift(1, (rshift(band(opcode, 0x38), 3)))
end

local cb_handlers = {
  function(value) -- 0x01 .. 0x07 (RLC)
    local carry = band(value, 0x80)
    local result = band(bor(lshift(value, 1), rshift(carry, 7)), 0xff)
    set_flags(result, false, false, carry == 0x80)
    return result
  end,
  function(value) -- 0x08 .. 0x0f (RRC)
    local carry = band(value, 0x01)
    local result = bor(rshift(value, 1), lshift(carry, 7))
    set_flags(result, false, false, carry == 0x01)
    return result
  end,
  function(value) -- 0x10 .. 0x17 (RL)
    local carry = band(value, 0x80)
    local result = band(bor(lshift(value, 1), band(rshift(cpu.f, 4), 1)), 0xff)
    set_flags(result, false, false, carry == 0x80)
    return result
  end,
  function(value) -- 0x18 .. 0x1f (RR)
    local carry = band(value, 0x01)
    local result = bor(rshift(value, 1), lshift(band(cpu.f, 0x10), 3))
    set_flags(result, false, false, carry == 0x01)
    return result
  end,
  function(value) -- 0x20 .. 0x27 (SLA)
    local carry = rshift(value, 7)
    local result = band(lshift(value, 1), 0xff)
    set_flags(result, false, false, carry == 0x01)
    return result
  end,
  function(value) -- 0x28 .. 0x2f (SRA)
    local carry = band(value, 0x01)
    local result = bor(rshift(value, 1), band(value, 0x80))
    set_flags(result, false, false, carry == 0x01)
    return result
  end,
  function(value) -- SWAP
    local result = bor(lshift(band(value, 0xf), 4), rshift(band(value, 0xf0), 4))
    cpu.f = result == 0 and 0x80 or 0
    return result
  end,
  function(value) -- SRL
    local result = rshift(value, 1)
    set_flags(result, false, false, band(value, 1) == 1)
    return result
  end,
}

local function cb()
  local opcode = nn()
  local range = rshift(opcode, 6)
  local register = registers[band(opcode, 0x07) + 1]
  local value = cpu[register]
  local carry = band(cpu.f, 0x10)

  if range == 0 then
    local handler = cb_handlers[rshift(opcode, 3) + 1]
    cpu[register] = handler(value, carry)
  elseif range == 1 then -- BIT
    cpu.f = bor(band(value, bit(opcode)) == 0 and 0x80 or 0, 0x20, band(cpu.f, 0x10))
  elseif range == 2 then
    cpu[register] = band(value, bxor(bit(opcode), 0xff))
  elseif range == 3 then
    cpu[register] = bor(value, bit(opcode))
  end

  local cycles = cb_cycles[opcode + 1]
  return cycles * 4
end

-- [[
-- End Instruction handlers
-- ]]

-- stylua: ignore start
local instructions = {
  { 0x00, "NOP ",         1, 4,  nop,        nil },
  { 0x01, "LD BC, d16",   3, 12, ld_r16_d16, { "b",    "c" } },
  { 0x02, "LD BC, A",     1, 8,  ld_mem_r8,  { bc,     "a" } },
  { 0x03, "INC BC",       1, 8,  inc_r16,    { "b",    "c" } },
  { 0x04, "INC B",        1, 4,  inc_r8,     "b" },
  { 0x05, "DEC B",        1, 4,  dec_r8,     "b" },
  { 0x06, "LD B, d8",     2, 8,  ld_r8_nn,   "b" },
  { 0x07, "RLCA ",        1, 4,  rlca,       nil },
  { 0x08, "LD a16, SP",   3, 20, ld_d16_sp,  nil },
  { 0x09, "ADD HL, BC",   1, 8,  add_hl_r16, bc },
  { 0x0A, "LD A, BC",     1, 8,  ld_r8_mem,  { "a",    bc } },
  { 0x0B, "DEC BC",       1, 8,  dec_r16,    { "b",    "c" } },
  { 0x0C, "INC C",        1, 4,  inc_r8,     "c" },
  { 0x0D, "DEC C",        1, 4,  dec_r8,     "c" },
  { 0x0E, "LD C, d8",     2, 8,  ld_r8_nn,   "c" },
  { 0x0F, "RRCA ",        1, 4,  rrca,       nil },
  { 0x10, "STOP d8",      2, 4,  nop,        nil },
  { 0x11, "LD DE, d16",   3, 12, ld_r16_d16, { "d",    "e" } },
  { 0x12, "LD DE, A",     1, 8,  ld_mem_r8,  { de,     "a" } },
  { 0x13, "INC DE",       1, 8,  inc_r16,    { "d",    "e" } },
  { 0x14, "INC D",        1, 4,  inc_r8,     "d" },
  { 0x15, "DEC D",        1, 4,  dec_r8,     "d" },
  { 0x16, "LD D, d8",     2, 8,  ld_r8_nn,   "d" },
  { 0x17, "RLA ",         1, 4,  rla,        nil },
  { 0x18, "JR r8",        2, 8,  jr_flag_r8, { 0x00,   0x00 } },
  { 0x19, "ADD HL, DE",   1, 8,  add_hl_r16, de },
  { 0x1A, "LD A, DE",     1, 8,  ld_r8_mem,  { "a",    de } },
  { 0x1B, "DEC DE",       1, 8,  dec_r16,    { "d",    "e"} },
  { 0x1C, "INC E",        1, 4,  inc_r8,     "e" },
  { 0x1D, "DEC E",        1, 4,  dec_r8,     "e" },
  { 0x1E, "LD E, d8",     2, 8,  ld_r8_nn,   "e" },
  { 0x1F, "RRA ",         1, 4,  rra,        nil },
  { 0x20, "JR NZ, r8",    2, 8,  jr_flag_r8, { 0x80,   0x00 } },
  { 0x21, "LD HL, d16",   3, 12, ld_r16_d16, { "h",    "l" } },
  { 0x22, "LD HL, A",     1, 8,  ld_mem_r8,  { hli,    "a" } },
  { 0x23, "INC HL",       1, 8,  inc_r16,    { "h",    "l" } },
  { 0x24, "INC H",        1, 4,  inc_r8,     "h" },
  { 0x25, "DEC H",        1, 4,  dec_r8,     "h" },
  { 0x26, "LD H, d8",     2, 8,  ld_r8_nn,   "h" },
  { 0x27, "DAA ",         1, 4,  daa,        nil },
  { 0x28, "JR Z, r8",     2, 8,  jr_flag_r8, { 0x80,   0x80 } },
  { 0x29, "ADD HL, HL",   1, 8,  add_hl_r16, hl },
  { 0x2A, "LD A, HL",     1, 8,  ld_r8_mem,  { "a",    hli } },
  { 0x2B, "DEC HL",       1, 8,  dec_r16,    { "h",    "l" } },
  { 0x2C, "INC L",        1, 4,  inc_r8,     "l" },
  { 0x2D, "DEC L",        1, 4,  dec_r8,     "l" },
  { 0x2E, "LD L, d8",     2, 8,  ld_r8_nn,   "l" },
  { 0x2F, "CPL ",         1, 4,  cpl,        nil },
  { 0x30, "JR NC, r8",    2, 8,  jr_flag_r8, { 0x10,   0x00 } },
  { 0x31, "LD SP, d16",   3, 12, ld_sp,      nnn },
  { 0x32, "LD HL, A",     1, 8,  ld_mem_r8,  { hld,    "a" } },
  { 0x33, "INC SP",       1, 8,  inc_sp,     nil },
  { 0x34, "INC HL",       1, 12, inc_r8,     "(hl)" },
  { 0x35, "DEC HL",       1, 12, dec_r8,     "(hl)" },
  { 0x36, "LD HL, d8",    2, 12, ld_mem_r8,  { hl,     "nn" } },
  { 0x37, "SCF ",         1, 4,  op_cf,      bor },
  { 0x38, "JR C, r8",     2, 8,  jr_flag_r8, { 0x10,   0x10 } },
  { 0x39, "ADD HL, SP",   1, 8,  add_hl_r16, sp },
  { 0x3A, "LD A, HL",     1, 8,  ld_r8_mem,  { "a",    hld } },
  { 0x3B, "DEC SP",       1, 8,  dec_sp,     nil },
  { 0x3C, "INC A",        1, 4,  inc_r8,     "a" },
  { 0x3D, "DEC A",        1, 4,  dec_r8,     "a" },
  { 0x3E, "LD A, d8",     2, 8,  ld_r8_nn,   "a" },
  { 0x3F, "CCF ",         1, 4,  op_cf,      bxor },
  { 0x40, "LD B, B",      1, 4,  ld_r8_r8,   { "b",    "b" } },
  { 0x41, "LD B, C",      1, 4,  ld_r8_r8,   { "b",    "c" } },
  { 0x42, "LD B, D",      1, 4,  ld_r8_r8,   { "b",    "d" } },
  { 0x43, "LD B, E",      1, 4,  ld_r8_r8,   { "b",    "e" } },
  { 0x44, "LD B, H",      1, 4,  ld_r8_r8,   { "b",    "h" } },
  { 0x45, "LD B, L",      1, 4,  ld_r8_r8,   { "b",    "l" } },
  { 0x46, "LD B, HL",     1, 8,  ld_r8_r8,   { "b",    "(hl)" } },
  { 0x47, "LD B, A",      1, 4,  ld_r8_r8,   { "b",    "a" } },
  { 0x48, "LD C, B",      1, 4,  ld_r8_r8,   { "c",    "b" } },
  { 0x49, "LD C, C",      1, 4,  ld_r8_r8,   { "c",    "c" } },
  { 0x4A, "LD C, D",      1, 4,  ld_r8_r8,   { "c",    "d" } },
  { 0x4B, "LD C, E",      1, 4,  ld_r8_r8,   { "c",    "e" } },
  { 0x4C, "LD C, H",      1, 4,  ld_r8_r8,   { "c",    "h" } },
  { 0x4D, "LD C, L",      1, 4,  ld_r8_r8,   { "c",    "l" } },
  { 0x4E, "LD C, HL",     1, 8,  ld_r8_r8,   { "c",    "(hl)" } },
  { 0x4F, "LD C, A",      1, 4,  ld_r8_r8,   { "c",    "a" } },
  { 0x50, "LD D, B",      1, 4,  ld_r8_r8,   { "d",    "b" } },
  { 0x51, "LD D, C",      1, 4,  ld_r8_r8,   { "d",    "c" } },
  { 0x52, "LD D, D",      1, 4,  ld_r8_r8,   { "d",    "d" } },
  { 0x53, "LD D, E",      1, 4,  ld_r8_r8,   { "d",    "e" } },
  { 0x54, "LD D, H",      1, 4,  ld_r8_r8,   { "d",    "h" } },
  { 0x55, "LD D, L",      1, 4,  ld_r8_r8,   { "d",    "l" } },
  { 0x56, "LD D, HL",     1, 8,  ld_r8_r8,   { "d",    "(hl)" } },
  { 0x57, "LD D, A",      1, 4,  ld_r8_r8,   { "d",    "a" } },
  { 0x58, "LD E, B",      1, 4,  ld_r8_r8,   { "e",    "b" } },
  { 0x59, "LD E, C",      1, 4,  ld_r8_r8,   { "e",    "c" } },
  { 0x5A, "LD E, D",      1, 4,  ld_r8_r8,   { "e",    "d" } },
  { 0x5B, "LD E, E",      1, 4,  ld_r8_r8,   { "e",    "e" } },
  { 0x5C, "LD E, H",      1, 4,  ld_r8_r8,   { "e",    "h" } },
  { 0x5D, "LD E, L",      1, 4,  ld_r8_r8,   { "e",    "l" } },
  { 0x5E, "LD E, HL",     1, 8,  ld_r8_r8,   { "e",    "(hl)" } },
  { 0x5F, "LD E, A",      1, 4,  ld_r8_r8,   { "e",    "a" } },
  { 0x60, "LD H, B",      1, 4,  ld_r8_r8,   { "h",    "b" } },
  { 0x61, "LD H, C",      1, 4,  ld_r8_r8,   { "h",    "c" } },
  { 0x62, "LD H, D",      1, 4,  ld_r8_r8,   { "h",    "d" } },
  { 0x63, "LD H, E",      1, 4,  ld_r8_r8,   { "h",    "e" } },
  { 0x64, "LD H, H",      1, 4,  ld_r8_r8,   { "h",    "h" } },
  { 0x65, "LD H, L",      1, 4,  ld_r8_r8,   { "h",    "l" } },
  { 0x66, "LD H, HL",     1, 8,  ld_r8_r8,   { "h",    "(hl)" } },
  { 0x67, "LD H, A",      1, 4,  ld_r8_r8,   { "h",    "a" } },
  { 0x68, "LD L, B",      1, 4,  ld_r8_r8,   { "l",    "b" } },
  { 0x69, "LD L, C",      1, 4,  ld_r8_r8,   { "l",    "c" } },
  { 0x6A, "LD L, D",      1, 4,  ld_r8_r8,   { "l",    "d" } },
  { 0x6B, "LD L, E",      1, 4,  ld_r8_r8,   { "l",    "e" } },
  { 0x6C, "LD L, H",      1, 4,  ld_r8_r8,   { "l",    "h" } },
  { 0x6D, "LD L, L",      1, 4,  ld_r8_r8,   { "l",    "l" } },
  { 0x6E, "LD L, HL",     1, 8,  ld_r8_r8,   { "l",    "(hl)" } },
  { 0x6F, "LD L, A",      1, 4,  ld_r8_r8,   { "l",    "a" } },
  { 0x70, "LD HL, B",     1, 8,  ld_r8_r8,   { "(hl)", "b" } },
  { 0x71, "LD HL, C",     1, 8,  ld_r8_r8,   { "(hl)", "c" } },
  { 0x72, "LD HL, D",     1, 8,  ld_r8_r8,   { "(hl)", "d" } },
  { 0x73, "LD HL, E",     1, 8,  ld_r8_r8,   { "(hl)", "e" } },
  { 0x74, "LD HL, H",     1, 8,  ld_r8_r8,   { "(hl)", "h" } },
  { 0x75, "LD HL, L",     1, 8,  ld_r8_r8,   { "(hl)", "l" } },
  { 0x76, "HALT ",        1, 4,  halt,       nil },
  { 0x77, "LD HL, A",     1, 8,  ld_r8_r8,   { "(hl)", "a" } },
  { 0x78, "LD A, B",      1, 4,  ld_r8_r8,   { "a",    "b" } },
  { 0x79, "LD A, C",      1, 4,  ld_r8_r8,   { "a",    "c" } },
  { 0x7A, "LD A, D",      1, 4,  ld_r8_r8,   { "a",    "d" } },
  { 0x7B, "LD A, E",      1, 4,  ld_r8_r8,   { "a",    "e" } },
  { 0x7C, "LD A, H",      1, 4,  ld_r8_r8,   { "a",    "h" } },
  { 0x7D, "LD A, L",      1, 4,  ld_r8_r8,   { "a",    "l" } },
  { 0x7E, "LD A, HL",     1, 8,  ld_r8_r8,   { "a",    "(hl)"} },
  { 0x7F, "LD A, A",      1, 4,  ld_r8_r8,   { "a",    "a" } },
  { 0x80, "ADD A, B",     1, 4,  add_a_r8,   "b" },
  { 0x81, "ADD A, C",     1, 4,  add_a_r8,   "c" },
  { 0x82, "ADD A, D",     1, 4,  add_a_r8,   "d" },
  { 0x83, "ADD A, E",     1, 4,  add_a_r8,   "e" },
  { 0x84, "ADD A, H",     1, 4,  add_a_r8,   "h" },
  { 0x85, "ADD A, L",     1, 4,  add_a_r8,   "l" },
  { 0x86, "ADD A, HL",    1, 8,  add_a_r8,   "(hl)" },
  { 0x87, "ADD A, A",     1, 4,  add_a_r8,   "a" },
  { 0x88, "ADC A, B",     1, 4,  adc_a_r8,   "b" },
  { 0x89, "ADC A, C",     1, 4,  adc_a_r8,   "c" },
  { 0x8A, "ADC A, D",     1, 4,  adc_a_r8,   "d" },
  { 0x8B, "ADC A, E",     1, 4,  adc_a_r8,   "e" },
  { 0x8C, "ADC A, H",     1, 4,  adc_a_r8,   "h" },
  { 0x8D, "ADC A, L",     1, 4,  adc_a_r8,   "l" },
  { 0x8E, "ADC A, HL",    1, 8,  adc_a_r8,   "(hl)" },
  { 0x8F, "ADC A, A",     1, 4,  adc_a_r8,   "a" },
  { 0x90, "SUB B",        1, 4,  sub_a_r8,   "b" },
  { 0x91, "SUB C",        1, 4,  sub_a_r8,   "c" },
  { 0x92, "SUB D",        1, 4,  sub_a_r8,   "d" },
  { 0x93, "SUB E",        1, 4,  sub_a_r8,   "e" },
  { 0x94, "SUB H",        1, 4,  sub_a_r8,   "h" },
  { 0x95, "SUB L",        1, 4,  sub_a_r8,   "l" },
  { 0x96, "SUB HL",       1, 8,  sub_a_r8,   "(hl)" },
  { 0x97, "SUB A",        1, 4,  sub_a_r8,   "a" },
  { 0x98, "SBC A, B",     1, 4,  sbc_a_r8,   "b" },
  { 0x99, "SBC A, C",     1, 4,  sbc_a_r8,   "c" },
  { 0x9A, "SBC A, D",     1, 4,  sbc_a_r8,   "d" },
  { 0x9B, "SBC A, E",     1, 4,  sbc_a_r8,   "e" },
  { 0x9C, "SBC A, H",     1, 4,  sbc_a_r8,   "h" },
  { 0x9D, "SBC A, L",     1, 4,  sbc_a_r8,   "l" },
  { 0x9E, "SBC A, HL",    1, 8,  sbc_a_r8,   "(hl)" },
  { 0x9F, "SBC A, A",     1, 4,  sbc_a_r8,   "a" },
  { 0xA0, "AND B",        1, 4,  and_a_r8,   "b" },
  { 0xA1, "AND C",        1, 4,  and_a_r8,   "c" },
  { 0xA2, "AND D",        1, 4,  and_a_r8,   "d" },
  { 0xA3, "AND E",        1, 4,  and_a_r8,   "e" },
  { 0xA4, "AND H",        1, 4,  and_a_r8,   "h" },
  { 0xA5, "AND L",        1, 4,  and_a_r8,   "l" },
  { 0xA6, "AND HL",       1, 8,  and_a_r8,   "(hl)" },
  { 0xA7, "AND A",        1, 4,  and_a_r8,   "a" },
  { 0xA8, "XOR B",        1, 4,  xor_a_r8,   "b" },
  { 0xA9, "XOR C",        1, 4,  xor_a_r8,   "c" },
  { 0xAA, "XOR D",        1, 4,  xor_a_r8,   "d" },
  { 0xAB, "XOR E",        1, 4,  xor_a_r8,   "e" },
  { 0xAC, "XOR H",        1, 4,  xor_a_r8,   "h" },
  { 0xAD, "XOR L",        1, 4,  xor_a_r8,   "l" },
  { 0xAE, "XOR HL",       1, 8,  xor_a_r8,   "(hl)" },
  { 0xAF, "XOR A",        1, 4,  xor_a_r8,   "a" },
  { 0xB0, "OR B",         1, 4,  or_a_r8,    "b" },
  { 0xB1, "OR C",         1, 4,  or_a_r8,    "c" },
  { 0xB2, "OR D",         1, 4,  or_a_r8,    "d" },
  { 0xB3, "OR E",         1, 4,  or_a_r8,    "e" },
  { 0xB4, "OR H",         1, 4,  or_a_r8,    "h" },
  { 0xB5, "OR L",         1, 4,  or_a_r8,    "l" },
  { 0xB6, "OR HL",        1, 8,  or_a_r8,    "(hl)" },
  { 0xB7, "OR A",         1, 4,  or_a_r8,    "a" },
  { 0xB8, "CP B",         1, 4,  compare,    "b" },
  { 0xB9, "CP C",         1, 4,  compare,    "c" },
  { 0xBA, "CP D",         1, 4,  compare,    "d" },
  { 0xBB, "CP E",         1, 4,  compare,    "e" },
  { 0xBC, "CP H",         1, 4,  compare,    "h" },
  { 0xBD, "CP L",         1, 4,  compare,    "l" },
  { 0xBE, "CP HL",        1, 8,  compare,    "(hl)" },
  { 0xBF, "CP A",         1, 4,  compare,    "a" },
  { 0xC0, "RET NZ",       1, 8,  jp_cond,    pop },
  { 0xC1, "POP BC",       1, 12, pop_r16,    { "b",    "c" } },
  { 0xC2, "JP NZ, a16",   3, 12, jp_cond_4,    nnn },
  { 0xC3, "JP a16",       3, 16, jp_nnn,     false },
  { 0xC4, "CALL NZ, a16", 3, 12, jp_cond,    push },
  { 0xC5, "PUSH BC",      1, 16, push_r16,   { "b",    "c" } },
  { 0xC6, "ADD A, d8",    2, 8,  add_a_r8,   "nn" },
  { 0xC7, "RST 00H",      1, 16, rst,        0x00 },
  { 0xC8, "RET Z",        1, 8,  jp_cond,    pop },
  { 0xC9, "RET ",         1, 16, ret,        nil },
  { 0xCA, "JP Z, a16",    3, 12, jp_cond_4,    nnn },
  { 0xCB, "PREFIX ",      2, 0,  cb,         nil },
  { 0xCC, "CALL Z, a16",  3, 12, jp_cond,    push },
  { 0xCD, "CALL a16",     3, 24, jp_nnn,     true },
  { 0xCE, "ADC A, d8",    2, 8,  adc_a_r8,   "nn" },
  { 0xCF, "RST 08H",      1, 16, rst,        0x08 },
  { 0xD0, "RET NC",       1, 8,  jp_cond,    pop },
  { 0xD1, "POP DE",       1, 12, pop_r16,    { "d",    "e" } },
  { 0xD2, "JP NC, a16",   3, 12, jp_cond_4,    nnn },
  { 0xD3, "ILLEGAL_D3 ",  1, 4,  nil,        nil },
  { 0xD4, "CALL NC, a16", 3, 12, jp_cond,    push },
  { 0xD5, "PUSH DE",      1, 16, push_r16,   { "d",    "e" } },
  { 0xD6, "SUB d8",       2, 8,  sub_a_r8,   "nn" },
  { 0xD7, "RST 10H",      1, 16, rst,        0x10 },
  { 0xD8, "RET C",        1, 8,  jp_cond,    pop },
  { 0xD9, "RETI ",        1, 16, ret,        true },
  { 0xDA, "JP C, a16",    3, 12, jp_cond_4,    nnn },
  { 0xDB, "ILLEGAL_DB ",  1, 4,  nil,        nil },
  { 0xDC, "CALL C, a16",  3, 12, jp_cond,    push },
  { 0xDD, "ILLEGAL_DD ",  1, 4,  nil,        nil },
  { 0xDE, "SBC A, d8",    2, 8,  sbc_a_r8,   "nn" },
  { 0xDF, "RST 18H",      1, 16, rst,        0x18 },
  { 0xE0, "LDH a8, A",    2, 12, write_io,   nn },
  { 0xE1, "POP HL",       1, 12, pop_r16,    { "h",    "l" } },
  { 0xE2, "LD C, A",      1, 8,  write_io,   c },
  { 0xE3, "ILLEGAL_E3 ",  1, 4,  nil,        nil },
  { 0xE4, "ILLEGAL_E4 ",  1, 4,  nil,        nil },
  { 0xE5, "PUSH HL",      1, 16, push_r16,   { "h",    "l" } },
  { 0xE6, "AND d8",       2, 8,  and_a_r8,   "nn" },
  { 0xE7, "RST 20H",      1, 16, rst,        0x20 },
  { 0xE8, "ADD SP, r8",   2, 16, add_sp,     "sp" },
  { 0xE9, "JP HL",        1, 4,  jp_hl,      nil },
  { 0xEA, "LD a16, A",    3, 16, ld_mem_r8,  { nnn,    "a" } },
  { 0xEB, "ILLEGAL_EB ",  1, 4,  nil,        nil },
  { 0xEC, "ILLEGAL_EC ",  1, 4,  nil,        nil },
  { 0xED, "ILLEGAL_ED ",  1, 4,  nil,        nil },
  { 0xEE, "XOR d8",       2, 8,  xor_a_r8,   "nn" },
  { 0xEF, "RST 28H",      1, 16, rst,        0x28 },
  { 0xF0, "LDH A, a8",    2, 12, read_io,    nn },
  { 0xF1, "POP AF",       1, 12, pop_af,     nil },
  { 0xF2, "LD A, C",      1, 8,  read_io,    c },
  { 0xF3, "DI ",          1, 4,  set_ime,    false },
  { 0xF4, "ILLEGAL_F4 ",  1, 4,  nil,        nil },
  { 0xF5, "PUSH AF",      1, 16, push_r16,   { "a",    "f" } },
  { 0xF6, "OR d8",        2, 8,  or_a_r8,    "nn" },
  { 0xF7, "RST 30H",      1, 16, rst,        0x30 },
  { 0xF8, "LD HL, SP+r8", 2, 12, add_sp,     "hl" },
  { 0xF9, "LD SP, HL",    1, 8,  ld_sp,      hl },
  { 0xFA, "LD A, a16",    3, 16, ld_r8_mem,  { "a",    nnn } },
  { 0xFB, "EI ",          1, 4,  set_ime,    true },
  { 0xFC, "ILLEGAL_FC ",  1, 4,  nil,        nil },
  { 0xFD, "ILLEGAL_FD ",  1, 4,  nil,        nil },
  { 0xFE, "CP d8",        2, 8,  compare,    "nn" },
  { 0xFF, "RST 38H",      1, 16, rst,        0x38 }
}
-- stylua: ignore end

function instructions:init(_cpu, _memory)
  -- set locals
  cpu = _cpu
  memory = _memory
end

return instructions
