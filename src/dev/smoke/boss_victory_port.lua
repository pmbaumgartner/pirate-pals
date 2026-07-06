-- The Pirate King boss sea, victory celebration, Home Port upgrades, and
-- New Voyage+ carry-over.
return function(ctx, h)
  local tap, wait, waitUntil, shot, expect =
    ctx.tap, ctx.wait, ctx.waitUntil, ctx.shot, ctx.expect
  local engine, game, meta, shipBattle, personBattle, CO =
    h.engine, h.game, h.meta, h.shipBattle, h.personBattle, h.CO

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

  -- Victory celebration.
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
  h.settle()
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
end
