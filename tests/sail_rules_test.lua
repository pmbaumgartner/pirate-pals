-- Plain-Lua unit tests for sail_rules hidden delights: the retuned
-- 'kingsniff' trigger (same bandana, party >= 3, no more solo-blocked 4+
-- count) and the 'wheee' icy slide-chain counter. Requiring sail_rules
-- pulls in engine/audio/game, which only touch love.* inside function
-- bodies, so a stub love table is enough (same approach as
-- person_battle_test.lua).
package.path = './?.lua;' .. package.path
love = {
  graphics = {},
  math = { random = function() return 0.5 end },
  audio = { newSource = function() return { play = function() end } end },
  sound = { newSoundData = function(len, rate, bits, ch)
    return { setSample = function() end }
  end },
  filesystem = {
    getInfo = function() return nil end,
    write = function() end,
    read = function() return nil end,
  },
}

local grid = require 'src.grid'
local game = require 'src.game'
local meta = require 'src.meta'
local audio = require 'src.audio'
local sailRules = require 'src.states.sail_rules'
audio.muted = true

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

local function freshRun()
  meta.newMeta()
  local t = {}
  for y = 0, game.SEA_H - 1 do
    t[y] = {}
    for x = 0, game.SEA_W - 1 do t[y][x] = game.T_WATER end
  end
  game.run = {
    mode = 'solo',
    hints = {},
    party = {},
    sea = { t = t, biome = 'plain', slick = {}, enemies = {}, boss = false,
      rocks = {}, rockT = 2.5, shipHurt = 0, rocksLanded = 0, rockBonks = 0 },
    ship = { x = 0, y = 0, face = 1 },
  }
  return game.run
end

-- kingsniff: party size >= 3 and every member wears the same bandana.
freshRun()
game.run.sea.boss = true
game.run.party = { { out = 'bandR' }, { out = 'bandR' } }
sailRules.checkKingSniff()
ok(meta.data.secrets.kingsniff == nil, 'kingsniff needs party size >= 3, not just matching bandanas')

freshRun()
game.run.sea.boss = true
game.run.party = { { out = 'bandR' }, { out = 'bandR' }, { out = 'cap' } }
sailRules.checkKingSniff()
ok(meta.data.secrets.kingsniff == nil, 'kingsniff needs every party member to match, not a majority')

freshRun()
game.run.sea.boss = true
game.run.party = { { out = 'bandB' }, { out = 'bandB' }, { out = 'bandB' } }
sailRules.checkKingSniff()
ok(meta.data.secrets.kingsniff == true, 'kingsniff fires for a solo-sized (3) all-matching-bandana party')

freshRun()
game.run.sea.boss = true
game.run.party = { { out = 'cap' }, { out = 'cap' }, { out = 'cap' } }
sailRules.checkKingSniff()
ok(meta.data.secrets.kingsniff == nil, 'kingsniff does not fire for a matching non-bandana outfit')

-- wheee: two chained icy slide continuations (3 hexes traveled) in one hop.
-- Ship rides along row y=0; slick landing tiles at x=1 and x=2 let the slide
-- continue twice before stopping at x=3.
local function fakeCtx(dir)
  return { moveDir = function() return dir end }
end

freshRun()
local run = game.run
run.sea.biome = 'icy'
run.sea.slick[grid.gk(1, 0)] = true
run.sea.slick[grid.gk(2, 0)] = true
local sh = run.ship
local ctx = fakeCtx('right')

sailRules.tickShip(sh, ctx, 'ship', 0.01) -- starts the first hop
ok(sh.slideChain == 0, 'a fresh hop resets the slide chain to 0')
sailRules.tickShip(sh, ctx, 'ship', 0.2) -- finishes hop 1 -> lands on slick (1,0), auto-continues
ok(sh.x == 2 and sh.y == 0, 'landing on a slick hex carries the ship one more hex')
ok(sh.slideChain == 1, 'one continuation increments the slide chain')
ok(meta.data.secrets.wheee == nil, 'a single continuation does not yet earn wheee')

sailRules.tickShip(sh, ctx, 'ship', 0.2) -- finishes the continuation anim -> lands on slick (2,0), continues again
ok(sh.x == 3 and sh.y == 0, 'a second continuation carries the ship a third hex')
ok(sh.slideChain == 2, 'two chained continuations reach a slide chain of 2')
ok(meta.data.secrets.wheee == true, 'a 3-hex chained slide earns wheee')

