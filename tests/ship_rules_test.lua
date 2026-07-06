package.path = './?.lua;' .. package.path
love = {
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

local data = require 'src.data'
local game = require 'src.game'
local shipRules = require 'src.ship_rules'

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

-- 1. Test data tables
ok(data.SHOTS ~= nil, 'data.SHOTS exists')
ok(data.SHOTS.round.power == 7, 'ROUND SHOT power is 7')
ok(data.SHOTS.chain.power == 4, 'CHAIN SHOT power is 4')
ok(data.SHOTS.grape.power == 3, 'GRAPE SHOT power is 3')
ok(data.SHOTS.fire.power == 5, 'FIRE SHOT power is 5')

ok(data.SHIPCLASSES ~= nil, 'data.SHIPCLASSES exists')
ok(data.SHIPCLASSES.sloop.hullBase == 24, 'SLOOP hullBase is 24')
ok(data.SHIPCLASSES.brig.hullScale == 8, 'BRIG hullScale is 8')
ok(data.SHIPCLASSES.fireship.weak == 'round', 'FIRESHIP weakness is round')
ok(data.SHIPCLASSES.manowar.armor == 1, 'MAN-O-WAR armor is 1')

ok(data.KING ~= nil, 'data.KING exists')
ok(data.KING.hull == 120, 'KING hull is 120')
ok(data.KING.fleetHull == 180, 'KING fleetHull is 180')
ok(data.KING.kraken.weak == 'chain', 'KING.kraken weak is chain')

-- 2. Test game initialization
game.newGame('solo')
ok(game.run.salvage ~= nil, 'game.run.salvage exists')
ok(game.run.salvage.timber == 0, 'game.run.salvage.timber starts at 0')
ok(game.run.fittings ~= nil, 'game.run.fittings exists')
ok(game.run.fittings.hull == 0, 'game.run.fittings.hull starts at 0')
ok(game.run.fittings.slot == nil, 'game.run.fittings.slot starts at nil')
ok(game.run.blueprints ~= nil, 'game.run.blueprints exists')
ok(game.run.bossFlotsam ~= nil, 'game.run.bossFlotsam exists')

-- 3. Test ship_rules helpers
game.newGame('solo')
ok(shipRules.getFittingTier('hull') == 0, 'fitting tier default is 0')
game.run.fittings.hull = 2
ok(shipRules.getFittingTier('hull') == 2, 'fitting tier retrieves correctly')

ok(shipRules.getFittingBonus('hull', 2) == 12, 'hull bonus tier 2 is 12')
ok(shipRules.getFittingBonus('sails', 3) == 3, 'sails bonus tier 3 is 3')
ok(shipRules.getFittingBonus('guns', 1) == 1, 'guns bonus tier 1 is 1')

-- Test stats calculations
game.run.fittings.hull = 2
game.run.fittings.sails = 1
game.run.fittings.guns = 3

-- Setup captain level 4
for _, p in ipairs(game.run.party) do
  if p.role == 'captain' then
    p.lvl = 4
  end
end

ok(shipRules.getPlayerHullMax(1) == 30 + 12, 'hull max is 30 + 12 = 42') -- base ship max HP is 30 (default meta)
ok(shipRules.getPlayerSails(1) == 1 + 1, 'sails is 1 + 1 = 2')
ok(shipRules.getPlayerGuns(1) == 1 + 3 + math.floor(4 / 2), 'guns is 1 + 3 + 2 = 6')

-- 4. Test known shots and blueprints
ok(shipRules.isShotKnown('round') == true, 'round is always known')
ok(shipRules.isShotKnown('chain') == false, 'chain is not known initially')
ok(shipRules.getKnownShots()[1] == 'round' and #shipRules.getKnownShots() == 1, 'only round is known')

game.run.blueprints.chain = true
ok(shipRules.hasBlueprint('chain') == true, 'chain blueprint collected')
ok(shipRules.hasBlueprint('grape') == false, 'grape blueprint not collected')

game.run.fittings.slot = 'chain'
ok(shipRules.isShotKnown('chain') == true, 'chain is now known when slotted')
ok(#shipRules.getKnownShots() == 2 and shipRules.getKnownShots()[2] == 'chain', 'round and chain are known')

-- 5. Test damage preview
-- min/max for round (power 7) near (power + 2 = 9), guns 6, armor 0, no weak/resist:
-- baseMin = 9 + 6 - 0 = 15. baseMax = 17.
local dMin, dMax = shipRules.getDamagePreview('round', 'NEAR', 6, 0, false, false)
ok(dMin == 15 and dMax == 17, 'ROUND NEAR damage preview is 15-17')

-- with armor 2: baseMin = 9 + 6 - 2 = 13. baseMax = 15.
dMin, dMax = shipRules.getDamagePreview('round', 'NEAR', 6, 2, false, false)
ok(dMin == 13 and dMax == 15, 'ROUND NEAR vs armor 2 damage preview is 13-15')

-- with weak: mult 1.5. baseMin = 15 * 1.5 = 22.5 -> 22. baseMax = 17 * 1.5 = 25.5 -> 25.
dMin, dMax = shipRules.getDamagePreview('round', 'NEAR', 6, 0, true, false)
ok(dMin == 22 and dMax == 25, 'ROUND NEAR weak damage preview is 22-25')

-- with resisted: mult 0.75. baseMin = 15 * 0.75 = 11.25 -> 11. baseMax = 17 * 0.75 = 12.75 -> 12.
dMin, dMax = shipRules.getDamagePreview('round', 'NEAR', 6, 0, false, true)
ok(dMin == 11 and dMax == 12, 'ROUND NEAR resisted damage preview is 11-12')

-- 6. Test enemy class stats
local eStats = shipRules.getEnemyClassStats('sloop', 3)
ok(eStats ~= nil, 'sloop stats exists')
ok(eStats.maxHp == 24 + 8 * 3, 'sloop hp scales correctly: 48')
ok(eStats.guns == 2, 'sloop guns is 2')
ok(eStats.sails == 3, 'sloop sails is 3')
ok(eStats.weak == 'chain', 'sloop weak is chain')
ok(eStats.armor == 0, 'sloop armor is 0')

-- 7. Test stage clamping and effective stats
ok(shipRules.clampStage(0) == 0, 'stage 0 clamp is 0')
ok(shipRules.clampStage(-1) == -1, 'stage -1 clamp is -1')
ok(shipRules.clampStage(-2) == -2, 'stage -2 clamp is -2')
ok(shipRules.clampStage(-3) == -2, 'stage -3 clamps to -2')
ok(shipRules.clampStage(1) == 1, 'stage 1 clamps to 1')
ok(shipRules.clampStage(2) == 1, 'stage 2 clamps to 1')

ok(shipRules.getEffectiveStat(3, 0) == 3, 'effective stat sails 3, stage 0 is 3')
ok(shipRules.getEffectiveStat(3, -1) == 2, 'effective stat sails 3, stage -1 is 2')
ok(shipRules.getEffectiveStat(3, -2) == 1, 'effective stat sails 3, stage -2 is 1')
ok(shipRules.getEffectiveStat(3, -3) == 1, 'effective stat sails 3, stage -3 clamps to 1')
ok(shipRules.getEffectiveStat(1, -2) == 0, 'effective stat sails 1, stage -2 clamps to 0')

-- 8. Test dodge quality
-- sails = 1 + tier. tier = sails - 1.
-- effective sails 3 (tier 2), stage 0 -> tier 2. Dodge = 0.4 + 2 * 0.15 = 0.70.
ok(math.abs(shipRules.getDodgeChance(3, 0, false) - 0.70) < 0.001, 'dodge chance sails 3, stage 0 is 0.70')
ok(math.abs(shipRules.getDodgeChance(3, -1, false) - 0.55) < 0.001, 'dodge chance sails 3, stage -1 is 0.55')
ok(math.abs(shipRules.getDodgeChance(3, -2, false) - 0.40) < 0.001, 'dodge chance sails 3, stage -2 is 0.40')
ok(math.abs(shipRules.getDodgeChance(3, -3, false) - 0.40) < 0.001, 'dodge chance sails 3, stage -3 is 0.40')
ok(math.abs(shipRules.getDodgeChance(1, -2, false) - 0.40) < 0.001, 'dodge chance sails 1, stage -2 is 0.40')
-- big threat should always dodge (1.0)
ok(shipRules.getDodgeChance(3, 0, true) == 1.0, 'dodge chance under big threat is 1.0')

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('ship_rules_test OK')
