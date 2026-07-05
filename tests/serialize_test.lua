-- Plain-Lua unit tests for src/serialize.lua (no LÖVE dependency). Run from
-- the project root with any Lua 5.1+: `lua tests/serialize_test.lua`.
package.path = './?.lua;' .. package.path
local serialize = require 'src.serialize'

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

local function roundTrip(v)
  return serialize.decode(serialize.encode(v))
end

-- Scalars and flat maps survive encode/decode.
local flat = { gold = 12, name = 'CAPPY', alive = true, ratio = 1.5 }
local flatOut = roundTrip(flat)
ok(flatOut.gold == 12, 'flat number round-trips')
ok(flatOut.name == 'CAPPY', 'flat string round-trips')
ok(flatOut.alive == true, 'flat boolean round-trips')
ok(flatOut.ratio == 1.5, 'flat float round-trips')

-- 0-indexed and sparse numeric keys (as used by the hex sea grid) keep
-- their exact indices rather than being renumbered from 1.
local sparse = { [0] = 'zero', [1] = 'one', [5] = 'five' }
local sparseOut = roundTrip(sparse)
ok(sparseOut[0] == 'zero', 'index 0 preserved')
ok(sparseOut[1] == 'one', 'index 1 preserved')
ok(sparseOut[5] == 'five', 'index 5 preserved')
ok(sparseOut[2] == nil, 'gap stays empty')

-- Nested tables (crew list, sea tiles) round-trip structurally.
local nested = {
  crew = {
    { name = 'CAPPY', lvl = 1, out = 'none' },
    { name = 'FIN', lvl = 2, out = 'hat' },
  },
  sea = { t = { [0] = { [0] = 1, [1] = 0 } } },
}
local nestedOut = roundTrip(nested)
ok(nestedOut.crew[1].name == 'CAPPY', 'nested array element field')
ok(nestedOut.crew[2].lvl == 2, 'second nested element field')
ok(nestedOut.sea.t[0][0] == 1, 'doubly-nested 0-indexed grid cell')
ok(nestedOut.sea.t[0][1] == 0, 'doubly-nested 0-indexed grid cell 2')

-- Strings needing escaping (quotes, newlines) still parse back correctly.
local weird = { line = 'a "quoted" line\nwith a break' }
ok(roundTrip(weird).line == weird.line, 'quotes and newlines survive escaping')

-- A corrupted/garbage file decodes to nil instead of raising.
ok(serialize.decode('not lua at all {{{') == nil, 'garbage input decodes to nil, not an error')
ok(serialize.decode('{ [1] = os.exit() }') == nil, 'sandboxed globals are unreachable, decodes to nil')

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('serialize_test OK')
