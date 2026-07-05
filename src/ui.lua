-- Small shared UI primitives.
local util = require 'src.util'
local palette = require 'src.palette'
local sprites = require 'src.sprites'
local CO = palette.CO
local gfx = love.graphics

local M = {}

-- Pixel-perfect 1px rectangle outline (avoids GPU line-rasterization drift).
function M.outline(x, y, w, h, color, alpha)
  gfx.setColor(color[1], color[2], color[3], alpha or 1)
  gfx.rectangle('fill', x, y, w, 1)
  gfx.rectangle('fill', x, y + h - 1, w, 1)
  gfx.rectangle('fill', x, y, 1, h)
  gfx.rectangle('fill', x + w - 1, y, 1, h)
end

function M.drawBar(x, y, w, h, frac)
  frac = util.clamp(frac, 0, 1)
  gfx.setColor(CO.ink)
  gfx.rectangle('fill', x - 1, y - 1, w + 2, h + 2)
  gfx.setColor(CO.grayD)
  gfx.rectangle('fill', x, y, w, h)
  gfx.setColor(frac > 0.35 and CO.hp or CO.hpBad)
  gfx.rectangle('fill', x, y, util.round(w * frac), h)
end

-- Intent-telegraph icon on a dark badge plate, so every icon reads at the
-- same contrast regardless of its own fill (solid-black bomb vs thin gray
-- wrench) or what it overlaps. uiBg2 rather than uiBg: the bomb icon is
-- pure ink and would vanish on an ink-colored plate.
function M.drawIntentIcon(name, x, y, scale)
  scale = scale or 1
  local pad = scale
  local s = 12 * scale + 2 * pad
  local px, py = x - pad, y - pad
  gfx.setColor(CO.uiBg2[1], CO.uiBg2[2], CO.uiBg2[3], 0.85)
  gfx.rectangle('fill', px + 1, py, s - 2, s)
  gfx.rectangle('fill', px, py + 1, s, s - 2)
  gfx.setColor(CO.ink)
  gfx.rectangle('fill', px + 1, py, s - 2, 1)
  gfx.rectangle('fill', px + 1, py + s - 1, s - 2, 1)
  gfx.rectangle('fill', px, py + 1, 1, s - 2)
  gfx.rectangle('fill', px + s - 1, py + 1, 1, s - 2)
  sprites.draw(name, x, y, false, scale)
end

-- Corner-bracket selection cursor.
function M.drawCursor(x, y, s, color)
  gfx.setColor(color)
  gfx.rectangle('fill', x, y, 5, 2); gfx.rectangle('fill', x, y, 2, 5)
  gfx.rectangle('fill', x + s - 5, y, 5, 2); gfx.rectangle('fill', x + s - 2, y, 2, 5)
  gfx.rectangle('fill', x, y + s - 2, 5, 2); gfx.rectangle('fill', x, y + s - 5, 2, 5)
  gfx.rectangle('fill', x + s - 5, y + s - 2, 5, 2); gfx.rectangle('fill', x + s - 2, y + s - 5, 2, 5)
end

return M
