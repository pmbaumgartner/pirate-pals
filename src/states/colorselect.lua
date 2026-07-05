-- Crew color pick: after mode select, before the run starts. Solo picks one
-- swatch; TWO CAPTAINS picks two (one cursor each, colors must differ),
-- with a live ship + captain preview per player.
local util = require 'src.util'
local palette = require 'src.palette'
local font = require 'src.font'
local sprites = require 'src.sprites'
local input = require 'src.input'
local audio = require 'src.audio'
local engine = require 'src.engine'
local game = require 'src.game'
local data = require 'src.data'
local ui = require 'src.ui'
local CO = palette.CO
local gfx = love.graphics
local SFX = audio.sfx

local VW, VH = 320, 180

local M = {}
local cs = nil

local COLS, ROWS = 4, 2
local SW_W, SW_H, SW_GAP = 44, 26, 8
local GRID_X = (VW - (COLS * SW_W + (COLS - 1) * SW_GAP)) / 2
local GRID_Y = 94

local function swatchXY(i)
  local col, row = i % COLS, math.floor(i / COLS)
  return GRID_X + col * (SW_W + SW_GAP), GRID_Y + row * (SW_H + SW_GAP)
end

-- Which swatch a tap lands on, or nil.
local function swatchAt(tx, ty)
  for i = 0, #data.PLAYER_COLORS - 1 do
    local x, y = swatchXY(i)
    if tx >= x and tx < x + SW_W and ty >= y and ty < y + SW_H then return i end
  end
  return nil
end

local function colorAt(i)
  return data.PLAYER_COLORS[i + 1]
end

-- The other player's confirmed swatch is off-limits in captains mode.
local function takenBy(who, i)
  local other = cs[who == 'p1' and 'p2' or 'p1']
  return other and other.done and other.i == i
end

-- Grid move with wraparound; a step landing on the other player's confirmed
-- swatch keeps going in the same direction.
local function moveCursor(pl, who, delta)
  local n = #data.PLAYER_COLORS
  for _ = 1, n do
    pl.i = (pl.i + delta) % n
    if not takenBy(who, pl.i) then break end
  end
  SFX.move()
end

local function launch()
  local colors = { p1 = colorAt(cs.p1.i).id, p2 = cs.p2 and colorAt(cs.p2.i).id or nil }
  local mode = cs.mode
  SFX.fanfare()
  engine.transition(mode == 'captains' and 'TWO CAPTAINS!' or 'SEA 1', function()
    game.newGame(mode, colors)
    engine.setState('sail')
  end)
end

-- One player's cursor: move, confirm (locks the pick), un-confirm on back.
-- Returns true when this player pressed back while nothing was confirmed.
local function drivePick(ctx, who)
  local pl = cs[who]
  if not pl.done then
    if ctx.rp('left') then moveCursor(pl, who, -1) end
    if ctx.rp('right') then moveCursor(pl, who, 1) end
    if ctx.rp('up') or ctx.rp('down') then moveCursor(pl, who, COLS) end
  end
  if ctx.jp('a') then
    if pl.done then
      SFX.bump()
    elseif takenBy(who, pl.i) then
      SFX.bump()
    elseif cs.p2 then
      pl.done = true
      SFX.sel()
      if cs.p1.done and cs.p2.done then launch() end
    else
      launch()
    end
  end
  if ctx.jp('b') then
    if pl.done then
      pl.done = false
      SFX.back()
    else
      return true
    end
  end
  return false
end

function M.start(mode)
  cs = {
    mode = mode,
    p1 = { i = 0, done = false },
    p2 = mode == 'captains' and { i = 4, done = false } or nil,
  }
  input.setCoop(mode == 'captains')
  engine.setState('colorSelect')
end

local function drawPreview(x, label, colorId, col, done)
  local bob = util.round(math.sin(engine.gt * 2.2) * 2)
  sprites.draw(sprites.shipSprite(colorId), x - 26, 46 + bob, false, 2)
  sprites.drawPirate('captain', 'none', x + 10, 50 + bob, false, 2, nil, colorId)
  if label then
    font.drawTextO(label, x + 10, 36, col, 1, 'center')
  end
  if done then
    font.drawTextO('READY!', x + 10, 84, col, 1, 'center')
  end
