require "fennel".install()

local emulator = require "emulator"
local graphics = require "graphics"

function love.keypressed(key)
  if key == "escape" then
    -- emulator:save_ram()
    love.event.quit()
  elseif key == "space" then
    emulator:toggle_boost()
  end
end

function love.load(args)
  love.graphics.setDefaultFilter("nearest", "nearest")

  emulator:init(args[1])
end

function love.update()
  emulator:step()
end

function love.draw()
  emulator:draw()
end
