local memory = require "memory"
local emulator = require "emulator"
local cpu = require "cpu"
local instructions = require "instructions"

function love.load()
  emulator:init("tetris.gb")
  memory:init(emulator.rom)
  cpu:init()
  instructions:init(cpu, memory)
end

function love.update()
  cpu:step()
end
