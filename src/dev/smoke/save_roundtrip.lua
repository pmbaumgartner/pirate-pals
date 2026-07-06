-- Save -> CONTINUE round-trip: gold and crew survive the save/load cycle,
-- and run.party keeps its reference identity into run.crew (game.lua:661-673).
return function(ctx, h)
  local tap, wait, waitUntil, expect = ctx.tap, ctx.wait, ctx.waitUntil, ctx.expect
  local engine, game = h.engine, h.game

  game.run.gold = 123
  game.save()
  expect(game.hasSave(), 'game.save() did not create a save file')
  local crewCountBefore = #game.run.crew

  engine.setState('title')
  wait(0.2)
  tap('z') -- CONTINUE (bound to 'a' when a save exists; title.lua:30-35)
  waitUntil(function() return engine.cur == 'sail' and not engine.trans.on end, 5)
  expect(game.run.gold == 123, 'CONTINUE did not round-trip run.gold')
  expect(#game.run.crew == crewCountBefore, 'CONTINUE did not round-trip the crew roster')
  local partyIsCrewRef = false
  for _, c in ipairs(game.run.crew) do
    if c == game.run.party[1] then partyIsCrewRef = true end
  end
  expect(partyIsCrewRef, 'loaded run.party[1] is not reference-identical to a run.crew entry')
end
