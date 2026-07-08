-- Plain-Lua unit tests for the "Grandma and the Pirates" questline:
-- data shape (ROLES.grandma/SECRETS/PERKS), Oliver's island tile placement
-- and the shaky-box enemy marker in game.genSea, the serialize round-trip
-- of the run flags, and newGamePlus filtering grandma out of carryover.
-- Requiring game pulls in engine/audio, which only touch love.* inside
-- function bodies, so a stub table is enough (same approach as
-- secrets_test.lua). genSea's placement retries need real variation to
-- converge, so love.math.random is backed by seeded math.random rather than
-- a fixed value (same approach as colors_test.lua). Run: `lua tests/grandma_test.lua`.
package.path = './?.lua;' .. package.path
math.randomseed(7)
love = {
  graphics = {},
  math = { random = function(a, b)
    if a then return math.random(a, b) end
    return math.random()
  end },
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
local data = require 'src.data'
local game = require 'src.game'
local meta = require 'src.meta'
local audio = require 'src.audio'
audio.muted = true

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

-- Data shape: ROLES.grandma has the documented stats and specials.
local role = data.ROLES.grandma
ok(role ~= nil, 'data.ROLES.grandma exists')
ok(role.label == 'GRANDMA', 'grandma role label is GRANDMA')
ok(role.hp == 13 and role.atk == 4 and role.move == 3 and role.range == 1,
  'grandma role has hp 13, atk 4, move 3, range 1')
ok(role.spec and role.spec.name == 'NOODLE WHIP', 'grandma role has the NOODLE WHIP special')
ok(role.ship and role.ship.name == 'NOODLE PUDDING CATAPULT', 'grandma role has the NOODLE PUDDING CATAPULT ship special')

-- SECRETS: the grandma entry has a hint and a slot, and (unlike
-- fishfriend/seashell) no reward -- rescuing her is its own reward.
local secret = data.secretById('grandma')
ok(secret ~= nil, "secretById('grandma') exists")
ok(secret.name == 'GRANDMA ABOARD!', 'grandma secret has the expected name')
ok(secret.hint ~= nil and secret.hint ~= '', 'grandma secret has a non-empty hint')
ok(secret.slot == 'slot_grandma', 'grandma secret has slot_grandma')
ok(secret.reward == nil, 'grandma secret has no reward (the rescue itself is the payoff)')

-- PERKS: grandma gets the same milestone-level perk pairs as every other role.
ok(data.PERKS.grandma ~= nil, 'data.PERKS.grandma exists')
for _, lvl in ipairs({ 2, 4, 6 }) do
  local pair = data.PERKS.grandma[lvl]
  ok(pair ~= nil and #pair == 2, 'grandma has a perk pair at level ' .. lvl)
end

-- statsOf: hp/atk scale with level the same as every other role.
local gran = game.makePirate('grandma', 'GRANDMA', 4)
local st = game.statsOf(gran)
ok(st.hp == 19, 'level-4 grandma has 13 + 2*3 = 19 hp, got ' .. tostring(st.hp))
ok(st.atk == 7, 'level-4 grandma has 4 + 3 = 7 atk, got ' .. tostring(st.atk))
ok(st.move == 3, 'grandma keeps her base move of 3')
ok(st.range == 1, 'grandma keeps her base range of 1')

-- Oliver placement: on a long-enough voyage, sea 3/4 generation places a
-- T_OLIVER tile somewhere on the map while the quest is still unstarted.
local function freshVoyageRun(length)
  meta.newMeta()
  game.newGame('solo')
  game.run.voyage.length = length
  return game.run
end

local function findTile(t, tile)
  for y = 0, game.SEA_H - 1 do
    for x = 0, game.SEA_W - 1 do
      if t[y][x] == tile then return true end
    end
  end
  return false
end

-- placeSpecials retries the whole board on every genSea attempt, and a
-- crowded board can (rarely) leave Oliver unplaced on any single generation
-- even though the quest is eligible; regenerate a few times and require the
-- tile to show up at least once, rather than assuming the first roll lands.
local run = freshVoyageRun(8)
local sawOliver = false
for _ = 1, 10 do
  game.genSea(3)
  if findTile(run.sea.t, game.T_OLIVER) then sawOliver = true; break end
end
ok(sawOliver, 'genSea(3) places a T_OLIVER tile on a long voyage with the quest unstarted')

-- Once grandmaQuest is set (she's already been found), sea 3 never places
-- another Oliver island -- the quest has moved on to the shaky-box phase.
run.grandmaQuest = true
game.genSea(3)
ok(not findTile(run.sea.t, game.T_OLIVER), 'genSea(3) places no T_OLIVER once grandmaQuest is set')

-- Shaky box: once grandmaQuest is on and she's not yet rescued, exactly one
-- enemy on non-boss seas >= 5 carries grandmaBox.
local function countBoxes(enemies)
  local n = 0
  for _, e in ipairs(enemies) do if e.grandmaBox then n = n + 1 end end
  return n
end

run = freshVoyageRun(8)
run.grandmaQuest = true
game.genSea(5)
ok(countBoxes(run.sea.enemies) == 1, 'genSea(5) marks exactly one enemy with grandmaBox while the quest is active')

-- Once rescued, the box never reappears.
run.grandmaRescued = true
game.genSea(5)
ok(countBoxes(run.sea.enemies) == 0, 'genSea(5) marks no grandmaBox enemy once grandmaRescued is set')

-- The box only rides seas >= 5, even with the quest active.
run = freshVoyageRun(8)
run.grandmaQuest = true
game.genSea(2)
ok(countBoxes(run.sea.enemies) == 0, 'genSea(2) never marks a grandmaBox enemy, quest active or not')

-- Serialization: the run flags (and a marked enemy) survive a round-trip
-- through the same snapshot/restore path save.lua uses (shapeRun/unshapeRun
-- via serialize.encode/decode), mirroring secrets_test's meta round-trip.
run = freshVoyageRun(8)
run.grandmaQuest = true
run.grandmaRescued = true
game.genSea(5) -- no box will be marked since grandmaRescued is set; force one for the test
run.sea.enemies[1] = run.sea.enemies[1] or { x = 0, y = 0, lv = 5 }
run.sea.enemies[1].grandmaBox = true

game.snapshot()
game.restore()
ok(game.run.grandmaQuest == true, 'run.grandmaQuest survives a serialize round-trip')
ok(game.run.grandmaRescued == true, 'run.grandmaRescued survives a serialize round-trip')
ok(game.run.sea.enemies[1].grandmaBox == true, 'enemy.grandmaBox survives a serialize round-trip')

-- newGamePlus: grandma never carries over into the next voyage's crew, even
-- if she was in the previous run's crew alongside normal pals.
meta.newMeta()
game.newGame('solo')
local cap = game.run.crew[1]
game.run.crew = { cap, game.makePirate('grandma', 'GRANDMA', 3), game.makePirate('medic', 'DOC', 2) }
game.newGamePlus()
for _, p in ipairs(game.run.crew) do
  ok(p.role ~= 'grandma', 'newGamePlus never carries a grandma role into the new crew')
end

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('grandma_test OK')
