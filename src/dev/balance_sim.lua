-- Headless auto-battle balance simulation for Stage 5

-- Ensure love is globally defined first!
if not _G.love then
  _G.love = {
    graphics = {},
    audio = {},
    sound = {},
    math = { random = math.random },
    filesystem = {
      getInfo = function() return nil end,
      write = function() end,
      read = function() return nil end,
    },
  }
end

local data = require 'src.data'
local shipRules = require 'src.ship_rules'
local game = require 'src.game'
local meta = require 'src.meta'

local M = {}

-- Simulates foe's next intent decision
local function decideFoeIntent(foe, player, level, isBoss)
  if foe.ablaze and foe.ablaze > 0 and (foe.class == 'fireship' or isBoss) then
    foe.intent = 'douse'
    return
  end

  if isBoss then
    if foe.hp < foe.max * 0.3 and foe.repairs > 0 and math.random() < 0.6 then
      foe.intent = 'fix'
    elseif (meta.data.tier or 0) >= 2 and foe.volleyKegs > 0 and math.random() < 0.25 then
      foe.intent = 'volley'
    elseif foe.bigshotKegs > 0 and math.random() < 0.35 then
      foe.intent = 'bigshot'
    else
      foe.intent = 'fire'
    end
    return
  end

  if foe.class == 'sloop' then
    if foe.hp < foe.max * 0.35 and foe.repairs > 0 and math.random() < 0.8 then
      foe.intent = 'fix'
    elseif math.random() < 0.35 then
      foe.intent = 'move'
    else
      foe.intent = 'fire'
    end
  elseif foe.class == 'manowar' then
    if foe.hp < foe.max * 0.35 and foe.repairs > 0 and math.random() < 0.8 then
      foe.intent = 'fix'
    elseif foe.bigshotKegs > 0 and math.random() < 0.5 then
      foe.intent = 'bigshot'
    else
      foe.intent = 'fire'
    end
  elseif foe.class == 'fireship' then
    foe.intent = 'fire'
  else -- brig or default
    if foe.hp < foe.max * 0.35 and foe.repairs > 0 and math.random() < 0.8 then
      foe.intent = 'fix'
    elseif math.random() < 0.18 then
      foe.intent = 'move'
    else
      foe.intent = 'fire'
    end
  end
end

