local ffi = require "ffi"

local cpu = require "cpu"
local graphics = require "graphics"
local instructions = require "instructions"
local memory = require "memory"

local band, bor, bxor = bit.band, bit.bor, bit.bxor
local lshift, rshift = bit.lshift, bit.rshift

local freqs = { 1024, 16, 64, 256 }

local emulator = {
  title = nil,

  boost = 1,
  div = 0,
  tima = 0,
}

local function read_rom(filename)
  local file = io.open(filename, "rb")
  local data = file:read("*a")
  file:close()

  -- read zip files
  if data:sub(1, 2) == "PK" then
    local filedata = love.filesystem.newFileData(data, filename)
    love.filesystem.mount(filedata, "rom")

    local items = love.filesystem.getDirectoryItems("rom")
    local item = items[1]

    data = love.filesystem.read("rom/" .. item)
    love.filesystem.unmount("rom")
  end

  local rom = ffi.new("uint8_t[?]", #data)
  local title = data:sub(0x135, 0x143)

  ffi.copy(rom, data)

  return rom, title
end

function emulator:init(filename)
  local rom, title = read_rom(filename)

  self.title = title

  local save = emulator:load_ram(title)

  memory:init(rom, save)
  cpu:init(memory)
  instructions:init(cpu, memory)
  graphics:init()

  self.image = love.graphics.newImage(graphics.framebuffer)
end

function emulator:step()
  local cycles_this_update = 0

  while cycles_this_update < 70224 * self.boost do
    cycles = cpu:step()
    self:update_timers(cycles)
    graphics:step(cycles)

    cycles_this_update = cycles_this_update + cycles
  end

  self.image:replacePixels(graphics.framebuffer)
end

function emulator:draw()
  love.graphics.draw(self.image, 0, 0, 0, 2, 2)

  if show_fps then
    love.graphics.setColor(0, 0, 0)
    love.graphics.rectangle("fill", 0, 0, 60, 20)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(string.format("FPS: %d", love.timer.getFPS()), 0, 0)
  end
end

-- TODO: maybe create timers object
function emulator:update_timers(cycles)
  local div = memory:get(0xFF04)
  local tima = memory:get(0xFF05)
  local tma = memory:get(0xFF06)
  local attributes = memory:get(0xFF07)

  self.div = self.div + cycles
  while self.div >= 256 do
    self.div = self.div - 256
    memory:set(0xFF04, band(memory:get(0xff04) + 1, 0xFF))
  end

  if band(attributes, 0x04) == 0x04 then
    self.tima = self.tima + cycles

    local freq = freqs[band(attributes, 0x03) + 1]

    while self.tima >= freq do
      self.tima = self.tima - freq
      memory:set(0xFF05, band(memory:get(0xff05) + 1, 0xFF))

      if memory:get(0xFF05) == 0 then
        memory:set(0xFF05, tma)
        cpu:interrupt "timer"
      end
    end
  end
end

function emulator:toggle_boost()
  if self.boost == 1 then
    self.boost = 2
  else
    self.boost = 1
  end
end

function emulator:save_ram()
  local data = ffi.string(memory.banks, 0x8000)
  local filename = self.title .. ".sav"

  love.filesystem.write(filename, data)
end

function emulator:load_ram(title)
  local filename = title .. ".sav"

  if love.filesystem.getInfo(filename) then
    return love.filesystem.read(filename)
  end
end


return emulator
