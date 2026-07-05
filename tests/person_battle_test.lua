-- Plain-Lua unit tests for the boarding-battle intent/preview pipeline:
-- previewDamage must agree with damage()'s own modifier chain,
-- and nextFoe must follow a planned intent while surviving a KO'd target.
-- Requiring person_battle/model.lua and ai.lua pulls in engine/audio/game,
-- which only touch love.* inside functions we never call here, so a stub
-- love table is enough (same approach as timing_test.lua).
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

local audio = require 'src.audio'
audio.muted = true -- silence SFX so model.damage()/ai calls don't touch love.sound

local grid = require 'src.grid'
local S = require 'src.states.person_battle.state'
local model = require 'src.states.person_battle.model'
local ai = require 'src.states.person_battle.ai'

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

local function mkUnit(fields)
  local u = {
    side = 'p', alive = true, hp = 10, max = 10, atk = 5, buff = 0, guard = false,
    x = 0, y = 0, role = 'deckhand', move = 3, range = 1, acted = false,
  }
  for k, v in pairs(fields) do u[k] = v end
  return u
end

local function freshPb(units, crates)
  S.pb = { units = units, crates = crates or {}, hazards = {}, flags = {}, defeated = {}, ox = 0, oy = 0 }
end

-- previewDamage/damage agreement: resolved 'good' damage must land in
-- [lo, hi] across guard/shell/cover combos.
local function checkAgreement(att, def, crates, label)
  freshPb({ att, def }, crates)
  local pv = model.previewDamage(att, def, att.atk + att.buff, {})
  local before = def.hp
  model.damage(att, def, att.atk + att.buff, 'good', {})
  local dealt = before - def.hp
  ok(dealt >= pv.lo and dealt <= pv.hi,
    label .. ': resolved dmg ' .. dealt .. ' should fall in [' .. pv.lo .. ',' .. pv.hi .. ']')
end

checkAgreement(
  mkUnit({ side = 'p', x = 3, y = 0, atk = 6 }),
  mkUnit({ side = 'e', x = 4, y = 0, hp = 30, max = 30 }),
  nil, 'plain hit')

checkAgreement(
  mkUnit({ side = 'p', x = 3, y = 0, atk = 6 }),
  mkUnit({ side = 'e', x = 4, y = 0, hp = 30, max = 30, guard = true }),
  nil, 'guarded target')

-- Crab shell: frontal (attacker at/left of crab.x) halves; flank (attacker
-- right of crab.x) doesn't.
local crabFront = mkUnit({ side = 'e', role = 'crab', x = 4, y = 0, hp = 30, max = 30 })
checkAgreement(mkUnit({ side = 'p', x = 3, y = 0, atk = 6 }), crabFront, nil, 'crab frontal (SHELL)')
local pvFront = model.previewDamage(mkUnit({ side = 'p', x = 3, y = 0, atk = 6 }), crabFront, 6, {})
local sawShell = false
for _, n in ipairs(pvFront.notes) do if n == 'SHELL' then sawShell = true end end
ok(sawShell, 'frontal crab preview notes SHELL')

local crabFlank = mkUnit({ side = 'e', role = 'crab', x = 4, y = 0, hp = 30, max = 30 })
local flankAtt = mkUnit({ side = 'p', x = 5, y = 0, atk = 6 })
local pvFlank = model.previewDamage(flankAtt, crabFlank, 6, {})
local sawFlankShell = false
for _, n in ipairs(pvFlank.notes) do if n == 'SHELL' then sawFlankShell = true end end
ok(not sawFlankShell, 'flanking crab preview has no SHELL note')