-- sorryisland: 5 bumps in a row from the same hex earns it; any successful
-- move in between resets the streak.
freshRun()
local run2 = game.run
run2.sea.t[0][1] = game.T_ISLE -- island dead ahead
local sh2 = run2.ship
local bumpCtx = fakeCtx('right')
for i = 1, 4 do
  sailRules.tickShip(sh2, bumpCtx, 'ship', 0.01)
  ok(meta.data.secrets.sorryisland == nil, 'bump ' .. i .. ' alone does not yet earn sorryisland')
end
sailRules.tickShip(sh2, bumpCtx, 'ship', 0.01) -- 5th bump in a row
ok(meta.data.secrets.sorryisland == true, 'a 5th consecutive bump earns sorryisland')
ok(sh2.bumpStreak == 0, 'earning sorryisland resets the bump streak')

freshRun()
run2 = game.run
run2.sea.t[0][1] = game.T_ISLE
sh2 = run2.ship
bumpCtx = fakeCtx('right')
for i = 1, 4 do sailRules.tickShip(sh2, bumpCtx, 'ship', 0.01) end
-- A successful move resets the streak, so 4 more bumps afterward don't add
-- up to 8 -- they restart at 1. Clear the island so the same rightward hop
-- succeeds instead of bumping.
run2.sea.t[0][1] = game.T_WATER
sailRules.tickShip(sh2, bumpCtx, 'ship', 0.01) -- starts the hop onto (1,0)
sailRules.tickShip(sh2, bumpCtx, 'ship', 0.2) -- finishes it -> bumpStreak resets to 0
ok(sh2.x == 1 and sh2.y == 0, 'the hop actually moved the ship this time')
ok(sh2.bumpStreak == 0, 'a successful move resets the bump streak')
run2.sea.t[0][2] = game.T_ISLE -- island now dead ahead again, from the new hex
for i = 1, 4 do sailRules.tickShip(sh2, bumpCtx, 'ship', 0.01) end
ok(meta.data.secrets.sorryisland == nil, 'a broken streak needs a fresh 5 bumps, not a running total')

-- hotfoot: 5+ rocks landed with zero hits on a volcano sea earns it at exit.
freshRun()
local run3 = game.run
run3.sea.biome = 'volcano'
run3.sea.rocksLanded, run3.sea.rockBonks = 4, 0
sailRules.checkHotfoot(run3.sea)
ok(meta.data.secrets.hotfoot == nil, 'hotfoot needs at least 5 rocks landed')

freshRun()
run3 = game.run
run3.sea.biome = 'volcano'
run3.sea.rocksLanded, run3.sea.rockBonks = 5, 1
sailRules.checkHotfoot(run3.sea)
ok(meta.data.secrets.hotfoot == nil, 'any rock hit blocks hotfoot')

freshRun()
run3 = game.run
run3.sea.biome = 'volcano'
run3.sea.rocksLanded, run3.sea.rockBonks = 5, 0
sailRules.checkHotfoot(run3.sea)
ok(meta.data.secrets.hotfoot == true, '5+ landed rocks with zero hits earns hotfoot')

-- updateRocks feeds those same counters: a landed rock always bumps
-- rocksLanded, and only a hit on the ship's hex bumps rockBonks too.
freshRun()
local run4 = game.run
run4.sea.biome = 'volcano'
run4.sea.rockT = 999 -- suppress spawning a new rock this tick
run4.sea.rocks = { { x = 5, y = 5, t = 0.01 } } -- lands, ship not there -> miss
sailRules.updateRocks(0.1)
ok(run4.sea.rocksLanded == 1, 'a landed rock increments rocksLanded')
ok(run4.sea.rockBonks == 0, 'a miss does not increment rockBonks')

run4.sea.rockT = 999
run4.sea.rocks = { { x = 0, y = 0, t = 0.01 } } -- lands right on the ship -> hit
sailRules.updateRocks(0.1)
ok(run4.sea.rocksLanded == 2, 'a second landed rock increments rocksLanded again')
ok(run4.sea.rockBonks == 1, 'a hit on the ship increments rockBonks')

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('sail_rules_test OK')
