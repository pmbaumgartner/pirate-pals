-- Sea variety: biome overrides, the treasure-map quest X, and the trader
-- buy card.
return function(ctx, h)
  local tap, wait, shot, expect = ctx.tap, ctx.wait, ctx.shot, ctx.expect
  local engine, game, loot = h.engine, h.game, h.loot

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
  h.settle()
  tap('z')
  wait(0.3)
  expect(game.run.gold == 25, 'trade buy did not cost 15 gold')
  tap('z') -- the inserted treasure card
  wait(1.0)
end
