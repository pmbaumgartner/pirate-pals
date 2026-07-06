local data = require 'src.data'
local game = require 'src.game'
local meta = require 'src.meta'

local M = {}

-- Returns the tier (0, 1, 2, or 3) of a given fitting ('hull', 'sails', 'guns')
function M.getFittingTier(fittingType)
  if not game.run or not game.run.fittings then return 0 end
  return game.run.fittings[fittingType] or 0
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
  local tier = M.getFittingTier('hull')
  local bonus = M.getFittingBonus('hull', tier)
  return meta.shipMaxHp() + bonus
end

-- Calculates the SAILS stat for player ship index (1 or 2)
function M.getPlayerSails(shipIndex)
  local tier = M.getFittingTier('sails')
  local bonus = M.getFittingBonus('sails', tier)
  return 1 + bonus
end

-- Calculates the GUNS stat for player ship index (1 or 2)
function M.getPlayerGuns(shipIndex)
  local tier = M.getFittingTier('guns')
  local bonus = M.getFittingBonus('guns', tier)
  local capLevel = 1
  if game.run and game.run.party then
    if game.run.mode == 'captains' then
      local owner = (shipIndex == 2) and 'p2' or 'p1'
      for _, p in ipairs(game.run.party) do
        if p.role == 'captain' and game.ownerOf(p) == owner then
          capLevel = p.lvl
          break
        end
      end
    else
      -- Solo: check first captain
      for _, p in ipairs(game.run.party) do
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
  if shotId == 'round' then return true end
  if game.run and game.run.fittings and game.run.fittings.slot == shotId then
    return true
  end
  return false
end

-- Returns the list of shot IDs known in battle
function M.getKnownShots()
  local list = { 'round' }
  if game.run and game.run.fittings and game.run.fittings.slot then
    list[#list + 1] = game.run.fittings.slot
  end
  return list
end

-- Checks if a blueprint has been collected/unlocked
function M.hasBlueprint(shotId)
  if not game.run or not game.run.blueprints then return false end
  return game.run.blueprints[shotId] == true
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

-- Calculates the effective stat after applying a stage modifier.
-- We clamp the stage to [-2, 0] since it's debuff-only and max debuff is -2.
function M.clampStage(stage)
  return math.max(-2, math.min(0, stage or 0))
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

return M


