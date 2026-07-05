-- Plain-Lua unit tests for the Phase 4 pure logic: grid.hexDirIndex (the
-- icy-sea slide's "same direction" primitive) and serialize round-trips of
-- the new biome/quest run shapes. Run from the project root with any
-- Lua 5.1+: `lua tests/biome_test.lua`.
package.path = './?.lua;' .. package.path
local grid = require 'src.grid'
local serialize = require 'src.serialize'

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

-- hexDirIndex: identifies each neighbor, returns nil for non-neighbors.
for _, origin in ipairs({ { 8, 4 }, { 8, 5 }, { 3, 0 }, { 5, 7 } }) do
  local x0, y0 = origin[1], origin[2]
  for i, nb in ipairs(grid.hexNeighbors(x0, y0)) do
    ok(grid.hexDirIndex(x0, y0, nb[1], nb[2]) == i,
      ('dir index of neighbor %d from (%d,%d)'):format(i, x0, y0))
  end
  ok(grid.hexDirIndex(x0, y0, x0, y0) == nil, 'self is not a neighbor')
  ok(grid.hexDirIndex(x0, y0, x0 + 3, y0 + 3) == nil, 'far cell is not a neighbor')
end

-- The slide contract: re-stepping with the same index continues in a
-- straight hex line across both row parities (distance grows 1 per step).
for _, start in ipairs({ { 8, 4 }, { 8, 5 } }) do
  for i = 1, 6 do
    local x, y = start[1], start[2]
    for step = 1, 3 do
      local nb = grid.hexNeighbors(x, y)[i]
      x, y = nb[1], nb[2]
      ok(grid.hexDistance(start[1], start[2], x, y) == step,
        ('dir %d from (%d,%d) is straight at step %d'):format(i, start[1], start[2], step))
    end
  end
end

-- Phase 4 run shapes survive encode/decode: sparse "x,y"-keyed slick set,
-- rock timers, quest, and the pre-rolled next biome.
local sea = {
  lv = 3, biome = 'icy',
  slick = { ['4,2'] = true, ['10,7'] = true },
  rocks = { { x = 5, y = 3, t = 1.25 } },
  rockT = 2.5, shipHurt = 3,
}
local run = { sea = sea, quest = { sea = 5 }, nextBiome = { sea = 4, biome = 'volcano' } }
local back = serialize.decode(serialize.encode(run))
ok(back ~= nil, 'phase 4 run shape decodes')
ok(back.sea.biome == 'icy', 'biome survives round-trip')
ok(back.sea.slick['4,2'] == true and back.sea.slick['10,7'] == true,
  'slick "x,y" keys survive round-trip')
ok(back.sea.slick['1,1'] == nil, 'no phantom slick keys')
ok(back.sea.rocks[1].x == 5 and back.sea.rocks[1].t == 1.25, 'rock entries survive')
ok(back.sea.shipHurt == 3, 'shipHurt survives')
ok(back.quest.sea == 5, 'quest survives')
ok(back.nextBiome.biome == 'volcano', 'nextBiome survives')

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('biome_test OK')