-- Simulates a single battle and returns (win, turnCount)
function M.runBattle(profile)
  -- Setup game.run for shipRules queries
  game.run = {
    fittings = {
      hull = profile.fittings.hull or 0,
      sails = profile.fittings.sails or 0,
      guns = profile.fittings.guns or 0,
      slot = profile.slot
    },
    blueprints = profile.blueprints or {},
    mode = 'solo'
  }

  local capLevel = profile.captainLevel or (math.floor(profile.level / 2) + 1)
  game.run.party = {
    { role = 'captain', lvl = capLevel }
  }

  meta.data = { upgrades = {} }

  -- Initialize player ship state
  local player = {
    hp = shipRules.getPlayerHullMax(1),
    max = shipRules.getPlayerHullMax(1),
    repairs = 3,
    maxRepairs = 3,
    dodge = 0,
    range = 'FAR',
    guns = shipRules.getPlayerGuns(1),
    sails = shipRules.getPlayerSails(1),
    gunsStage = 0,
    sailsStage = 0,
    ablaze = nil,
    powder = {
      round = 999999,
      chain = data.SHOTS.chain.powder,
      grape = data.SHOTS.grape.powder,
      fire = data.SHOTS.fire.powder,
    }
  }

  -- Initialize foe ship state
  local foe = {}
  local isBoss = profile.isBoss
  if isBoss then
    foe.max = data.KING.hull
    foe.guns = 3
    foe.sails = 1
    foe.armor = data.KING.armor
    foe.weak = data.KING.weak
    foe.repairs = data.KING.repairs
    foe.maxRepairs = data.KING.repairs
    foe.bigshotKegs = data.KING.bigshotKegs
    foe.maxBigshotKegs = data.KING.bigshotKegs
    foe.volleyKegs = data.KING.volleyKegs
    foe.maxVolleyKegs = data.KING.volleyKegs
    foe.class = 'king'
  else
    local cStats = shipRules.getEnemyClassStats(profile.class, profile.level)
    foe.max = cStats.maxHp
    foe.guns = cStats.guns
    foe.sails = cStats.sails
    foe.armor = cStats.armor
    foe.weak = cStats.weak
    foe.repairs = 2
    foe.maxRepairs = 2
    foe.bigshotKegs = (profile.class == 'manowar') and 3 or 0
    foe.maxBigshotKegs = foe.bigshotKegs
    foe.volleyKegs = 0
    foe.maxVolleyKegs = 0
    foe.class = profile.class
  end
  foe.hp = foe.max
  foe.gunsStage = 0
  foe.sailsStage = 0
  foe.ablaze = nil
  foe.range = 'FAR'
  foe.dodge = 0
  foe.intent = nil

  decideFoeIntent(foe, player, profile.level, isBoss)

  local turns = 0
  while player.hp > 0 and foe.hp > 0 and turns < 100 do
    turns = turns + 1

    -- Player Turn policy (fix under 40%, dodge kegs, fire weakness)
    local action
    local shotId = 'round'

    if player.hp < player.max * 0.40 and player.repairs > 0 then
      action = 'fix'
    elseif foe.intent == 'bigshot' or foe.intent == 'volley' then
      action = 'move'
    else
      action = 'fire'
      local weakShot = foe.weak
      if weakShot and player.powder[weakShot] and player.powder[weakShot] > 0 and shipRules.isShotKnown(weakShot) then
        shotId = weakShot
      end
    end

    -- Execute Player Action
    if action == 'fix' then
      player.repairs = player.repairs - 1
      player.hp = math.min(player.max, player.hp + 15)
    elseif action == 'move' then
      player.range = (player.range == 'NEAR') and 'FAR' or 'NEAR'
      local bigThreat = isBoss and foe.intent == 'bigshot'
      player.dodge = shipRules.getDodgeChance(player.sails, player.sailsStage, bigThreat)
    elseif action == 'fire' then
      if shotId ~= 'round' then
        player.powder[shotId] = player.powder[shotId] - 1
      end

      -- Timing bar resolution: 15% perfect, 75% good, 10% miss
      local r = math.random()
      local res
      if r < 0.15 then
        res = 'perfect'
      elseif r < 0.90 then
        res = 'good'
      else
        res = 'miss'
      end

      local effectiveGuns = shipRules.getEffectiveStat(player.guns, player.gunsStage)
      local armor = foe.armor or 0
      local isWeak = (foe.weak == shotId)
      local isResisted = (foe.armor > 0 and foe.weak ~= shotId)

      local pwr = data.SHOTS[shotId].power
      if player.range == 'NEAR' then
        pwr = pwr + 2
      end
      local baseDmg = pwr + effectiveGuns - armor + math.random(0, 2)
      local dmg = baseDmg
      if res == 'perfect' then
        dmg = math.floor(dmg * 1.5)
      elseif res == 'miss' then
        dmg = math.max(1, math.floor(dmg * 0.6))
      end

      local mult = 1
      if isWeak then
        mult = 1.5
      elseif isResisted then
        mult = 0.75
      end
      dmg = math.max(0, math.floor(dmg * mult))

      -- Foe dodge check
      local foeDodged = false
      if foe.dodge > 0 then
        foeDodged = (math.random() < foe.dodge)
        foe.dodge = 0
      end

      if not foeDodged then
        foe.hp = math.max(0, foe.hp - dmg)
        if res ~= 'miss' then
          if shotId == 'chain' then
            foe.sailsStage = math.max(-2, foe.sailsStage - 1)
          elseif shotId == 'grape' then
            foe.gunsStage = math.max(-2, foe.gunsStage - 1)
          elseif shotId == 'fire' then
            foe.ablaze = 3
          end
        end
      end
    end

    if foe.hp <= 0 then break end

    -- Foe Turn
    -- 1. Foe ablaze tick
    if foe.ablaze and foe.ablaze > 0 then
      foe.hp = math.max(0, foe.hp - 4)
      foe.ablaze = foe.ablaze - 1
      if foe.hp <= 0 then break end
    end

    -- 2. Execute Foe Action
    local fIntent = foe.intent
    foe.intent = nil

    if fIntent == 'fix' then
      foe.repairs = foe.repairs - 1
      foe.hp = math.min(foe.max, foe.hp + 10 + 2 * profile.level)
    elseif fIntent == 'douse' then
      foe.ablaze = nil
    elseif fIntent == 'move' then
      player.range = (player.range == 'NEAR') and 'FAR' or 'NEAR'
      foe.dodge = shipRules.getDodgeChance(foe.sails, foe.sailsStage, false)
    elseif fIntent == 'bigshot' then
      foe.bigshotKegs = foe.bigshotKegs - 1
      local dmg = isBoss and 20 or (14 + profile.level)
      if foe.gunsStage < 0 then
        dmg = math.max(1, dmg + foe.gunsStage * 2)
      end
      local dodged = false
      if player.dodge > 0 then
        dodged = (math.random() < player.dodge)
        player.dodge = 0
      end
      if not dodged then
        player.hp = math.max(0, player.hp - dmg)
      end
    elseif fIntent == 'volley' then
      foe.volleyKegs = foe.volleyKegs - 1
      local dmg = 8 + profile.level
      if foe.gunsStage < 0 then
        dmg = math.max(1, dmg + foe.gunsStage)
      end
      -- Hit 1
      local dodged1 = false
      if player.dodge > 0 then
        dodged1 = (math.random() < player.dodge)
        player.dodge = 0
      end
      if not dodged1 then
        player.hp = math.max(0, player.hp - dmg)
      end
      -- Hit 2
      local dodged2 = false
      if player.dodge > 0 then
        dodged2 = (math.random() < player.dodge)
        player.dodge = 0
      end
      if not dodged2 then
        player.hp = math.max(0, player.hp - dmg)
      end
    else -- fire / default
      local dmg
      if isBoss then
        local base = 3 + math.floor(profile.level / 2)
        if player.range ~= 'NEAR' then
          base = base - 2
        end
        dmg = base + math.random(0, 2)
        if foe.gunsStage < 0 then
          dmg = math.max(1, dmg + foe.gunsStage * 2)
        end
      else
        local effectiveGuns = shipRules.getEffectiveStat(foe.guns or 1, foe.gunsStage)
        local pwr = (foe.class == 'fireship') and 5 or 7
        if player.range == 'NEAR' then
          pwr = pwr + 2
        end
        dmg = pwr + effectiveGuns + math.random(0, 2)
      end

      local dodged = false
      if player.dodge > 0 then
        dodged = (math.random() < player.dodge)
        player.dodge = 0
      end
      if not dodged then
        player.hp = math.max(0, player.hp - dmg)
        if player.hp > 0 and foe.class == 'fireship' then
          player.ablaze = 3
        end
      end
    end

    if player.hp <= 0 then break end

    -- Player Ablaze Tick
    if player.ablaze and player.ablaze > 0 then
      player.hp = math.max(0, player.hp - 4)
      player.ablaze = player.ablaze - 1
      if player.hp <= 0 then break end
    end

    decideFoeIntent(foe, player, profile.level, isBoss)
  end

  return (player.hp > 0 and foe.hp <= 0), turns
