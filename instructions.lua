local cpu = nil
local memory = nil

local rshift, lshift, rol = bit.rshift, bit.lshift, bit.rol
local band, bor, bxor = bit.band, bit.bor, bit.bxor

local instructions = {}

local function nnn()
  return bor(lshift(memory:get(cpu.pc - 1), 0x8), memory:get(cpu.pc - 2))
end

local function set_flags(z, n, h, c)
  cpu.f = bor(z == 0 and 0x80 or 0, lshift(n, 6), lshift(h, 5), lshift(c, 4))
end

--[[
-- Start Instructions handlers
--]]

local function nop() end

local function jp_nn() cpu.pc = nnn() end

local function ld_r16_d16(reg)
  cpu[reg[1]], cpu[reg[2]] = memory:get(cpu.pc - 1), memory:get(cpu.pc - 2)
end

local function ld_sp_d16()
  cpu.sp = nnn()
end

local function bop_a_r8(register)
  cpu.a = bxor(cpu.a, cpu[register])
  cpu.f = cpu.a == 0 and 0x80 or 0
end

-- [[
-- End Instruction handlers
-- ]]

local lookup = {}

local function create_solo(format)
  table.insert(lookup, format)
end

local function create_col3(format)
  local start, m, b, c, h = unpack(format)
  table.insert(lookup, { start + 0x00, m, b, c, h, { "b", "c" } })
  table.insert(lookup, { start + 0x10, m, b, c, h, { "d", "e" } })
  table.insert(lookup, { start + 0x20, m, b, c, h, { "h", "l" } })
end

local function create_row8(format)
  local registers = { "b", "c", "d", "e", "h", "l", "(hl)", "a" }
  local start, m, b, c, h = unpack(format)
  for i = 1, 8 do
    table.insert(lookup, { start + i - 1, m, b, c, h, registers[i], })
  end
end

create_row8({ 0xa8, "XOR _", 1, 4, bop_a_r8 })
create_col3({ 0x01, "LD r16, d16", 3, 12, ld_r16_d16 })
create_solo({ 0x00, "NOP", 1, 3, nop })
create_solo({ 0xc3, "JP a16", 3, 15, jp_nn })

function instructions:init(_cpu, _memory)
  for _, data in ipairs(lookup) do
    local index, mnemonic, bytes, cycles, handler, params = unpack(data)

    local instruction = {
      mnemonic = mnemonic,
      bytes = bytes,
      cycles = cycles,
      handler = handler,
      params = params
    }

    instructions[index] = instruction
  end

  -- set locals
  cpu = _cpu
  memory = _memory
end

return instructions
