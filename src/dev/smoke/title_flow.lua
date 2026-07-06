-- Title + mode select: walked via the real input path (not setState) before
-- the deterministic run starts, so the title<->modeSelect wiring gets
-- exercised. hasSave decides which key opens modeSelect (title.lua binds
-- CONTINUE to 'a' only when a save exists, bumping NEW VOYAGE to 'b').
return function(ctx, h)
  local tap, wait, waitUntil, shot, expect =
    ctx.tap, ctx.wait, ctx.waitUntil, ctx.shot, ctx.expect
  local engine, game = h.engine, h.game

  engine.setState('title')
  waitUntil(function() return math.floor(engine.gt * 2) % 2 == 0 end, 1)
  shot('title')
  tap(game.hasSave() and 'x' or 'z')
  expect(engine.cur == 'modeSelect', 'title did not open modeSelect')
  tap('left')
  wait(0.2)
  tap('right')
  wait(0.2)
  shot('modeselect')
  -- Color selector sits between mode pick and the new run; back out of both
  -- (Z here would start a run, which the deterministic sections own).
  tap('z')
  wait(0.2)
  expect(engine.cur == 'colorSelect', 'modeSelect Z did not open colorSelect')
  tap('right')
  wait(0.2)
  shot('colorselect')
  tap('x')
  wait(0.2)
  expect(engine.cur == 'modeSelect', 'colorSelect back did not return to modeSelect')
  tap('x')
  wait(0.2)
  expect(engine.cur == 'title', 'expected modeSelect back to return to title')
end
