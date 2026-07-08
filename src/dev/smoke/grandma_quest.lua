-- Grandma and the Pirates questline: Oliver's island loot card (which flips
-- run.grandmaQuest), then the sea >=5 grandmaBox boarding beat (smashing the
-- SHAKY BOX pops pb.grandmaFound; winning the fight banks run.grandmaRescued
-- and a GRANDMA recruit card).
return function(ctx, h)
  local tap, tapCell, wait, waitUntil, shot, expect =
    ctx.tap, ctx.tapCell, ctx.wait, ctx.waitUntil, ctx.shot, ctx.expect
  local engine, game, grid = h.engine, h.game, h.grid
  local personBattle, ai = h.personBattle, h.pbAi
  local foeOf, teleport, freeNeighbor = h.foeOf, h.teleport, h.freeNeighbor
  local palAttack, walkLoot = h.palAttack, h.walkLoot

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

  local function findTile(tt)
    for y = 0, game.SEA_H - 1 do
      for x = 0, game.SEA_W - 1 do
        if game.tileAt(x, y) == tt then return x, y end
      end
    end
  end

  -- Beat 1: sail onto Oliver's island. placeSpecials (game.lua) guarantees a
  -- T_OLIVER tile on sea 3/4 while the quest is unstarted, but regen a couple
  -- of times in case a crowded gen or a blocked neighbor ate the first try.
  game.run.grandmaQuest = nil
  game.run.grandmaRescued = nil
  local ox, oy = nil, nil
  for _ = 1, 4 do
    game.genSea(3, 'calm')
    engine.setState('sail')
    wait(0.3)
    game.run.sea.enemies = {}
    local tx, ty = findTile(game.T_OLIVER)
    if tx and parkAdjacentTo(tx, ty) then
      ox, oy = tx, ty
      break
    end
  end
  expect(ox ~= nil, 'no Oliver tile with an open neighbor turned up in 4 sea regens')

  if ox then
    tapCell(ox, oy)
    waitUntil(function() return engine.cur == 'loot' end, 10)
    h.settle()
    expect(game.run.grandmaQuest == true, 'meeting Oliver did not set run.grandmaQuest')
    shot('grandma-oliver')
    walkLoot()
    expect(engine.cur == 'sail' and not engine.trans.on, 'Oliver card did not return to sail')
  end

  -- Beat 2: Grandma's box rides one random foe from sea 5 on. Regen until a
  -- non-boss sea turns up an enemy roster with the flag (game.lua requires
  -- #enemies > 0), then board that exact foe with a small, deterministic
  -- comp so the grunt is easy to finish off after the box is smashed.
  game.run.grandmaQuest = true
  game.run.grandmaRescued = nil
  local boxFoe = nil
  for _ = 1, 6 do
    game.genSea(5, 'calm')
    engine.setState('sail')
    wait(0.3)
    for _, e in ipairs(game.run.sea.enemies) do
      if e.grandmaBox then
        boxFoe = e
        break
      end
    end
    if boxFoe then break end
  end
  expect(boxFoe ~= nil, 'no grandmaBox-flagged enemy turned up in 6 sea-5 regens')

  if boxFoe then
    game.run.party = { game.run.crew[1], game.run.crew[2] }
    personBattle.start(boxFoe, { 'grunt' }, 'classic')
    expect(engine.cur == 'personBattle', 'scripted grandma-box boarding did not start')
    wait(0.3)
    local pb = personBattle.pb
    expect(pb.grandmaBoxK ~= nil, 'boarding a grandmaBox foe did not seed pb.grandmaBoxK')
    shot('grandma-box')

    local grunt = foeOf(pb, 'grunt')
    grunt.hp = 1
    local cu, fu = pb.units[1], pb.units[2]
    local gx, gy = grid.parseKey(pb.grandmaBoxK)
    teleport(cu, freeNeighbor(pb, gx, gy))
    teleport(fu, freeNeighbor(pb, grunt.x, grunt.y))
    ai.planFoeIntents()

    -- Drive CAPPY onto the ATTACK target stage, then pick the SHAKY BOX
    -- entry directly (adjacentCrates is appended after the live targets, so
    -- pressing straight to confirm could hit the grunt instead).
    local pl = pb.pl.p1
    pl.sel, pl.stage = nil, 'pick'
    pl.cursor.x, pl.cursor.y = cu.x, cu.y
    tap('z') -- select
    wait(0.2)
    tap('z') -- move in place -> act menu
    wait(0.2)
    expect(pl.stage == 'act', 'CAPPY did not reach the act menu next to the box')
    tap('z') -- ATTACK -> target stage
    wait(0.2)
    expect(pl.stage == 'target', 'attack did not reach the target stage')
    local boxIdx = nil
    for i, t in ipairs(pl.targets) do
      if t.isCrate and grid.gk(t.x, t.y) == pb.grandmaBoxK then boxIdx = i - 1 end
    end
    expect(boxIdx ~= nil, 'the SHAKY BOX was not offered as an attack target')
    pl.tIdx = boxIdx
    tap('z') -- confirm -> smashCrate -> popGrandma (instant, no timing bar)
    wait(0.3)
    expect(pb.grandmaFound == true, 'smashing the SHAKY BOX did not set pb.grandmaFound')
    shot('grandma-found')

    -- Finish the lone grunt (1 hp) with FIN to end the battle and roll into
    -- victoryLoot's grandma-rescue branch.
    palAttack(pb, fu, h.landTimingPerfect)
    expect(pb.over, 'perfect hit on the 1-hp grunt did not end the grandma-box battle')
    local seen = {}
    walkLoot(seen)
    expect(seen.recruit, "grandma's rescue win did not offer a recruit card")
    expect(game.run.grandmaRescued == true, 'winning the grandma-box battle did not set run.grandmaRescued')
    local hasGrandma = false
    for _, p in ipairs(game.run.crew) do
      if p.role == 'grandma' then hasGrandma = true end
    end
    expect(hasGrandma, "accepting the recruit card did not add GRANDMA to run.crew")
  end

  -- Leave on a clean sea for whatever runs after this module.
  game.genSea(3, 'calm')
  engine.setState('sail')
  wait(0.3)
end
