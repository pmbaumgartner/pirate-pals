-- Canonical smoke script (0.4): drives every state once, exercising hex
-- tap-to-sail, ship battle, boarding, loot cards, and the menu screens.
-- Supersedes the old fixed-timestamp src/smoke.lua — transitions are forced
-- directly (not gated on real battle outcomes) so the walk stays short and
-- deterministic regardless of RNG. `--smoke` runs this via `--script=...
-- --speed=8`; add `--shots` to also dump PNGs into the LÖVE save dir.
local engine = require 'src.engine'
local game = require 'src.game'
local data = require 'src.data'
local meta = require 'src.meta'
local grid = require 'src.grid'
local input = require 'src.input'
local shipBattle = require 'src.states.ship_battle'
local personBattle = require 'src.states.person_battle'
local loot = require 'src.states.loot'
local chart = require 'src.states.chart'
local palette = require 'src.palette'
local CO = palette.CO

-- Title + mode select: walked via the real input path (not setState) before
-- the deterministic run starts, so the title<->modeSelect wiring gets
-- exercised. hasSave decides which key opens modeSelect (title.lua binds
-- CONTINUE to 'a' only when a save exists, bumping NEW VOYAGE to 'b').
engine.setState('title')
waitUntil(function() return math.floor(engine.gt * 2) % 2 == 0 end, 1)
shot('title')
tap(game.hasSave() and 'x' or 'z')
expect(engine.cur == 'modeSelect', 'title did not open modeSelect')
tap('left')
wait(0.2)
tap('right')
wait(0.2)
shot('modeselect')
-- Color selector sits between mode pick and the new run; back out of both
-- (Z here would start a run, which the deterministic section below owns).
tap('z')
wait(0.2)
expect(engine.cur == 'colorSelect', 'modeSelect Z did not open colorSelect')
tap('right')
wait(0.2)
shot('colorselect')
tap('x')
wait(0.2)
expect(engine.cur == 'modeSelect', 'colorSelect back did not return to modeSelect')
tap('x')
wait(0.2)
expect(engine.cur == 'title', 'expected modeSelect back to return to title')

meta.newMeta()
game.newGame()
engine.setState('sail')
wait(0.5)

tap('right')
tap('up')
tap('down')

-- Tap the whirlpool (always reachable) to exercise tap-to-sail.
local e = game.run.sea.exit
tapCell(e.x, e.y)
wait(1.0)

shot('sail')

game.run.fittings.slot = 'chain'
shipBattle.start(game.run.sea.enemies[1])
expect(engine.cur == 'shipBattle', 'shipBattle.start did not switch state')
wait(2.5)

-- Telegraph gallery: foe intents are pure render-side during the player's
-- pick phase, so poke each one in and shot it for the CI artifact.
local sbTel = shipBattle.sb
waitUntil(function() return sbTel.turn == 'you' and not engine.trans.on end, 5)

-- Stage shot submenu with preview screenshot
sbTel.submenu = 'shot'
sbTel.sub = 0
wait(0.2)
shot('ship-shot-submenu')
sbTel.submenu = nil

-- Stage foe HUD details (hp, pips, stages, ablaze)
local oldFoeHp = sbTel.foe.hp
local oldFoeSails = sbTel.foe.sailsStage
local oldFoeGuns = sbTel.foe.gunsStage
local oldFoeAblaze = sbTel.foe.ablaze
local oldFoeRep = sbTel.foe.repairs
local oldFoeMaxRep = sbTel.foe.maxRepairs

sbTel.foe.hp = 12
sbTel.foe.sailsStage = -1
sbTel.foe.gunsStage = -1
sbTel.foe.ablaze = 3
sbTel.foe.repairs = 1
sbTel.foe.maxRepairs = 2
wait(0.2)
shot('ship-foe-hud-details')

-- Solo HUD screenshot
shot('ship-solo-hud')

