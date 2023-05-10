local cpu = nil
local memory = nil

local rshift, lshift, rol = bit.rshift, bit.lshift, bit.rol
local band, bor, bxor = bit.band, bit.bor, bit.bxor

local instructions = {}

local function nnn()
  return bor(lshift(memory:get(cpu.pc - 1), 0x8), memory:get(cpu.pc - 2))
end

local function nop() end

local function jp_nn() cpu.pc = nnn() end

local function bop_a_r8(input, op, carry)
  cpu.a = op(cpu.a, cpu[register])
  -- TODO: set f
end

local lookup = {
  { 0x00, "NOP", 1, 3, nop, {} },
  { 0xaf, "XOR A", 1, 4, bop_a_r8, { "a", bxor, 0 } },
  { 0xc3, "JP a16", 3, 15, jp_nn, {} },
}

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