end

function M.runAll(nTrials)
  nTrials = nTrials or 1000

  local normalProfiles = {
    { name = "Sloop Sea 1", class = "sloop", level = 1, fittings = { hull = 0, sails = 0, guns = 0 }, blueprints = {}, slot = nil },
    { name = "Brig Sea 2", class = "brig", level = 2, fittings = { hull = 1, sails = 0, guns = 0 }, blueprints = {}, slot = nil },
    { name = "Fireship Sea 3", class = "fireship", level = 3, fittings = { hull = 1, sails = 1, guns = 0 }, blueprints = {}, slot = nil },
    { name = "Sloop Sea 4 (Chain)", class = "sloop", level = 4, fittings = { hull = 1, sails = 1, guns = 1 }, blueprints = { chain = true }, slot = "chain" },
    { name = "Man-O-War Sea 5 (Fire)", class = "manowar", level = 5, fittings = { hull = 2, sails = 1, guns = 1 }, blueprints = { fire = true }, slot = "fire" },
    { name = "Brig Sea 6 (Grape)", class = "brig", level = 6, fittings = { hull = 2, sails = 2, guns = 2 }, blueprints = { grape = true }, slot = "grape" },
    { name = "Man-O-War Sea 6 (Fire)", class = "manowar", level = 6, fittings = { hull = 2, sails = 2, guns = 2 }, blueprints = { fire = true }, slot = "fire" },
    { name = "Sloop Sea 6 (Chain)", class = "sloop", level = 6, fittings = { hull = 2, sails = 2, guns = 2 }, blueprints = { chain = true }, slot = "chain" }
  }

  local bossProfiles = {
    { name = "Pirate King Sea 7 (Prepared - Fire)", isBoss = true, level = 7, fittings = { hull = 2, sails = 2, guns = 2 }, blueprints = { fire = true }, slot = "fire" },
    { name = "Pirate King Sea 7 (Unprepared - Round)", isBoss = true, level = 7, fittings = { hull = 2, sails = 2, guns = 2 }, blueprints = {}, slot = nil }
  }

  local allPassed = true

  print("======================================================================")
  print("                    SHIP COMBAT BALANCE HARNESS                       ")
  print("======================================================================")
  print(string.format("%-30s | %-8s | %-8s | %-12s", "Profile Name", "Win Rate", "Avg Turns", "Status"))
  print("----------------------------------------------------------------------")

  for _, profile in ipairs(normalProfiles) do
    local wins = 0
    local totalTurns = 0
    for _ = 1, nTrials do
      local win, turns = M.runBattle(profile)
      if win then
        wins = wins + 1
      end
      totalTurns = totalTurns + turns
    end
    local winRate = wins / nTrials
    local avgTurns = totalTurns / nTrials

    local status = "OK"
    if winRate < 0.75 or winRate > 0.95 then
      status = "FAIL (75-95%)"
      allPassed = false
    end
    print(string.format("%-30s | %7.1f%%  | %8.2f  | %-12s", profile.name, winRate * 100, avgTurns, status))
  end

  print("----------------------------------------------------------------------")
  for _, profile in ipairs(bossProfiles) do
    local wins = 0
    local totalTurns = 0
    for _ = 1, nTrials do
      local win, turns = M.runBattle(profile)
      if win then
        wins = wins + 1
      end
      totalTurns = totalTurns + turns
    end
    local winRate = wins / nTrials
    local avgTurns = totalTurns / nTrials

    local status = "OK"
    -- Check target range 55-85% for Prepared Pirate King profile, and expect Unprepared to be <25%.
    if profile.slot == "fire" then
      if winRate < 0.55 or winRate > 0.85 then
        status = "FAIL (55-85%)"
        allPassed = false
      end
    else
      if winRate > 0.25 then
        status = "FAIL (unprepared should be <25%)"
        allPassed = false
      end
    end
    print(string.format("%-30s | %7.1f%%  | %8.2f  | %-12s", profile.name, winRate * 100, avgTurns, status))
  end
  print("======================================================================")

  return allPassed
end

-- If run directly from the command line
if arg and arg[0] and arg[0]:find("balance_sim.lua") then
  local ok = M.runAll()
  if not ok then
    print("FAIL: Win rates out of range!")
    os.exit(1)
  else
    print("BALANCE HARNESS OK")
    os.exit(0)
  end
end

return M
