local cpu = require "cpu"
local memory = require "memory"

local ffi = require "ffi"
local cast = ffi.cast

local band, bor, bnot = bit.band, bit.bor, bit.bnot
local rshift, lshift = bit.rshift, bit.lshift
local mod = math.fmod

local LCDC = 0xFF40
local STAT = 0xFF41
local SCY = 0xFF42
local SCX = 0xFF43
local LY = 0xFF44
local LYC = 0xFF45
local WY = 0xFF4A
local WX = 0xFF4B

local OAM = 0xFE00

local graphics = {
  cycles = 0,
  mode = "hblank",
  framebuffer = nil,
  bg_priority = {},
  palette = 4,
}

local modes = {
  hblank = 0,
  vblank = 1,
  oam = 2,
  vram = 3,
}

local palettes = {
  { "#f4f4f4", "#566c86", "#333c57", "#1a1c2c", },
  { "#f4f4f4", "#41a6f6", "#3b5dc9", "#29366f", },
  { "#f4f4f4", "#ffcd75", "#ef7d57", "#b13e53", },
}

local addresses = {
  0xff47,
  0xff48,
  0xff49,
}

local function parse_color(rgba)
  local rb = tonumber(string.sub(rgba, 2, 3), 16)
  local gb = tonumber(string.sub(rgba, 4, 5), 16)
  local bb = tonumber(string.sub(rgba, 6, 7), 16)
  local ab = tonumber(string.sub(rgba, 8, 9), 16) or nil
  return love.math.colorFromBytes(rb, gb, bb, ab)
end

for palette in ipairs(palettes) do
  for index, color in ipairs(palettes[palette]) do
    palettes[palette][index] = { parse_color(color) }
  end
end

function graphics:get_color(value, num)
  local address = addresses[num]
  local palette = memory:get(address)

  local low_bit = band(rshift(palette, value * 2), 0x01)
  local high_bit = band(rshift(palette, value * 2 + 1), 0x01)
  local index = bor(lshift(high_bit, 1), low_bit)
  local color = palettes[num][index + 1]

  return color[1], color[2], color[3]
end

function graphics:init()
  self.framebuffer = love.image.newImageData(160, 144)

  self.mode = "hblank"

  for x = 0, 159 do 
    self.bg_priority[x] = {}
    for y = 0, 143 do
      self.bg_priority[x][y] = false
    end
  end

  self:next_palette()
end

