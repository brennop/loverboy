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

local function bop_a_r8(register)
  cpu.a = bxor(cpu.a, cpu[register])
  cpu.f = cpu.a == 0 and 0x80 or 0
end

-- [[
-- End Instruction handlers
-- ]]

local function create_row_8(lookup, format)
  local registers = { "b", "c", "d", "e", "h", "l", "(hl)", "a" }
  local start, m, b, c, h = unpack(format)
  for i = 1, 8 do
    table.insert(lookup, { start + i - 1, m, b, c, h, registers[i], })
  end
end

local lookup = {
  { 0x00, "NOP", 1, 3, nop, },
  { 0xc3, "JP a16", 3, 15, jp_nn, },
}

create_row_8(lookup, { 0xa8, "XOR _", 1, 4, bop_a_r8 })

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
