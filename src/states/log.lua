-- Treasure log: the 12-slot collection checklist plus milestone rewards, with
-- sibling SECRETS and DEEDS tabs reusing the same slot-grid idiom.
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

local TABS = { 'treasure', 'secrets', 'deeds' }

local function slotCount()
  if lg.tab == 'treasure' then return 12 end
  if lg.tab == 'secrets' then return #data.SECRETS end
  return #data.DEEDS
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
      for i, t in ipairs(TABS) do
        if t == lg.tab then lg.tab = TABS[i % #TABS + 1]; break end
      end
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
    elseif lg.tab == 'secrets' then
      -- 18 entries, same over-12 pagination idiom as DEEDS below: the page
      -- follows lg.i in blocks of 12 (6x2), no separate page-cursor state.
      local list = data.SECRETS
      local page = math.floor(lg.i / 12)
      local pageStart = page * 12
      local pageEnd = math.min(pageStart + 11, #list - 1)
      font.drawText('SECRETS', 8, 6, CO.gold, 2)
      font.drawText(game.distinctSecrets() .. '/' .. #list .. ' FOUND', VW - 8, 8, CO.purple, 1, 'right')

      for i = pageStart, pageEnd do
        local within = i - pageStart
        local col, row = within % 6, math.floor(within / 6)
        local x, y = 30 + col * 45, 26 + row * 42
        local sd = list[i + 1]
        local got = meta.data.secrets[sd.id]
        gfx.setColor(CO.ink)
        gfx.rectangle('fill', x, y, 32, 32)
        if i == lg.i then ui.outline(x, y, 32, 32, CO.gold) end
        if got and sd.slot then
          -- Curios shelf: "find a thing" secrets draw their trinket
          -- sprite (a 16x6 hat strip) instead of the generic checkmark,
          -- scaled up and centered in the 32x32 slot.
          sprites.draw(sd.slot, x, y + 10, false, 2)
        elseif got then
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
    else
      -- DEEDS: 18 entries, more than the 12-per-screen grid fits, so this
      -- tab pages in blocks of 12 (6x2) -- the page just follows lg.i, no
      -- separate page-cursor state to keep in sync.
      local list = data.DEEDS
      local page = math.floor(lg.i / 12)
      local pageStart = page * 12
      local pageEnd = math.min(pageStart + 11, #list - 1)
      font.drawText('DEEDS', 8, 6, CO.gold, 2)
      font.drawText(game.distinctDeeds() .. '/' .. #list .. ' DONE', VW - 8, 8, CO.purple, 1, 'right')

      for i = pageStart, pageEnd do
        local within = i - pageStart
        local col, row = within % 6, math.floor(within / 6)
        local x, y = 30 + col * 45, 26 + row * 42
        local dd = list[i + 1]
        local got = meta.data.deeds[dd.id]
        gfx.setColor(CO.ink)
        gfx.rectangle('fill', x, y, 32, 32)
        if i == lg.i then ui.outline(x, y, 32, 32, CO.gold) end
        if got then
          sprites.draw('secretCheck', x + 8, y + 8, false, 1)
        else
          font.drawText('#', x + 16, y + 12, CO.grayD, 2, 'center')
        end
      end

      local hov = list[lg.i + 1]
      if hov then
        local got = meta.data.deeds[hov.id]
        local cur, goal = game.deedProgress(hov)
        local caption = hov.name .. ' - ' .. hov.goalText
        if cur ~= nil then caption = caption .. ' - ' .. cur .. '/' .. goal end
        font.drawText(caption, VW / 2, 114, got and CO.gold or CO.white, 1, 'center')
      end
    end

    gfx.setColor(CO.ink)
    gfx.rectangle('fill', 0, VH - 14, VW, 14)
    local nextTab = TABS[({ treasure = 2, secrets = 3, deeds = 1 })[lg.tab]]
    font.drawText(input.promptKey(input.p1, 'b') .. ' BACK   ' .. input.promptKey(input.p1, 'crew') .. ': ' .. nextTab:upper(),
      VW / 2, VH - 10, CO.gray, 1, 'center')
  end,
}

return {}