end

engine.states.colorSelect = {
  update = function(dt)
    if cs.p2 then
      local back1 = drivePick(input.p1, 'p1')
      local back2 = drivePick(input.p2, 'p2')
      if back1 or back2 then
        SFX.back()
        input.setCoop(false)
        engine.setState('modeSelect')
      end
    else
      if input.tap then
        local hit = swatchAt(input.tap.x, input.tap.y)
        if hit then cs.p1.i = hit; SFX.move() end
      end
      if drivePick(input, 'p1') then
        SFX.back()
        engine.setState('modeSelect')
      end
    end
  end,

  draw = function()
    gfx.setColor(CO.sky); gfx.rectangle('fill', 0, 0, VW, VH)
    gfx.setColor(CO.sea); gfx.rectangle('fill', 0, 150, VW, VH - 150)
    font.drawText(cs.p2 and 'PICK YOUR COLORS!' or 'PICK YOUR COLOR!', VW / 2, 12, CO.gold, 2, 'center')

    if cs.p2 then
      drawPreview(VW / 2 - 80, 'P1', colorAt(cs.p1.i).id, CO.gold, cs.p1.done)
      drawPreview(VW / 2 + 60, 'P2', colorAt(cs.p2.i).id, CO.green, cs.p2.done)
    else
      drawPreview(VW / 2 - 10, nil, colorAt(cs.p1.i).id, CO.gold, false)
    end

    for i = 0, #data.PLAYER_COLORS - 1 do
      local c = colorAt(i)
      local x, y = swatchXY(i)
      gfx.setColor(palette.hex(c.sail))
      gfx.rectangle('fill', x, y, SW_W, SW_H)
      gfx.setColor(palette.hex(c.flag))
      gfx.rectangle('fill', x, y + SW_H - 6, SW_W, 6)
      ui.outline(x, y, SW_W, SW_H, CO.ink)
      if cs.p2 and (takenBy('p2', i) or takenBy('p1', i)) then
        local owner = cs.p1.done and cs.p1.i == i and 'p1' or 'p2'
        gfx.setColor(CO.ink[1], CO.ink[2], CO.ink[3], 0.55)
        gfx.rectangle('fill', x, y, SW_W, SW_H)
        font.drawTextO(owner == 'p2' and 'P2' or 'P1', x + SW_W / 2, y + SW_H / 2 - 4,
          owner == 'p2' and CO.green or CO.gold, 1, 'center')
      end
      if i == cs.p1.i then ui.outline(x - 2, y - 2, SW_W + 4, SW_H + 4, CO.gold) end
      if cs.p2 and i == cs.p2.i then ui.outline(x - 4, y - 4, SW_W + 8, SW_H + 8, CO.green) end
    end

    local nameY = GRID_Y + ROWS * SW_H + (ROWS - 1) * SW_GAP + 8
    if cs.p2 then
      font.drawTextO(colorAt(cs.p1.i).name, VW / 2 - 70, nameY, CO.gold, 1, 'center')
      font.drawTextO(colorAt(cs.p2.i).name, VW / 2 + 70, nameY, CO.green, 1, 'center')
      font.drawTextO('P1: WASD + ' .. input.promptKey(input.p1, 'a') .. '   P2: ARROWS + ' .. input.promptKey(input.p2, 'a') .. '   ' .. input.promptKey(input.p1, 'b') .. ' BACK', VW / 2, VH - 10, CO.foam, 1, 'center')
    else
      font.drawTextO(colorAt(cs.p1.i).name, VW / 2, nameY, CO.paper, 1, 'center')
      font.drawTextO('< > PICK - ' .. input.promptKey(input.p1, 'a') .. ' SAIL - ' .. input.promptKey(input.p1, 'b') .. ' BACK', VW / 2, VH - 10, CO.foam, 1, 'center')
    end
  end,
}

return M
