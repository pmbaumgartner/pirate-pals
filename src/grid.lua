-- Pure grid helpers shared by sea generation and both battle modes.
-- Cells are addressed by "x,y" string keys so sparse sets (crates, flood
-- costs) can live in plain tables.
local M = {}

M.DIRS4 = { {1, 0}, {-1, 0}, {0, 1}, {0, -1} }

function M.gk(x, y) return x .. ',' .. y end

function M.parseKey(k)
  local x, y = k:match('(-?%d+),(-?%d+)')
  return tonumber(x), tonumber(y)
end

function M.manhattan(ax, ay, bx, by)
  return math.abs(ax - bx) + math.abs(ay - by)
end

-- Hex helpers interpret the same t[y][x] storage as an odd-r offset grid of
-- pointy-top hexes (odd rows shifted right half a cell). Axial coordinates
-- would give branch-free math but would need a remapping layer at every
-- array access, so offset it is (used by sail mode only).

-- Neighbor offsets depend on row parity: even rows' diagonals lean left,
-- odd rows' lean right.
local HEX_DIRS = {
  [0] = { {1, 0}, {-1, 0}, {0, -1}, {-1, -1}, {0, 1}, {-1, 1} },
  [1] = { {1, 0}, {-1, 0}, {1, -1}, {0, -1}, {1, 1}, {0, 1} },
}

-- The six hex neighbors of (x, y) as a list of {x, y} pairs.
function M.hexNeighbors(x, y)
  local out = {}
  for i, d in ipairs(HEX_DIRS[y % 2]) do
    out[i] = { x + d[1], y + d[2] }
  end
  return out
end

-- Index (1..6) of the direction from (ax,ay) to hex-adjacent (bx,by), or nil
-- if not adjacent. The index names the same compass direction on both row
-- parities (1 E, 2 W, 3 NE, 4 NW, 5 SE, 6 SW), so stepping again with the
-- same index continues in a straight hex line — the icy-sea slide relies on
-- this to carry the ship one extra hex "in the same direction".
function M.hexDirIndex(ax, ay, bx, by)
  for i, nb in ipairs(M.hexNeighbors(ax, ay)) do
    if nb[1] == bx and nb[2] == by then return i end
  end
  return nil
end

-- Hex distance in steps: convert odd-r offset -> cube, then cube distance.
function M.hexDistance(ax, ay, bx, by)
  local aq = ax - (ay - ay % 2) / 2
  local bq = bx - (by - by % 2) / 2
  local dq, dr = aq - bq, ay - by
  return (math.abs(dq) + math.abs(dr) + math.abs(dq + dr)) / 2
end

local function dirs4Neighbors(x, y)
  return { {x + 1, y}, {x - 1, y}, {x, y + 1}, {x, y - 1} }
end

-- BFS flood fill: returns {cost = {key -> steps}, par = {key -> parentKey}}
-- expanding up to maxCost steps through cells where passFn(x, y) is true.
-- neighborFn(x, y) -> list of {x, y}; defaults to the 4-dir square grid
-- (pass M.hexNeighbors for hex floods).
function M.bfsFlood(sx, sy, maxCost, passFn, neighborFn)
  neighborFn = neighborFn or dirs4Neighbors
  local q, head = { {sx, sy} }, 1
  local cost, par = {}, {}
  cost[M.gk(sx, sy)] = 0
  while head <= #q do
    local c = q[head]
    head = head + 1
    local cc = cost[M.gk(c[1], c[2])]
    if cc < maxCost then
      for _, nb in ipairs(neighborFn(c[1], c[2])) do
        local nx, ny = nb[1], nb[2]
        local kk = M.gk(nx, ny)
        if cost[kk] == nil and passFn(nx, ny) then
          cost[kk] = cc + 1
          par[kk] = M.gk(c[1], c[2])
          q[#q + 1] = { nx, ny }
        end
      end
    end
  end
  return { cost = cost, par = par }
end

-- Walk parent links back from (tx, ty) to the flood origin.
-- Returns a list of {x, y} steps (origin first), or nil if unreachable.
function M.bfsPath(flood, tx, ty)
  local kk = M.gk(tx, ty)
  if flood.cost[kk] == nil then return nil end
  local path = {}
  while kk do
    local x, y = M.parseKey(kk)
    table.insert(path, 1, { x, y })
    kk = flood.par[kk]
  end
  return path
end

return M
