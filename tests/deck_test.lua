-- Guardrails for boarding deck shapes (design-gaps/05): every src.data.DECKS
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

-- Weighted selection (Gap 6): classic alone on seas 1-2, every template must
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

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('deck_test OK')
