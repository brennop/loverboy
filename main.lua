local emulator = require "emulator"
local graphics = require "graphics"

function love.keypressed(key)
  if key == "escape" then
    love.event.quit()
  elseif key == "p" then
    graphics:next_palette()
  end
end

function love.load(args)
  love.graphics.setDefaultFilter("nearest", "nearest")

  -- trace = true
  emulator:init(args[1])
end

function love.update()
  emulator:step()
end

function love.draw()
  emulator:draw()
end
