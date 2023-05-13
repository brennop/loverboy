local cpu = require "cpu"
local memory = require "memory"

local band, bor = bit.band, bit.bor

local LCDC = 0xFF40
local STAT = 0xFF41
local SCY  = 0xFF42
local SCX  = 0xFF43
local LY   = 0xFF44
local LYC  = 0xFF45
local WY   = 0xFF4A
local WX   = 0xFF4B

local graphics = {
  cycles = 0,
  mode = "hblank",
}

local modes = {
  hblank = 0,
  vblank = 1,
  oam    = 2,
  vram   = 3,
}

function graphics:init()
  -- TODO: maybe set correct mode from memory?
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
    status = band(status, 0xFB)
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

return graphics
