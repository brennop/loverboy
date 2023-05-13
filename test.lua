local json = require "json"
local cpu = require "cpu"
local instructions = require "instructions"

local bor, band, bxor, lshift, rshift = bit.bor, bit.band, bit.bxor, bit.lshift, bit.rshift

local memory = { data = {} }

for i = 0, 0x10000 do memory.data[i] = 0 end

function memory:get(addr) return self.data[addr] end
function memory:set(addr, value) self.data[addr] = value end

local testfolder = "cpu_tests/"
local testsuite = arg[1]
local filepath = testfolder .. testsuite .. ".json"
print(filepath)

local file = io.open(filepath, "r")
local data = file:read "*all"
file:close()

local tests = json.decode(data)

instructions:init(cpu, memory)

local function run_test(test)
  cpu:init(memory)

  for _, v in ipairs(test.initial.ram) do
    address, value = unpack(v)
    address, value = tonumber(address), tonumber(value)
    memory:set(address, value)
  end

  cpu.a = tonumber(test.initial.cpu.a)
  cpu.f = tonumber(test.initial.cpu.f)
  cpu.b = tonumber(test.initial.cpu.b)
  cpu.c = tonumber(test.initial.cpu.c)
  cpu.d = tonumber(test.initial.cpu.d)
  cpu.e = tonumber(test.initial.cpu.e)
  cpu.h = tonumber(test.initial.cpu.h)
  cpu.l = tonumber(test.initial.cpu.l)
  cpu.sp = tonumber(test.initial.cpu.sp)
  cpu.pc = tonumber(test.initial.cpu.pc)

  cpu:step()

  local function assert_register(name)
    local expected = tonumber(test.final.cpu[name])
    local actual = cpu[name]

    local message = [[

    TEST FAILED
      test: %s
      register: %s
      expected: 0x%04x
      actual: 0x%04x
    ]]

    assert(actual == expected, message:format(test.name, name, expected, actual))
  end

  local function assert_flag(offset, name)
    local flags = tonumber(test.final.cpu.f)
    local expected = band(flags, lshift(1, offset))
    local actual = band(cpu.f, lshift(1, offset))

    local message = [[

    TEST FAILED
      test: %s
      flag: %s
      expected: 0x%04x
      actual: 0x%04x
    ]]

    assert(actual == expected, message:format(test.name, name, expected, actual))
  end

  -- check registers
  assert_register("a")
  assert_register("b")
  assert_register("c")
  assert_register("d")
  assert_register("e")
  assert_register("h")
  assert_register("l")
  assert_register("sp")
  assert_register("pc")

  -- check flags
  assert_flag(7, "zero")
  assert_flag(6, "sub")
  assert_flag(5, "half")
  assert_flag(4, "carry")

  -- check memory
  for _, v in ipairs(test.final.ram) do
    address, value = unpack(v)
    address, value = tonumber(address), tonumber(value)

    local actual = memory:get(address)

    local message = [[

    TEST FAILED
      test: %s
      address: 0x%04x
      expected: 0x%04x
      actual: 0x%04x
    ]]

    assert(actual == value, message:format(test.name, address, value, actual))
  end
end

local function run_tests(tests)
  local start = os.clock()
  local errors = 0
  for i = 1, 10000 do
    local test = tests[i]

    local ok, err = pcall(run_test, test)

    if not ok then
      print(err, "at ", test.name)
      errors = errors + 1
    end

    if errors >= 10 then
      print("too many errors, stopping")
      os.exit(1)
    end
  end

  print(string.format("Passing: %d/%d", 10000 - errors, 10000))
  print(string.format("elapsed time: %.2f\n", os.clock() - start))
end

run_tests(tests)