function graphics:next_palette()
  self.palette = mod(self.palette, #palettes) + 1
end

function graphics:update_stat(mode)
  local status = band(memory:get(STAT), 0xFC)
  local scanline = memory:get(LY)
  local coincidence = memory:get(LYC)

  if scanline == coincidence then
    -- 0x04: set coincidence
    status = bor(status, 0x04)
    -- if coincidence interrupt is enabled, call interrupt
    cpu:conditional_interrupt("stat", status, 0x40)
  else
    -- unset coincidence (~0x04)
    -- status = band(status, 0xFB)
    status = band(status, bnot(0x04))
  end

  memory:set(STAT, bor(status, modes[mode]))
end

function graphics:set_mode(mode)
  self:update_stat(mode)
  local status = memory:get(STAT)

  if mode == "oam" then
    cpu:conditional_interrupt("stat", status, 0x20)
  elseif mode == "hblank" then
    cpu:conditional_interrupt("stat", status, 0x08)
  elseif mode == "vblank" then
    cpu:conditional_interrupt("stat", status, 0x10)
    cpu:interrupt "vblank"
  end

  self.mode = mode
end

function graphics:step(cycles)
  if self:is_lcd_enabled() then
    self.cycles = self.cycles + cycles

    local scanline = memory:get(LY)

    -- TODO: maybe merge ifs
    if self.mode == "oam" then
      if self.cycles >= 80 then
        self.cycles = self.cycles - 80
        self:set_mode "vram"
      end
    elseif self.mode == "vram" then
      if self.cycles >= 172 then
        self.cycles = self.cycles - 172
        self:set_mode "hblank"
        self:render_scanline()
      end
    elseif self.mode == "hblank" then
      if self.cycles >= 204 then
        self.cycles = self.cycles - 204
        memory:set(LY, scanline + 1)

        if scanline == 143 then
          self:set_mode "vblank"
        else
          self:set_mode "oam"
        end
      end
    elseif self.mode == "vblank" then
      if self.cycles >= 456 then
        self.cycles = self.cycles - 456

        memory:set(LY, scanline + 1)

        if scanline == 153 then
          self:set_mode "oam"
          memory:set(LY, 0)
        end
      end
    end
  end
end

function graphics:is_lcd_enabled()
  return band(memory:get(LCDC), 0x80) == 0x80
end

function graphics:render_scanline()
  local control = memory:get(LCDC)

  if band(control, 0x01) == 0x01 then
    self:render_tiles()
  end

  if band(control, 0x02) == 0x02 then
    self:render_sprites()
  end
end

function graphics:render_tiles()
  local lcdc = memory:get(LCDC)
  local scanline = memory:get(LY)

  local scroll_y = memory:get(SCY)
  local scroll_x = memory:get(SCX)
  local window_y = memory:get(WY)
  local window_x = memory:get(WX) - 7

  local window_enabled = band(lcdc, 0x20) == 0x20

  -- is current scanline within window
  local using_window = window_enabled and window_y <= scanline

  -- which tile data are we using
  local is_unsigned = band(lcdc, 0x10) == 0x10
  local tile_data = is_unsigned and 0x8000 or 0x8800

  -- which bg memory
  local mask = using_window and 0x40 or 0x08
  local background_memory = band(lcdc, mask) == mask and 0x9C00 or 0x9800

  local y_pos = band(using_window and scanline - window_y or scroll_y + scanline, 0xff)

  local tile_row = lshift(rshift(y_pos, 3), 5)

  -- draw each pixel
  for pixel = 0, 160 - 1 do
    local x_pos = pixel + scroll_x

    if using_window and pixel >= window_x then
      x_pos = pixel - window_x
    end

    local tile_col = band(rshift(x_pos, 3), 0x1F)

    local tile_address = background_memory + tile_row + tile_col
    local tile_num = memory:get(tile_address)

    if not is_unsigned then
      tile_num = tonumber(cast("int8_t", tile_num) + 128)
    end

    local tile_location = tile_data + tile_num * 16

    local line = mod(y_pos, 8) * 2

    local data_right = memory:get(tile_location + line)
    local data_left = memory:get(tile_location + line + 1)

    local color_bit = 7 - mod(x_pos, 8)

    -- combine data
    local left_bit = rshift(band(lshift(1, color_bit), data_left), color_bit)
    local right_bit = rshift(band(lshift(1, color_bit), data_right), color_bit)

    local color_num = bor(lshift(left_bit, 1), right_bit)

    local r, g, b = self:get_color(color_num, 1)

    if scanline >= 0 and scanline < 144 then
      self.bg_priority[pixel][scanline] = color_num ~= 0

      self.framebuffer:setPixel(pixel, scanline, r, g, b, 1)
    end
  end
end

local function sort_by_x_pos(a, b)
  return a.x_pos < b.x_pos
end

function graphics:render_sprites()
  local lcdc = memory:get(LCDC)
  local scanline = memory:get(LY)

  local sprite_size = band(lcdc, 0x04) == 0x04 and 16 or 8

  local sprites_to_draw = {}

  for sprite = 1, 40 do
    local index = (sprite - 1) * 4

    local y_pos = memory:get(OAM + index) - 16
    local x_pos = memory:get(OAM + index + 1) - 8
    local tile_location = memory:get(OAM + index + 2)
    local attributes = memory:get(OAM + index + 3)

    if scanline < y_pos + sprite_size then
      sprites_to_draw[#sprites_to_draw + 1] = {
        y_pos = y_pos,
        x_pos = x_pos,
        tile_location = tile_location,
        attributes = attributes,
      }
    end
  end

  -- sort sprites by x_pos
  table.sort(sprites_to_draw, sort_by_x_pos)

  for _, sprite in ipairs(sprites_to_draw) do
    local y_pos = sprite.y_pos
    local x_pos = sprite.x_pos
    local tile_location = sprite.tile_location
    local attributes = sprite.attributes

    local y_flip = band(attributes, 0x40) == 0x40
    local x_flip = band(attributes, 0x20) == 0x20

    local palette = band(attributes, 0x10) == 0x10 and 3 or 2

    -- should sprite be drawn on this scanline
    if scanline >= y_pos and scanline < (y_pos + sprite_size) then
      local line = scanline - y_pos

      if y_flip then
        line = sprite_size - line - 1
      end

      line = lshift(line, 1)

      local address = 0x8000 + tile_location * 16 + line
      local data_right = memory:get(address)
      local data_left = memory:get(address + 1)

      for tile_pixel = 7, 0, -1 do
        local color_bit = tile_pixel

        if x_flip then
          color_bit = 7 - tile_pixel
        end

        local color_num = bor(
          lshift(rshift(band(lshift(1, color_bit), data_left), color_bit), 1),
          rshift(band(lshift(1, color_bit), data_right), color_bit)
        )

        local r, g, b = self:get_color(color_num, palette)

        local x = x_pos + (7 - tile_pixel)
        if color_num ~= 0 and x >= 0 and x < 160 and scanline >= 0 and scanline < 144 then
          -- check if sprite is behind bg
          local bg_priority = band(attributes, 0x80) == 0x80
          local is_bg = self.bg_priority[x][scanline]

          if not bg_priority or not is_bg then
            self.framebuffer:setPixel(x, scanline, r, g, b, 1)
          end
        end
      end
    end
  end
end

return graphics