-- Restore foe stats
sbTel.foe.hp = oldFoeHp
sbTel.foe.sailsStage = oldFoeSails
sbTel.foe.gunsStage = oldFoeGuns
sbTel.foe.ablaze = oldFoeAblaze
sbTel.foe.repairs = oldFoeRep
sbTel.foe.maxRepairs = oldFoeMaxRep
for _, intent in ipairs({ 'fire', 'bigshot', 'volley', 'fix' }) do
  sbTel.foe.intent = intent
  wait(0.1)
  shot('ship-telegraph-' .. intent)
end

-- CREW SPECIALS submenu: the highlighted special's desc renders at the
-- bottom of the box.
sbTel.submenu = 'special'
sbTel.sub = 0
wait(0.1)
shot('ship-sub-desc')
sbTel.submenu = nil

personBattle.start(game.run.sea.enemies[1])
expect(engine.cur == 'personBattle', 'personBattle.start did not switch state')
for _ = 1, 8 do
  tap('z')
  wait(0.4)
end

shot('battle')

game.run.treas.coin = 1
loot.start({
  { type = 'gold', n = 12 },
  { type = 'treasure', id = 'coin' },
  { type = 'level', names = { 'CAPPY' } },
  { type = 'recruit', pirate = game.makePirate('deckhand', 'GULLY', 1) },
  { type = 'clear', n = 20 },
}, 'TEST')
wait(1.0)

-- Roster pressure + level-up choices (Phase 3).

-- Perk pick: switching the highlighted option then confirming applies that
-- option's id (not the default) to the pirate.
local perky = game.makePirate('deckhand', 'PERKY', 1)
local perkOpts = data.perksFor('deckhand', 2)
loot.start({ { type = 'perk', pirate = perky, options = perkOpts, choice = 1 } }, 'TEST PERK')
wait(0.3)
tap('right')
wait(0.2)
tap('z')
wait(0.3)
expect(perky.perks and perky.perks[1] == perkOpts[2].id, 'perk card did not apply the chosen perk')

-- The iris transition swallows input for its full 1.2s (main.lua skips
-- state updates while it plays), so wait it out before tapping a card that
-- was started on its heels.
local function settle()
  waitUntil(function() return not engine.trans.on end, 5)
end

-- Best Mates card is a plain display card; just make sure it advances.
loot.start({ { type = 'bond', a = 'CAPPY', b = 'FIN' } }, 'TEST BOND')
settle()
tap('z')
waitUntil(function() return engine.cur == 'sail' end, 5)

