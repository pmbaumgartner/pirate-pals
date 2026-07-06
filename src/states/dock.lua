local palette = require 'src.palette'
local font = require 'src.font'
local sprites = require 'src.sprites'
local input = require 'src.input'
local audio = require 'src.audio'
local engine = require 'src.engine'
local game = require 'src.game'
local ui = require 'src.ui'
local CO = palette.CO
local gfx = love.graphics
local SFX = audio.sfx

local VW, VH = 320, 180

local M = {}
local dk = nil

local OPTIONS = { 'TAILOR', 'DRY DOCK', 'BACK TO SEA' }

engine.states.dock = {
  enter = function()
    dk = { i = 0 }
  end,

  update = function(dt)
    local n = #OPTIONS
    if input.rp('up') then dk.i = (dk.i + n - 1) % n; SFX.move() end
    if input.rp('down') then dk.i = (dk.i + 1) % n; SFX.move() end
    if input.jp('a') then
      if dk.i == 0 then
        SFX.sel()
        engine.setState('tailor')
      elseif dk.i == 1 then
        SFX.sel()
        engine.setState('drydock')
      elseif dk.i == 2 then
        SFX.back()
        engine.setState('sail')
      end
    end
    if input.jp('b') then
      SFX.back()
      engine.setState('sail')
    end
  end,

  draw = function()
    gfx.setColor(CO.woodD)
    gfx.rectangle('fill', 0, 0, VW, VH)
    gfx.setColor(CO.wood)
    gfx.rectangle('fill', 4, 4, VW - 8, VH - 8)

    font.drawTextO('PORT DOCK', VW / 2, 20, CO.gold, 2, 'center')

    for i, opt in ipairs(OPTIONS) do
      local sel = dk.i == i - 1
      local y = 60 + (i - 1) * 24
      if sel then
        gfx.setColor(CO.uiBg)
        gfx.rectangle('fill', 40, y - 2, VW - 80, 20)
        ui.outline(40, y - 2, VW - 80, 20, CO.gold)
      end
      font.drawText((sel and '> ' or '  ') .. opt, VW / 2, y + 2, sel and CO.gold or CO.white, 1, 'center')
    end

    -- Draw resources summary at the bottom
    local rx = 20
    local ry = 145
    gfx.setColor(CO.uiBg)
    gfx.rectangle('fill', rx, ry, VW - 2 * rx, 25)
    ui.outline(rx, ry, VW - 2 * rx, 25, CO.gold)

    -- Draw gold
    sprites.draw('coinS', rx + 10, ry + 9)
    font.drawTextO('' .. game.run.gold, rx + 20, ry + 10, CO.gold, 1)

    -- Draw salvage
    sprites.draw('sal_timber', rx + 75, ry + 5)
    font.drawTextO('' .. game.run.salvage.timber, rx + 90, ry + 10, CO.white, 1)

    sprites.draw('sal_cloth', rx + 145, ry + 5)
    font.drawTextO('' .. game.run.salvage.cloth, rx + 160, ry + 10, CO.white, 1)

    sprites.draw('sal_iron', rx + 215, ry + 5)
    font.drawTextO('' .. game.run.salvage.iron, rx + 230, ry + 10, CO.white, 1)
  end
}

return M
