-- Voyage Log: the game remembers what happened, never what went
-- wrong -- triumphs and firsts only, appended to run.log by game.logMoment.
-- Event-driven, unlike log.lua's stat-driven treasure checklist, so it gets
-- its own state. Entered from the sail HUD (L) or the victory screen; exits
-- back to wherever it was opened from.
local palette = require 'src.palette'
local font = require 'src.font'
local sprites = require 'src.sprites'
local input = require 'src.input'
local audio = require 'src.audio'
local engine = require 'src.engine'
local game = require 'src.game'
local CO = palette.CO
local gfx = love.graphics
local SFX = audio.sfx

local VW, VH = 320, 180
local ROWS, ROW_H, TOP = 7, 19, 24

local vl = nil

engine.states.voyagelog = {
  enter = function(from)
    vl = { top = 0, from = from or 'sail' }
  end,

  update = function(dt)
    local n = #game.run.log
    local maxTop = math.max(0, n - ROWS)
    if input.rp('down') then vl.top = math.min(maxTop, vl.top + 1); SFX.move() end
    if input.rp('up') then vl.top = math.max(0, vl.top - 1); SFX.move() end
    if input.jp('b') or input.jp('vlog') or input.jp('a') then
      SFX.back()
      engine.setState(vl.from)
    end
  end,

  draw = function()
    local run = game.run
    gfx.setColor(CO.uiBg)
    gfx.rectangle('fill', 0, 0, VW, VH)
    font.drawText('VOYAGE LOG', 8, 6, CO.gold, 2)
    font.drawText(#run.log .. ' MOMENTS', VW - 8, 8, CO.purple, 1, 'right')

    local n = #run.log
    if n == 0 then
      font.drawText('NO MOMENTS YET -- SET SAIL!', VW / 2, VH / 2, CO.gray, 1, 'center')
    end
    for row = 0, ROWS - 1 do
      local idx = n - vl.top - row -- newest-first
      local e = run.log[idx]
      if e then
        local y = TOP + row * ROW_H
        sprites.draw(e.icon, 10, y, false, 1)
        font.drawText(e.text, 30, y + 4, CO.white, 1)
      end
    end

    if vl.top > 0 then font.drawTextO('^ MORE', VW - 8, TOP - 10, CO.gray, 1, 'right') end
    if n - vl.top > ROWS then font.drawTextO('v MORE', VW - 8, TOP + ROWS * ROW_H, CO.gray, 1, 'right') end

    gfx.setColor(CO.ink)
    gfx.rectangle('fill', 0, VH - 14, VW, 14)
    font.drawText('UP/DOWN SCROLL   ' .. input.promptKey(input.p1, 'b') .. ' BACK', VW / 2, VH - 10, CO.gray, 1, 'center')
  end,
}

return {}
