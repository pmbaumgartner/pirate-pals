-- A basic boarding walk, then the loot-card gallery: gold/treasure/level/
-- recruit/clear, perk pick, bond card, first-recruit voyage log, and naps.
return function(ctx, h)
  local tap, wait, waitUntil, shot, expect =
    ctx.tap, ctx.wait, ctx.waitUntil, ctx.shot, ctx.expect
  local engine, game, data, personBattle, loot =
    h.engine, h.game, h.data, h.personBattle, h.loot

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

  -- Roster pressure and level-up choices.

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

  -- Best Mates card is a plain display card; just make sure it advances.
  loot.start({ { type = 'bond', a = 'CAPPY', b = 'FIN' } }, 'TEST BOND')
  h.settle()
  tap('z')
  waitUntil(function() return engine.cur == 'sail' end, 5)

  -- Voyage Log: accepting a recruit logs a one-time "first recruit"
  -- moment, gated on the starting crew size (still 2 here -- CAPPY/FIN only).
  local logBefore = #game.run.log
  loot.start({ { type = 'recruit', pirate = game.makePirate('deckhand', 'SPARKY', 1) } }, 'TEST RECRUIT')
  h.settle()
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
end
