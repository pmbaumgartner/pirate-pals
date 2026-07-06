local data = require 'src.data'
local game = require 'src.game'
local meta = require 'src.meta'

local M = {}

local function runOrCurrent(run)
  return run or game.run
end

local function chance(chanceFn, p)
  if chanceFn then return chanceFn(p) end
  return math.random() < p
end

local function ownerOf(run, pirate)
  if not run or not pirate then return nil end
  if run.owners then return run.owners[pirate.name] end
  if run == game.run then return game.ownerOf(pirate) end
  return nil
end

-- Returns the tier (0, 1, 2, or 3) of a given fitting ('hull', 'sails', 'guns')
function M.getFittingTier(fittingType)
  return M.getFittingTierForRun(game.run, fittingType)
end

function M.getFittingTierForRun(run, fittingType)
  run = runOrCurrent(run)
  if not run or not run.fittings then return 0 end
  return run.fittings[fittingType] or 0
end

-- Returns the stat bonus granted by a fitting at the given tier
function M.getFittingBonus(fittingType, tier)
  if fittingType == 'hull' then
    return tier * 6
  elseif fittingType == 'sails' then
    return tier
  elseif fittingType == 'guns' then
    return tier
  end
  return 0
end

-- Calculates the maximum HP for player ship index (1 or 2)
function M.getPlayerHullMax(shipIndex)
  return M.getPlayerHullMaxForRun(game.run, shipIndex)
end

function M.getPlayerHullMaxForRun(run, shipIndex)
  local tier = M.getFittingTierForRun(run, 'hull')
  local bonus = M.getFittingBonus('hull', tier)
  return meta.shipMaxHp() + bonus
end

-- Calculates the SAILS stat for player ship index (1 or 2)
function M.getPlayerSails(shipIndex)
  return M.getPlayerSailsForRun(game.run, shipIndex)
end

function M.getPlayerSailsForRun(run, shipIndex)
  local tier = M.getFittingTierForRun(run, 'sails')
  local bonus = M.getFittingBonus('sails', tier)
  return 1 + bonus
end

-- Calculates the GUNS stat for player ship index (1 or 2)
function M.getPlayerGuns(shipIndex)
  return M.getPlayerGunsForRun(game.run, shipIndex)
end

function M.getPlayerGunsForRun(run, shipIndex)
  run = runOrCurrent(run)
  local tier = M.getFittingTierForRun(run, 'guns')
  local bonus = M.getFittingBonus('guns', tier)
  local capLevel = 1
  if run and run.party then
    if run.mode == 'captains' then
      local owner = (shipIndex == 2) and 'p2' or 'p1'
      for _, p in ipairs(run.party) do
        if p.role == 'captain' and ownerOf(run, p) == owner then
          capLevel = p.lvl
          break
        end
      end
    else
      -- Solo: check first captain
      for _, p in ipairs(run.party) do
        if p.role == 'captain' then
          capLevel = p.lvl
          break
        end
      end
    end
  end
  return 1 + bonus + math.floor(capLevel / 2)
end

-- Checks if a shot type is currently known (equipped or default)
function M.isShotKnown(shotId)
  return M.isShotKnownForRun(game.run, shotId)
end

function M.isShotKnownForRun(run, shotId)
  run = runOrCurrent(run)
  if shotId == 'round' then return true end
  if run and run.fittings and run.fittings.slot == shotId then
    return true
  end
  return false
end

-- Returns the list of shot IDs known in battle
function M.getKnownShots()
  return M.getKnownShotsForRun(game.run)
end

