package.path = './?.lua;' .. package.path
local files = {}
love = {
  graphics = {},
  audio = {},
  sound = {},
  math = { random = math.random },
  filesystem = {
    getInfo = function(path) return files[path] and {} or nil end,
    write = function(path, text) files[path] = text end,
    read = function(path) return files[path] end,
  },
}

require 'src.data'
local game = require 'src.game'
require 'src.ship_rules'

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

-- 1. Test game initialization fields
game.newGame('solo')
ok(game.run.salvage ~= nil, 'salvage table exists')
ok(game.run.salvage.timber == 0, 'timber starts at 0')
ok(game.run.salvage.cloth == 0, 'cloth starts at 0')
ok(game.run.salvage.iron == 0, 'iron starts at 0')

ok(game.run.fittings ~= nil, 'fittings table exists')
ok(game.run.fittings.hull == 0, 'hull fitting starts at 0')
ok(game.run.fittings.sails == 0, 'sails fitting starts at 0')
ok(game.run.fittings.guns == 0, 'guns fitting starts at 0')
ok(game.run.fittings.slot == nil, 'fitted blueprint slot starts at nil')

ok(game.run.blueprints ~= nil, 'blueprints table exists')
ok(game.run.blueprintDrops ~= nil, 'blueprintDrops milestone table exists')
ok(game.run.blueprintDrops.sea2 == false, 'sea 2 blueprint drop starts at false')
ok(game.run.blueprintDrops.sea5 == false, 'sea 5 blueprint drop starts at false')

-- 2. Current save/load keeps these fields intact.
game.run.salvage = { timber = 10, cloth = 5, iron = 2 }
game.run.fittings = { hull = 1, sails = 2, guns = 3, slot = 'chain' }
game.run.blueprints = { chain = true }
game.run.blueprintDrops = { sea2 = true, sea5 = false }
game.save()
ok(game.load() == true, 'game.load parses current save format')
ok(game.run.salvage.timber == 10, 'loaded timber salvage matches')
ok(game.run.salvage.cloth == 5, 'loaded cloth salvage matches')
ok(game.run.salvage.iron == 2, 'loaded iron salvage matches')
ok(game.run.fittings.hull == 1, 'loaded hull fitting matches')
ok(game.run.fittings.sails == 2, 'loaded sails fitting matches')
ok(game.run.fittings.guns == 3, 'loaded guns fitting matches')
ok(game.run.fittings.slot == 'chain', 'loaded fitted slot matches')
ok(game.run.blueprints.chain == true, 'loaded blueprints matches')
ok(game.run.blueprintDrops.sea2 == true, 'loaded blueprintDrops sea2 matches')
ok(game.run.blueprintDrops.sea5 == false, 'loaded blueprintDrops sea5 matches')

-- 3. Unsupported old save shapes fail cleanly and leave the run alone.
local before = game.run
local serialize = require 'src.serialize'
files[game.SAVE_PATH] = serialize.encode({ version = game.SAVE_VERSION - 1, crew = {}, party = {} })
ok(game.load() == false, 'unsupported old save returns false')
ok(game.run == before, 'failed load leaves the current run untouched')

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('stage4_test OK')
