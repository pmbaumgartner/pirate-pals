-- Named --warp scenarios (0.2): jump straight to a specific game state
-- with hand-built data, instead of playing through to reach it. Dev-only:
-- required lazily by main.lua only when --warp is present.
local game = require 'src.game'
local data = require 'src.data'
local engine = require 'src.engine'
local input = require 'src.input'
local shipBattle = require 'src.states.ship_battle'
local personBattle = require 'src.states.person_battle'
local loot = require 'src.states.loot'
local chart = require 'src.states.chart'
local victory = require 'src.states.victory'
local meta = require 'src.meta'

local M = {}

M.scenarios = {
  ['sail-lv5'] = function()
    game.newGame()
    game.run.party[1].lvl = 5
    game.run.party[2].lvl = 5
    local sm = game.makePirate('strongman', 'BRUNO', 5)
    game.run.crew[#game.run.crew + 1] = sm
    game.run.party[#game.run.party + 1] = sm
    game.run.gold = 250
    game.run.treas.ruby = 1
    game.genSea(5)
    engine.setState('sail')
  end,

  ['ship-lv3'] = function()
    game.newGame()
    game.genSea(3)
    shipBattle.start(game.run.sea.enemies[1])
  end,

  ['boarding-lv5'] = function()
    game.newGame()
    game.run.party[1].lvl = 5
    game.run.party[2].lvl = 5
    game.genSea(5)
    personBattle.start(game.run.sea.enemies[1])
  end,

  ['loot-all'] = function()
    game.newGame()
    game.run.treas.ruby = 1
    loot.start({
      { type = 'gold', n = 42 },
      { type = 'treasure', id = 'ruby' },
      { type = 'level', names = { 'CAPPY', 'FIN' } },
      { type = 'recruit', pirate = game.makePirate('medic', 'PIPPA', 2) },
      { type = 'unlock', id = 'bandB' },
      { type = 'clear', n = 20 },
    }, 'WARP: LOOT ALL')
  end,

  ['tailor-rich'] = function()
    game.newGame()
    game.run.gold = 9999
    engine.setState('tailor')
  end,

  ['crew-full'] = function()
    game.newGame()
    local cap = game.run.crew[1]
    game.run.crew = { cap }
    game.run.party = { cap }
    local roles = { 'deckhand', 'strongman', 'sharpshooter', 'medic' }
    for i = 1, 9 do
      local role = roles[(i - 1) % #roles + 1]
      local lvl = ((i - 1) % 6) + 1
      local p = game.makePirate(role, data.PAL_NAMES[i], lvl)
      game.run.crew[#game.run.crew + 1] = p
      if #game.run.party < 3 then game.run.party[#game.run.party + 1] = p end
    end
    game.run.gold = 500
    engine.setState('crew')
  end,

  ['gallery'] = function()
    require 'src.dev.gallery'
    engine.setState('gallery')
  end,

  ['chart'] = function()
    game.newGame()
    game.run.voyage.sea = 3
    chart.startView()
  end,

  ['boss-ship'] = function()
    game.newGame()
    game.run.voyage.sea = 8
    game.genSea(8)
    shipBattle.start(game.run.sea.enemies[1])
  end,

  ['boss-boarding'] = function()
    game.newGame()
    game.run.voyage.sea = 8
    game.genSea(8)
    personBattle.startBoss(game.run.sea.enemies[1])
  end,

  -- TWO CAPTAINS (C2): both ships on one sea from the start, P2 controlling
  -- ship2 via input.p2 (arrows + N/M).
  ['captains-sail'] = function()
    game.newGame('captains')
    input.setCoop(true)
    engine.setState('sail')
  end,

  ['captains-ship'] = function()
    game.newGame('captains')
    input.setCoop(true)
    game.genSea(3)
    shipBattle.start(game.run.sea.enemies[1])
  end,

  -- Risky-UI shots: land directly in the states whose menus have to fit
  -- the bottom panel, for --shot eyeballing and bounds-invariant coverage.
  ['fleet-menu'] = function()
    game.newGame('captains')
    input.setCoop(true)
    game.genSea(3)
    shipBattle.start(game.run.sea.enemies[1])
  end,

  ['fleet-submenu'] = function()
    game.newGame('captains')
    input.setCoop(true)
    game.genSea(3)
    shipBattle.start(game.run.sea.enemies[1])
    for _, sh in ipairs(shipBattle.sb.ships) do sh.subOpen = true end
  end,

  ['act-menu'] = function()
    game.newGame('captains')
    input.setCoop(true)
    game.genSea(3)
    personBattle.start(game.run.sea.enemies[1])
    for _, player in ipairs({ 'p1', 'p2' }) do
      local pl = personBattle.pb.pl[player]
      for _, u in ipairs(personBattle.pb.units) do
        if u.side == 'p' and u.owner == player then
          pl.sel = u
          break
        end
      end
      pl.stage = 'act'
    end
  end,

  -- TWO CAPTAINS (C4): dual-cursor boarding, 2+2 party with split owners.
  ['captains-boarding'] = function()
    game.newGame('captains')
    input.setCoop(true)
    for _, p in ipairs(game.run.party) do p.lvl = 3 end
    game.genSea(3)
    personBattle.start(game.run.sea.enemies[1])
  end,

  -- TWO CAPTAINS (C5): the duo victory banner and captains-first lineup.
  ['captains-victory'] = function()
    game.newGame('captains')
    input.setCoop(true)
    game.run.gold = 500
    game.run.treas.ruby = 1
    victory.start()
  end,

  -- Biomes (4.1): one warp per twist, mid-voyage difficulty.
  ['sea-icy'] = function()
    game.newGame()
    game.genSea(3, 'icy')
    engine.setState('sail')
  end,

  ['sea-foggy'] = function()
    game.newGame()
    game.genSea(3, 'foggy')
    engine.setState('sail')
  end,

  ['sea-volcano'] = function()
    game.newGame()
    game.genSea(3, 'volcano')
    engine.setState('sail')
  end,

  -- Gimmick enemies (4.3) via the comp override.
  ['boarding-crab'] = function()
    game.newGame()
    game.run.party[1].lvl = 3
    game.run.party[2].lvl = 3
    game.genSea(4)
    personBattle.start(game.run.sea.enemies[1], { 'crab', 'crab', 'grunt' })
  end,

  ['boarding-thief'] = function()
    game.newGame()
    game.run.gold = 50
    game.run.party[1].lvl = 3
    game.run.party[2].lvl = 3
    game.genSea(4)
    personBattle.start(game.run.sea.enemies[1], { 'thief', 'grunt' })
  end,

  -- Event cards (4.2): bottle + trader, both trade options live.
  ['events'] = function()
    game.newGame()
    game.run.gold = 40
    game.run.treas.coin = 2
    loot.start({
      { type = 'bottle', sea = 3 },
      { type = 'trade', choice = 1, options = {
        { id = 'buy', name = 'GET A SHINY', desc = 'PAY 15 GOLD', ok = true },
        { id = 'sell', name = 'SWAP A SPARE', desc = 'GET 25 GOLD', ok = true, tid = 'coin' },
      } },
    }, 'WARP: EVENTS')
  end,

  ['victory'] = function()
    game.newGame()
    game.run.party[1].lvl = 6
    game.run.gold = 999
    victory.start()
  end,

  -- Home Port (5.2): meta already has a few voyages/gold banked so upgrades
  -- are affordable and NEW VOYAGE is reachable.
  ['port'] = function()
    meta.newMeta()
    meta.data.voyagesWon = 2
    meta.data.gold = 400
    game.newGame()
    engine.setState('port')
  end,

  -- New Voyage+ (5.3): meta already has a completed voyage + tier bump so
  -- newGamePlus's crew-reseed and comp-widening wrinkles are visible.
  ['new-voyage-plus'] = function()
    meta.newMeta()
    meta.data.voyagesWon = 1
    meta.data.gold = 200
    game.newGame()
    local sm = game.makePirate('strongman', 'BRUNO', 4)
    game.run.crew[#game.run.crew + 1] = sm
    game.run.party[#game.run.party + 1] = sm
    game.newGamePlus()
    engine.setState('sail')
  end,

  -- Battle map variety (design-gaps/05): one warp per deck shape, forced via
  -- the deckOverride arg, for a legibility pass with --shots.
  ['boarding-classic'] = function()
    game.newGame()
    game.genSea(5)
    personBattle.start(game.run.sea.enemies[1], nil, 'classic')
  end,

  ['boarding-gangplank'] = function()
    game.newGame()
    game.genSea(5)
    personBattle.start(game.run.sea.enemies[1], nil, 'gangplank')
  end,

  ['boarding-lshape'] = function()
    game.newGame()
    game.genSea(5)
    personBattle.start(game.run.sea.enemies[1], nil, 'lshape')
  end,

  ['boarding-twin'] = function()
    game.newGame()
    game.genSea(5)
    personBattle.start(game.run.sea.enemies[1], nil, 'twinDecks')
  end,

  ['boarding-crowsnest'] = function()
    game.newGame()
    game.genSea(5)
    personBattle.start(game.run.sea.enemies[1], nil, 'crowsnest')
  end,

  ['boarding-big'] = function()
    game.newGame()
    game.genSea(5)
    personBattle.start(game.run.sea.enemies[1], nil, 'bigDeck')
  end,

  -- Golden Compass (5.3): 12/12 treasure log already banked, so sea 9's
  -- kraken rematch is reachable straight from a fresh voyage.
  ['boss-kraken'] = function()
    meta.newMeta()
    meta.data.golden = true
    game.newGame()
    game.run.voyage.sea = 9
    game.genSea(9)
    shipBattle.start(game.run.sea.enemies[1])
  end,
}

function M.run(name)
  local fn = M.scenarios[name]
  if not fn then
    local names = {}
    for k in pairs(M.scenarios) do names[#names + 1] = k end
    table.sort(names)
    error('unknown --warp scenario "' .. tostring(name) .. '" — valid: ' .. table.concat(names, ', '), 0)
  end
  fn()
end

return M
