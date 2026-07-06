-- Plain-Lua unit tests for game.logMoment (Voyage Log): entry shape,
-- sea stamping, and the 40-entry cap keeping "first" milestones over
-- routine repeats. game.lua pulls in engine/audio, which only touch love.*
-- inside function bodies, so a stub table is enough to load them (same
-- approach as person_battle_test.lua).
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
local game = require 'src.game'
local serialize = require 'src.serialize'

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

game.run = { voyage = { sea = 3 }, log = {} }
game.logMoment('gemS', 'SEA 3: BONES + PEG = BEST MATES!', { 'BONES', 'PEG' })
ok(#game.run.log == 1, 'logMoment appends one entry')
local e = game.run.log[1]
ok(e.sea == 3, 'entry stamps the current voyage sea')
ok(e.icon == 'gemS', 'entry keeps the icon sprite key')
ok(e.text == 'SEA 3: BONES + PEG = BEST MATES!', 'entry keeps the caption text')
ok(e.pals[1] == 'BONES' and e.pals[2] == 'PEG', 'entry keeps pal names, not references')
ok(not e.first, 'entry is not flagged first unless asked')

game.logMoment('flagW', 'SEA 1: PEG JOINED THE CREW!', { 'PEG' }, true)
ok(game.run.log[2].first == true, 'first flag is recorded when passed')

-- Cap at 40: filling past the cap drops the oldest non-first entry, but
-- the first-flagged entries above survive.
game.run = { voyage = { sea = 1 }, log = {} }
game.logMoment('flagW', 'SEA 1: FIRST!', {}, true)
for i = 1, 45 do
  game.logMoment('coinS', 'SEA 1: CLEARED THE SEA! ' .. i, {})
end
ok(#game.run.log <= 40, 'log never grows past the 40-entry cap')
ok(game.run.log[1].first == true, 'the first-flagged entry survives the cap')

-- A run with log entries (and a meta with legends) still encodes/decodes
-- intact through the plain-data serializer -- strings only, no functions or
-- shared references, which is why entries store pal names.
local meta = require 'src.meta'
meta.data.legends = { PEG = { 'SEA 1: PEG JOINED THE CREW!' } }
local runOut = serialize.decode(serialize.encode(game.run))
ok(#runOut.log == 40, 'run.log round-trips through serialize')
ok(runOut.log[1].icon == 'flagW', 'round-tripped entry keeps its icon')
ok(runOut.log[1].pals ~= nil, 'round-tripped entry keeps its pals list')
local metaOut = serialize.decode(serialize.encode(meta.data))
ok(metaOut.legends.PEG[1] == 'SEA 1: PEG JOINED THE CREW!', 'meta.legends round-trips through serialize')

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('log_test OK')
