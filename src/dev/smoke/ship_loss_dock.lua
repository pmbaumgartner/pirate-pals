-- Ship-battle losses (capped banner + the real ablaze-tick route) and the
-- dock walk. Leaves the script solo on a fresh run for the sections after.
return function(ctx, h)
  local tap, wait, waitUntil, shot, expect =
    ctx.tap, ctx.wait, ctx.waitUntil, ctx.shot, ctx.expect
  local engine, game, input, shipBattle, CO = h.engine, h.game, h.input, h.shipBattle, h.CO

  -- Set up a ship battle loss to capture the capped-loss banner.
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

  -- Real ship-battle loss: force the deterministic ablaze-tick route to
  -- shipDown (backToTurnLogic, ship_battle.lua:395-409) instead of relying on
  -- foe FIRE rolls. MOVE resolves with no timing bar, so the round runs
  -- straight through to the ablaze tick, safeEscape, and back to sail.
  input.setCoop(false)
  game.newGame()
  engine.setState('sail')
  wait(0.3)

  local sbReal = h.startSmokeShipBattle({ lv = 1, name = 'TEST SLOOP', class = 'sloop' }, nil)
  local shReal = sbReal.ships[1]
  shReal.ablaze, shReal.hp, shReal.dodge = 1, 4, 0
  sbReal.foe.intent = 'fix'
  h.chooseSoloShipAction(sbReal, 1) -- MOVE
  waitUntil(function() return sbReal.over end, 8)
  expect(shReal.hp == 0, 'ablaze tick did not zero the player hull')
  waitUntil(function() return engine.cur == 'sail' and not engine.trans.on end, 5)
  expect(game.run ~= nil, 'run should still be intact after the ship-battle loss')
  shot('real-loss')

  -- Dock walk: TAILOR and DRY DOCK both return to dock (which resets its
  -- cursor to the top on every enter), then BACK TO SEA lands on sail.
  engine.setState('dock')
  wait(0.2)
  tap('z') -- TAILOR
  expect(engine.cur == 'tailor', 'dock did not open tailor')
  tap('x') -- back to dock
  expect(engine.cur == 'dock', 'tailor back did not return to dock')
  tap('down')
  tap('z') -- DRY DOCK
  expect(engine.cur == 'drydock', 'dock did not open drydock')
  tap('x') -- back to dock
  expect(engine.cur == 'dock', 'drydock back did not return to dock')
  wait(0.2)
  shot('dock')
  tap('down')
  tap('down')
  tap('z') -- BACK TO SEA
  expect(engine.cur == 'sail', 'dock BACK TO SEA did not return to sail')
  wait(0.2)
end
