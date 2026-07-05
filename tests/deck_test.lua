-- Guardrails for boarding deck shapes: every src.data.DECKS
-- template must parse into one connected region, keep enough open tiles
-- after max crate scatter, give both sides a non-empty spawn band spaced
-- apart, and fit the fixed 320x180 canvas.
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

local audio = require 'src.audio'
audio.muted = true

local grid = require 'src.grid'
local data = require 'src.data'
local model = require 'src.states.person_battle.model'

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

local MAX_CRATES = 6

for _, tpl in ipairs(data.DECKS) do
  local d = model.buildDeck(tpl.id)
  local total = #d.deckList

  ok(total - MAX_CRATES >= 18,
    tpl.id .. ': needs >=18 open tiles after max crate scatter, has ' .. total)
  ok(#d.pSpawns > 0, tpl.id .. ': party spawn band is empty')
  ok(#d.eSpawns > 0, tpl.id .. ': enemy spawn band is empty')

  local minD = math.huge
  for _, p in ipairs(d.pSpawns) do
    for _, e in ipairs(d.eSpawns) do
      minD = math.min(minD, grid.manhattan(p[1], p[2], e[1], e[2]))
    end
  end
  ok(minD >= 4, tpl.id .. ': spawn bands must be >=4 apart at nearest point, got ' .. minD)

  local start = d.deckList[1]
  local flood = grid.bfsFlood(start[1], start[2], total,
    function(x, y) return d.deck[grid.gk(x, y)] ~= nil end)
  local reached = 0
  for _ in pairs(flood.cost) do reached = reached + 1 end
  ok(reached == total, tpl.id .. ': deck is not one connected region (' .. reached .. '/' .. total .. ')')

  local ox, oy = model.deckOrigin(d.w, d.h)
  ok(ox >= 0 and oy >= 0 and ox + d.w * model.TILE <= 320 and oy + d.h * model.TILE <= 180,
    tpl.id .. ': deck does not fit the 320x180 canvas')
end

-- Weighted selection: classic alone on seas 1-2, every template must
-- be reachable once the full pool opens up at sea 3+.
for _, tpl in ipairs(data.DECKS) do
  ok(model.pickDeckId(1) == 'classic', 'sea 1 must always draw classic')
end
local seen = {}
for _ = 1, 500 do
  seen[model.pickDeckId(3)] = true
end
for _, tpl in ipairs(data.DECKS) do
  ok(seen[tpl.id], tpl.id .. ' never came up in 500 sea-3+ draws')
end

local function checkConnectivity(deckInfo, crates)
  local start = deckInfo.pSpawns[1]
  if not start then return false end
  local startK = grid.gk(start[1], start[2])
  if crates[startK] then return false end

  local visited = { [startK] = true }
  local q = { start }
  local head = 1
  while head <= #q do
    local curr = q[head]
    head = head + 1
    for i = 1, 4 do
      local nx = curr[1] + grid.DIRS4[i][1]
      local ny = curr[2] + grid.DIRS4[i][2]
      local nk = grid.gk(nx, ny)
      if deckInfo.deck[nk] and not crates[nk] and not visited[nk] then
        visited[nk] = true
        q[#q + 1] = { nx, ny }
      end
    end
  end

  for _, p in ipairs(deckInfo.pSpawns) do
    if not visited[grid.gk(p[1], p[2])] then return false end
  end
  for _, e in ipairs(deckInfo.eSpawns) do
    if not visited[grid.gk(e[1], e[2])] then return false end
  end
  return true
end

-- Perch, preCrates and connectivity guard checks
for _, tpl in ipairs(data.DECKS) do
  local d = model.buildDeck(tpl.id)

  -- ≤1 perch per deck
  local perchCount = 0
  for _, row in ipairs(tpl.rows) do
    for i = 1, #row do
      if row:sub(i, i) == '^' then perchCount = perchCount + 1 end
    end
  end
  ok(perchCount <= 1, tpl.id .. ': has ' .. perchCount .. ' perches, expected <= 1')

  if perchCount == 1 then
    ok(d.perch ~= nil, tpl.id .. ': has perch character but deckInfo.perch is nil')
  else
    ok(d.perch == nil, tpl.id .. ': has no perch character but deckInfo.perch is set')
  end

  -- Pre-placed crates (b) check
  local preCratesCount = 0
  for _, row in ipairs(tpl.rows) do
    for i = 1, #row do
      if row:sub(i, i) == 'b' then preCratesCount = preCratesCount + 1 end
    end
  end
  local preCratesTableCount = 0
  if d.preCrates then
    for _ in pairs(d.preCrates) do preCratesTableCount = preCratesTableCount + 1 end
  end
  ok(preCratesCount == preCratesTableCount, tpl.id .. ': preCrates mismatch ' .. preCratesCount .. ' vs ' .. preCratesTableCount)

  -- Barricade gate check
  if tpl.id == 'barricade' then
    ok(d.preCrates[grid.gk(5, 0)] == true, 'expected pre-placed crate at x=5, y=0')
    ok(d.preCrates[grid.gk(5, 1)] == true, 'expected pre-placed crate at x=5, y=1')
    ok(d.preCrates[grid.gk(5, 2)] == nil, 'expected gate gap (no crate) at x=5, y=2')
    ok(d.preCrates[grid.gk(5, 3)] == true, 'expected pre-placed crate at x=5, y=3')
    ok(d.preCrates[grid.gk(5, 4)] == true, 'expected pre-placed crate at x=5, y=4')

    local initialOk = checkConnectivity(d, d.preCrates)
    ok(initialOk, 'barricade pre-placed wall itself should not block the gate path')
  end

  -- Scatter guard property: 200 seeded scatters per template always leave a path
  local passedScatters = true
  for seed = 1, 200 do
    math.randomseed(seed)
    local scattered = model.scatterCrates(d)
    if not checkConnectivity(d, scattered) then
      passedScatters = false
      break
    end
  end
  ok(passedScatters, tpl.id .. ': 200 seeded scatters must always leave a P-band to E-band path')
end

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('deck_test OK')
