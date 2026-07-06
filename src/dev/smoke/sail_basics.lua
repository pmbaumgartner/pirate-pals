-- Fresh run onto the sail state: arrow steering plus tap-to-sail.
return function(ctx, h)
  local tap, tapCell, wait, shot = ctx.tap, ctx.tapCell, ctx.wait, ctx.shot
  local engine, game, meta = h.engine, h.game, h.meta

  meta.newMeta()
  game.newGame()
  engine.setState('sail')
  wait(0.5)

  tap('right')
  tap('up')
  tap('down')

  -- Tap the whirlpool (always reachable) to exercise tap-to-sail.
  local e = game.run.sea.exit
  tapCell(e.x, e.y)
  wait(1.0)

  shot('sail')
end
