-- Loot reveal: rewards shown one card at a time. Recruit cards welcome the
-- pal aboard on advance; perk/trade cards are the interactive ones.
local util = require 'src.util'
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

local VW = 320

local M = {}
local loot = nil

local function partSfx(part)
  if not part then return end
  if part.type == 'gold' or part.type == 'treasure' or part.type == 'trade' or part.type == 'salvage' then SFX.coin()
  elseif part.type == 'level' or part.type == 'perk' then SFX.level()
  elseif part.type == 'unlock' or part.type == 'recruit' or part.type == 'bond'
    or part.type == 'bottle' or part.type == 'blueprint_choice' or part.type == 'blueprint_single' then SFX.fanfare()
  elseif part.type == 'clear' then SFX.bigwin() end
end

-- Interactive cards about a specific pal take that pal's owner's input
-- (C5): your pal's perk, your pick. Everything else stays advanceable by
-- either player via the input shim.
local function cardCtx(pirate)
  if not game.isCoop() then return input end
  return game.ownerOf(pirate) == 'p2' and input.p2 or input.p1
end

local function ownerTag(owner)
  return owner == 'p2' and 'P2' or 'P1'
end

-- The captain who receives a recruit (captains mode shows their face on
-- the card); nil when the recruit would sit out of the party anyway.
local function receivingCaptain(owner)
  for _, p in ipairs(game.run.party) do
    if p.role == 'captain' and game.ownerOf(p) == owner then return p end
  end
  return nil
end

