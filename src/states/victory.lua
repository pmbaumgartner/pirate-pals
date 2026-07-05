-- Victory celebration: shown after the Pirate King falls. Crew lineup,
-- treasure tally, gold total, confetti — then back to the title screen with
-- the save marked completed (run.legend = true). Home Port (Phase 5) will
-- give this a real next step; for now the voyage just ends here.
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
local barks = require 'src.barks'
local CO = palette.CO
local gfx = love.graphics
local SFX = audio.sfx

local VW, VH = 320, 180

local M = {}
local vc = nil

-- Victory screen highlights: first recruit and first Best Mates
-- (found oldest-first, since the gate in loot.lua/rewards.lua only logs
-- those once) plus the most recent boss-bar break, so the King's fight
-- gets a beat too. The voyage-won entry itself is excluded -- this screen
-- already says PIRATE LEGENDS!, no need to repeat it.
local function findFirst(run, icon)
  for i = 1, #run.log do
    if run.log[i].icon == icon then return run.log[i] end
  end
  return nil
end

local function findLast(run, icon)
  for i = #run.log, 1, -1 do
    if run.log[i].icon == icon then return run.log[i] end
  end
  return nil
end

local function topHighlights(run)
  local picks = {}
  for _, e in ipairs({ findFirst(run, 'flagW'), findFirst(run, 'gemS'), findLast(run, 'kingSil') }) do
    if e then picks[#picks + 1] = e end
  end
  return picks
end

-- Legends across voyages (pairs with New Voyage+): keep up to 2
-- highlight captions per pal who sailed this voyage, read newest-first out
-- of run.log, so loot.lua can flex a returning recruit's past. Capped at
-- the 10-pal crew cap so meta.data.legends can't grow forever across many
-- voyages -- an evicted name just stops flexing until it earns fresh ones.
local function distillLegends(run)
  local legends = meta.data.legends
  for _, p in ipairs(run.crew) do
    local highlights = {}
    for i = #run.log, 1, -1 do
      local e = run.log[i]
      for _, nm in ipairs(e.pals) do
        if nm == p.name then highlights[#highlights + 1] = e.text end
      end
      if #highlights >= 2 then break end
    end
    if #highlights > 0 then
      if not legends[p.name] then
        local count = 0
        for _ in pairs(legends) do count = count + 1 end
        if count >= 10 then
          for nm in pairs(legends) do
            local inCrew = false
            for _, q in ipairs(run.crew) do if q.name == nm then inCrew = true end end
            if not inCrew then legends[nm] = nil; break end
          end
        end
      end
      legends[p.name] = highlights
    end
  end
end

function M.start()
  local run = game.run
  run.legend = true
  game.logMoment('hat_crown', 'SEA ' .. run.voyage.sea .. ': PIRATE LEGENDS!', {})
  -- Gold gets a job (5.4): the voyage's gold banks into the meta pool spent
  -- at Home Port; the 12/12 treasure log permanently unlocks sea 9.
  meta.data.gold = meta.data.gold + run.gold
  meta.data.voyagesWon = meta.data.voyagesWon + 1
  local golden = game.distinctTreasures() >= 12
  if golden then meta.data.golden = true end
  distillLegends(run)
  meta.save()
  game.save()
  -- Defeat gag payoff: one random party pal wears the King's
  -- popped-off crown in the lineup. Draw-time only -- never touches run.party
  -- or the pal's real `out` field.
  local crownedName = util.pick(run.party).name
  vc = { t = 0, confettiCd = 0, golden = golden, barked = {}, crownedName = crownedName,
    highlights = topHighlights(run) }
  engine.setState('victory')
  SFX.bigwin()
end

engine.states.victory = {
  update = function(dt)
    vc.t = vc.t + dt
    vc.confettiCd = vc.confettiCd - dt
    if vc.confettiCd <= 0 then
      vc.confettiCd = 0.12
      engine.addParts(util.irand(20, VW - 20), -4, 4,
        util.pick({ CO.gold, CO.red, CO.foam, CO.green, CO.purple }), 30, 40)
    end
    if input.jp('vlog') then
      SFX.sel()
      engine.setState('voyagelog', 'victory')
      return
    end
    if input.jp('a') or input.jp('b') then
      SFX.sel()
      engine.transition('HOME PORT!', function()
        engine.setState('port')
      end)
    end
  end,

  draw = function()
    gfx.setColor(CO.night)
    gfx.rectangle('fill', 0, 0, VW, VH)
    engine.drawFx()

    local run = game.run
    -- TWO CAPTAINS (C5): the duo banner variant, both captains celebrated.
    if run.mode == 'captains' then
      font.drawText('PIRATE LEGENDS,', VW / 2, 8, vc.golden and CO.gold or CO.paper, 2, 'center')
      font.drawText('THE BOTH OF YE!', VW / 2, 26, vc.golden and CO.gold or CO.paper, 2, 'center')
    else
      font.drawText('PIRATE LEGENDS!', VW / 2, 14, vc.golden and CO.gold or CO.paper, 2, 'center')
    end
    if vc.golden then
      font.drawTextO('FULL TREASURE LOG!', VW / 2, 42, CO.gold, 1, 'center')
    end

    -- Voyage Log highlights: a few of this voyage's triumphs, read
    -- back before the crew lineup. `L: FULL LOG` only shows once there's
    -- more to see than fits here.
    for i, e in ipairs(vc.highlights) do
      font.drawTextO(e.text, VW / 2, 50 + (i - 1) * 7, CO.paper, 1, 'center')
    end
    if #run.log > #vc.highlights + 1 then
      font.drawTextO('L: FULL LOG', VW / 2, 50 + #vc.highlights * 7, CO.gray, 1, 'center')
    end

    -- Captains front and center: lineup ordered captains-first in the
    -- middle, companions flanking them.
    local lineup = run.party
    if run.mode == 'captains' then
      local caps, pals = {}, {}
      for _, p in ipairs(run.party) do
        if p.role == 'captain' then caps[#caps + 1] = p else pals[#pals + 1] = p end
      end
      lineup = { pals[1], caps[1], caps[2], pals[2] }
      local packed = {}
      for _, p in ipairs(lineup) do
        if p then packed[#packed + 1] = p end
      end
      lineup = packed
    end
    local n = #lineup
    local spacing = math.min(70, math.floor((VW - 40) / math.max(1, n)))
    local startX = VW / 2 - (n - 1) * spacing / 2
    for i, p in ipairs(lineup) do
      local x = startX + (i - 1) * spacing
      local ph = vc.t * 2 + i
      -- Per-role pose: a shared bob read as one crowd; a distinct
      -- wobble per role reads as individuals. Strongman also gets a small
      -- scale pulse (a flex) layered on top of the shared bob.
      local bob = util.round(math.sin(ph) * 2)
      local scale = 2
      if p.role == 'deckhand' then
        bob = bob + util.round(math.sin(ph * 1.5) * 1)
      elseif p.role == 'strongman' then
        scale = 2 + 0.08 * math.sin(ph * 1.3)
      elseif p.role == 'sharpshooter' then
        bob = util.round(math.sin(ph * 0.6) * 2)
      end
      sprites.drawPirate(p.role, p.out, x - 8, 70 + bob, false, scale, nil, game.palColor(p))
      if p.name == vc.crownedName then
        sprites.draw('hat_crown', x - 8, 70 + bob, false, scale)
      end
      font.drawTextO(p.name, x, 106, CO.white, 1, 'center')
      -- Each pal barks once, on a staggered timer, instead of all at once.
      if not vc.barked[i] and vc.t > 0.6 + (i - 1) * 0.45 then
        vc.barked[i] = true
        barks.say(p, x, 70 + bob, 'victory')
      end
    end

    font.drawText('GOLD BANKED  ' .. run.gold, VW / 2, 128, CO.gold, 1, 'center')
    font.drawText('TREASURE  ' .. game.distinctTreasures() .. '/12', VW / 2, 140, CO.purple, 1, 'center')
    font.drawText('SECRETS  ' .. game.distinctSecrets() .. '/' .. #data.SECRETS, VW / 2, 152, CO.foam, 1, 'center')

    if math.floor(vc.t * 2) % 2 == 0 then
      font.drawTextO('Z TO HOME PORT   L FULL LOG', VW / 2, VH - 14, CO.gray, 1, 'center')
    end
  end,
}

return M
