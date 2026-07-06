-- Color-select confirm/launch paths: title_flow.lua deliberately backs out
-- of colorSelect without launching, so this module drives both real
-- launches (solo instant-confirm, and captains' two-cursor pick incl. the
-- taken-swatch skip). Runs dead last in the smoke walk -- both flows below
-- overwrite game.run via game.newGame, which nothing later depends on.
return function(ctx, h)
  local tap, tap2, wait, waitUntil, shot, expect =
    ctx.tap, ctx.tap2, ctx.wait, ctx.waitUntil, ctx.shot, ctx.expect
  local engine, game, data, input = h.engine, h.game, h.data, h.input

  -- Solo launch: a save exists by now, so CONTINUE is bound to 'z' and NEW
  -- VOYAGE to 'x' (title.lua: hasSave and 'b' or 'a', i.e. 'x' when a save
  -- exists). modeSelect starts on SOLO (index 0); confirming with no P2
  -- launches immediately from a single cursor move.
  engine.setState('title')
  wait(0.3)
  tap(game.hasSave() and 'x' or 'z')
  expect(engine.cur == 'modeSelect', 'title did not open modeSelect')
  tap('z')
  expect(engine.cur == 'colorSelect', 'modeSelect Z did not open colorSelect (solo)')
  tap('right')
  wait(0.15)
  tap('z')
  waitUntil(function() return engine.cur == 'sail' end, 10)
  h.settle()
  expect(game.colorOf('p1') == data.PLAYER_COLORS[2].id,
    'solo color-select launch did not apply the picked swatch')

  -- Captains two-cursor pick: back to title, into modeSelect (RIGHT to the
  -- second card), into colorSelect in captains mode (two cursors).
  engine.setState('title')
  wait(0.3)
  tap(game.hasSave() and 'x' or 'z')
  expect(engine.cur == 'modeSelect', 'title did not reopen modeSelect for captains')
  tap('right')
  wait(0.15)
  tap('z')
  expect(engine.cur == 'colorSelect', 'modeSelect Z did not open colorSelect (captains)')

  -- P1 confirms first (locks swatch index 0) and waits on P2.
  tap('z')
  wait(0.15)
  expect(engine.cur == 'colorSelect', "P1's confirm should wait on P2, not launch alone")

  -- Taken-swatch skip: P2 starts at index 4; walking left toward P1's
  -- locked index 0 must hop over it (moveCursor/takenBy in colorselect.lua).
  for _ = 1, 4 do
    tap2('left')
    wait(0.1)
  end
  shot('colorselect-captains')

  -- P2 confirms; both ready triggers the launch.
  tap2('a')
  waitUntil(function() return engine.cur == 'sail' end, 10)
  h.settle()
  expect(game.run.mode == 'captains', 'captains color-select launch did not set run.mode')
  expect(game.run.ship2 ~= nil, 'captains launch did not create ship2')
  expect(game.colorOf('p1') ~= game.colorOf('p2'), "captains launch gave both players the same color")

  -- newGame() doesn't touch coop; M.start turned it on for the picker and
  -- it must not leak into whatever runs after this module.
  input.setCoop(false)
end
