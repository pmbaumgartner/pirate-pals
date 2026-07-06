-- Captains (co-op) pass: P2 steering, the fleet ship battle round structure,
-- patch/rejoin, broadside, dual-cursor boarding, chart, convoy, and the duo
-- victory screen.
return function(ctx, h)
  local tap, tap2, tapCell, wait, waitUntil, shot, expect =
    ctx.tap, ctx.tap2, ctx.tapCell, ctx.wait, ctx.waitUntil, ctx.shot, ctx.expect
  local engine, game, grid, input, timing, shipBattle, personBattle, chart =
    h.engine, h.game, h.grid, h.input, h.timing, h.shipBattle, h.personBattle, h.chart

  -- Captains sailing: both ships share one sea from the start; P2 drives
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

  -- One full fleet round: both captains pick MOVE from their own menus,
  -- actions resolve in confirm order, the foe takes its turn, and control
  -- comes back to select. (Runs deterministically now that scripted runs use
  -- a fixed dt.)
  local sbT = shipBattle.sb
  local function fleetSettled()
    return not engine.trans.on and sbT.turn == 'select' and not sbT.anim
      and sbT.wait <= 0 and not timing.on
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

  -- A downed fleet ship auto-picks PATCH when P2 is idle, uses P2's timing
  -- owner, and rejoins when its patch counter expires.
  sbT.ships[2].patched = true
  sbT.ships[2].patchRounds = 1
  sbT.ships[2].hp = 0
  sbT.ships[2].chosen = nil
  sbT.ships[2].confirmOrder = nil
  sbT.p2AutoFire = false
  sbT.idleT = 999
  sbT.ships[1].menu = 1 -- MOVE
  sbT.ships[1].submenu = nil
  tap('z')
  waitUntil(function() return timing.on and timing.player == 'p2' end, 5)
  h.landTiming('p2')
  waitUntil(fleetSettled, 15)
  expect(sbT.p2AutoFire, 'idle P2 did not auto-pick for the patched fleet ship')
  expect(not sbT.ships[2].patched, 'patched fleet ship did not rejoin after its patch round')
  expect(sbT.ships[2].hp >= math.floor(sbT.ships[2].max * 0.4),
    'rejoined fleet ship did not recover to its minimum hull')
  shot('fleet-patch-rejoin')
  sbT.p2AutoFire = false
  sbT.idleT = 0

  -- BROADSIDE: both captains on FIRE while both ships are NEAR arms the
  -- shared two-marker bar, once per battle.
  sbT.ships[1].range, sbT.ships[2].range = 'NEAR', 'NEAR'
  sbT.idleT = 0
  for _, sh in ipairs(sbT.ships) do
    sh.patched = false
    sh.patchRounds = 0
    sh.hp = math.max(sh.hp, math.floor(sh.max * 0.8))
    sh.chosen = nil
    sh.confirmOrder = nil
    sh.menu = 0 -- FIRE
    sh.submenu = nil
  end
  tap('z') -- open P1 fire submenu
  tap('z') -- lock in ROUND SHOT
  wait(0.1)
  expect(sbT.ships[1].chosen == 'fire_round', 'P1 did not lock in FIRE')
  tap2('a') -- open P2 fire submenu
  tap2('a') -- lock in ROUND SHOT
  waitUntil(function() return timing.coopMode or sbT.over end, 5)
  expect(sbT.broadsideUsed, 'both FIRE at NEAR did not arm BROADSIDE')
  shot('broadside')
  tap('z') -- both captains press the shared bar
  tap2('a')
  waitUntil(function() return sbT.over or fleetSettled() end, 15)
  wait(0.5)

  -- Dual-cursor boarding: per-player interaction state, each cursor
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

  -- Solo-collapse auto-act: a long-idle P2's pals act on their own so
  -- the fight never stalls on an empty chair. Park a foe adjacent to a P2
  -- pal first so the auto-act strike path (not just the walk) executes.
  tap('x')
  wait(0.2)
  expect(pbT.pl.p1.sel == nil, 'P1 back did not clear their selection')
  local p2pal, autoFoe
  for _, u in ipairs(pbT.units) do
    if not p2pal and u.side == 'p' and u.alive and not u.acted and (u.owner or 'p1') == 'p2' then
      p2pal = u
    end
    if not autoFoe and u.side == 'e' and u.alive then autoFoe = u end
  end
  expect(p2pal and autoFoe, 'no idle P2 pal + live foe to stage the auto-act strike')
  local pbModelT = require 'src.states.person_battle.model'
  for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
    local nx, ny = p2pal.x + d[1], p2pal.y + d[2]
    if pbModelT.inDeck(nx, ny) and not pbModelT.unitAt(nx, ny)
      and not pbT.crates[grid.gk(nx, ny)] then
      autoFoe.x, autoFoe.y, autoFoe.fx, autoFoe.fy = nx, ny, nx, ny
      break
    end
  end
  local autoFoeHp = autoFoe.hp
  pbT.idleT = 999
  wait(8)
  expect(not autoFoe.alive or autoFoe.hp < autoFoeHp, 'idle-P2 auto-act never landed a strike')
  expect(pbT.p2Auto, 'long P2 idle did not latch p2Auto')
  local p2Acted = 0
  for _, u in ipairs(pbT.units) do
    if u.side == 'p' and u.owner == 'p2' and u.acted then p2Acted = p2Acted + 1 end
  end
  expect(p2Acted >= 1, 'idle P2 pals did not auto-act')
  engine.setState('sail')
  wait(0.3)

  -- Captains chart view: both fleet tokens draw.
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

  -- Captains victory: the duo banner and captains-first lineup draw.
  require('src.states.victory').start()
  expect(engine.cur == 'victory', 'captains victory did not switch state')
  wait(0.4)
  shot('captains-victory')
end
