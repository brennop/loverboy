local emulator = require "emulator"

function love.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  emulator:init("tetris.gb", arg)
end

function love.update()
  emulator:step()
end

function love.draw()
  emulator:draw()
end
