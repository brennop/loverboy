local emulator = require "emulator"

function love.load()
  emulator:init("tetris.gb")

end

function love.update()
  emulator:step()
end
