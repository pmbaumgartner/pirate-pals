-- Plain-Lua unit tests for src/grid.lua (no LÖVE dependency). Run from the
-- project root with any Lua 5.1+: `lua tests/grid_test.lua` (texlua works).
package.path = './?.lua;' .. package.path
local grid = require 'src.grid'

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

local function keyset(list)
  local s = {}
  for _, p in ipairs(list) do s[p[1] .. ',' .. p[2]] = true end
  return s
end

-- hexNeighbors: exact neighbor sets for both row parities (odd-r offset,
-- odd rows shifted right).
local even = keyset(grid.hexNeighbors(4, 4))
for _, k in ipairs({ '5,4', '3,4', '4,3', '3,3', '4,5', '3,5' }) do
  ok(even[k], 'even-row neighbor ' .. k)
end
ok(#grid.hexNeighbors(4, 4) == 6, 'even row has 6 neighbors')

local odd = keyset(grid.hexNeighbors(4, 5))
for _, k in ipairs({ '5,5', '3,5', '5,4', '4,4', '5,6', '4,6' }) do
  ok(odd[k], 'odd-row neighbor ' .. k)
end
ok(#grid.hexNeighbors(4, 5) == 6, 'odd row has 6 neighbors')

-- Every neighbor is at hexDistance 1, from cells of both parities.
for _, origin in ipairs({ { 7, 2 }, { 7, 3 }, { 0, 0 }, { 3, 1 } }) do
  for _, nb in ipairs(grid.hexNeighbors(origin[1], origin[2])) do
    ok(grid.hexDistance(origin[1], origin[2], nb[1], nb[2]) == 1,
      ('neighbor of (%d,%d) at distance 1'):format(origin[1], origin[2]))
  end
end

-- hexDistance: identity and symmetry across a swath of pairs.
math.randomseed(7)
for _ = 1, 200 do
  local ax, ay = math.random(0, 18), math.random(0, 8)
  local bx, by = math.random(0, 18), math.random(0, 8)
  ok(grid.hexDistance(ax, ay, ax, ay) == 0, 'distance to self is 0')
  ok(grid.hexDistance(ax, ay, bx, by) == grid.hexDistance(bx, by, ax, ay),
    'distance is symmetric')
end

-- BFS over hex neighbors on an open field must reproduce hexDistance
-- exactly, and reach the hex-number count of cells (1 + 6 * tri(R)).
local R = 5
local flood = grid.bfsFlood(9, 9, R, function() return true end, grid.hexNeighbors)
local count = 0
for k, c in pairs(flood.cost) do
  count = count + 1
  local x, y = grid.parseKey(k)
  ok(c == grid.hexDistance(9, 9, x, y), 'flood cost == hexDistance at ' .. k)
end
ok(count == 1 + 6 * (R * (R + 1) / 2), 'hex flood covers ' .. count .. ' cells')

-- bfsPath along the hex flood: consecutive steps are hex-adjacent and the
-- path length matches the flood cost.
local path = grid.bfsPath(flood, 12, 6)
ok(path ~= nil and #path == flood.cost[grid.gk(12, 6)] + 1, 'hex path length')
for i = 2, #path do
  ok(grid.hexDistance(path[i - 1][1], path[i - 1][2], path[i][1], path[i][2]) == 1,
    'hex path step ' .. i .. ' is adjacent')
end

-- Default (square) behavior unchanged: 4-dir flood is a manhattan diamond.
local sq = grid.bfsFlood(0, 0, 2, function() return true end)
local sqCount = 0
for k, c in pairs(sq.cost) do
  sqCount = sqCount + 1
  local x, y = grid.parseKey(k)
  ok(c == grid.manhattan(0, 0, x, y), 'square flood cost == manhattan at ' .. k)
end
ok(sqCount == 13, 'square flood radius 2 covers 13 cells, got ' .. sqCount)

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('grid_test OK')
