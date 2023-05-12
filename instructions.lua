local cpu = nil
local memory = nil

local rshift, lshift, rol = bit.rshift, bit.lshift, bit.rol
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot

local instructions = {}

local function compose(high, low)
  return bor(lshift(high, 0x8), low)
end

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

local function jp_nn()
	cpu.pc = nnn()
end

local function ld_r16_d16(reg)
	cpu[reg[1]], cpu[reg[2]] = memory:get(cpu.pc - 1), memory:get(cpu.pc - 2)
end

local function ld_sp_d16()
	cpu.sp = nnn()
end

local function xor_a_r8(register)
	cpu.a = bxor(cpu.a, cpu[register])
	cpu.f = cpu.a == 0 and 0x80 or 0
end

local function ld_r8_nn(register)
  cpu[register] = memory:get(cpu.pc - 1)
end

local function ld_hl_nn()
  memory:set(compose(cpu.h, cpu.l), memory:get(cpu.pc - 1))
end

local function ld_hl_a(inc)
  local hl = compose(cpu.h, cpu.l)
  memory:set(hl, cpu.a)
  cpu.h = band(rshift(hl + inc, 0x8), 0xff)
  cpu.l = band(hl + inc, 0xff)
end

local function dec_r8(register)
  local result = band(cpu[register] - 1, 0xff)

  cpu[register] = result

  cpu.f = bor(result == 0 and 0x80 or 0,
              0x40,
              band(result, 0xf) == 0xf and 0x20 or 0,
              band(cpu.f, 0x10))
end

-- [[
-- End Instruction handlers
-- ]]

