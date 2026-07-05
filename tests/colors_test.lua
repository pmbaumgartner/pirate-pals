-- Plain-Lua unit tests for crew colors (color selector): PLAYER_COLORS
-- shape, playerColorById fallback, run.colors defaults + helpers, and the
-- save/load migration for pre-color saves. game.lua pulls in engine/audio,
-- which only touch love.* inside function bodies, so a stub table is enough
-- (same approach as secrets_test.lua). Run: `lua tests/colors_test.lua`.
package.path = './?.lua;' .. package.path

math.randomseed(7)
local files = {}
love = {
  graphics = {},
  math = {
    random = function(a, b)
      if a then return math.random(a, b) end
      return math.random()
    end,
    setRandomSeed = function() end,
  },
  audio = { newSource = function() return { play = function() end } end },
  sound = { newSoundData = function()
    return { setSample = function() end }
  end },
  filesystem = {
    getInfo = function(path) return files[path] and {} or nil end,
    write = function(path, text) files[path] = text end,
    read = function(path) return files[path] end,
  },
}

local data = require 'src.data'
local meta = require 'src.meta'
local game = require 'src.game'
local audio = require 'src.audio'
audio.muted = true
meta.newMeta()

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

-- PLAYER_COLORS shape: unique ids, names, parseable 6-digit hexes.
local seen = {}
for _, c in ipairs(data.PLAYER_COLORS) do
  ok(c.id ~= nil and c.id ~= '', 'color has a non-empty id')
  ok(not seen[c.id], c.id .. ' is not a duplicate id')
  seen[c.id] = true
  ok(c.name ~= nil and c.name ~= '', c.id .. ' has a non-empty name')
  for _, field in ipairs({ 'sail', 'flag', 'accent' }) do
    local hexStr = c[field]
    ok(type(hexStr) == 'string' and hexStr:match('^#%x%x%x%x%x%x$') ~= nil,
      c.id .. ' ' .. field .. ' is a #rrggbb hex')
  end
end
ok(#data.PLAYER_COLORS == 8, 'eight swatches')
ok(data.PLAYER_COLORS[1].id == 'white', 'white (classic) is the default first entry')

-- playerColorById: lookup by id, safe fallback to the first entry.
ok(data.playerColorById('green').id == 'green', 'playerColorById finds a real id')
ok(data.playerColorById('nope') == data.PLAYER_COLORS[1], 'unknown id falls back to [1]')
ok(data.playerColorById(nil) == data.PLAYER_COLORS[1], 'nil id falls back to [1]')

-- Solo new game: classic white, no P2 color.
game.newGame()
ok(game.run.colors.p1 == 'white', 'solo newGame defaults p1 to white')
ok(game.run.colors.p2 == nil, 'solo newGame has no p2 color')
ok(game.colorOf('p1') == 'white', 'colorOf p1 reads the run color')
ok(game.colorOf('p2') == 'white', 'colorOf p2 falls back to white in solo')
ok(game.palColor(game.run.crew[1]) == 'white', 'palColor follows the owner')

-- Captains new game: two distinct default colors, palColor follows owners.
game.newGame('captains')
ok(game.run.colors.p1 == 'white' and game.run.colors.p2 == 'green',
  'captains newGame defaults to white/green')
ok(game.run.colors.p1 ~= game.run.colors.p2, 'captains colors are distinct')
ok(game.palColor(game.run.crew[3]) == 'green', "P2's captain wears P2's color")

-- Explicit colors (colorSelect hands these in) land as-is.
game.newGame('captains', { p1 = 'red', p2 = 'blue' })
ok(game.colorOf('p1') == 'red' and game.colorOf('p2') == 'blue',
  'newGame accepts picked colors')

-- run.colors survives save/load.
game.save()
ok(game.load(), 'saved captains run loads back')
ok(game.colorOf('p1') == 'red' and game.colorOf('p2') == 'blue',
  'colors survive the save/load round-trip')

-- Migration: a pre-color captains save gets white/green (green only because
-- ship2 exists), a pre-color solo save gets white only.
game.run.colors = nil
game.save()
ok(game.load(), 'pre-color captains save loads')
ok(game.run.colors.p1 == 'white' and game.run.colors.p2 == 'green',
  'pre-color captains save migrates to white/green')

game.newGame()
game.run.colors = nil
game.save()
ok(game.load(), 'pre-color solo save loads')
ok(game.run.colors.p1 == 'white' and game.run.colors.p2 == nil,
  'pre-color solo save migrates to white only')

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('colors_test OK')
