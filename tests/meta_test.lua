-- Plain-Lua unit tests for meta.lua's pure logic (5.1/5.2): upgrade costs,
-- ship-HP/dodge/cook derivations, and the serialize round-trip of meta data.
-- No LÖVE dependency: run with `lua tests/meta_test.lua`.
package.path = './?.lua;' .. package.path
local meta = require 'src.meta'
local serialize = require 'src.serialize'

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

-- A fresh meta (no save loaded) starts at the un-upgraded baseline.
meta.newMeta()
ok(meta.shipMaxHp() == 30, 'fresh meta ships start at 30 max hp')
ok(meta.hasFreeDodge() == false, 'fresh meta has no free dodge')
ok(meta.cookTier() == 0, 'fresh meta cook tier is 0')

-- Each FIGUREHEAD tier adds +10 max hp.
meta.data.upgrades.figurehead = 1
ok(meta.shipMaxHp() == 40, 'figurehead tier 1 adds 10 max hp')
meta.data.upgrades.figurehead = 3
ok(meta.shipMaxHp() == 60, 'figurehead tier 3 (max) adds 30 max hp')

meta.data.upgrades.sails = 1
ok(meta.hasFreeDodge() == true, 'any sails tier grants the free dodge')

meta.data.upgrades.cook = 2
ok(meta.cookTier() == 2, 'cookTier reflects the current tier')

-- STEADY HANDS (design-gaps/04): a bought ship part, widening timing
-- windows and, at tier 2 only, slowing the sweep.
meta.data.upgrades.steady = 0
ok(meta.steadyMult().win == 1 and meta.steadyMult().sweep == 1, 'no steady tier is a no-op')
meta.data.upgrades.steady = 1
ok(meta.steadyMult().win == 1.25 and meta.steadyMult().sweep == 1, 'steady tier 1 widens windows only')
meta.data.upgrades.steady = 2
ok(meta.steadyMult().win == 1.5 and meta.steadyMult().sweep == 1.15, 'steady tier 2 widens more and slows the sweep')

-- Every upgrade has as many costs as its max tier, so port.lua's
-- `costs[tier+1]` lookup never silently reads nil mid-tier.
for key, def in pairs(meta.UPGRADES) do
  ok(#def.costs == def.max, key .. ' has one cost per tier up to max')
end

-- meta.data is plain data (same constraint as game.run) so it round-trips
-- through serialize.lua, same as save.lua.
meta.data.gold = 250
meta.data.voyagesWon = 2
meta.data.golden = true
meta.data.hats = { none = true, bandR = true }
local encoded = serialize.encode(meta.data)
local decoded = serialize.decode(encoded)
ok(decoded.gold == 250, 'meta round-trips gold through serialize')
ok(decoded.voyagesWon == 2, 'meta round-trips voyagesWon through serialize')
ok(decoded.golden == true, 'meta round-trips golden through serialize')
ok(decoded.hats.bandR == true, 'meta round-trips hats through serialize')
ok(decoded.upgrades.cook == 2, 'meta round-trips upgrades through serialize')

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('meta_test OK')
