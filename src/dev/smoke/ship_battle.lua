-- Ship battle: telegraph/HUD gallery via render-side pokes, then a real
-- mechanics pass per shot type, then MOVE/FIX/SPECIAL actions.
return function(ctx, h)
  local tap, wait, waitUntil, shot, expect =
    ctx.tap, ctx.wait, ctx.waitUntil, ctx.shot, ctx.expect
  local engine, game, data, shipBattle = h.engine, h.game, h.data, h.shipBattle

  game.run.fittings.slot = 'chain'
  shipBattle.start(game.run.sea.enemies[1])
  expect(engine.cur == 'shipBattle', 'shipBattle.start did not switch state')
  wait(2.5)

  -- Telegraph gallery: foe intents are pure render-side during the player's
  -- pick phase, so poke each one in and shot it for the CI artifact.
  local sbTel = shipBattle.sb
  waitUntil(function() return sbTel.turn == 'select' and not engine.trans.on end, 5)

  -- Set up the shot submenu preview screenshot. Force weak to a known shot
  -- so the artifact shows the mini_weak marker on its menu row.
  local oldWeak = sbTel.foe.weak
  sbTel.foe.weak = 'chain'
  sbTel.ships[1].submenu = 'shot'
  sbTel.ships[1].sub = 0
  wait(0.2)
  shot('ship-shot-submenu')
  sbTel.ships[1].submenu = nil
  sbTel.foe.weak = oldWeak

  -- Set up foe HUD details: hp, pips, stat stages, and ablaze.
  local oldFoeHp = sbTel.foe.hp
  local oldFoeSails = sbTel.foe.sailsStage
  local oldFoeGuns = sbTel.foe.gunsStage
  local oldFoeAblaze = sbTel.foe.ablaze
  local oldFoeRep = sbTel.foe.repairs
  local oldFoeMaxRep = sbTel.foe.maxRepairs

  sbTel.foe.hp = 12
  sbTel.foe.sailsStage = -1
  sbTel.foe.gunsStage = -1
  sbTel.foe.ablaze = 3
  sbTel.foe.repairs = 1
  sbTel.foe.maxRepairs = 2
  wait(0.2)
  shot('ship-foe-hud-details')

  -- Solo HUD screenshot
  shot('ship-solo-hud')

  -- Restore foe stats
  sbTel.foe.hp = oldFoeHp
  sbTel.foe.sailsStage = oldFoeSails
  sbTel.foe.gunsStage = oldFoeGuns
  sbTel.foe.ablaze = oldFoeAblaze
  sbTel.foe.repairs = oldFoeRep
  sbTel.foe.maxRepairs = oldFoeMaxRep
  for _, intent in ipairs({ 'fire', 'bigshot', 'volley', 'fix' }) do
    sbTel.foe.intent = intent
    wait(0.1)
    shot('ship-telegraph-' .. intent)
  end

  -- CREW SPECIALS submenu: the highlighted special's desc renders at the
  -- bottom of the box.
  sbTel.ships[1].submenu = 'special'
  sbTel.ships[1].sub = 0
  wait(0.1)
  shot('ship-sub-desc')
  sbTel.ships[1].submenu = nil

  -- Ship battle mechanics pass: these use the real menus, timing bars, cannon
  -- animation, impact handler, and foe-turn coroutine rather than only staging
  -- HUD state for screenshots.
  local sbChain = h.startSmokeShipBattle({ lv = 3, name = 'CHAIN SLOOP', class = 'sloop' }, 'chain')
  h.fireSoloShot(sbChain, 'chain')
  waitUntil(function() return sbChain.foe.sailsStage == -1 end, 5)
  expect(sbChain.ships[1].powder.chain == data.SHOTS.chain.powder - 1, 'CHAIN SHOT did not spend powder')
  shot('ship-chain-hit')

  local sbGrape = h.startSmokeShipBattle({ lv = 3, name = 'GRAPE BRIG', class = 'brig' }, 'grape')
  h.fireSoloShot(sbGrape, 'grape')
  waitUntil(function() return sbGrape.foe.gunsStage == -1 end, 5)
  expect(sbGrape.ships[1].powder.grape == data.SHOTS.grape.powder - 1, 'GRAPE SHOT did not spend powder')
  shot('ship-grape-hit')

  local sbFire = h.startSmokeShipBattle({ lv = 3, name = 'FIRE MAN-O-WAR', class = 'manowar' }, 'fire')
  h.fireSoloShot(sbFire, 'fire')
  waitUntil(function() return sbFire.foe.ablaze == 3 end, 5)
  expect(sbFire.ships[1].powder.fire == data.SHOTS.fire.powder - 1, 'FIRE SHOT did not spend powder')
  shot('ship-fire-ablaze')

  local sbKraken = h.startSmokeShipBattle({ lv = 9, name = 'THE KRAKEN', boss = true, kraken = true }, 'fire')
  expect(sbKraken.foe.class == 'kraken', 'kraken boss did not build the kraken ship state')
  shot('ship-kraken-ready')
  h.fireSoloShot(sbKraken, 'fire')
  expect(sbKraken.ships[1].powder.fire == data.SHOTS.fire.powder - 1, 'kraken FIRE SHOT did not spend powder')
  expect(not sbKraken.foe.ablaze, 'kraken should be immune to ablaze')
  shot('ship-kraken-immune')

  local sbAction = h.startSmokeShipBattle({ lv = 8, name = 'SMOKE KING', boss = true }, nil)
  local shAction = sbAction.ships[1]
  sbAction.foe.intent = 'bigshot'
  sbAction.foe.target = 1
  h.chooseSoloShipAction(sbAction, 1) -- MOVE
  waitUntil(function() return shAction.range == 'NEAR' and shAction.dodge > 0 end, 5)
  shot('ship-move-dodge')
  h.shipBattleReady(sbAction, 'select', 12)

  shAction.hp = math.max(1, shAction.max - 18)
  local hpBeforeFix = shAction.hp
  local repairsBeforeFix = shAction.repairs
  sbAction.foe.intent = 'fix'
  sbAction.foe.hp = math.max(1, sbAction.foe.max - 20)
  sbAction.foe.repairs = 1
  h.chooseSoloShipAction(sbAction, 2) -- FIX
  waitUntil(function() return shAction.hp > hpBeforeFix end, 5)
  expect(shAction.repairs == repairsBeforeFix - 1, 'FIX did not spend a repair pip')
  shot('ship-fix-action')
  h.shipBattleReady(sbAction, 'select', 12)

  sbAction.foe.intent = 'move'
  h.chooseSoloShipAction(sbAction, 3) -- SPECIAL
  waitUntil(function() return shAction.submenu == 'special' end, 3)
  tap('z')
  waitUntil(function() return sbAction.specUsed[game.run.party[1].name] end, 5)
  shot('ship-special-action')
  h.shipBattleReady(sbAction, 'select', 12)

  game.run.fittings.slot = nil
end
