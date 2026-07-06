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
  end

  -- 2/3. Bottle and trader share one event-tile slot per sea, so regen
  -- until both have turned up at least once.
  local sawBottle, sawTrader = false, false
  for _ = 1, 6 do
    if sawBottle and sawTrader then break end
    game.run.quest = nil
    game.run.gold = 40
    game.genSea(3, 'calm')
    engine.setState('sail')
    wait(0.3)
    game.run.sea.enemies = {}

    if not sawBottle then
      local bx, by = findTile(game.T_BOTTLE)
      if bx and parkAdjacentTo(bx, by) then
        tapCell(bx, by)
        h.walkLoot()
        expect(game.run.quest ~= nil, 'finding the bottle did not set a quest')
        sawBottle = true
      end
    end

    if not sawTrader then
      local tx, ty = findTile(game.T_TRADER)
      if tx and parkAdjacentTo(tx, ty) then
        tapCell(tx, ty)
        waitUntil(function() return engine.cur == 'loot' end, 10)
        h.settle()
        tap('z') -- buy option is the default choice when gold >= 15
        h.walkLoot()
        sawTrader = true
      end
    end
  end
  expect(sawBottle, 'the bottle tile never spawned across 6 sea regens')
  expect(sawTrader, 'the trader tile never spawned across 6 sea regens')

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
end