local lookup = {
  { 0x00, "NOP ",         1, 4,  nop,        nil },
  { 0x01, "LD BC, d16",   3, 12, ld_r16_d16, { "b",    "c" } },
  { 0x02, "LD BC, A",     1, 8,  nil,        nil },
  { 0x03, "INC BC",       1, 8,  nil,        nil },
  { 0x04, "INC B",        1, 4,  nil,        nil },
  { 0x05, "DEC B",        1, 4,  dec_r8,     "b" },
  { 0x06, "LD B, d8",     2, 8,  ld_r8_nn,   "b" },
  { 0x07, "RLCA ",        1, 4,  nil,        nil },
  { 0x08, "LD a16, SP",   3, 20, nil,        nil },
  { 0x09, "ADD HL, BC",   1, 8,  nil,        nil },
  { 0x0A, "LD A, BC",     1, 8,  nil,        nil },
  { 0x0B, "DEC BC",       1, 8,  nil,        nil },
  { 0x0C, "INC C",        1, 4,  nil,        nil },
  { 0x0D, "DEC C",        1, 4,  dec_r8,     "c" },
  { 0x0E, "LD C, d8",     2, 8,  ld_r8_nn,   "c" },
  { 0x0F, "RRCA ",        1, 4,  nil,        nil },
  { 0x10, "STOP d8",      2, 4,  nil,        nil },
  { 0x11, "LD DE, d16",   3, 12, ld_r16_d16, { "d",    "e" } },
  { 0x12, "LD DE, A",     1, 8,  nil,        nil },
  { 0x13, "INC DE",       1, 8,  nil,        nil },
  { 0x14, "INC D",        1, 4,  nil,        nil },
  { 0x15, "DEC D",        1, 4,  dec_r8,     "d" },
  { 0x16, "LD D, d8",     2, 8,  ld_r8_nn,   "d" },
  { 0x17, "RLA ",         1, 4,  nil,        nil },
  { 0x18, "JR r8",        2, 12, nil,        nil },
  { 0x19, "ADD HL, DE",   1, 8,  nil,        nil },
  { 0x1A, "LD A, DE",     1, 8,  nil,        nil },
  { 0x1B, "DEC DE",       1, 8,  nil,        nil },
  { 0x1C, "INC E",        1, 4,  nil,        nil },
  { 0x1D, "DEC E",        1, 4,  dec_r8,     "e" },
  { 0x1E, "LD E, d8",     2, 8,  ld_r8_nn,   "e" },
  { 0x1F, "RRA ",         1, 4,  nil,        nil },
  { 0x20, "JR NZ, r8",    2, 12, nil,        nil },
  { 0x21, "LD HL, d16",   3, 12, ld_r16_d16, { "h",    "l" } },
  { 0x22, "LD HL, A",     1, 8,  ld_hl_a,    1   },
  { 0x23, "INC HL",       1, 8,  nil,        nil },
  { 0x24, "INC H",        1, 4,  nil,        nil },
  { 0x25, "DEC H",        1, 4,  dec_r8,     "h" },
  { 0x26, "LD H, d8",     2, 8,  ld_r8_nn,   "h" },
  { 0x27, "DAA ",         1, 4,  nil,        nil },
  { 0x28, "JR Z, r8",     2, 12, nil,        nil },
  { 0x29, "ADD HL, HL",   1, 8,  nil,        nil },
  { 0x2A, "LD A, HL",     1, 8,  nil,        nil },
  { 0x2B, "DEC HL",       1, 8,  nil,        nil },
  { 0x2C, "INC L",        1, 4,  nil,        nil },
  { 0x2D, "DEC L",        1, 4,  dec_r8,     "l" },
  { 0x2E, "LD L, d8",     2, 8,  ld_r8_nn,   "l" },
  { 0x2F, "CPL ",         1, 4,  nil,        nil },
  { 0x30, "JR NC, r8",    2, 12, nil,        nil },
  { 0x31, "LD SP, d16",   3, 12, nil,        nil },
  { 0x32, "LD HL, A",     1, 8,  ld_hl_a,    -1  },
  { 0x33, "INC SP",       1, 8,  nil,        nil },
  { 0x34, "INC HL",       1, 12, nil,        nil },
  { 0x35, "DEC HL",       1, 12, dec_r8,     "(hl)" },
  { 0x36, "LD HL, d8",    2, 12, ld_hl_nn,   "(hl)" },
  { 0x37, "SCF ",         1, 4,  nil,        nil },
  { 0x38, "JR C, r8",     2, 12, nil,        nil },
  { 0x39, "ADD HL, SP",   1, 8,  nil,        nil },
  { 0x3A, "LD A, HL",     1, 8,  nil,        nil },
  { 0x3B, "DEC SP",       1, 8,  nil,        nil },
  { 0x3C, "INC A",        1, 4,  nil,        nil },
  { 0x3D, "DEC A",        1, 4,  dec_r8,     "a" },
  { 0x3E, "LD A, d8",     2, 8,  ld_r8_nn,   "a" },
  { 0x3F, "CCF ",         1, 4,  nil,        nil },
  { 0x40, "LD B, B",      1, 4,  nil,        nil },
  { 0x41, "LD B, C",      1, 4,  nil,        nil },
  { 0x42, "LD B, D",      1, 4,  nil,        nil },
  { 0x43, "LD B, E",      1, 4,  nil,        nil },
  { 0x44, "LD B, H",      1, 4,  nil,        nil },
  { 0x45, "LD B, L",      1, 4,  nil,        nil },
  { 0x46, "LD B, HL",     1, 8,  nil,        nil },
  { 0x47, "LD B, A",      1, 4,  nil,        nil },
  { 0x48, "LD C, B",      1, 4,  nil,        nil },
  { 0x49, "LD C, C",      1, 4,  nil,        nil },
  { 0x4A, "LD C, D",      1, 4,  nil,        nil },
  { 0x4B, "LD C, E",      1, 4,  nil,        nil },
  { 0x4C, "LD C, H",      1, 4,  nil,        nil },
  { 0x4D, "LD C, L",      1, 4,  nil,        nil },
  { 0x4E, "LD C, HL",     1, 8,  nil,        nil },
  { 0x4F, "LD C, A",      1, 4,  nil,        nil },
  { 0x50, "LD D, B",      1, 4,  nil,        nil },
  { 0x51, "LD D, C",      1, 4,  nil,        nil },
  { 0x52, "LD D, D",      1, 4,  nil,        nil },
  { 0x53, "LD D, E",      1, 4,  nil,        nil },
  { 0x54, "LD D, H",      1, 4,  nil,        nil },
  { 0x55, "LD D, L",      1, 4,  nil,        nil },
  { 0x56, "LD D, HL",     1, 8,  nil,        nil },
  { 0x57, "LD D, A",      1, 4,  nil,        nil },
  { 0x58, "LD E, B",      1, 4,  nil,        nil },
  { 0x59, "LD E, C",      1, 4,  nil,        nil },
  { 0x5A, "LD E, D",      1, 4,  nil,        nil },
  { 0x5B, "LD E, E",      1, 4,  nil,        nil },
  { 0x5C, "LD E, H",      1, 4,  nil,        nil },
  { 0x5D, "LD E, L",      1, 4,  nil,        nil },
  { 0x5E, "LD E, HL",     1, 8,  nil,        nil },
  { 0x5F, "LD E, A",      1, 4,  nil,        nil },
  { 0x60, "LD H, B",      1, 4,  nil,        nil },
  { 0x61, "LD H, C",      1, 4,  nil,        nil },
  { 0x62, "LD H, D",      1, 4,  nil,        nil },
  { 0x63, "LD H, E",      1, 4,  nil,        nil },
  { 0x64, "LD H, H",      1, 4,  nil,        nil },
  { 0x65, "LD H, L",      1, 4,  nil,        nil },
  { 0x66, "LD H, HL",     1, 8,  nil,        nil },
  { 0x67, "LD H, A",      1, 4,  nil,        nil },
  { 0x68, "LD L, B",      1, 4,  nil,        nil },
  { 0x69, "LD L, C",      1, 4,  nil,        nil },
  { 0x6A, "LD L, D",      1, 4,  nil,        nil },
  { 0x6B, "LD L, E",      1, 4,  nil,        nil },
  { 0x6C, "LD L, H",      1, 4,  nil,        nil },
  { 0x6D, "LD L, L",      1, 4,  nil,        nil },
  { 0x6E, "LD L, HL",     1, 8,  nil,        nil },
  { 0x6F, "LD L, A",      1, 4,  nil,        nil },
  { 0x70, "LD HL, B",     1, 8,  nil,        nil },
  { 0x71, "LD HL, C",     1, 8,  nil,        nil },
  { 0x72, "LD HL, D",     1, 8,  nil,        nil },
  { 0x73, "LD HL, E",     1, 8,  nil,        nil },
  { 0x74, "LD HL, H",     1, 8,  nil,        nil },
  { 0x75, "LD HL, L",     1, 8,  nil,        nil },
  { 0x76, "HALT ",        1, 4,  nil,        nil },
  { 0x77, "LD HL, A",     1, 8,  nil,        nil },
  { 0x78, "LD A, B",      1, 4,  nil,        nil },
  { 0x79, "LD A, C",      1, 4,  nil,        nil },
  { 0x7A, "LD A, D",      1, 4,  nil,        nil },
  { 0x7B, "LD A, E",      1, 4,  nil,        nil },
  { 0x7C, "LD A, H",      1, 4,  nil,        nil },
  { 0x7D, "LD A, L",      1, 4,  nil,        nil },
  { 0x7E, "LD A, HL",     1, 8,  nil,        nil },
  { 0x7F, "LD A, A",      1, 4,  nil,        nil },
  { 0x80, "ADD A, B",     1, 4,  nil,        nil },
  { 0x81, "ADD A, C",     1, 4,  nil,        nil },
  { 0x82, "ADD A, D",     1, 4,  nil,        nil },
  { 0x83, "ADD A, E",     1, 4,  nil,        nil },
  { 0x84, "ADD A, H",     1, 4,  nil,        nil },
  { 0x85, "ADD A, L",     1, 4,  nil,        nil },
  { 0x86, "ADD A, HL",    1, 8,  nil,        nil },
  { 0x87, "ADD A, A",     1, 4,  nil,        nil },
  { 0x88, "ADC A, B",     1, 4,  nil,        nil },
  { 0x89, "ADC A, C",     1, 4,  nil,        nil },
  { 0x8A, "ADC A, D",     1, 4,  nil,        nil },
  { 0x8B, "ADC A, E",     1, 4,  nil,        nil },
  { 0x8C, "ADC A, H",     1, 4,  nil,        nil },
  { 0x8D, "ADC A, L",     1, 4,  nil,        nil },
  { 0x8E, "ADC A, HL",    1, 8,  nil,        nil },
  { 0x8F, "ADC A, A",     1, 4,  nil,        nil },
  { 0x90, "SUB B",        1, 4,  nil,        nil },
  { 0x91, "SUB C",        1, 4,  nil,        nil },
  { 0x92, "SUB D",        1, 4,  nil,        nil },
  { 0x93, "SUB E",        1, 4,  nil,        nil },
  { 0x94, "SUB H",        1, 4,  nil,        nil },
  { 0x95, "SUB L",        1, 4,  nil,        nil },
  { 0x96, "SUB HL",       1, 8,  nil,        nil },
  { 0x97, "SUB A",        1, 4,  nil,        nil },
  { 0x98, "SBC A, B",     1, 4,  nil,        nil },
  { 0x99, "SBC A, C",     1, 4,  nil,        nil },
  { 0x9A, "SBC A, D",     1, 4,  nil,        nil },
  { 0x9B, "SBC A, E",     1, 4,  nil,        nil },
  { 0x9C, "SBC A, H",     1, 4,  nil,        nil },
  { 0x9D, "SBC A, L",     1, 4,  nil,        nil },
  { 0x9E, "SBC A, HL",    1, 8,  nil,        nil },
  { 0x9F, "SBC A, A",     1, 4,  nil,        nil },
  { 0xA0, "AND B",        1, 4,  nil,        nil },
  { 0xA1, "AND C",        1, 4,  nil,        nil },
  { 0xA2, "AND D",        1, 4,  nil,        nil },
  { 0xA3, "AND E",        1, 4,  nil,        nil },
  { 0xA4, "AND H",        1, 4,  nil,        nil },
  { 0xA5, "AND L",        1, 4,  nil,        nil },
  { 0xA6, "AND HL",       1, 8,  nil,        nil },
  { 0xA7, "AND A",        1, 4,  nil,        nil },
  { 0xA8, "XOR B",        1, 4,  xor_a_r8,   "b" },
  { 0xA9, "XOR C",        1, 4,  xor_a_r8,   "c" },
  { 0xAA, "XOR D",        1, 4,  xor_a_r8,   "d" },
  { 0xAB, "XOR E",        1, 4,  xor_a_r8,   "e" },
  { 0xAC, "XOR H",        1, 4,  xor_a_r8,   "h" },
  { 0xAD, "XOR L",        1, 4,  xor_a_r8,   "l" },
  { 0xAE, "XOR HL",       1, 8,  xor_a_r8,   "(hl)" },
  { 0xAF, "XOR A",        1, 4,  xor_a_r8,   "a" },
  { 0xB0, "OR B",         1, 4,  nil,        nil },
  { 0xB1, "OR C",         1, 4,  nil,        nil },
  { 0xB2, "OR D",         1, 4,  nil,        nil },
  { 0xB3, "OR E",         1, 4,  nil,        nil },
  { 0xB4, "OR H",         1, 4,  nil,        nil },
  { 0xB5, "OR L",         1, 4,  nil,        nil },
  { 0xB6, "OR HL",        1, 8,  nil,        nil },
  { 0xB7, "OR A",         1, 4,  nil,        nil },
  { 0xB8, "CP B",         1, 4,  nil,        nil },
  { 0xB9, "CP C",         1, 4,  nil,        nil },
  { 0xBA, "CP D",         1, 4,  nil,        nil },
  { 0xBB, "CP E",         1, 4,  nil,        nil },
  { 0xBC, "CP H",         1, 4,  nil,        nil },
  { 0xBD, "CP L",         1, 4,  nil,        nil },
  { 0xBE, "CP HL",        1, 8,  nil,        nil },
  { 0xBF, "CP A",         1, 4,  nil,        nil },
  { 0xC0, "RET NZ",       1, 20, nil,        nil },
  { 0xC1, "POP BC",       1, 12, nil,        nil },
  { 0xC2, "JP NZ, a16",   3, 16, nil,        nil },
  { 0xC3, "JP a16",       3, 16, jp_nn,      nil },
  { 0xC4, "CALL NZ, a16", 3, 24, nil,        nil },
  { 0xC5, "PUSH BC",      1, 16, nil,        nil },
  { 0xC6, "ADD A, d8",    2, 8,  nil,        nil },
  { 0xC7, "RST 00H",      1, 16, nil,        nil },
  { 0xC8, "RET Z",        1, 20, nil,        nil },
  { 0xC9, "RET ",         1, 16, nil,        nil },
  { 0xCA, "JP Z, a16",    3, 16, nil,        nil },
  { 0xCB, "PREFIX ",      1, 4,  nil,        nil },
  { 0xCC, "CALL Z, a16",  3, 24, nil,        nil },
  { 0xCD, "CALL a16",     3, 24, nil,        nil },
  { 0xCE, "ADC A, d8",    2, 8,  nil,        nil },
  { 0xCF, "RST 08H",      1, 16, nil,        nil },
  { 0xD0, "RET NC",       1, 20, nil,        nil },
  { 0xD1, "POP DE",       1, 12, nil,        nil },
  { 0xD2, "JP NC, a16",   3, 16, nil,        nil },
  { 0xD3, "ILLEGAL_D3 ",  1, 4,  nil,        nil },
  { 0xD4, "CALL NC, a16", 3, 24, nil,        nil },
  { 0xD5, "PUSH DE",      1, 16, nil,        nil },
  { 0xD6, "SUB d8",       2, 8,  nil,        nil },
  { 0xD7, "RST 10H",      1, 16, nil,        nil },
  { 0xD8, "RET C",        1, 20, nil,        nil },
  { 0xD9, "RETI ",        1, 16, nil,        nil },
  { 0xDA, "JP C, a16",    3, 16, nil,        nil },
  { 0xDB, "ILLEGAL_DB ",  1, 4,  nil,        nil },
  { 0xDC, "CALL C, a16",  3, 24, nil,        nil },
  { 0xDD, "ILLEGAL_DD ",  1, 4,  nil,        nil },
  { 0xDE, "SBC A, d8",    2, 8,  nil,        nil },
  { 0xDF, "RST 18H",      1, 16, nil,        nil },
  { 0xE0, "LDH a8, A",    2, 12, nil,        nil },
  { 0xE1, "POP HL",       1, 12, nil,        nil },
  { 0xE2, "LD C, A",      1, 8,  nil,        nil },
  { 0xE3, "ILLEGAL_E3 ",  1, 4,  nil,        nil },
  { 0xE4, "ILLEGAL_E4 ",  1, 4,  nil,        nil },
  { 0xE5, "PUSH HL",      1, 16, nil,        nil },
  { 0xE6, "AND d8",       2, 8,  nil,        nil },
  { 0xE7, "RST 20H",      1, 16, nil,        nil },
  { 0xE8, "ADD SP, r8",   2, 16, nil,        nil },
  { 0xE9, "JP HL",        1, 4,  nil,        nil },
  { 0xEA, "LD a16, A",    3, 16, nil,        nil },
  { 0xEB, "ILLEGAL_EB ",  1, 4,  nil,        nil },
  { 0xEC, "ILLEGAL_EC ",  1, 4,  nil,        nil },
  { 0xED, "ILLEGAL_ED ",  1, 4,  nil,        nil },
  { 0xEE, "XOR d8",       2, 8,  nil,        nil },
  { 0xEF, "RST 28H",      1, 16, nil,        nil },
  { 0xF0, "LDH A, a8",    2, 12, nil,        nil },
  { 0xF1, "POP AF",       1, 12, nil,        nil },
  { 0xF2, "LD A, C",      1, 8,  nil,        nil },
  { 0xF3, "DI ",          1, 4,  nil,        nil },
  { 0xF4, "ILLEGAL_F4 ",  1, 4,  nil,        nil },
  { 0xF5, "PUSH AF",      1, 16, nil,        nil },
  { 0xF6, "OR d8",        2, 8,  nil,        nil },
  { 0xF7, "RST 30H",      1, 16, nil,        nil },
  { 0xF8, "LD HL, SP+r8", 2, 12, nil,        nil },
  { 0xF9, "LD SP, HL",    1, 8,  nil,        nil },
  { 0xFA, "LD A, a16",    3, 16, nil,        nil },
  { 0xFB, "EI ",          1, 4,  nil,        nil },
  { 0xFC, "ILLEGAL_FC ",  1, 4,  nil,        nil },
  { 0xFD, "ILLEGAL_FD ",  1, 4,  nil,        nil },
  { 0xFE, "CP d8",        2, 8,  nil,        nil },
  { 0xFF, "RST 38H",      1, 16, nil,        nil }
}

function instructions:init(_cpu, _memory)
	for _, data in ipairs(lookup) do
		local index, mnemonic, bytes, cycles, handler, params = unpack(data)

		local instruction = {
			mnemonic = mnemonic,
			bytes = bytes,
			cycles = cycles,
			handler = handler,
			params = params,
		}

		instructions[index] = instruction
	end

	-- set locals
	cpu = _cpu
	memory = _memory
end

return instructions