function M.getKnownShotsForRun(run)
  run = runOrCurrent(run)
  local list = { 'round' }
  if run and run.fittings and run.fittings.slot then
    list[#list + 1] = run.fittings.slot
  end
  return list
end

-- Checks if a blueprint has been collected/unlocked
function M.hasBlueprint(shotId)
  if not game.run or not game.run.blueprints then return false end
  return game.run.blueprints[shotId] == true
end

function M.defaultPowder()
  return {
    round = data.SHOTS.round.powder,
    chain = data.SHOTS.chain.powder,
    grape = data.SHOTS.grape.powder,
    fire = data.SHOTS.fire.powder,
  }
end

-- Calculates the damage preview range [minDmg, maxDmg] before timing.
-- shotId: 'round', 'chain', 'grape', 'fire'
-- range: 'NEAR' or 'FAR'
-- attackerGuns: attacker's GUNS stat
-- defenderArmor: defender's armor tier (0 or more)
-- isWeak: boolean, true if defender is weak to this shot
-- isResisted: boolean, true if shot is resisted by defender
function M.getDamagePreview(shotId, range, attackerGuns, defenderArmor, isWeak, isResisted)
  local shot = data.SHOTS[shotId]
  if not shot then return 0, 0 end
  local pwr = shot.power
  if range == 'NEAR' then
    pwr = pwr + 2
  end
  local baseMin = pwr + attackerGuns - defenderArmor
  local baseMax = baseMin + 2

  local mult = 1
  if isWeak then
    mult = 1.5
  elseif isResisted then
    mult = 0.75
  end

  local minDmg = math.max(0, math.floor(baseMin * mult))
  local maxDmg = math.max(0, math.floor(baseMax * mult))
  return minDmg, maxDmg
end

function M.getShotPreview(attacker, defender, shotId)
  local effectiveGuns = M.getEffectiveStat(attacker.guns, attacker.gunsStage)
  local armor = defender.armor or 0
  local isWeak = defender.weak == shotId
  local isResisted = armor > 0 and defender.weak ~= shotId
  return M.getDamagePreview(shotId, attacker.range, effectiveGuns, armor, isWeak, isResisted)
end

function M.resolveShotDamage(attacker, defender, shotId, timingResult, roll)
  roll = roll or 0
  local effectiveGuns = M.getEffectiveStat(attacker.guns, attacker.gunsStage)
  local armor = defender.armor or 0
  local isWeak = defender.weak == shotId
  local isResisted = armor > 0 and defender.weak ~= shotId
  local shot = data.SHOTS[shotId]
  local pwr = shot.power
  if attacker.range == 'NEAR' then pwr = pwr + 2 end
  local dmg = pwr + effectiveGuns - armor + roll
  if timingResult == 'perfect' then
    dmg = math.floor(dmg * 1.5)
  elseif timingResult == 'miss' then
    dmg = math.max(1, math.floor(dmg * 0.6))
  end
  if isWeak then
    dmg = math.floor(dmg * 1.5)
  elseif isResisted then
    dmg = math.floor(dmg * 0.75)
  end
  return {
    damage = math.max(0, dmg),
    isWeak = isWeak,
    isResisted = isResisted,
  }
end

function M.resolveBroadsideDamage(ship1, ship2, foe, res1, res2, roll1, roll2)
  local armor = foe.armor or 0
  local isWeak = foe.weak == 'round'
  local isResisted = armor > 0 and foe.weak ~= 'round'
  local base1 = 9 + ship1.guns - armor + (roll1 or 0)
  if res1 == 'perfect' then
    base1 = math.floor(base1 * 1.5)
  elseif res1 == 'miss' then
    base1 = math.max(1, math.floor(base1 * 0.6))
  end

  local base2 = 9 + ship2.guns - armor + (roll2 or 0)
  if res2 == 'perfect' then
    base2 = math.floor(base2 * 1.5)
  elseif res2 == 'miss' then
    base2 = math.max(1, math.floor(base2 * 0.6))
  end

  local rainbow = res1 ~= 'miss' and res2 ~= 'miss'
  local dmg = base1 + base2 + (rainbow and 8 or 0)
  if isWeak then
    dmg = math.floor(dmg * 1.5)
  elseif isResisted then
    dmg = math.floor(dmg * 0.75)
  end
  return {
    damage = math.max(0, dmg),
    isWeak = isWeak,
    isResisted = isResisted,
    rainbow = rainbow,
  }
end

-- Returns stats of an enemy ship class
function M.getEnemyClassStats(className, level)
  local class = data.SHIPCLASSES[className]
  if not class then return nil end
  return {
    name = class.name,
    maxHp = class.hullBase + class.hullScale * level,
    guns = class.guns,
    sails = class.sails,
    weak = class.weak,
    armor = class.armor or 0,
  }
end

function M.foeClassFor(foe)
  local isBoss = foe.boss == true
  if foe.class then return foe.class end
  if isBoss then return foe.kraken and 'kraken' or 'king' end
  return 'brig'
end

function M.buildFoeState(foe, level, fleet, startSailsStage)
  local isBoss = foe.boss == true
  local className = M.foeClassFor(foe)
  local maxHp, guns, sails, armor, weak, repairs, bigshotKegs, volleyKegs, immuneAblaze
  immuneAblaze = false

  if isBoss then
    if className == 'kraken' then
      maxHp = data.KING.kraken.hull
      guns, sails, armor = 3, 1, 0
      weak = data.KING.kraken.weak
      repairs, bigshotKegs, volleyKegs = 2, 0, 0
      immuneAblaze = data.KING.kraken.immuneAblaze
    else
      maxHp = data.KING.hull
      guns, sails = 3, 1
      armor = data.KING.armor
      weak = data.KING.weak
      repairs = data.KING.repairs
      bigshotKegs = data.KING.bigshotKegs
      volleyKegs = data.KING.volleyKegs
    end
  else
    local stats = M.getEnemyClassStats(className, level)
    maxHp = stats.maxHp
    guns = stats.guns
    sails = stats.sails
    armor = stats.armor
    weak = stats.weak
    repairs = 2
    bigshotKegs = className == 'manowar' and 3 or 0
    volleyKegs = 0
  end

  if fleet then
    maxHp = math.floor(maxHp * 1.5)
    if isBoss and className ~= 'kraken' then
      bigshotKegs = bigshotKegs + 1
    else
      repairs = 3
    end
  end

  return {
    hp = maxHp, max = maxHp, name = foe.name, lv = level,
    repairs = repairs, maxRepairs = repairs,
    dodge = 0, intent = nil, target = 1,
    bigshotKegs = bigshotKegs, maxBigshotKegs = bigshotKegs,
    volleyKegs = volleyKegs, maxVolleyKegs = volleyKegs,
    guns = guns, sails = sails, armor = armor, weak = weak,
    class = className, gunsStage = 0, sailsStage = startSailsStage or 0,
    ablaze = nil, immuneAblaze = immuneAblaze,
  }
end

function M.buildPlayerShip(run, shipIndex, opts)
  opts = opts or {}
  local maxHp = M.getPlayerHullMaxForRun(run, shipIndex)
  return {
    hp = maxHp - (opts.hurt or 0), max = maxHp, repairs = 3, maxRepairs = 3,
    dodge = opts.dodge or 0,
    range = 'FAR', pt = 0, owner = opts.owner or (shipIndex == 2 and 'p2' or 'p1'),
    menu = 0, submenu = nil, sub = 0, chosen = nil, confirmOrder = nil,
    patched = false, patchRounds = 0,
    guns = M.getPlayerGunsForRun(run, shipIndex),
    sails = M.getPlayerSailsForRun(run, shipIndex),
    gunsStage = 0, sailsStage = opts.sailsStage or 0,
    powder = M.defaultPowder(),
  }
end

-- Calculates the effective stat after applying a stage modifier.
-- We clamp the stage to [-2, 0] since it's debuff-only and max debuff is -2.
function M.clampStage(stage)
  return math.max(-2, math.min(1, stage or 0))
end

function M.getEffectiveStat(baseStat, stage)
  local clamped = M.clampStage(stage)
  return math.max(0, baseStat + clamped)
end

-- Calculates the dodge chance for a ship using its sails stat and sails stage.
-- sails: the SAILS stat (e.g. 1 + tier for player).
-- stage: the stage debuff (0, -1, -2).
-- isBigThreat: boolean, true if dodging a telegraphed bigshot (guaranteed 100% dodge)
function M.getDodgeChance(sails, stage, isBigThreat)
  if isBigThreat then return 1 end
  local effectiveSails = M.getEffectiveStat(sails, stage)
  -- sails = 1 + tier, so tier = sails - 1.
  local tier = math.max(0, effectiveSails - 1)
  return 0.4 + tier * 0.15
end

function M.foePhase(foe)
  local hpRatio = foe.hp / foe.max
  if hpRatio <= 0.33 then return 3 end
  if hpRatio <= 0.67 then return 2 end
  return 1
end

function M.chooseFoeIntent(foe, opts)
  opts = opts or {}
  if foe.ablaze and foe.ablaze > 0 and (foe.class == 'fireship' or opts.isBoss) then
    return 'douse'
  end

  if opts.isBoss then
    if foe.class == 'kraken' then return 'fire' end
    local phase = M.foePhase(foe)
    if foe.hp < foe.max * 0.3 and foe.repairs > 0 and chance(opts.chance, 0.6) then
      return 'fix'
    elseif phase == 3 then
      if chance(opts.chance, 0.5) then
        return 'ram'
      elseif foe.bigshotKegs > 0 and chance(opts.chance, 0.35) then
        return 'bigshot'
      end
      return 'fire'
    elseif phase == 2 then
      if (opts.tier or 0) >= 2 and foe.volleyKegs > 0 and chance(opts.chance, 0.25) then
        return 'volley'
      elseif foe.bigshotKegs > 0 and chance(opts.chance, 0.35) then
        return 'bigshot'
      end
      return 'fire'
    end
    if foe.bigshotKegs > 0 and chance(opts.chance, 0.35) then return 'bigshot' end
    return 'fire'
  end

  if foe.class == 'sloop' then
    if foe.hp < foe.max * 0.35 and foe.repairs > 0 and chance(opts.chance, 0.8) then
      return 'fix'
    elseif chance(opts.chance, 0.35) then
      return 'move'
    end
    return 'fire'
  elseif foe.class == 'manowar' then
    if foe.hp < foe.max * 0.35 and foe.repairs > 0 and chance(opts.chance, 0.8) then
      return 'fix'
    elseif foe.bigshotKegs > 0 and chance(opts.chance, 0.5) then
      return 'bigshot'
    end
    return 'fire'
  elseif foe.class == 'fireship' then
    return 'fire'
  end

  if foe.hp < foe.max * 0.35 and foe.repairs > 0 and chance(opts.chance, 0.8) then
    return 'fix'
  elseif chance(opts.chance, 0.18) then
    return 'move'
  end
  return 'fire'
end

function M.foeAttackDamage(foe, intent, targetRange, isBoss, level, roll)
  roll = roll or 0
  if intent == 'bigshot' then
    local dmg = isBoss and 20 or (14 + level)
    if foe.gunsStage < 0 then dmg = math.max(1, dmg + foe.gunsStage * 2) end
    return dmg
  elseif intent == 'volley' then
    local dmg = 8 + level
    if foe.gunsStage < 0 then dmg = math.max(1, dmg + foe.gunsStage) end
    return dmg
  elseif isBoss then
    local base = 3 + math.floor(level / 2)
    if targetRange ~= 'NEAR' then base = base - 2 end
    local dmg = base + roll
    if foe.gunsStage < 0 then dmg = math.max(1, dmg + foe.gunsStage * 2) end
    return dmg
  end

  local effectiveGuns = M.getEffectiveStat(foe.guns or 1, foe.gunsStage)
  local pwr = (foe.class == 'fireship') and 5 or 7
  if targetRange == 'NEAR' then pwr = pwr + 2 end
  return pwr + effectiveGuns + roll
end

function M.applyShotEffect(target, shotId, timingResult)
  if timingResult == 'miss' then return nil end
  if shotId == 'chain' then
    target.sailsStage = math.max(-2, target.sailsStage - 1)
    return 'sails_down'
  elseif shotId == 'grape' then
    target.gunsStage = math.max(-2, target.gunsStage - 1)
    return 'guns_down'
  elseif shotId == 'fire' then
    if target.immuneAblaze then return 'immune_ablaze' end
    target.ablaze = 3
    return 'ablaze'
  end
  return nil
end

return M
