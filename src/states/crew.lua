-- Crew menu: pick the 3-pirate party and swap owned hats.
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

local cm = nil

-- Shared join/leave/hat logic for one player's cursor. `owner` is the
-- player confirming ('p1'/'p2' in captains mode, nil in solo where
-- assignOwner's auto-balance picks instead of the confirming player).
local function driveCursor(ctx, cursorKey, owner)
  local run = game.run
  local n = #run.crew
  if ctx.rp('up') then cm[cursorKey] = (cm[cursorKey] + n - 1) % n; SFX.move() end
  if ctx.rp('down') then cm[cursorKey] = (cm[cursorKey] + 1) % n; SFX.move() end

  local p = run.crew[cm[cursorKey] + 1]
  if ctx.jp('left') or ctx.jp('right') then
    local list = game.ownedOutfitList()
    local idx = 0
    for j = 0, #list - 1 do
      if list[j + 1] == p.out then idx = j end
    end
    idx = (idx + (ctx.jp('left') and #list - 1 or 1)) % #list
    p.out = list[idx + 1]
    SFX.sel()
  end

  if ctx.jp('a') then
    if game.inParty(p) then
      if p.role == 'captain' then
        SFX.bump()
        engine.addFloat(VW / 2, 60, 'THE CAPTAIN MUST SAIL!', CO.red, 1)
      elseif owner and game.ownerOf(p) ~= owner then
        SFX.bump() -- not your pal to dismiss (2+2 captains split)
      elseif #run.party <= 1 then
        SFX.bump()
      else
        for k, q in ipairs(run.party) do
          if q == p then
            table.remove(run.party, k)
            break
          end
        end
        SFX.back()
      end
    elseif game.isNapping(p) then
      SFX.bump()
      engine.addFloat(VW / 2, 60, 'TUCKERED OUT!', CO.red, 1)
    elseif #run.party < game.partyCap() then
      run.party[#run.party + 1] = p
      if owner then run.owners[p.name] = owner
      elseif game.isCoop() then game.assignOwner(p) end
      SFX.sel()
    else
      SFX.bump()
      engine.addFloat(VW / 2, 60, 'PARTY IS FULL! (' .. game.partyCap() .. ')', CO.red, 1)
    end
  end
end

engine.states.crew = {
  enter = function()
    cm = { i = 0, i2 = 0 }
  end,

  update = function(dt)
    local run = game.run
    -- Hidden delight (for the 'napbuddies' secret): two tuckered-out pals
    -- listed back-to-back snore in sync. Purely cosmetic, checked every
    -- frame the crew screen is open; foundSecret no-ops once it's found.
    for i = 1, #run.crew - 1 do
      if game.isNapping(run.crew[i]) and game.isNapping(run.crew[i + 1]) then
        game.foundSecret('napbuddies')
        break
      end
    end
    if run.mode == 'captains' then
      driveCursor(input.p1, 'i', 'p1')
      driveCursor(input.p2, 'i2', 'p2')
    else
      driveCursor(input, 'i', nil)
    end
    if input.jp('b') or input.jp('crew') then
      SFX.back()
      engine.setState('sail')
    end
  end,

  draw = function()
    local run = game.run
    gfx.setColor(CO.uiBg)
    gfx.rectangle('fill', 0, 0, VW, VH)
    font.drawText('YOUR CREW', 8, 6, CO.gold, 2, 'left')
    font.drawText('PARTY ' .. #run.party .. '/' .. game.partyCap(), VW - 8, 8, CO.paper, 1, 'right')

    local top = math.max(0, math.min(cm.i - 5, #run.crew - 9))
    for i = top, math.min(#run.crew, top + 9) - 1 do
      local p = run.crew[i + 1]
      local yy = 24 + (i - top) * 12
      local sel = i == cm.i
      local sel2 = run.mode == 'captains' and i == cm.i2
      if sel or sel2 then
        gfx.setColor(CO.uiBg2)
        gfx.rectangle('fill', 4, yy - 2, 152, 11)
      end
      if sel then ui.outline(4, yy - 2, 152, 11, CO.gold) end
      if sel2 then ui.outline(4, yy - 2, 152, 11, CO.green) end
      font.drawText((sel and '>' or ' ') .. (game.inParty(p) and '*' or ' ') .. ' ' .. p.name,
        8, yy, game.isNapping(p) and CO.gray or (game.inParty(p) and CO.gold or CO.white), 1)
      if game.isNapping(p) then
        font.drawText('ZZZ', 122, yy, CO.foam, 1)
      elseif game.isCoop() and game.inParty(p) then
        font.drawText(game.ownerOf(p) == 'p2' and 'P2' or 'P1', 122, yy,
          game.ownerOf(p) == 'p2' and CO.green or CO.gold, 1)
      end
      font.drawText('LV ' .. p.lvl, 140, yy, CO.gray, 1)
    end

    -- Detail card for the highlighted pirate.
    local cp = run.crew[cm.i + 1]
    local st = game.statsOf(cp)
    local r = data.ROLES[cp.role]
    gfx.setColor(CO.ink)
    gfx.rectangle('fill', 164, 20, 150, 132)
    ui.outline(164, 20, 150, 132, CO.gold)
    sprites.drawPirate(cp.role, cp.out, 178, 30, false, 3, nil, game.palColor(cp))
    font.drawText(cp.name, 236, 30, CO.gold, 1)
    font.drawText(r.label .. ' LV' .. cp.lvl, 236, 40, CO.gray, 1)
    font.drawText('@' .. st.hp .. ' ATK' .. st.atk .. ' MV' .. st.move, 236, 52, CO.white, 1)
    font.drawText('SPECIAL:', 236, 66, CO.paper, 1)
    font.drawText(r.spec.name, 236, 75, CO.gold, 1)
    font.drawText(r.spec.desc, 236, 84, CO.gray, 1)
    font.drawText('AT SEA: ' .. r.ship.name, 236, 98, CO.foam, 1)
    font.drawText('HAT:', 178, 86, CO.paper, 1)
    font.drawText('< ' .. data.outfitById(cp.out).name .. ' >', 178, 96, CO.white, 1)
    local k1a, k1b = input.promptKey(input.p1, 'a'), input.promptKey(input.p1, 'b')
    if game.isNapping(cp) then
      font.drawText('ZZZ TUCKERED OUT!', 178, 128, CO.foam, 1)
    else
      font.drawText(k1a .. (game.inParty(cp) and ': LEAVE PARTY' or ': JOIN PARTY'), 178, 128, CO.gold, 1)
    end
    engine.drawFx()
    gfx.setColor(CO.ink)
    gfx.rectangle('fill', 0, VH - 14, VW, 14)
    local hint = run.mode == 'captains'
      and ('P1: ' .. k1a .. ' PARTY < > HAT   P2: ' .. input.promptKey(input.p2, 'a') .. ' PARTY < > HAT   ' .. k1b .. ' BACK')
      or (k1a .. ' PARTY  < > HAT  ' .. k1b .. ' BACK')
    font.drawText(hint, VW / 2, VH - 10, CO.gray, 1, 'center')
  end,
}

return {}
