-- Boarding galleries: the crab+thief gimmick verbs, readability shots for
-- intents/act-menu/previews/floaters, and the deck-shape gallery.
return function(ctx, h)
  local tap, wait, waitUntil, shot, expect =
    ctx.tap, ctx.wait, ctx.waitUntil, ctx.shot, ctx.expect
  local engine, game, grid, personBattle = h.engine, h.game, h.grid, h.personBattle

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
  expect(h.meta.data.secrets.sogybird, 'shoving the thief parrot into the splash did not find the sogybird secret')
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
end
