-- Treasure log: the 12-slot collection checklist plus milestone rewards, and
-- a sibling SECRETS tab reusing the same slot-grid idiom.
local palette = require 'src.palette'
local font = require 'src.font'
local sprites = require 'src.sprites'
local input = require 'src.input'
local audio = require 'src.audio'
local engine = require 'src.engine'
local game = require 'src.game'
local data = require 'src.data'
local meta = require 'src.meta'
local ui = require 'src.ui'
local CO = palette.CO
local gfx = love.graphics
local SFX = audio.sfx

local VW, VH = 320, 180

local lg = nil

local function slotCount()
  return lg.tab == 'treasure' and 12 or #data.SECRETS
end

engine.states.log = {
  enter = function()
    lg = { i = 0, tab = 'treasure' }
  end,

  update = function(dt)
    local n = slotCount()
    if input.rp('left') then lg.i = (lg.i + n - 1) % n; SFX.move() end
    if input.rp('right') then lg.i = (lg.i + 1) % n; SFX.move() end
    if input.rp('up') or input.rp('down') then lg.i = (lg.i + 6) % n; SFX.move() end
    if input.jp('crew') then
      lg.tab = lg.tab == 'treasure' and 'secrets' or 'treasure'
      lg.i = 0
      SFX.sel()
    end
    if input.jp('b') or input.jp('log') or input.jp('a') then
      SFX.back()
      engine.setState('sail')
    end
  end,

  draw = function()
    local run = game.run
    gfx.setColor(CO.uiBg)
    gfx.rectangle('fill', 0, 0, VW, VH)

    if lg.tab == 'treasure' then
      font.drawText('TREASURE LOG', 8, 6, CO.gold, 2)
      font.drawText(game.distinctTreasures() .. '/12 KINDS', VW - 8, 8, CO.purple, 1, 'right')

      for i = 0, 11 do
        local col, row = i % 6, math.floor(i / 6)
        local x, y = 30 + col * 45, 26 + row * 42
        local td = data.TREASURES[i + 1]
        local cnt = run.treas[td.id] or 0
        gfx.setColor(CO.ink)
        gfx.rectangle('fill', x, y, 32, 32)
        if i == lg.i then ui.outline(x, y, 32, 32, CO.gold) end
        if cnt > 0 then
          sprites.draw('tr_' .. td.id, x + 4, y + 4, false, 2)
          font.drawText('x' .. cnt, x + 30, y + 25, CO.gold, 1, 'right')
        else
          font.drawText('?', x + 16, y + 12, CO.grayD, 2, 'center')
        end
      end

      local hov = data.TREASURES[lg.i + 1]
      local hc = run.treas[hov.id] or 0
      font.drawText(hc > 0 and hov.name or '? ? ?', VW / 2, 114, hc > 0 and CO.white or CO.grayD, 1, 'center')

      for m = 0, #data.MILESTONES - 1 do
        local ms = data.MILESTONES[m + 1]
        local got = run.owned[ms.id]
        font.drawText(ms.n .. ' KINDS: ' .. data.outfitById(ms.id).name .. (got and ' - GOT IT!' or ''),
          VW / 2, 130 + m * 11, got and CO.gold or CO.gray, 1, 'center')
      end
    else
      local list = data.SECRETS
      font.drawText('SECRETS', 8, 6, CO.gold, 2)
      font.drawText(game.distinctSecrets() .. '/' .. #list .. ' FOUND', VW - 8, 8, CO.purple, 1, 'right')

      for i = 0, #list - 1 do
        local col, row = i % 6, math.floor(i / 6)
        local x, y = 30 + col * 45, 26 + row * 42
        local sd = list[i + 1]
        local got = meta.data.secrets[sd.id]
        gfx.setColor(CO.ink)
        gfx.rectangle('fill', x, y, 32, 32)
        if i == lg.i then ui.outline(x, y, 32, 32, CO.gold) end
        if got then
          sprites.draw('secretCheck', x + 8, y + 8, false, 1)
        else
          font.drawText('?', x + 16, y + 12, CO.grayD, 2, 'center')
        end
      end

      local hov = list[lg.i + 1]
      if hov then
        local got = meta.data.secrets[hov.id]
        font.drawText(got and hov.name or (hov.hint or '? ? ?'), VW / 2, 114,
          got and CO.white or CO.grayD, 1, 'center')
      end
    end

    gfx.setColor(CO.ink)
    gfx.rectangle('fill', 0, VH - 14, VW, 14)
    font.drawText('X BACK   C: ' .. (lg.tab == 'treasure' and 'SECRETS' or 'TREASURE'),
      VW / 2, VH - 10, CO.gray, 1, 'center')
  end,
}

return {}