-- Cover: an adjacent crate to a non-adjacent attacker halves damage, unless
-- ignoreCover (LONGSHOT) is set.
local coverDef = mkUnit({ side = 'e', x = 6, y = 0, hp = 30, max = 30 })
local coverAtt = mkUnit({ side = 'p', x = 3, y = 0, atk = 6 })
checkAgreement(coverAtt, coverDef, { [grid.gk(7, 0)] = true }, 'covered target')
local pvCover = model.previewDamage(coverAtt, coverDef, 6, {})
ok(pvCover.notes[1] == 'COVER', 'covered preview notes COVER')
local pvIgnoreCover = model.previewDamage(coverAtt, coverDef, 6, { ignoreCover = true })
ok(#pvIgnoreCover.notes == 0, 'ignoreCover preview drops the COVER note')

-- Intent-follow: plan intents, then KO the intended target before the foe
-- turn runs; nextFoe must fall back to a legal target instead of crashing
-- or attacking a corpse.
local function freshBoardingPb()
  local p1 = mkUnit({ side = 'p', x = 0, y = 2, hp = 20, max = 20 })
  local p2 = mkUnit({ side = 'p', x = 0, y = 3, hp = 20, max = 20 })
  local foe = mkUnit({ side = 'e', x = 1, y = 2, hp = 20, max = 20, atk = 3, range = 1, move = 2 })
  local classicDeck = model.buildDeck('classic')
  S.pb = {
    units = { p1, p2, foe }, crates = {}, hazards = {}, flags = {}, defeated = {},
    deck = classicDeck.deck, deckList = classicDeck.deckList, eastEdge = classicDeck.eastEdge,
    w = classicDeck.w, h = classicDeck.h,
    over = false, phase = 'foe', queue = {}, wait = 0, next = nil, lv = 1,
    pl = { p1 = { sel = nil }, p2 = { sel = nil } }, ox = 0, oy = 0,
  }
  return p1, p2, foe
end

local p1, _, foe = freshBoardingPb()
ai.planFoeIntents()
ok(foe.intent ~= nil and foe.intent.kind == 'attack' and foe.intent.target == p1,
  'plans an attack on the nearer party unit')

-- KO the intended target, then run the foe turn headless via the public
-- entry point (startFoePhase); pumpForTest drains the foe-turn coroutine
-- (pb.co) in one call instead of the real per-frame update() loop.
p1.alive = false
local ranOk, err = pcall(function()
  ai.startFoePhase()
  ai.pumpForTest()
end)
ok(ranOk, 'foe turn runs without error after its intended target is koed: ' .. tostring(err))
ok(p1.hp == 20, 'the dead intended target takes no damage')

-- Deck mask: thief escape fires at the mask's own east edge, not a
-- hardcoded column — lshape's top rows are narrower than the full width.
local game = require 'src.game'
local lshape = model.buildDeck('lshape')
ok(lshape.eastEdge[0] < lshape.w - 1,
  'lshape row 0 should have a shorter east edge than the full deck width')
game.run = { gold = 10 }
local thiefEdge = lshape.eastEdge[0]
local thief = mkUnit({ side = 'e', role = 'thief', x = thiefEdge, y = 0, loot = 5, move = 0, alive = true })
local bystander = mkUnit({ side = 'p', x = 0, y = 4, hp = 20, max = 20 })
S.pb = {
  units = { bystander, thief }, crates = {}, hazards = {}, flags = {}, defeated = {},
  deck = lshape.deck, deckList = lshape.deckList, eastEdge = lshape.eastEdge,
  w = lshape.w, h = lshape.h, ox = 0, oy = 0,
  over = false, phase = 'foe', queue = { thief }, wait = 0, next = nil, lv = 1,
  pl = { p1 = { sel = nil, cursor = { x = 0, y = 0 } }, p2 = { sel = nil, cursor = { x = 0, y = 0 } } },
}
-- Escaping the thief drops enemy count to 0, which would otherwise route
-- through the full victory/transition machinery this unit test doesn't set
-- up (game.run.party, etc.) — stub checkEnd so only the escape math is exercised.
local origCheckEnd = model.checkEnd
model.checkEnd = function() return false end
local ranOk2, err2 = pcall(function()
  ai.startFoePhase()
  ai.pumpForTest()
end)
model.checkEnd = origCheckEnd
ok(ranOk2, 'thief turn runs without error at the mask edge: ' .. tostring(err2))
ok(thief.escaped, 'thief should escape once at the mask east edge, regardless of column')
ok(game.run.gold == 5, 'escaping thief should take its held gold')

-- Shove-into-hole: sliding toward a hole/mask edge stops on the edge tile,
-- then the shared impact helper applies SPLASH damage/soggy/loot-drop.
local gangplank = model.buildDeck('gangplank')
ok(not gangplank.deck[grid.gk(5, 0)], 'expected a hole at (5,0) in the gangplank template')
local pusher = mkUnit({ side = 'p', x = 3, y = 0 })
local pushed = mkUnit({ side = 'e', role = 'thief', x = 4, y = 0, hp = 10, loot = 5 })
S.pb = { units = { pusher, pushed }, crates = {}, hazards = {}, flags = {}, defeated = {}, deck = gangplank.deck, ox = 0, oy = 0 }
local shove = model.slideTarget(pusher, pushed, 2)
ok(gangplank.deck[grid.gk(shove.x, shove.y)] ~= nil, 'shoved target must land on a deck tile, not a hole')
ok(shove.x == 4 and shove.y == 0 and shove.steps == 0 and shove.impact.kind == 'splash',
  'shove into adjacent hole stops at edge and returns a splash impact')
pushed.x, pushed.y = shove.x, shove.y
model.applySlideImpact(pushed, shove.impact)
ok(pushed.soggy, 'shoved unit should be soggy')
ok(pushed.hp == 3, 'shoved unit should take 7 damage from splash')
ok(pushed.loot == nil, 'soggy thief should drop carried gold')

-- Perch range is the canonical attack range, not a call-site convention.
local shooter = mkUnit({ side = 'p', x = 2, y = 2, range = 3 })
local farFoe = mkUnit({ side = 'e', x = 6, y = 2 })
freshPb({ shooter, farFoe })
S.pb.perch = { 2, 2 }
ok(model.attackRange(shooter) == 4, 'perch adds +1 range to ranged units')
ok(model.canAttack(shooter, farFoe), 'canAttack uses perch-boosted range')

-- Test crate smash
local crateAttacker = mkUnit({ side = 'p', x = 1, y = 1 })
S.pb.crates[grid.gk(2, 1)] = true
model.smashCrate(crateAttacker, 2, 1)
ok(S.pb.crates[grid.gk(2, 1)] == nil, 'crate should be removed after smash')

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('person_battle_test OK')
