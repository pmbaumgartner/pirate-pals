-- Boarding-battle win rewards: gold, a treasure roll (with milestone
-- unlock checks), party level-ups, a possible recruit, and a sea-clear
-- bonus. Split out from person_battle.lua so the reward-resolution
-- concern doesn't compete for space with battle model/AI/draw code.
local util = require 'src.util'
local grid = require 'src.grid'
local game = require 'src.game'
local data = require 'src.data'
local shipRewards = require 'src.ship_rewards'
local loot = require 'src.states.loot'
local barks = require 'src.barks'
local S = require 'src.states.person_battle.state'

local M = {}

function M.victoryLoot()
  -- Lazy require: model.lua requires this module at load time, so a
  -- top-level require here would deadlock into the cycle-detection sentinel.
  -- By the time victoryLoot() actually runs, model.lua is fully loaded.
  local model = require 'src.states.person_battle.model'
  local pb = S.pb
  local run = game.run
  local lv = pb.lv
  local parts = {}
  local goldN = 8 + 6 * lv + util.irand(0, 4)
  run.gold = run.gold + goldN
  parts[#parts + 1] = { type = 'gold', n = goldN }
  if util.chance(0.92) then
    local tr = game.rollTreasure(lv)
    local treasurePart, unlocks = game.awardTreasure(tr)
    parts[#parts + 1] = treasurePart
    for _, u in ipairs(unlocks) do parts[#parts + 1] = u end
  end
  -- Slower leveling: every pal in this fight banks a win; leveling
  -- happens on even wins so the milestone perk picks (2/4/6) land on a
  -- predictable cadence. Perk milestones swap in an interactive perk card
  -- instead of the plain level-up card.
  local lvNames = {}
  for _, u in ipairs(pb.units) do
    if u.side == 'p' and u.ref then
      local p = u.ref
      p.wins = (p.wins or 0) + 1
      if p.wins % 2 == 0 and p.lvl < 6 then
        p.lvl = p.lvl + 1
        local ux, uy = model.px(u.x, u.y)
        barks.say(u, ux, uy, 'levelUp')
        local options = data.perksFor(p.role, p.lvl)
        if options then
          parts[#parts + 1] = { type = 'perk', pirate = p, options = options, choice = 1 }
        else
          lvNames[#lvNames + 1] = p.name
        end
      end
    end
  end
  if #lvNames > 0 then parts[#parts + 1] = { type = 'level', names = lvNames } end

  -- Best Mates: pals who ended the fight adjacent build toward a bond;
  -- crossing the threshold shows a one-time BEST MATES card.
  local BOND_THRESHOLD = 3
  for i = 1, #pb.units do
    local ui_ = pb.units[i]
    if ui_.side == 'p' and ui_.ref then
      for j = i + 1, #pb.units do
        local uj = pb.units[j]
        if uj.side == 'p' and uj.ref and grid.manhattan(ui_.x, ui_.y, uj.x, uj.y) == 1 then
          local key = game.bondKey(ui_.ref.name, uj.ref.name)
          run.bonds[key] = (run.bonds[key] or 0) + 1
          if run.bonds[key] >= BOND_THRESHOLD and not run.bondsMade[key] then
            local wasFirstBond = next(run.bondsMade) == nil
            run.bondsMade[key] = true
            parts[#parts + 1] = { type = 'bond', a = ui_.ref.name, b = uj.ref.name }
            game.logMoment('gemS', 'SEA ' .. lv .. ': ' .. ui_.ref.name .. ' + ' .. uj.ref.name .. ' = BEST MATES!',
              { ui_.ref.name, uj.ref.name }, wasFirstBond)
            local ax, ay = model.px(ui_.x, ui_.y)
            barks.say(ui_, ax, ay, 'bestMates')
          end
        end
      end
    end
  end

  -- Only roles with a join mapping can knock and ask (escaped/KO'd thieves
  -- have join = nil — no recruiting the gold-grabber).
  local joinable = {}
  for _, d in ipairs(pb.defeated) do
    if data.EROLES[d.role].join then joinable[#joinable + 1] = d end
  end
  if #run.crew < 10 and #joinable > 0 and (#run.crew < 3 or util.chance(0.6)) then
    local dfd = util.pick(joinable)
    local role = (util.chance(0.18) and not game.crewHasRole('medic')) and 'medic' or data.EROLES[dfd.role].join
    local used = {}
    for _, p in ipairs(run.crew) do used[p.name] = true end
    local nm = nil
    for _ = 1, 20 do
      local cand = util.pick(data.PAL_NAMES)
      if not used[cand] then
        nm = cand
        break
      end
    end
    if nm then
      parts[#parts + 1] = { type = 'recruit', pirate = game.makePirate(role, nm, math.min(4, math.max(1, lv))) }
    end
  end

  for _, part in ipairs(shipRewards.victoryParts(run, pb.foeRef, lv)) do
    parts[#parts + 1] = part
  end

  local es = run.sea.enemies
  for i, e in ipairs(es) do
    if e == pb.foeRef then
      table.remove(es, i)
      break
    end
  end
  if #es == 0 and not run.sea.cleared then
    run.sea.cleared = true
    run.gold = run.gold + 20
    parts[#parts + 1] = { type = 'clear', n = 20 }
    game.logMoment('coinS', 'SEA ' .. lv .. ': CREW CLEARED THE SEA!', {})
  end
  run.wins = run.wins + 1
  loot.start(parts, 'YOU WIN!')
end

return M
