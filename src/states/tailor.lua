-- Tailor shop at the dock: buy hats with gold (milestone hats can't be
-- bought here; they unlock from the treasure log), pick up benched pals,
-- and re-pick crew colors for free on the SAILS tab (the tailor sews sails).
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

local tl = nil

local TABS = { 'shop', 'bench', 'sails' }
local TAB_LABEL = { shop = 'SHOP', bench = 'WAITING AT THE PORT', sails = 'SAILS' }

local function shopItems()
  local items = {}
  for i = 2, #data.OUTFITS do
    items[#items + 1] = data.OUTFITS[i]
  end
  return items
end

-- SAILS tab: one player's cursor + free color re-pick. In captains mode the
-- other captain's current color is taken; solo has nobody to collide with.
local function driveSailsCursor(ctx, cursorKey, who)
  local n = #data.PLAYER_COLORS
  if ctx.rp('up') then tl[cursorKey] = (tl[cursorKey] + n - 1) % n; SFX.move() end
  if ctx.rp('down') then tl[cursorKey] = (tl[cursorKey] + 1) % n; SFX.move() end
  if ctx.jp('a') then
    local id = data.PLAYER_COLORS[tl[cursorKey] + 1].id
    local other = who == 'p1' and 'p2' or 'p1'
    if game.isCoop() and game.colorOf(other) == id then
      SFX.bump()
      engine.addFloat(240, 60, 'TAKEN!', CO.red, 1)
    elseif game.colorOf(who) == id then
      SFX.bump()
    else
      game.run.colors[who] = id
      SFX.buy()
      engine.addParts(240, 70, 14, CO.gold, 45)
      engine.addFloat(240, 56, 'NEW SAILS!', CO.gold, 2)
    end
  end
end

local function driveSails()
  if game.isCoop() then
    driveSailsCursor(input.p1, 'i', 'p1')
    driveSailsCursor(input.p2, 'i2', 'p2')
  else
    driveSailsCursor(input, 'i', 'p1')
  end
end

engine.states.tailor = {
  enter = function()
    tl = { i = 0, i2 = 0, tab = 'shop' }
  end,

  update = function(dt)
    local run = game.run
    if input.jp('left') or input.jp('right') then
      local idx = 1
      for k, t in ipairs(TABS) do
        if t == tl.tab then idx = k end
      end
      tl.tab = TABS[(idx - 1 + (input.jp('left') and -1 or 1)) % #TABS + 1]
      tl.i, tl.i2 = 0, 0
      SFX.sel()
      return
    end
    if tl.tab == 'sails' then
      driveSails()
      if input.jp('b') then
        SFX.back()
        engine.setState('sail')
      end
      return
    end
    if tl.tab == 'bench' then
      local n = #run.bench
      if n == 0 then
        if input.jp('b') then SFX.back(); engine.setState('sail') end
        return
      end
      if input.rp('up') then tl.i = (tl.i + n - 1) % n; SFX.move() end
      if input.rp('down') then tl.i = (tl.i + 1) % n; SFX.move() end
      if input.jp('a') then
        if #run.crew < 10 then
          local p = table.remove(run.bench, tl.i + 1)
          run.crew[#run.crew + 1] = p
          SFX.fanfare()
          engine.addFloat(240, 60, p.name .. ' JOINED!', CO.gold, 1)
          tl.i = math.max(0, math.min(tl.i, #run.bench - 1))
        else
          SFX.bump()
          engine.addFloat(240, 60, 'CREW IS FULL!', CO.red, 1)
        end
      end
      if input.jp('b') then
        SFX.back()
        engine.setState('sail')
      end
      return
    end

    local items = shopItems()
    local n = #items
    if input.rp('up') then tl.i = (tl.i + n - 1) % n; SFX.move() end
    if input.rp('down') then tl.i = (tl.i + 1) % n; SFX.move() end
    if input.jp('a') then
      local it = items[tl.i + 1]
      if run.owned[it.id] then
        SFX.bump()
        engine.addFloat(240, 60, 'OWNED!', CO.gray, 1)
      elseif it.price and run.gold >= it.price then
        run.gold = run.gold - it.price
        game.unlockHat(it.id)
        SFX.buy()
        engine.addParts(240, 70, 14, CO.gold, 45)
        engine.addFloat(240, 56, 'GOT IT!', CO.gold, 2)
      elseif it.price then
        SFX.bump()
        engine.addFloat(240, 60, 'NEED MORE GOLD!', CO.red, 1)
      else
        SFX.bump()
        engine.addFloat(240, 60, 'FIND ' .. it.mile .. ' TREASURES!', CO.purple, 1)
      end
    end
    if input.jp('b') then
      SFX.back()
      engine.setState('sail')
    end
  end,

  draw = function()
    local run = game.run
    gfx.setColor(CO.woodD)
    gfx.rectangle('fill', 0, 0, VW, VH)
    gfx.setColor(CO.wood)
    gfx.rectangle('fill', 4, 4, VW - 8, VH - 8)
    gfx.setColor(CO.woodD)
    for yy = 4, VH - 9, 14 do
      gfx.rectangle('fill', 4, yy, VW - 8, 1)
    end
    font.drawTextO('SNIPS THE TAILOR', 10, 8, CO.paper, 2)
    sprites.draw('coinS', VW - 60, 9)
    font.drawTextO('' .. run.gold, VW - 50, 9, CO.gold, 1)
    font.drawText('< ' .. TAB_LABEL[tl.tab] .. ' >', VW / 2, 20, CO.foam, 1, 'center')

    if tl.tab == 'sails' then
      local coop = game.isCoop()
      for i = 0, #data.PLAYER_COLORS - 1 do
        local c = data.PLAYER_COLORS[i + 1]
        local y2 = 30 + i * 13
        local sel = i == tl.i
        local sel2 = coop and i == tl.i2
        if sel or sel2 then
          gfx.setColor(CO.uiBg)
          gfx.rectangle('fill', 8, y2 - 2, 168, 12)
        end
        if sel then ui.outline(8, y2 - 2, 168, 12, CO.gold) end
        if sel2 then ui.outline(8, y2 - 2, 168, 12, CO.green) end
        gfx.setColor(palette.hex(c.sail))
        gfx.rectangle('fill', 12, y2, 8, 8)
        font.drawText((sel and '>' or ' ') .. c.name, 24, y2, sel and CO.gold or CO.white, 1)
        local tag = (game.colorOf('p1') == c.id and 'P1 SAILS')
          or (coop and game.colorOf('p2') == c.id and 'P2 SAILS') or 'FREE'
        local tagCol = tag == 'P1 SAILS' and CO.gold
          or (tag == 'P2 SAILS' and CO.green) or CO.gray
        font.drawText(tag, 172, y2, tagCol, 1, 'right')
      end

      -- Preview pane: ship + captain in the hovered color, per player.
      gfx.setColor(CO.uiBg)
      gfx.rectangle('fill', 190, 28, 118, 116)
      ui.outline(190, 28, 118, 116, CO.gold)
      font.drawText('FRESH SAILS!', 249, 34, CO.paper, 1, 'center')
      if coop then
        for pi, who in ipairs({ 'p1', 'p2' }) do
          local hover = data.PLAYER_COLORS[(pi == 1 and tl.i or tl.i2) + 1]
          local py = 46 + (pi - 1) * 48
          font.drawText(pi == 1 and 'P1' or 'P2', 200, py + 8,
            pi == 1 and CO.gold or CO.green, 1)
          sprites.draw(sprites.shipSprite(hover.id), 216, py, false, 1.5)
          sprites.drawPirate('captain', 'none', 248, py + 4, false, 1.5, nil, hover.id)
          font.drawText(hover.name, 276, py + 8, CO.white, 1)
        end
      else
        local hover = data.PLAYER_COLORS[tl.i + 1]
        sprites.draw(sprites.shipSprite(hover.id), 212, 48, false, 2)
        sprites.drawPirate('captain', 'none', 252, 52, false, 2, nil, hover.id)
        font.drawText(hover.name, 249, 104, CO.white, 1, 'center')
        if game.colorOf('p1') ~= hover.id then
          font.drawText('Z: HOIST!', 249, 118, CO.gold, 1, 'center')
        end
      end
      engine.drawFx()
      gfx.setColor(CO.ink)
      gfx.rectangle('fill', 0, VH - 14, VW, 14)
      font.drawText(coop and '< > SHOP  P1 Z / P2 N: HOIST  X LEAVE' or '< > SHOP  Z HOIST  X LEAVE',
        VW / 2, VH - 10, CO.gray, 1, 'center')
      return
    end

    if tl.tab == 'bench' then
      if #run.bench == 0 then
        font.drawText('NOBODY WAITING YET!', VW / 2, 90, CO.gray, 1, 'center')
      else
        for i = 0, #run.bench - 1 do
          local p = run.bench[i + 1]
          local y2 = 30 + i * 13
          local sel = i == tl.i
          if sel then
            gfx.setColor(CO.uiBg)
            gfx.rectangle('fill', 8, y2 - 2, 168, 12)
          end
          font.drawText((sel and '>' or ' ') .. p.name, 12, y2, sel and CO.gold or CO.white, 1)
          font.drawText(data.ROLES[p.role].label .. ' LV' .. p.lvl, 172, y2, CO.gray, 1, 'right')
        end
      end
      gfx.setColor(CO.ink)
      gfx.rectangle('fill', 0, VH - 14, VW, 14)
      font.drawText('< > SHOP  Z PICK UP  X LEAVE', VW / 2, VH - 10, CO.gray, 1, 'center')
      engine.drawFx()
      return
    end

    local items = shopItems()
    for i = 0, #items - 1 do
      local it = items[i + 1]
      local y2 = 30 + i * 13
      local sel = i == tl.i
      if sel then
        gfx.setColor(CO.uiBg)
        gfx.rectangle('fill', 8, y2 - 2, 168, 12)
      end
      local col = run.owned[it.id] and CO.gray or CO.white
      font.drawText((sel and '>' or ' ') .. it.name, 12, y2, sel and CO.gold or col, 1)
      local tag = run.owned[it.id] and 'OWNED' or (it.price and (it.price .. 'G') or (it.mile .. ' GEMS'))
      local canAfford = it.price and run.gold >= it.price
      local tagCol = run.owned[it.id] and CO.gray
        or (it.price and (canAfford and CO.gold or CO.red) or CO.purple)
      font.drawText(tag, 172, y2, tagCol, 1, 'right')
    end

    -- Try-on preview.
    gfx.setColor(CO.uiBg)
    gfx.rectangle('fill', 190, 28, 118, 116)
    ui.outline(190, 28, 118, 116, CO.gold)
    font.drawText('TRY IT ON!', 249, 34, CO.paper, 1, 'center')
    local it = items[tl.i + 1]
    sprites.drawPirate('captain', it.id, 225, 48, false, 3)
    font.drawText(it.name, 249, 104, CO.white, 1, 'center')
    if not run.owned[it.id] and it.price then
      font.drawText('Z: BUY', 249, 118, CO.gold, 1, 'center')
    end
    engine.drawFx()
    gfx.setColor(CO.ink)
    gfx.rectangle('fill', 0, VH - 14, VW, 14)
    font.drawText('< > BENCH  Z BUY  X LEAVE', VW / 2, VH - 10, CO.gray, 1, 'center')
  end,
}

return {}
