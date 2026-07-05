-- Sail hex layout + hit-testing + autopilot path helpers (odd-r offset grid,
-- pointy-top hexes — see grid.lua). No game rules here: just geometry and
-- pathfinding over the sea grid, shared by sail.lua and sail_rules.lua.
local grid = require 'src.grid'
local game = require 'src.game'
local gfx = love.graphics

local M = {}

local VW = 320
local SEA_W, SEA_H, SEA_TOP = game.SEA_W, game.SEA_H, game.SEA_TOP

-- Hex layout. Hexes are 16 px wide (matching the 16x16 sprites) with a 13 px
-- vertical pitch; outline corners at (0,-9)(8,-4)(8,4)(0,9)(-8,4)(-8,-4)
-- tessellate exactly at that pitch. The grid is centered in the same
-- 144 px band between the HUD and the hint bar that the square sea used.
local HEX_W = 16
local ROW_H = 13
local HEX_TOP, HEX_SIDE = 9, 4 -- corner y-offsets of the outline polygon
local SEA_BAND = 144
local SEA_OX = math.floor((VW - (SEA_W * HEX_W + HEX_W / 2)) / 2)
local SEA_OY = SEA_TOP + math.floor((SEA_BAND - ((SEA_H - 1) * ROW_H + 2 * HEX_TOP)) / 2) + HEX_TOP

M.SEA_BAND = SEA_BAND

-- Odd rows shift right half a cell. Continuous in y so hop animations that
-- cross rows slide the shift instead of snapping it.
local function rowShift(y)
  local m = y % 2
  return (m <= 1 and m or 2 - m) * (HEX_W / 2)
end

function M.hexCenter(x, y)
  return SEA_OX + x * HEX_W + rowShift(y) + HEX_W / 2, SEA_OY + y * ROW_H
end

-- Top-left of a 16x16 sprite box centered on the hex; safe for fractional
-- (animated) coordinates.
function M.sailPx(x, y)
  local cx, cy = M.hexCenter(x, y)
  return cx - 8, cy - 8
end

-- Nearest hex to a canvas point, or nil if the point is off the sea.
function M.hexAt(px, py)
  local bx, by, bd = nil, nil, 999999
  for y = 0, SEA_H - 1 do
    for x = 0, SEA_W - 1 do
      local cx, cy = M.hexCenter(x, y)
      local d = (px - cx) ^ 2 + (py - cy) ^ 2
      if d < bd then bx, by, bd = x, y, d end
    end
  end
  if bd <= 100 then return bx, by end
  return nil
end

-- Map a d-pad press to a hex step. Left/right follow the row; up/down are
-- ambiguous on pointy-top hexes (NE-vs-NW, SE-vs-SW), so the ship's facing
-- picks the diagonal: press up while facing right and you sail NE.
function M.hexStep(x, y, dir, face)
  if dir == 'left' then return x - 1, y end
  if dir == 'right' then return x + 1, y end
  local odd = y % 2
  local dy = dir == 'up' and -1 or 1
  local dx
  if face >= 0 then dx = odd == 1 and 1 or 0
  else dx = odd == 1 and 0 or -1 end
  return x + dx, y + dy
end

function M.inSea(x, y)
  return x >= 0 and y >= 0 and x < SEA_W and y < SEA_H
end

local HEX_POLY = {
  { 0, -HEX_TOP }, { HEX_W / 2, -HEX_SIDE }, { HEX_W / 2, HEX_SIDE },
  { 0, HEX_TOP }, { -HEX_W / 2, HEX_SIDE }, { -HEX_W / 2, -HEX_SIDE },
}

local hexOutlineV = {}
for i = 1, #HEX_POLY * 2 do hexOutlineV[i] = 0 end

function M.drawHexOutline(cx, cy)
  for i, p in ipairs(HEX_POLY) do
    hexOutlineV[i * 2 - 1] = cx + p[1]
    hexOutlineV[i * 2] = cy + p[2]
  end
  gfx.polygon('line', hexOutlineV)
end

local CHEVRON_DIR = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- Small chevron marking where a d-pad press will land: apex 2px out in the
-- travel direction, rows widening back toward the hex center.
function M.drawChevron(cx, cy, dir)
  local dx, dy = CHEVRON_DIR[dir][1], CHEVRON_DIR[dir][2]
  for r = 0, 2 do
    if dy ~= 0 then
      gfx.rectangle('fill', cx - r, cy + (2 - r) * dy, r * 2 + 1, 1)
    else
      gfx.rectangle('fill', cx + (2 - r) * dx, cy - r, 1, r * 2 + 1)
    end
  end
end

function M.drawWhirl(px, py, gt, CO, util)
  local cx, cy = px + 8, py + 8
  for i = 0, 23 do
    local a = gt * 3 + i * 0.5
    local r = 0.8 + i * 0.29
    gfx.setColor(i % 2 == 1 and CO.foam or CO.seaL)
    gfx.rectangle('fill', util.round(cx + math.cos(a) * r), util.round(cy + math.sin(a) * r * 0.75), 1, 1)
  end
end

-- Tap-to-sail: flood from the ship and path to the tapped hex. Autopilot
-- refuses to sail through enemies unless the tap was on that enemy.
function M.planRoute(sh, gx, gy)
  local target = game.enemyAt(gx, gy)
  local flood = grid.bfsFlood(sh.x, sh.y, 999, function(x, y)
    if not M.inSea(x, y) or game.tileAt(x, y) == game.T_ISLE then return false end
    local e = game.enemyAt(x, y)
    return not e or e == target
  end, grid.hexNeighbors)
  local path = grid.bfsPath(flood, gx, gy)
  if not path or #path < 2 then return nil end
  table.remove(path, 1) -- drop the ship's own cell
  return { steps = path, foe = target }
end

return M
