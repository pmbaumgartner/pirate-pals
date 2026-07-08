-- Sail tile triggers: chest, bottle, trader, treasure-map X, port, volcano
-- rock hit, icy slide, and the whirlpool exit into the next sea.
return function(ctx, h)
  local tap, tapCell, wait, waitUntil, shot, expect =
    ctx.tap, ctx.tapCell, ctx.wait, ctx.waitUntil, ctx.shot, ctx.expect
  local engine, game, grid = h.engine, h.game, h.grid

  local function findTile(tt)
    for y = 0, game.SEA_H - 1 do
      for x = 0, game.SEA_W - 1 do
        if game.tileAt(x, y) == tt then return x, y end
      end
    end
  end

  local function parkAdjacentTo(tx, ty)
    for _, nb in ipairs(grid.hexNeighbors(tx, ty)) do
      local nx, ny = nb[1], nb[2]
      if nx >= 0 and ny >= 0 and nx < game.SEA_W and ny < game.SEA_H
        and game.tileAt(nx, ny) == game.T_WATER and not game.enemyAt(nx, ny) then
        local sh = game.run.ship
        sh.x, sh.y, sh.fx, sh.fy = nx, ny, nx, ny
        sh.route, sh.anim = nil, nil
        return true
      end
    end
    return false
  end

  -- Regenerates (via genFn) up to `tries` times looking for tile type `tt`,
  -- parking the ship adjacent to it once found. Returns the tile coords, or
  -- nil if no attempt turned one up with an open neighbor to park on.
  local function stageTile(tt, genFn, tries)
    for _ = 1, tries do
      genFn()
      engine.setState('sail')
      wait(0.3)
      game.run.sea.enemies = {}
      local tx, ty = findTile(tt)
      if tx and parkAdjacentTo(tx, ty) then return tx, ty end
    end
    return nil
  end

  -- 1. Chest: sail onto it, expect a loot card and a gold gain.
  local cx, cy = stageTile(game.T_CHEST, function() game.genSea(3, 'calm') end, 4)
  expect(cx ~= nil, 'no chest with an open neighbor turned up in 4 sea regens')
  if cx then
    local goldBefore = game.run.gold
    tapCell(cx, cy)
    waitUntil(function() return engine.cur == 'loot' end, 10)
    h.settle()
    shot('sail-chest')
    h.walkLoot()
    expect(game.run.gold > goldBefore, 'opening the chest did not add gold')
    expect(h.meta.data.counts.chestsOpened and h.meta.data.counts.chestsOpened >= 1,
      'opening a chest did not tick the chestsOpened counter')
  end

  -- Deterministic variant of stageTile: regen once via genFn, then convert a
  -- water tile into `tt` directly (arrival handlers key off the tile type
  -- alone, so a planted tile behaves exactly like a spawned one).
  local function plantTile(tt, genFn)
    genFn()
    engine.setState('sail')
    wait(0.3)
    game.run.sea.enemies = {}
    local ship = game.run.ship
    for y = 0, game.SEA_H - 1 do
      for x = 0, game.SEA_W - 1 do
        if game.tileAt(x, y) == game.T_WATER and not (x == ship.x and y == ship.y) then
          game.setTile(x, y, tt)
          if parkAdjacentTo(x, y) then return x, y end
          game.setTile(x, y, game.T_WATER)
        end
      end
    end
    expect(false, 'no water tile with an open neighbor to plant tile type ' .. tt)
  end

  -- 2/3. Bottle and trader share one event-tile slot per sea, so plant each
  -- deterministically instead of regenning until RNG deals both.
  game.run.quest = nil
  game.run.gold = 40
  local bx, by = plantTile(game.T_BOTTLE, function() game.genSea(3, 'calm') end)
  tapCell(bx, by)
  h.walkLoot()
  expect(game.run.quest ~= nil, 'finding the bottle did not set a quest')

  game.run.gold = 40
  local trx, try2 = plantTile(game.T_TRADER, function() game.genSea(3, 'calm') end)
  tapCell(trx, try2)
  waitUntil(function() return engine.cur == 'loot' end, 10)
  h.settle()
  tap('z') -- buy option is the default choice when gold >= 15
  h.walkLoot()

  -- 4. X dig: a held quest for this sea places the X; digging clears it.
  local xx, xy = stageTile(game.T_X, function()
    game.run.quest = { sea = 3 }
    game.genSea(3, 'calm')
  end, 4)
  expect(xx ~= nil, 'no quest X with an open neighbor turned up in 4 sea regens')
  if xx then
    tapCell(xx, xy)
    waitUntil(function() return engine.cur == 'loot' end, 10)
    h.settle()
    shot('sail-xdig')
    h.walkLoot()
    expect(game.run.quest == nil, 'digging the X did not clear the quest')
    expect(h.meta.data.deeds.xmarks, 'digging up the quest X did not earn the xmarks deed')
  end

  -- 5. Port: sail onto it, expect the dock state, then back out to sail.
  local px, py = stageTile(game.T_PORT, function() game.genSea(3, 'calm') end, 4)
  expect(px ~= nil, 'no port with an open neighbor turned up in 4 sea regens')
  if px then
    tapCell(px, py)
    waitUntil(function() return engine.cur == 'dock' end, 10)
    tap('x') -- back (BACK TO SEA/B share the same exit, per dock.lua)
    waitUntil(function() return engine.cur == 'sail' end, 10)
  end

  -- 6. Volcano rock: a rock timed to land on the ship's own hex hurts it.
  game.genSea(3, 'volcano')
  engine.setState('sail')
  wait(0.3)
  game.run.sea.enemies = {}
  local sh = game.run.ship
  table.insert(game.run.sea.rocks, { x = sh.x, y = sh.y, t = 0.05 })
  wait(0.6)
  shot('sail-volcano-hit')
  expect(game.run.sea.shipHurt >= 1, 'a rock landing on the ship did not raise shipHurt')

  -- 7. Icy slide: entering a slick hex carries the ship one hex further in
  -- the same direction it hopped from.
  local function findSlideCase()
    for k in pairs(game.run.sea.slick) do
      local sx, sy = grid.parseKey(k)
      for _, nb in ipairs(grid.hexNeighbors(sx, sy)) do
        local ax, ay = nb[1], nb[2]
        if ax >= 0 and ay >= 0 and ax < game.SEA_W and ay < game.SEA_H
          and game.tileAt(ax, ay) == game.T_WATER and not game.enemyAt(ax, ay) then
          local idx = grid.hexDirIndex(ax, ay, sx, sy)
          local cont = grid.hexNeighbors(sx, sy)[idx]
          local cx2, cy2 = cont[1], cont[2]
          if cx2 >= 0 and cy2 >= 0 and cx2 < game.SEA_W and cy2 < game.SEA_H
            and game.tileAt(cx2, cy2) == game.T_WATER and not game.enemyAt(cx2, cy2) then
            return ax, ay, sx, sy
          end
        end
      end
    end
  end
  local slideA, slideS = nil, nil
  for _ = 1, 4 do
    game.genSea(3, 'icy')
    engine.setState('sail')
    wait(0.3)
    game.run.sea.enemies = {}
    local ax, ay, sx, sy = findSlideCase()
    if ax then
      slideA, slideS = { ax, ay }, { sx, sy }
      break
    end
  end
  expect(slideA ~= nil, 'no icy sea turned up a slide-able slick hex in 4 regens')
  if slideA then
    local ship = game.run.ship
    ship.x, ship.y, ship.fx, ship.fy = slideA[1], slideA[2], slideA[1], slideA[2]
    ship.route, ship.anim = nil, nil
    tapCell(slideS[1], slideS[2])
    waitUntil(function() return not ship.anim end, 5)
    wait(0.3)
    shot('sail-icy-slide')
    expect(not (ship.x == slideS[1] and ship.y == slideS[2]),
      'the ship stopped on the slick hex instead of sliding past it')
  end

  -- 8. Exit tile: sail onto the whirlpool and advance to the next sea. Last,
  -- since it moves the voyage forward; a low sea keeps clear of the boss.
  game.genSea(3, 'calm')
  engine.setState('sail')
  wait(0.3)
  game.run.sea.enemies = {}
  local seaBefore = game.run.voyage.sea
  local ex, ey = game.run.sea.exit.x, game.run.sea.exit.y
  expect(parkAdjacentTo(ex, ey), 'no open neighbor to park next to the exit whirlpool')
  tapCell(ex, ey)
  -- Arrival opens the voyage chart; its advance animation runs ~1.1s and
  -- then waits for a confirm press before dropping into the next sea.
  waitUntil(function() return engine.cur == 'chart' end, 10)
  waitUntil(function() return game.run.voyage.sea == seaBefore + 1 end, 5)
  tap('z')
  waitUntil(function() return engine.cur == 'sail' and not engine.trans.on end, 15)
  expect(game.run.voyage.sea == seaBefore + 1, 'sailing into the whirlpool did not advance the voyage')

  -- 9. Solo enemy bump: tap a sea foe's own hex from next door. planRoute
  -- (sail_map.lua) sets route.foe to the tapped enemy so routeStep's
  -- interrupt check lets the hop land on it, and tryMove's foe branch
  -- (sail_rules.lua) opens the ship-battle encounter chain -- a bump always
  -- starts with the ship battle, never boarding directly.
  local bumpFoe = nil
  for _ = 1, 4 do
    game.genSea(3, 'calm')
    engine.setState('sail')
    wait(0.3)
    if game.run.sea.enemies[1] then bumpFoe = game.run.sea.enemies[1] end
    if bumpFoe and parkAdjacentTo(bumpFoe.x, bumpFoe.y) then break end
    bumpFoe = nil
  end
  expect(bumpFoe ~= nil, 'no sea foe with an open neighbor turned up in 4 sea regens')
  if bumpFoe then
    bumpFoe.t = 0
    tapCell(bumpFoe.x, bumpFoe.y)
    waitUntil(function() return engine.cur == 'shipBattle' end, 10)
    shot('sail-bump')
    engine.setState('sail')
    h.settle()
  end

  -- 10. Island bump: tryMove's blocked arm (sail_rules.lua). 'left'/'right'
  -- hops are unambiguous (+-1 on x, no facing-dependent diagonal), so park
  -- one hex to either side of an isle and press straight into it.
  local function findIsleBumpCase()
    for y = 0, game.SEA_H - 1 do
      for x = 0, game.SEA_W - 1 do
        if game.tileAt(x, y) == game.T_ISLE then
          if x + 1 < game.SEA_W and game.tileAt(x + 1, y) == game.T_WATER and not game.enemyAt(x + 1, y) then
            return x + 1, y, 'left'
          end
          if x - 1 >= 0 and game.tileAt(x - 1, y) == game.T_WATER and not game.enemyAt(x - 1, y) then
            return x - 1, y, 'right'
          end
        end
      end
    end
  end
  local isleSx, isleSy, isleDir = nil, nil, nil
  for _ = 1, 4 do
    game.genSea(3, 'calm')
    engine.setState('sail')
    wait(0.3)
    game.run.sea.enemies = {}
    isleSx, isleSy, isleDir = findIsleBumpCase()
    if isleSx then break end
  end
  expect(isleSx ~= nil, 'no island turned up a straight left/right bump case in 4 sea regens')
  if isleSx then
    local ship = game.run.ship
    ship.x, ship.y, ship.fx, ship.fy = isleSx, isleSy, isleSx, isleSy
    ship.route, ship.anim = nil, nil
    local px2, py2 = ship.x, ship.y
    tap(isleDir)
    wait(0.3)
    shot('sail-island-bump')
    expect(ship.x == px2 and ship.y == py2, 'bumping an island moved the ship instead of blocking it')
  end

  -- 11. Last-sea gossip: arriving at the port on the voyage's second-to-last
  -- sea (the index sail_rules.lua's handleArrival checks) shows the one-time
  -- gossip card -- and a bundled fire blueprint if it isn't already known --
  -- before continuing into dock instead of straight back to sail.
  game.run.gossipShown = false
  local lastSea = (game.run.voyage.length or 8) - 1
  local gpx, gpy = stageTile(game.T_PORT, function() game.genSea(lastSea, 'calm') end, 4)
  expect(gpx ~= nil, 'no port with an open neighbor turned up in 4 sea regens for the last-sea gossip')
  if gpx then
    tapCell(gpx, gpy)
    waitUntil(function() return engine.cur == 'loot' end, 10)
    h.settle()
    shot('sail-gossip')
    for _ = 1, 5 do
      if engine.cur ~= 'loot' then break end
      tap('z')
      wait(0.35)
    end
    waitUntil(function() return engine.cur == 'dock' and not engine.trans.on end, 10)
    expect(game.run.gossipShown, 'arriving at port on the last sea did not show the gossip card')
    tap('x') -- back to sea (dock.lua's BACK TO SEA/B share the same exit)
    waitUntil(function() return engine.cur == 'sail' end, 10)
  end

  -- 12. Kind-trader gift: too poor to buy (gold < 15) and no spare treasure
  -- to sell (>= 2 of a kind) collapses the two-way trade card into a plain
  -- +10 gold gift (sail_rules.lua's meetTrader).
  game.run.quest = nil
  game.run.gold = 5
  game.run.treas = {}
  local tgx, tgy = plantTile(game.T_TRADER, function() game.genSea(3, 'calm') end)
  if tgx then
    local goldBefore = game.run.gold
    tapCell(tgx, tgy)
    waitUntil(function() return engine.cur == 'loot' end, 10)
    h.settle()
    shot('sail-trader-gift')
    h.walkLoot()
    expect(game.run.gold == goldBefore + 10, 'a broke trader meeting did not grant the flat +10 gold gift')
    expect(h.meta.data.secrets.kindtrader, 'a broke trader gift did not find the kindtrader secret')
  end

  -- 13. Dig-anywhere: P1's A press next to any island hex ticks DIG DOG
  -- regardless of the (10% chance) seashell find.
  game.genSea(3, 'calm')
  engine.setState('sail')
  wait(0.3)
  game.run.sea.enemies = {}
  local digsBefore = h.meta.data.counts.digs or 0
  local function findIslandNeighbor()
    for y = 0, game.SEA_H - 1 do
      for x = 0, game.SEA_W - 1 do
        if game.tileAt(x, y) == game.T_ISLE then
          for _, nb in ipairs(grid.hexNeighbors(x, y)) do
            local nx, ny = nb[1], nb[2]
            if nx >= 0 and ny >= 0 and nx < game.SEA_W and ny < game.SEA_H
              and game.tileAt(nx, ny) == game.T_WATER and not game.enemyAt(nx, ny) then
              return nx, ny
            end
          end
        end
      end
    end
  end
  local digX, digY = findIslandNeighbor()
  expect(digX ~= nil, 'no island with an open neighbor turned up to stage a dig')
  if digX then
    local ship = game.run.ship
    ship.x, ship.y, ship.fx, ship.fy = digX, digY, digX, digY
    ship.route, ship.anim = nil, nil
    tap('z') -- P1's A button: the dig-anywhere verb
    wait(0.2)
    expect((h.meta.data.counts.digs or 0) == digsBefore + 1, 'digging near an island did not tick the digs counter')
  end

  -- Leave on a normal, clean sea for whatever runs after this module.
  game.genSea(3, 'calm')
  engine.setState('sail')
  wait(0.3)
end