-- Voyage Log: accepting a recruit logs a one-time "first recruit"
-- moment, gated on the starting crew size (still 2 here -- CAPPY/FIN only).
local logBefore = #game.run.log
loot.start({ { type = 'recruit', pirate = game.makePirate('deckhand', 'SPARKY', 1) } }, 'TEST RECRUIT')
settle()
tap('z')
wait(0.3)
expect(#game.run.log == logBefore + 1, 'accepting the first recruit did not append a voyage log moment')
expect(game.run.log[#game.run.log].first, 'first-recruit log entry should be flagged first')
local sparkyJoined = false
for _, p in ipairs(game.run.crew) do
  if p.name == 'SPARKY' then sparkyJoined = true end
end
expect(sparkyJoined, 'recruit card did not add SPARKY to the crew')

-- Tuckered-out pals: napping blocks party join and decrements on new-sea
-- entry (genSea is the "entering a new sea" hook — see game.lua).
local sleepy = game.run.party[1]
sleepy.nap = 1
expect(game.isNapping(sleepy), 'isNapping should be true right after napping')
game.genSea(game.run.sea.lv)
expect(not game.isNapping(sleepy), 'nap should clear after entering a new sea')

engine.setState('crew')
wait(1.0)
shot('crew')
engine.setState('tailor')
wait(1.0)
shot('tailor')

-- SAILS tab (color selector): a free mid-run re-pick at the tailor.
tap('left')
wait(0.2)
shot('tailor-sails')
tap('down')
wait(0.2)
tap('z')
wait(0.3)
expect(game.colorOf('p1') == 'red', 'SAILS tab did not re-pick the crew color')

-- DRY DOCK screenshot
game.run.salvage.timber = 4
game.run.salvage.cloth = 7
game.run.salvage.iron = 2
game.run.blueprints.fire = true
game.run.blueprints.chain = true
engine.setState('drydock')
wait(1.0)
shot('drydock')

engine.setState('log')
wait(1.0)
shot('log')

-- Voyage Log screen: opened via the real L hotkey from sail, shows
-- the moments logged above, and B returns to sail.
engine.setState('sail')
wait(0.2)
tap('l')
expect(engine.cur == 'voyagelog', 'L hotkey did not open the voyage log from sail')
wait(0.3)
shot('voyagelog')
tap('x')
wait(0.2)
expect(engine.cur == 'sail', 'expected voyagelog back to return to sail')

-- Voyage chart: read-only view, then back to sail.
chart.startView()
expect(engine.cur == 'chart', 'chart.startView did not switch state')
wait(0.3)
shot('chart-view')
tap('x')
wait(0.3)
expect(engine.cur == 'sail', 'expected back on sail after chart view')

-- Sea variety (Phase 4): biomes, events, gimmick enemies.

-- Biome override sticks and each twist's data materializes.
game.genSea(3, 'icy')
expect(game.run.sea.biome == 'icy', 'genSea biome override did not stick')
expect(next(game.run.sea.slick) ~= nil, 'icy sea generated no slick hexes')

game.genSea(3, 'volcano')
expect(game.run.sea.biome == 'volcano', 'volcano biome did not stick')
engine.setState('sail')
wait(6.0) -- long enough for a rock to telegraph and land
shot('volcano')

game.genSea(3, 'foggy')
expect(game.run.sea.biome == 'foggy', 'foggy biome did not stick')
engine.setState('sail')
wait(0.5)
shot('foggy')

-- Treasure-map quest: a held quest places its X when that sea generates.
game.run.quest = { sea = 4 }
game.genSea(4)
local foundX = false
for y = 0, game.SEA_H - 1 do
  for x = 0, game.SEA_W - 1 do
    if game.tileAt(x, y) == game.T_X then foundX = true end
  end
end
expect(foundX or game.run.quest.sea == 5,
  'quest X neither placed on its sea nor carried forward')

-- Trader card: buying converts 15 gold into a treasure, shown as a card.
game.run.gold = 40
loot.start({
  { type = 'trade', choice = 1, options = {
    { id = 'buy', name = 'GET A SHINY', desc = 'PAY 15 GOLD', ok = true },
    { id = 'sell', name = 'SWAP A SPARE', desc = 'GET 25 GOLD', ok = false },
  } },
}, 'TEST TRADE')
settle()
tap('z')
wait(0.3)
expect(game.run.gold == 25, 'trade buy did not cost 15 gold')
tap('z') -- the inserted treasure card
wait(1.0)

-- Crab + thief boarding on gangplank; script a crate smash and a shove-SPLASH
-- so both new verbs execute headlessly every CI run.
game.run.gold = 30
personBattle.start(game.run.sea.enemies[1], { 'crab', 'thief' }, 'gangplank')
expect(engine.cur == 'personBattle', 'comp-override boarding did not start')
wait(0.2) -- let the state transition settle

local hasCrab, hasThief = false, false
local thief = nil
for _, u in ipairs(personBattle.pb.units) do
  if u.role == 'crab' then hasCrab = true end
  if u.role == 'thief' then hasThief = true; thief = u end
end
expect(hasCrab and hasThief, 'comp override did not spawn the crab + thief')

local pb = personBattle.pb
local cappy = pb.units[1]
cappy.x, cappy.y = 0, 0
cappy.fx, cappy.fy = 0, 0
pb.crates = { [grid.gk(1, 0)] = true }

for _, u in ipairs(pb.units) do
  if u.side == 'e' then
    u.x, u.y = 8, 1
    u.fx, u.fy = 8, 1
  end
end

require('src.states.person_battle.ai').planFoeIntents()

pb.pl.p1.cursor.x, pb.pl.p1.cursor.y = 0, 0
tap('z') -- select Cappy
wait(0.2)
tap('z') -- stay
wait(0.2)
tap('z') -- select ATTACK
wait(0.2)
tap('z') -- confirm attack on crate
wait(0.3)
expect(pb.crates[grid.gk(1, 0)] == nil, 'crate should be smashed')

local fin = pb.units[2]
fin.acted = false
fin.x, fin.y = 3, 0
fin.fx, fin.fy = 3, 0
thief.x, thief.y = 4, 0
thief.fx, thief.fy = 4, 0
thief.hp = 10
thief.soggy = false

pb.pl.p1.sel = nil
pb.pl.p1.stage = 'pick'
pb.pl.p1.cursor.x, pb.pl.p1.cursor.y = 3, 0

tap('z') -- select Fin
wait(0.2)
tap('z') -- stay
wait(0.2)
tap('down')
wait(0.1)
tap('down')
wait(0.1)
tap('z') -- select SHOVE
wait(0.2)
tap('z') -- confirm target (thief)
wait(0.6)
expect(thief.soggy, 'thief should be soggy after splash')
expect(thief.hp == 3, 'thief should take 7 damage from splash (10 - 7 = 3)')
shot('gimmick')

-- Battle-readability shots: stage a boarding with every foe parked within
-- two tiles of a pal (closest first, so badges sit adjacent), then walk one
-- attack through act menu -> target preview -> floaters, shotting each.
local pbModel = require 'src.states.person_battle.model'
personBattle.start(game.run.sea.enemies[1], { 'grunt', 'grunt', 'brute' })
wait(0.3)
local pbI = personBattle.pb
local pal1 = nil
for _, u in ipairs(pbI.units) do
  if u.side == 'p' and not pal1 then pal1 = u end
end
local spots = {}
for _, t in ipairs(pbI.deckList) do
  local d = grid.manhattan(t[1], t[2], pal1.x, pal1.y)
  if d >= 1 and d <= 2 and not pbModel.unitAt(t[1], t[2]) then
    spots[#spots + 1] = t
  end
end
table.sort(spots, function(a, b)
  return grid.manhattan(a[1], a[2], pal1.x, pal1.y) < grid.manhattan(b[1], b[2], pal1.x, pal1.y)
end)
for _, u in ipairs(pbI.units) do
  if u.side == 'e' and #spots > 0 then
    local s = table.remove(spots, 1)
    u.x, u.y, u.fx, u.fy = s[1], s[2], s[1], s[2]
  end
end
require('src.states.person_battle.ai').planFoeIntents()
expect(pbI.phase == 'party', 'staged boarding not on the party phase')
-- Let the intro banner and spawn barks clear so the badges are the shot.
waitUntil(function() return engine.banner.t >= engine.banner.dur end, 5)
wait(1.2)
shot('boarding-intents')

pbI.pl.p1.cursor.x, pbI.pl.p1.cursor.y = pal1.x, pal1.y
tap('z') -- select the pal
wait(0.2)
tap('z') -- move in place -> act menu
wait(0.2)
tap('down') -- GUARD: the solo panel now shows every action's desc line
wait(0.2)
shot('act-desc-guard')
tap('up')
wait(0.2)
tap('z') -- ATTACK (a foe is adjacent by construction)
wait(0.2)
expect(pbI.pl.p1.stage == 'target', 'staged attack did not reach the target stage')
shot('damage-preview')
tap('z') -- confirm the attack (opens the timing bar)
waitUntil(function() return require('src.timing').on end, 3)
wait(0.5) -- let the pointer travel toward the hit window
tap('z') -- land the hit
waitUntil(function() return not require('src.timing').on and #engine.floaters > 0 end, 5)
shot('floaters')
wait(1.0)

-- New shape-gallery pass: exercise BFS + intents on every non-classic deck,
-- and screenshot icy/volcano variants on tidepool and barricade.
local shapes = { 'gangplank', 'lshape', 'twinDecks', 'crowsnest', 'bigDeck', 'barricade', 'tidepool' }
local oldSea = game.run.sea
for _, id in ipairs(shapes) do
  if id == 'tidepool' then
    game.run.sea = { lv = 3, biome = 'icy', enemies = oldSea.enemies }
  elseif id == 'barricade' then
    game.run.sea = { lv = 3, biome = 'volcano', enemies = oldSea.enemies }
  else
    game.run.sea = { lv = 3, biome = 'calm', enemies = oldSea.enemies }
  end
  personBattle.start(game.run.sea.enemies[1], nil, id)
  expect(engine.cur == 'personBattle', 'failed to start ' .. id)
  wait(0.5)
  if id == 'tidepool' then
    shot('deck-tidepool-icy')
  elseif id == 'barricade' then
    shot('deck-barricade-volcano')
  else
    shot('deck-' .. id)
  end
  require('src.states.person_battle.ai').startFoePhase()
  wait(1.5)
end
game.run.sea = oldSea
engine.setState('sail')
wait(0.3)

-- The Pirate King: sea 8 special-cases into the boss ship + boarding fight.
game.run.voyage.sea = 8
game.genSea(8)
expect(game.run.sea.boss, 'sea 8 did not generate as the boss sea')

shipBattle.start(game.run.sea.enemies[1])
expect(engine.cur == 'shipBattle', 'boss shipBattle.start did not switch state')
expect(shipBattle.sb.isBoss, 'expected isBoss on the boss ship battle')
wait(2.5)
shot('boss-ship')

local sbB = shipBattle.sb
sbB.announcedPhase = 2
sbB.foe.hp = 30
sbB.foe.intent = 'ram'
sbB.msg = "THE KING BELLOWS - RAMMING SPEED!"
engine.showBanner("THE KING BELLOWS - RAMMING SPEED!", CO.red, 1.5)
wait(0.2)
shot('boss-king-ram')
engine.banner.t = engine.banner.dur -- clear banner

personBattle.startBoss(game.run.sea.enemies[1])
expect(engine.cur == 'personBattle', 'personBattle.startBoss did not switch state')
expect(personBattle.pb.isBoss, 'expected isBoss on the boss boarding battle')
for _ = 1, 6 do
  tap('z')
  wait(0.4)
end
shot('boss')

-- Victory celebration, then Home Port (Phase 5).
game.run.gold = 1000
require('src.states.victory').start()
expect(engine.cur == 'victory', 'victory.start did not switch state')
wait(0.3)
shot('victory')

-- Voyage Log: victory.start() logs its own PIRATE LEGENDS moment
-- and distills a Legend highlight for any pal (SPARKY, recruited above)
-- named in this voyage's log.
local hasFirstRecruitLog, hasVictoryLog = false, false
for _, entry in ipairs(game.run.log) do
  if entry.icon == 'flagW' then hasFirstRecruitLog = true end
  if entry.icon == 'hat_crown' then hasVictoryLog = true end
end
expect(hasFirstRecruitLog, 'first-recruit moment missing from the voyage log')
expect(hasVictoryLog, 'victory did not log a PIRATE LEGENDS moment')
expect(meta.data.legends.SPARKY ~= nil, 'victory did not distill a legend highlight for SPARKY')

tap('z')
settle()
expect(engine.cur == 'port', 'expected victory to continue into Home Port')
expect(meta.data.voyagesWon == 1, 'victory did not bank a voyage win into meta')
expect(meta.data.gold >= 1000, 'victory did not bank the run gold into meta')

-- Home Port: buy the cheapest tier of every upgrade, then check its effect
-- shows up in a fresh run.
shot('port')
for _ = 1, 4 do
  local before = meta.data.gold
  tap('z')
  wait(0.2)
  expect(meta.data.gold < before, 'buying an upgrade did not spend banked gold')
  tap('down')
  wait(0.1)
end
expect(meta.data.upgrades.figurehead >= 1, 'figurehead upgrade did not apply')
expect(meta.data.upgrades.sails >= 1, 'sails upgrade did not apply')
expect(meta.data.upgrades.cook >= 1, 'cook upgrade did not apply')
expect(meta.data.upgrades.steady >= 1, 'steady hands upgrade did not apply')

-- NEW VOYAGE: crew names/roles carry over at level 1; a fresh ship battle
-- picks up the FIGUREHEAD/BETTER SAILS bonuses just bought. The loop above
-- already left the cursor on the NEW VOYAGE row after its last tap('down').
tap('z')
waitUntil(function() return engine.cur == 'sail' end, 5)
expect(game.run.crew[1].lvl == 1, 'new voyage+ crew was not reset to level 1')
expect(game.run.metaTier == 1, 'new voyage+ did not bump metaTier')

shipBattle.start(game.run.sea.enemies[1])
expect(shipBattle.sb.ships[1].max == meta.shipMaxHp(), 'ship battle did not pick up the FIGUREHEAD upgrade')
expect(shipBattle.sb.ships[1].dodge == 1, 'ship battle did not grant BETTER SAILS free dodge')

game.newGame()
game.genSea(3) -- exercise generation at a higher level
engine.setState('sail')
wait(0.7)

shot('sail2')
wait(0.3)

expect(engine.cur == 'sail', 'expected to land back on sail')

-- TWO CAPTAINS (C2): both ships share one sea from the start; P2 drives
-- ship2 directly via input.p2 (arrows + N/M), no join prompt needed.
game.newGame('captains')
input.setCoop(true)
engine.setState('sail')
wait(0.3)
expect(game.run.ship2 ~= nil, 'captains mode did not create ship2')
expect(grid.hexDistance(game.run.ship.x, game.run.ship.y,
  game.run.ship2.x, game.run.ship2.y) <= 1, 'ship2 did not spawn adjacent to ship')

-- Any one open direction proves P2 steering; a fixed 'right' can hit an
-- isle on some seeds and bump in place.
local sx0, sy0 = game.run.ship2.x, game.run.ship2.y
for _, d in ipairs({ 'right', 'left', 'up', 'down' }) do
  if game.run.ship2.x == sx0 and game.run.ship2.y == sy0 then
    tap2(d)
    wait(0.4)
  end
end
expect(game.run.ship2.x ~= sx0 or game.run.ship2.y ~= sy0, 'ship2 did not move on P2 input')

-- Either ship bumping a foe pulls the fleet into one shared battle. Park
-- next to the foe and tap-step onto it — a long scripted route can cross a
-- port/chest/event tile and hijack the state.
local foe = game.run.sea.enemies[1]
local near = nil
for _, nb in ipairs(grid.hexNeighbors(foe.x, foe.y)) do
  local nx, ny = nb[1], nb[2]
  if nx >= 0 and ny >= 0 and nx < game.SEA_W and ny < game.SEA_H
    and game.tileAt(nx, ny) == game.T_WATER and not game.enemyAt(nx, ny) then
    near = { nx, ny }
  end
end
expect(near ~= nil, 'no open water next to the foe to stage the encounter')
local sh1e = game.run.ship
sh1e.x, sh1e.y, sh1e.fx, sh1e.fy = near[1], near[2], near[1], near[2]
sh1e.route, sh1e.anim = nil, nil
foe.t = 0 -- just-moved timer: the foe holds still while the tap lands
tapCell(foe.x, foe.y)
waitUntil(function() return engine.cur == 'shipBattle' end, 10)
expect(grid.hexDistance(game.run.ship.x, game.run.ship.y,
  game.run.ship2.x, game.run.ship2.y) <= 1, 'ship2 was not pulled adjacent into the fleet encounter')
expect(shipBattle.sb.fleet, 'captains ship battle did not use the fleet round structure')
expect(#shipBattle.sb.ships == 2, 'fleet ship battle should have 2 ships')

-- The fleet battle is forced (never won), so its foe stays alive in the
-- sea. Clear the roster now — the boarding start below keeps its direct
-- `foe` reference — or a wandering foe catches an adjacent ship during the
-- later sail windows and hijacks the state (chart/convoy checks).
game.run.sea.enemies = {}

-- C3: one full fleet round — both captains pick MOVE from their own menus,
-- actions resolve in confirm order, the foe takes its turn, and control
-- comes back to select. (Runs deterministically now that scripted runs use
-- a fixed dt.)
local sbT = shipBattle.sb
local function fleetSettled()
  return not engine.trans.on and sbT.turn == 'select' and not sbT.anim
    and sbT.wait <= 0 and not require('src.timing').on
end
waitUntil(fleetSettled, 5)

-- Risky-UI shots (bounds invariant coverage): the 2x2 fleet menu grid and
-- the 2-row-capped SPECIAL submenu, both live in the bottom panel.
shot('fleet-menu')
shot('ship-fleet-hud')
tap('d')
tap('d')
tap('d') -- P1 menu: FIRE -> SPECIAL
tap('z')
expect(sbT.ships[1].submenu == 'special', "P1 SPECIAL did not open the fleet submenu")
shot('fleet-submenu')
tap('x')
expect(sbT.ships[1].submenu == nil, 'P1 back did not close the fleet submenu')
tap('d') -- SPECIAL wraps back to FIRE
sbT.idleT = 0

tap('d') -- P1 menu: FIRE -> MOVE
tap('z')
wait(0.1)
expect(sbT.ships[1].chosen == 'move', 'P1 did not lock in MOVE')
sbT.idleT = 0
tap2('right') -- P2 menu: FIRE -> MOVE
tap2('a')
waitUntil(function() return sbT.turn ~= 'select' end, 5)
waitUntil(fleetSettled, 15) -- resolve both MOVEs + the foe turn
expect(sbT.ships[1].chosen == nil and sbT.ships[2].chosen == nil,
  'fleet round did not clear chosen actions for the next select')

-- BROADSIDE: both captains on FIRE while both ships are NEAR arms the
-- shared two-marker bar, once per battle.
sbT.ships[1].range, sbT.ships[2].range = 'NEAR', 'NEAR'
sbT.idleT = 0
tap('a') -- P1 menu: MOVE -> back to FIRE
tap('z') -- open P1 fire submenu
tap('z') -- lock in ROUND SHOT
wait(0.1)
expect(sbT.ships[1].chosen == 'fire_round', 'P1 did not lock in FIRE')
tap2('left')
tap2('a') -- open P2 fire submenu
tap2('a') -- lock in ROUND SHOT
waitUntil(function() return require('src.timing').coopMode or sbT.over end, 5)
expect(sbT.broadsideUsed, 'both FIRE at NEAR did not arm BROADSIDE')
shot('broadside')
tap('z') -- both captains press the shared bar
tap2('a')
waitUntil(function() return sbT.over or fleetSettled() end, 15)
wait(0.5)

-- C4: dual-cursor boarding — per-player interaction state, each cursor
-- locked to its owner's pals. Fixed waits + direct state pokes only; avoid
-- adding waitUntil-on-timing here.
personBattle.start(foe)
expect(engine.cur == 'personBattle', 'captains boarding did not start')
local pbT = personBattle.pb
expect(pbT.pl and pbT.pl.p1 and pbT.pl.p2, 'boarding is missing per-player interaction state')
tap('z')
wait(0.2)
expect(pbT.pl.p1.sel and pbT.pl.p1.sel.owner == 'p1', "P1's cursor did not select a P1 pal")

-- Act menu open (move-in-place), shot for bounds coverage, then back out
-- to the move stage so the flow below continues unchanged.
tap('z')
wait(0.2)
expect(pbT.pl.p1.stage == 'act', 'P1 move-in-place did not open the act menu')
shot('act-menu')
tap('s') -- GUARD (P1 is WASD in captains): the half-panel shows a desc line
wait(0.2)
shot('coop-act-desc')
tap('w')
wait(0.2)
tap('x')
wait(0.2)
expect(pbT.pl.p1.stage == 'move', 'act menu back did not return to the move stage')

tap2('a')
wait(0.2)
expect(pbT.pl.p2.sel and pbT.pl.p2.sel.owner == 'p2', "P2's cursor did not select a P2 pal")
-- P2 backs out, parks on P1's selected pal, and must not be able to grab it.
tap2('b')
wait(0.2)
expect(pbT.pl.p2.sel == nil, 'P2 back did not clear their selection')
pbT.pl.p2.cursor.x, pbT.pl.p2.cursor.y = pbT.pl.p1.sel.x, pbT.pl.p1.sel.y
tap2('a')
wait(0.2)
expect(pbT.pl.p2.sel == nil, "P2 selected P1's pal — cursors must stay on their own units")
shot('captains-boarding')

-- Solo-collapse auto-act (C4): a long-idle P2's pals act on their own so
-- the fight never stalls on an empty chair.
tap('x')
wait(0.2)
expect(pbT.pl.p1.sel == nil, 'P1 back did not clear their selection')
pbT.idleT = 999
wait(8)
expect(pbT.p2Auto, 'long P2 idle did not latch p2Auto')
local p2Acted = 0
for _, u in ipairs(pbT.units) do
  if u.side == 'p' and u.owner == 'p2' and u.acted then p2Acted = p2Acted + 1 end
end
expect(p2Acted >= 1, 'idle P2 pals did not auto-act')
engine.setState('sail')
wait(0.3)

-- C5: the chart shows both fleet tokens in captains mode.
chart.startView()
wait(0.3)
shot('captains-chart')
tap('x')
wait(0.3)

-- Solo-collapse: no P2 input for ~10s -> ship2 raises its pennant and
-- auto-follows, never gating a single player behind an idle second ship.
-- Park both ships on known water instead of tapping a step: a scripted
-- move could land on a chest/event tile and open loot, freezing sail's
-- idle timer (seed-dependent timeout).
local sh1, sh2 = game.run.ship, game.run.ship2
sh1.x, sh1.y, sh1.fx, sh1.fy, sh1.route, sh1.anim = 1, 4, 1, 4, nil, nil
local spot = nil
for y = 0, game.SEA_H - 1 do
  for x = 0, game.SEA_W - 1 do
    if not spot and game.tileAt(x, y) == game.T_WATER
      and grid.hexDistance(x, y, 1, 4) >= 4 and grid.hexDistance(x, y, 1, 4) <= 6 then
      spot = { x, y }
    end
  end
end
expect(spot ~= nil, 'no open water found to park ship2 for the convoy check')
sh2.x, sh2.y, sh2.fx, sh2.fy = spot[1], spot[2], spot[1], spot[2]
sh2.route, sh2.anim, sh2.convoy, sh2.idleT = nil, nil, false, 0
waitUntil(function() return game.run.ship2.convoy end, 20)
wait(1.5) -- let it take a few convoy steps
expect(grid.hexDistance(game.run.ship.x, game.run.ship.y, game.run.ship2.x, game.run.ship2.y) <= 3,
  'convoying ship2 did not step toward ship')

-- C5: captains victory — the duo banner and captains-first lineup draw.
require('src.states.victory').start()
expect(engine.cur == 'victory', 'captains victory did not switch state')
wait(0.4)
shot('captains-victory')

-- Stage a ship battle loss to capture the capped-loss banner
local dummyFoe = { lv = 1, boss = false, class = 'sloop', name = 'TEST PIRATE' }
shipBattle.start(dummyFoe)
expect(engine.cur == 'shipBattle', 'dummy shipBattle.start did not switch state')
wait(0.2)
local sbLoss = shipBattle.sb
sbLoss.ships[1].hp = 0
sbLoss.over = true
sbLoss.msg = "HER HULL SHRUGGED OFF OUR SHOTS - WE NEED HEAVIER GUNS OR HOTTER SHOT."
engine.showBanner("SLIPPED AWAY!", CO.orange, 1.3)
wait(0.2)
shot('capped-loss')
engine.banner.t = engine.banner.dur -- clear banner
wait(0.2)

print('SMOKE OK')
love.event.quit(0)
