-- Menu screens: crew, tailor (incl. SAILS re-pick), drydock, log,
-- voyage log via the real hotkey, and the read-only chart view.
return function(ctx, h)
  local tap, wait, shot, expect = ctx.tap, ctx.wait, ctx.shot, ctx.expect
  local engine, game, chart = h.engine, h.game, h.chart

  engine.setState('crew')
  wait(1.0)
  shot('crew')
  engine.setState('tailor')
  wait(1.0)
  shot('tailor')

  -- SAILS tab (color selector): a free mid-run re-pick at the tailor.
  tap('left')
  wait(0.2)
  shot('tailor-sails')
  tap('down')
  wait(0.2)
  tap('z')
  wait(0.3)
  expect(game.colorOf('p1') == 'red', 'SAILS tab did not re-pick the crew color')

  -- DRY DOCK screenshot
  game.run.salvage.timber = 4
  game.run.salvage.cloth = 7
  game.run.salvage.iron = 2
  game.run.blueprints.fire = true
  game.run.blueprints.chain = true
  engine.setState('drydock')
  wait(1.0)
  shot('drydock')

  engine.setState('log')
  wait(1.0)
  shot('log')

  -- Voyage Log screen: opened via the real L hotkey from sail, shows
  -- the moments logged above, and B returns to sail.
  engine.setState('sail')
  wait(0.2)
  tap('l')
  expect(engine.cur == 'voyagelog', 'L hotkey did not open the voyage log from sail')
  wait(0.3)
  shot('voyagelog')
  tap('x')
  wait(0.2)
  expect(engine.cur == 'sail', 'expected voyagelog back to return to sail')

  -- Voyage chart: read-only view, then back to sail.
  chart.startView()
  expect(engine.cur == 'chart', 'chart.startView did not switch state')
  wait(0.3)
  shot('chart-view')
  tap('x')
  wait(0.3)
  expect(engine.cur == 'sail', 'expected back on sail after chart view')
end
