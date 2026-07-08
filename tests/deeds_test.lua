-- Plain-Lua unit tests for DEEDS: data-shape, game.deedTick/deedFlag/earnDeed
-- idempotency, and the meta round-trip of deeds/counts. Mirrors
-- secrets_test.lua's stub-love approach. Run: `lua tests/deeds_test.lua`.
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
local data = require 'src.data'
local meta = require 'src.meta'
local game = require 'src.game'
local audio = require 'src.audio'
local serialize = require 'src.serialize'
audio.muted = true

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

-- Data shape: every DEEDS entry has an id and a name, ids are unique, and
-- counter/collection deeds carry a goal.
local seen = {}
for _, d in ipairs(data.DEEDS) do
  ok(d.id ~= nil and d.id ~= '', 'deed has a non-empty id')
  ok(d.name ~= nil and d.name ~= '', d.id .. ' has a non-empty name')
  ok(d.goalText ~= nil and d.goalText ~= '', d.id .. ' has a non-empty goalText')
  ok(not seen[d.id], d.id .. ' is not a duplicate id')
  seen[d.id] = true
  if d.key then ok(type(d.goal) == 'number', d.id .. ' has a numeric goal for its counter key') end
  if d.flagKeys then ok(type(d.goal) == 'number', d.id .. ' has a numeric goal for its flag set') end
end

-- game.deedTick: increments meta.data.counts[key], fires the deed exactly
-- once it reaches goal, and further ticks are no-ops (count shape only).
meta.newMeta()
local counterId = 'shipwrecker'
local counterKey = 'shipsSunk'
for i = 1, 14 do
  game.deedTick(counterKey, 15, counterId)
end
ok(meta.data.counts[counterKey] == 14, 'deedTick bumps the counter each call')
ok(meta.data.deeds[counterId] == nil, 'deedTick has not fired before the goal')
game.deedTick(counterKey, 15, counterId)
ok(meta.data.counts[counterKey] == 15, 'deedTick counts the goal-reaching tick')
ok(meta.data.deeds[counterId] == true, 'deedTick fires exactly at goal')
game.deedTick(counterKey, 15, counterId)
ok(meta.data.deeds[counterId] == true, 'a repeat deedTick past goal is still a no-op-safe true')

-- game.earnDeed idempotency, mirroring foundSecret.
meta.newMeta()
local boolId = data.DEEDS[1].id
ok(meta.data.deeds[boolId] == nil, 'fresh meta has no deeds earned yet')
game.earnDeed(boolId)
ok(meta.data.deeds[boolId] == true, 'earnDeed marks the id done')
game.earnDeed(boolId)
ok(meta.data.deeds[boolId] == true, 'a repeat earnDeed call is a no-op')
ok(game.distinctDeeds() == 1, 'distinctDeeds counts earned deeds')

-- game.deedFlag: a collection deed only completes once every flag is set.
meta.newMeta()
local flagKeys = { 'biome_calm', 'biome_icy', 'biome_foggy', 'biome_volcano' }
game.deedFlag('biome_calm', flagKeys, 'seenseas')
game.deedFlag('biome_icy', flagKeys, 'seenseas')
game.deedFlag('biome_foggy', flagKeys, 'seenseas')
ok(meta.data.deeds.seenseas == nil, 'deedFlag has not fired with one flag still missing')
game.deedFlag('biome_volcano', flagKeys, 'seenseas')
ok(meta.data.deeds.seenseas == true, 'deedFlag fires once every flag is set')

-- Meta round-trip: deeds/counts survive serialize like secrets/hats/etc.
local encoded = serialize.encode(meta.data)
local decoded = serialize.decode(encoded)
ok(decoded.deeds.seenseas == true, 'meta round-trips an earned deed through serialize')
ok(decoded.counts.biome_calm == 1, 'meta round-trips a counts flag through serialize')

-- meta.load() defaults deeds/counts to {} for saves written before these
-- fields existed, mirroring how secrets/hats/voyagesWon/etc default on load.
local savedNoDeeds = { version = 1 }
local origRead = love.filesystem.read
love.filesystem.read = function() return serialize.encode(savedNoDeeds) end
meta.load()
ok(type(meta.data.deeds) == 'table', 'meta.load() defaults a missing deeds field to a table')
ok(type(meta.data.counts) == 'table', 'meta.load() defaults a missing counts field to a table')
love.filesystem.read = origRead

-- KRAKEN TAMER reward unlock: routes through game.unlockHat like any other
-- deed reward.
meta.newMeta()
game.run = { owned = {} }
game.earnDeed('krakentamer')
ok(meta.data.hats.kraken == true, 'krakentamer reward unlocks KRAKEN CAP')

-- All-deeds prize: GOLD BANDANA unlocks only once every deed in data.DEEDS
-- is earned, and not a moment before.
meta.newMeta()
game.run = { owned = {} }
for _, d in ipairs(data.DEEDS) do
  if d.id ~= data.DEEDS[#data.DEEDS].id then game.earnDeed(d.id) end
end
ok(not meta.data.hats.goldband, 'GOLD BANDANA is not granted before the last deed is earned')
game.earnDeed(data.DEEDS[#data.DEEDS].id)
ok(meta.data.hats.goldband == true, 'earning every deed unlocks GOLD BANDANA')

-- Retro-grant: an older save with every deed already earned before this
-- reward existed should backfill GOLD BANDANA on load.
local allDeeds = {}
for _, d in ipairs(data.DEEDS) do allDeeds[d.id] = true end
local savedAllDone = { version = 1, deeds = allDeeds, hats = {} }
love.filesystem.read = function() return serialize.encode(savedAllDone) end
meta.load()
ok(meta.data.hats.goldband == true,
  'meta.load() retro-grants GOLD BANDANA once every deed is already earned')
love.filesystem.read = origRead

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('deeds_test OK')
