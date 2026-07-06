-- Home Port hub: reached from the victory screen (and from the title
-- once a voyage has been won). Spend gold banked from finished voyages on
-- permanent ship upgrades, or set out on a New Voyage+.
local palette = require 'src.palette'
local font = require 'src.font'
local sprites = require 'src.sprites'
local input = require 'src.input'
local audio = require 'src.audio'
local engine = require 'src.engine'
local game = require 'src.game'
local meta = require 'src.meta'
local CO = palette.CO
local gfx = love.graphics
local SFX = audio.sfx

local VW, VH = 320, 180

local M = {}
local pt = nil

local UPGRADE_KEYS = { 'figurehead', 'sails', 'cook', 'steady' }
local ROW_H = 24

engine.states.port = {
  enter = function()
    pt = { i = 0 }
  end,

  update = function(dt)
    local m = meta.data
    local n = #UPGRADE_KEYS + 1 -- + NEW VOYAGE row
    if input.rp('up') then pt.i = (pt.i + n - 1) % n; SFX.move() end
    if input.rp('down') then pt.i = (pt.i + 1) % n; SFX.move() end
    if input.jp('a') then
      if pt.i == n - 1 then
        SFX.fanfare()
        engine.transition('NEW VOYAGE!', function()
          game.newGamePlus()
          engine.setState('sail')
        end)
        return
      end
      local key = UPGRADE_KEYS[pt.i + 1]
      local def = meta.UPGRADES[key]
      local tier = m.upgrades[key] or 0
      local cost = def.costs[tier + 1]
      local rowY = 40 + pt.i * ROW_H
      if not cost then
        SFX.bump()
        engine.addFloat(VW - 12, rowY - 8, 'MAXED OUT!', CO.gray, 1)
      elseif m.gold >= cost then
        m.gold = m.gold - cost
        m.upgrades[key] = tier + 1
        meta.save()
        SFX.buy()
        engine.addParts(VW - 50, 9, 14, CO.gold, 45)
        engine.addFloat(VW - 12, rowY - 8, 'UPGRADED!', CO.gold, 1)
      else
        SFX.bump()
        engine.addFloat(VW - 12, rowY - 8, 'NEED MORE GOLD!', CO.red, 1)
      end
    end
    if input.jp('b') then
      SFX.back()
      engine.setState('title')
    end
  end,

  draw = function()
    local m = meta.data
    gfx.setColor(CO.woodD)
    gfx.rectangle('fill', 0, 0, VW, VH)
    gfx.setColor(CO.wood)
    gfx.rectangle('fill', 4, 4, VW - 8, VH - 8)
    font.drawTextO('HOME PORT', 10, 8, CO.paper, 2)
    sprites.draw('coinS', VW - 60, 8)
    font.drawTextO('' .. m.gold, VW - 50, 9, CO.gold, 1)
    font.drawText('VOYAGES WON: ' .. m.voyagesWon, VW / 2, 22, CO.foam, 1, 'center')

    for i, key in ipairs(UPGRADE_KEYS) do
      local def = meta.UPGRADES[key]
      local tier = m.upgrades[key] or 0
      local y = 40 + (i - 1) * ROW_H
      local sel = pt.i == i - 1
      if sel then
        gfx.setColor(CO.uiBg)
        gfx.rectangle('fill', 8, y - 2, VW - 16, ROW_H - 2)
      end
      font.drawText((sel and '>' or ' ') .. def.name, 12, y, sel and CO.gold or CO.white, 1)
      font.drawTextO(def.desc, 16, y + 11, CO.gray, 1)
      local pips = ''
      for t = 1, def.max do pips = pips .. (t <= tier and '*' or '.') end
      font.drawText(pips, VW - 96, y, CO.gold, 1, 'right')
      local cost = def.costs[tier + 1]
      font.drawTextO(cost and (cost .. 'G') or 'MAX', VW - 12, y, cost and CO.gold or CO.gray, 1, 'right')
    end

    local nvY = 40 + #UPGRADE_KEYS * ROW_H + 6
    local selNv = pt.i == #UPGRADE_KEYS
    if selNv then
      gfx.setColor(CO.uiBg)
      gfx.rectangle('fill', 8, nvY - 2, VW - 16, 14)
    end
    font.drawText((selNv and '>' or ' ') .. 'NEW VOYAGE',
      12, nvY, selNv and CO.gold or CO.white, 1)
    if m.golden then
      font.drawText('GOLDEN COMPASS! SEA 9 AWAITS...', VW - 12, nvY, CO.purple, 1, 'right')
    end

    engine.drawFx()
    gfx.setColor(CO.ink)
    gfx.rectangle('fill', 0, VH - 14, VW, 14)
    font.drawText('UP DOWN SELECT  ' .. input.promptKey(input.p1, 'a') .. ' CONFIRM  '
      .. input.promptKey(input.p1, 'b') .. ' BACK', VW / 2, VH - 10, CO.gray, 1, 'center')
  end,
}

return M
