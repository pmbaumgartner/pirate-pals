-- Voyage chart: a read-only view of progress (V key from sail) or the
-- screen shown after riding a whirlpool, animating the ship token hopping
-- to the next island before the next sea is generated. Sea `voyage.length`
-- (8) is the Pirate King's dot — the voyage ends there, not beyond it.
local util = require 'src.util'
local palette = require 'src.palette'
local font = require 'src.font'
local sprites = require 'src.sprites'
local input = require 'src.input'
local audio = require 'src.audio'
local engine = require 'src.engine'
local game = require 'src.game'
local data = require 'src.data'
local CO = palette.CO
local gfx = love.graphics
local SFX = audio.sfx

local VW, VH = 320, 180

local M = {}
local ch = nil

local function dotXY(i, n)
  local x0, x1 = 34, VW - 34
  local x = n > 1 and (x0 + (x1 - x0) * (i - 1) / (n - 1)) or (x0 + x1) / 2
  local y = 92 + math.sin((i - 1) * 0.9) * 24
  return x, y
end

-- Read-only: opened from sail via the V hotkey. B returns without changing
-- anything.
function M.startView()
  local v = game.run.voyage
  ch = { advancing = false, animT = 1, fromSea = v.sea, toSea = v.sea, length = v.length }
  engine.setState('chart')
end

-- Shown after riding a whirlpool: animates the hop, then Z continues into
-- the next sea. The next sea's biome is pre-rolled here (stashed in
-- run.nextBiome for genSea to consume) so its twist can be announced on the
-- chart before the sea exists.
function M.startAdvance()
  local v = game.run.voyage
  local toSea = math.min(v.sea + 1, v.length)
  local biome = game.rollBiome(toSea)
  game.run.nextBiome = { sea = toSea, biome = biome }
  ch = { advancing = true, animT = 0, fromSea = v.sea, toSea = toSea, length = v.length, biome = biome }
  engine.setState('chart')
end

engine.states.chart = {
  update = function(dt)
    if ch.advancing and ch.animT < 1 then
      ch.animT = math.min(1, ch.animT + dt / 1.1)
      if ch.animT >= 1 then
        game.run.voyage.sea = ch.toSea
        SFX.sel()
      end
      return
    end
    if ch.advancing then
      if input.jp('a') then
        local toSea = ch.toSea
        SFX.sel()
        engine.transition('SEA ' .. toSea .. '!', function()
          game.genSea(toSea)
          engine.setState('sail')
        end)
      end
    else
      if input.jp('a') or input.jp('b') then
        SFX.sel()
        engine.setState('sail')
      end
    end
  end,

  draw = function()
    gfx.setColor(CO.night)
    gfx.rectangle('fill', 0, 0, VW, VH)
    font.drawText('THE VOYAGE', VW / 2, 12, CO.gold, 2, 'center')

    local n = ch.length
    local reached = math.max(ch.fromSea, ch.toSea)
    for i = 1, n do
      local x, y = dotXY(i, n)
      if i == n then
        sprites.draw('kingSil', x - 8, y - 20, false, 1)
        font.drawTextO('THE PIRATE KING', x, y - 28, CO.purple, 1, 'center')
      else
        gfx.setColor(i <= reached and CO.gold or CO.grayD)
        gfx.circle('fill', x, y, 4)
      end
      font.drawTextO('' .. i, x, y + 7, CO.paper, 1, 'center')
    end

    local t = util.ease(ch.animT)
    local fx, fy = dotXY(ch.fromSea, n)
    local tx, ty = dotXY(ch.toSea, n)
    local sx = util.lerp(fx, tx, t)
    local sy = util.lerp(fy, ty, t) - 14
    sprites.draw(sprites.shipSprite(game.colorOf('p1')), sx - 8, sy - 8, false, 1)
    -- TWO CAPTAINS (C5): both ship tokens hop the island path together.
    if game.run.mode == 'captains' then
      sprites.draw(sprites.shipSprite(game.colorOf('p2')), sx - 18, sy - 4, false, 1)
    end

    if ch.advancing and ch.animT >= 1 then
      if ch.biome and ch.biome ~= 'calm' then
        local b = data.BIOMES[ch.biome]
        sprites.draw(b.icon, VW / 2 - 66, VH - 38)
        font.drawTextO(b.name .. ' - ' .. b.twist, VW / 2 + 8, VH - 34, CO.foam, 1, 'center')
      end
      font.drawTextO('SET SAIL FOR SEA ' .. ch.toSea .. '! (Z)', VW / 2, VH - 20, CO.gold, 1, 'center')
    elseif not ch.advancing then
      font.drawTextO('SEA ' .. ch.fromSea .. ' OF ' .. n, VW / 2, VH - 26, CO.paper, 1, 'center')
      font.drawTextO('X BACK TO SAILING', VW / 2, VH - 14, CO.gray, 1, 'center')
    end
  end,
}

return M