-- Two-column option picker shared by the perk and trade cards: columns at
-- VW/2 +-42, selection outline, sprite, then centered name/desc. `card`
-- returns the per-option looks (outline/name/desc colors, sprite, and the
-- sprite's half-width for centering).
local function drawOptionPair(part, top, oh, card)
  for i = 1, 2 do
    local opt = part.options[i]
    local cx = VW / 2 + (i == 1 and -42 or 42)
    local sel = part.choice == i
    local c = card(opt, i, sel)
    if sel then ui.outline(cx - 32, top, 64, oh, c.outline) end
    sprites.draw(c.sprite, cx - c.sw, top + 4, false, 2)
    font.drawText(opt.name, cx, top + 20, c.name, 1, 'center')
    font.drawText(opt.desc, cx, top + 28, c.desc, 1, 'center')
  end
end

function M.start(partsList, title)
  loot = { parts = partsList, i = 0, title = title, done = false }
  M.loot = loot
  engine.setState('loot')
  partSfx(partsList[1])
end

local function advance()
  loot.i = loot.i + 1
  if loot.i >= #loot.parts then
    if loot.done then return end
    loot.done = true
    engine.transition('SET SAIL!', function()
      engine.setState('sail')
    end)
  else
    partSfx(loot.parts[loot.i + 1])
  end
end

engine.states.loot = {
  update = function(dt)
    if loot.done then return end
    local part = loot.parts[loot.i + 1]
    if part.type == 'recruit' then
      if input.jp('a') or input.jp('b') then
        local run = game.run
        -- Voyage Log: the very first recruit of the voyage, caught
        -- by checking crew size against the starting roster (2 solo, 4 in
        -- TWO CAPTAINS) before this pal is added.
        local wasFirst = #run.crew == (run.mode == 'captains' and 4 or 2)
        run.crew[#run.crew + 1] = part.pirate
        if wasFirst then
          game.logMoment('flagW', 'SEA ' .. run.voyage.sea .. ': ' .. part.pirate.name .. ' JOINED THE CREW!',
            { part.pirate.name }, true)
        end
        if #run.party < game.partyCap() then
          run.party[#run.party + 1] = part.pirate
          if game.isCoop() then game.assignOwner(part.pirate) end
        end
        SFX.fanfare()
        engine.addParts(VW / 2, 90, 16, CO.gold, 50)
        advance()
      end
    elseif part.type == 'perk' then
      local ctx = cardCtx(part.pirate)
      if ctx.jp('left') or ctx.jp('right') then
        part.choice = part.choice == 1 and 2 or 1
        SFX.move()
      elseif ctx.jp('a') then
        local p = part.pirate
        p.perks = p.perks or {}
        p.perks[#p.perks + 1] = part.options[part.choice].id
        SFX.fanfare()
        engine.addParts(VW / 2, 90, 16, CO.gold, 50)
        advance()
      end
    elseif part.type == 'trade' then
      -- Friendly trader (4.2): one fair swap, gold <-> treasure. The gained
      -- side is inserted as the next card so the reward is shown, not told.
      if input.jp('left') or input.jp('right') then
        part.choice = part.choice == 1 and 2 or 1
        SFX.move()
      elseif input.jp('a') then
        local opt = part.options[part.choice]
        if not opt.ok then
          SFX.bump()
        else
          local run = game.run
          if opt.id == 'buy' then
            run.gold = run.gold - 15
            local pool = {}
            for _, t in ipairs(data.TREASURES) do
              if t.tier == 1 then pool[#pool + 1] = t end
            end
            local tr = util.pick(pool)
            local treasurePart, unlocks = game.awardTreasure(tr)
            table.insert(loot.parts, loot.i + 2, treasurePart)
            for _, u in ipairs(unlocks) do loot.parts[#loot.parts + 1] = u end
          else
            run.treas[opt.tid] = run.treas[opt.tid] - 1
            run.gold = run.gold + 25
            table.insert(loot.parts, loot.i + 2, { type = 'gold', n = 25 })
          end
          SFX.coin()
          advance()
        end
      end
    elseif part.type == 'blueprint_choice' then
      if #part.options > 1 and (input.jp('left') or input.jp('right')) then
        part.choice = part.choice == 1 and 2 or 1
        SFX.move()
      elseif input.jp('a') then
        local opt = part.options[part.choice]
        if opt then
          game.run.blueprints[opt.id] = true
          SFX.fanfare()
          advance()
        end
      end
    elseif input.jp('a') or input.jp('b') then
      advance()
    end
  end,

  draw = function()
    local gt = engine.gt
    gfx.setColor(CO.seaD)
    gfx.rectangle('fill', 0, 0, VW, 180)
    for y = 0, 11 do
      for x = 0, 19 do
        if (x * 71 + y * 53 + math.floor(gt * 2) * 37) % 37 == 0 then
          gfx.setColor(CO.sea)
          gfx.rectangle('fill', x * 16 + 4, y * 16 + 7, 5, 1)
        end
      end
    end
    font.drawText(loot.title, VW / 2, 12, CO.gold, 3, 'center')
    sprites.draw('chest', VW / 2 - 24, 28, false, 3)
    if loot.done or loot.i >= #loot.parts then return end

    local part = loot.parts[loot.i + 1]
    local bw, bx, by, bh = 200, (VW - 200) / 2, 84, 70
    gfx.setColor(CO.uiBg)
    gfx.rectangle('fill', bx, by, bw, bh)
    ui.outline(bx, by, bw, bh, CO.gold)

    if part.type == 'gold' then
      sprites.draw('coinS', VW / 2 - 22, by + 14, false, 2)
      font.drawText('+' .. part.n, VW / 2 + 4, by + 14, CO.gold, 2)
      font.drawText('GOLD!', VW / 2, by + 38, CO.paper, 1, 'center')
    elseif part.type == 'treasure' then
      local tdef = data.treasureById(part.id)
      sprites.draw('tr_' .. part.id, VW / 2 - 12, by + 6, false, 2)
      font.drawText(tdef.name, VW / 2, by + 34, CO.white, 1, 'center')
      local cnt = game.run.treas[part.id] or 0
      font.drawText(cnt == 1 and '* NEW! *' or ('x' .. cnt), VW / 2, by + 46,
        cnt == 1 and CO.gold or CO.gray, 1, 'center')
    elseif part.type == 'unlock' then
      font.drawText('NEW OUTFIT!', VW / 2, by + 6, CO.gold, 1, 'center')
      sprites.drawPirate('captain', part.id, VW / 2 - 16, by + 14, false, 2, nil, game.colorOf('p1'))
      font.drawText(data.outfitById(part.id).name, VW / 2, by + 50, CO.white, 1, 'center')
    elseif part.type == 'level' then
      font.drawText('LEVEL UP!', VW / 2, by + 8, CO.gold, 2, 'center')
      font.drawText(table.concat(part.names, ' + '), VW / 2, by + 28, CO.white, 1, 'center')
      font.drawText('+2 @  +1 ATK', VW / 2, by + 42, CO.green, 1, 'center')
    elseif part.type == 'recruit' then
      sprites.drawPirate(part.pirate.role, 'none', bx + 14, by + 14, false, 2, nil, game.palColor(part.pirate))
      font.drawText(part.pirate.name, VW / 2 + 16, by + 10, CO.gold, 1, 'center')
      font.drawText(data.ROLES[part.pirate.role].label .. ' LV' .. part.pirate.lvl, VW / 2 + 16, by + 20, CO.gray, 1, 'center')
      font.drawText('JOINS THE CREW!', VW / 2 + 16, by + 32, CO.white, 1, 'center')
      -- Legends across voyages: a returning pal who earned
      -- highlights last voyage flexes one of them here instead of the
      -- owner tag, which only applies once the party's still got room.
      local legend = meta.data.legends[part.pirate.name]
      if legend then
        font.drawText('* LEGEND *', bx + bw - 4, by + 4, CO.gold, 1, 'right')
      end
      -- Show who gets them (C1/C5): the receiving captain's face.
      if game.isCoop() and #game.run.party < game.partyCap() then
        local owner = game.nextOwner()
        local col = owner == 'p2' and CO.green or CO.gold
        local cap = receivingCaptain(owner)
        if cap then
          sprites.drawPirate(cap.role, cap.out, bx + bw - 26, by + 40, false, 1, nil, game.palColor(cap))
          font.drawText('JOINS ' .. cap.name .. '!', VW / 2 + 16, by + 40, col, 1, 'center')
        else
          font.drawText('JOINS ' .. ownerTag(owner) .. '!', VW / 2 + 16, by + 40, col, 1, 'center')
        end
      elseif legend then
        font.drawText(legend[1], VW / 2 + 16, by + 40, CO.gray, 1, 'center')
      end
    elseif part.type == 'clear' then
      font.drawText('SEA CLEAR!', VW / 2, by + 10, CO.gold, 2, 'center')
      font.drawText('BONUS +' .. part.n .. ' GOLD', VW / 2, by + 34, CO.paper, 1, 'center')
    elseif part.type == 'perk' then
      font.drawText(part.pirate.name .. ' LEVEL ' .. part.pirate.lvl .. '!', VW / 2, by + 4, CO.gold, 1, 'center')
      font.drawText('PICK A PERK!', VW / 2, by + 12, CO.paper, 1, 'center')
      drawOptionPair(part, by + 19, 40, function(opt, _, sel)
        return {
          outline = CO.gold, sprite = 'perk_' .. opt.icon, sw = 8,
          name = sel and CO.gold or CO.white, desc = CO.green,
        }
      end)
      local perkHint = '< > PICK   ' .. input.promptKey(input.p1, 'a') .. ' CONFIRM'
      if game.isCoop() then
        local owner = game.ownerOf(part.pirate)
        local ctx = owner == 'p2' and input.p2 or input.p1
        perkHint = ownerTag(owner) .. ' PICKS!  < >  ' .. input.promptKey(ctx, 'a') .. ' CONFIRM'
      end
      font.drawText(perkHint, VW / 2, by + 63, CO.paper, 1, 'center')
    elseif part.type == 'bond' then
      font.drawText('BEST MATES!', VW / 2, by + 8, CO.gold, 2, 'center')
      font.drawText(part.a .. ' @ ' .. part.b, VW / 2, by + 30, CO.white, 1, 'center')
      font.drawText('+1 ATK WHEN TOGETHER', VW / 2, by + 46, CO.green, 1, 'center')
    elseif part.type == 'bottle' then
      sprites.draw('tr_map', VW / 2 - 12, by + 6, false, 2)
      font.drawText('A TREASURE MAP!', VW / 2, by + 34, CO.gold, 1, 'center')
      font.drawText('X MARKS SEA ' .. part.sea .. '!', VW / 2, by + 46, CO.white, 1, 'center')
    elseif part.type == 'trade' then
      font.drawText('TRADE?', VW / 2, by + 4, CO.gold, 1, 'center')
      drawOptionPair(part, by + 16, 42, function(opt, i, sel)
        return {
          outline = opt.ok and CO.gold or CO.grayD,
          sprite = i == 1 and 'gemS' or 'coinS', sw = 7,
          name = not opt.ok and CO.grayD or (sel and CO.gold or CO.white),
          desc = opt.ok and CO.green or CO.grayD,
        }
      end)
      font.drawText('< > PICK   ' .. input.promptKey(input.p1, 'a') .. ' CONFIRM', VW / 2, by + 63, CO.paper, 1, 'center')
    elseif part.type == 'salvage' then
      sprites.draw('sal_' .. part.material, VW / 2 - 12, by + 6, false, 2)
      local matLabel = part.material == 'cloth' and 'SAILCLOTH' or part.material:upper()
      font.drawText('+' .. part.n .. ' ' .. matLabel, VW / 2, by + 34, CO.gold, 1, 'center')
      font.drawText('SALVAGE ADDED!', VW / 2, by + 46, CO.paper, 1, 'center')
    elseif part.type == 'blueprint_choice' then
      font.drawText('BLUEPRINT FOUND!', VW / 2, by + 4, CO.gold, 1, 'center')
      font.drawText('CHOOSE A BLUEPRINT!', VW / 2, by + 12, CO.paper, 1, 'center')
      drawOptionPair(part, by + 19, 40, function(opt, _, sel)
        return {
          outline = CO.gold, sprite = 'sal_blueprint', sw = 6,
          name = sel and CO.gold or CO.white, desc = CO.green,
        }
      end)
      font.drawText('< > PICK   ' .. input.promptKey(input.p1, 'a') .. ' CONFIRM', VW / 2, by + 63, CO.paper, 1, 'center')
    elseif part.type == 'blueprint_single' then
      font.drawText('BLUEPRINT FOUND!', VW / 2, by + 6, CO.gold, 1, 'center')
      sprites.draw('sal_blueprint', VW / 2 - 12, by + 16, false, 2)
      font.drawText(data.SHOTS[part.id].label, VW / 2, by + 44, CO.white, 1, 'center')
      font.drawText('UNLOCKED!', VW / 2, by + 54, CO.green, 1, 'center')
    end

    for i = 0, #loot.parts - 1 do
      gfx.setColor(i <= loot.i and CO.gold or CO.grayD)
      gfx.rectangle('fill', VW / 2 - #loot.parts * 4 + i * 8, 158, 5, 5)
    end
    -- perk/trade/blueprint_choice draw their hint above, inside the card
    if part.type ~= 'perk' and part.type ~= 'trade' and part.type ~= 'blueprint_choice' then
      font.drawText(input.promptKey(input.p1, 'a') .. ' NEXT', VW / 2, 168, CO.gray, 1, 'center')
    end
  end,
}

return M
