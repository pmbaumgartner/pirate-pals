-- Plain-Lua unit tests for bark data shape (src/data.lua) and delivery
-- (src/barks.lua). barks.lua's transitive requires (audio/engine/font) only
-- touch love.* inside function bodies, so a stub table is enough to load
-- them. Run from the project root: `lua tests/barks_test.lua`.
package.path = './?.lua;' .. package.path
love = {
  graphics = {},
  math = { random = function() return 0.5 end },
  audio = { newSource = function() return { play = function() end } end },
  sound = { newSoundData = function(len, rate, bits, ch)
    return { setSample = function() end }
  end },
}
local data = require 'src.data'
local barks = require 'src.barks'
local engine = require 'src.engine'

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

-- Every player role + king has every trigger; every line is a short,
-- non-empty, ALL-CAPS floater (allowing digits/punctuation).
local ROLES = { 'captain', 'deckhand', 'strongman', 'sharpshooter', 'medic', 'grandma', 'king' }
for _, role in ipairs(ROLES) do
  local tbl = data.BARKS[role]
  ok(tbl ~= nil, role .. ' has a BARKS table')
  for _, trigger in ipairs(data.BARK_TRIGGERS) do
    local lines = tbl and tbl[trigger]
    ok(lines ~= nil and #lines >= 2 and #lines <= 4,
      role .. '.' .. trigger .. ' has 2-4 lines')
    for _, line in ipairs(lines or {}) do
      ok(#line > 0 and #line <= 14, role .. '.' .. trigger .. ' line fits a floater: ' .. line)
      ok(line == line:upper(), role .. '.' .. trigger .. ' line is ALL-CAPS: ' .. line)
    end
  end
end

-- barks.say resolves name overrides before the role table.
local gully = { id = 1, role = 'strongman', name = 'GULLY' }
local seen = {}
local origAddFloat = engine.addFloat
engine.addFloat = function(x, y, text) seen[#seen + 1] = text end
engine.gt = 0
barks.say(gully, 0, 0, 'battleStart')
ok(#seen == 1 and seen[1] == 'SMASH SMASH!', 'name override wins over the role table')

-- A generic strongman (no override) gets the role table's battleStart line.
seen = {}
engine.gt = 10 -- fresh unit id, no throttle history
local grunt = { id = 2, role = 'strongman', name = 'BRUNO' }
barks.say(grunt, 0, 0, 'battleStart')
ok(#seen == 1, 'role table used when no name override exists')

-- Throttling: a second bark from the same unit within 0.9s is suppressed.
seen = {}
engine.gt = 20
barks.say(grunt, 0, 0, 'perfect')
engine.gt = 20.5
barks.say(grunt, 0, 0, 'perfect')
ok(#seen == 1, 'a bark within 0.9s of the last one is throttled')

-- ...but the same unit can bark again once the throttle window passes.
engine.gt = 21.5
barks.say(grunt, 0, 0, 'perfect')
ok(#seen == 2, 'a bark after 0.9s is allowed through')

-- Suppressed entirely while a banner is active, so boss beats stay readable.
seen = {}
engine.gt = 30
engine.banner = { t = 0, dur = 1 }
barks.say(grunt, 0, 0, 'perfect')
ok(#seen == 0, 'barks are suppressed while a banner is active')
engine.banner = { t = 9, dur = 0 }
barks.say(grunt, 0, 0, 'perfect')
ok(#seen == 1, 'barks resume once the banner has expired')

-- Units with no role (or an unknown role) are silently skipped, not errors.
ok(pcall(barks.say, { name = 'NOBODY' }, 0, 0, 'battleStart'), 'a roleless unit is a no-op, not an error')
ok(pcall(barks.say, nil, 0, 0, 'battleStart'), 'a nil unit is a no-op, not an error')

engine.addFloat = origAddFloat

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('barks_test OK')
