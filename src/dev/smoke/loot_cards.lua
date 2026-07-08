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
  expect(h.meta.data.deeds.firstpal, 'the voyage-first recruit did not earn the firstpal deed')
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

  -- Draw-only cards: salvage bag, treasure map bottle, blueprint pickup, an
  -- outfit unlock, and the roaming gossip lore card -- none of these take
  -- input beyond advancing.
  loot.start({
    { type = 'salvage', material = 'timber', n = 2 },
    { type = 'bottle', sea = 5 },
    { type = 'blueprint_single', id = 'grape' },
    { type = 'unlock', id = 'bandR' },
    { type = 'gossip' },
  }, 'TEST DRAW')
  h.settle()
  shot('loot-cards-2')
  for _ = 1, 5 do
    tap('z')
    wait(0.35)
  end
  waitUntil(function() return engine.cur == 'sail' end, 5)

  -- Trade SELL: the mirror of sea_biomes.lua's trade-buy branch. Selecting
  -- option 2 sells a held treasure for gold instead of buying one.
  game.run.treas.coin = 2
  local goldBefore = game.run.gold
  loot.start({
    { type = 'trade', choice = 1, options = {
      { id = 'buy', name = 'GET A SHINY', desc = 'PAY 15 GOLD', ok = true },
      { id = 'sell', name = 'SWAP A SPARE', desc = 'GET 25 GOLD', ok = true, tid = 'coin' },
    } },
  }, 'TEST TRADE SELL')
  h.settle()
  tap('right')
  wait(0.15)
  tap('z')
  wait(0.3)
  expect(game.run.gold == goldBefore + 25, 'trade sell did not award 25 gold')
  expect(game.run.treas.coin == 1, 'trade sell did not deduct the sold treasure')
  tap('z') -- the inserted gold card
  wait(0.3)
  waitUntil(function() return engine.cur == 'sail' end, 5)
end
