-- Menu screens: crew, tailor (incl. SAILS re-pick), drydock, log,
-- voyage log via the real hotkey, and the read-only chart view.
return function(ctx, h)
  local tap, wait, shot, expect = ctx.tap, ctx.wait, ctx.shot, ctx.expect
  local engine, game, chart = h.engine, h.game, h.chart

  engine.setState('crew')
  wait(1.0)
  shot('crew')

  -- Crew list cursor starts on row 0, the captain (CAPPY). Snapshot the
  -- party so every branch below can be restored to it afterwards.
  local partySnapshot = {}
  for i, p in ipairs(game.run.party) do partySnapshot[i] = p end

  -- Hat cycle: right then left should round-trip the highlighted pal's
  -- outfit. This early in the run only NO HAT is owned, so the round trip
  -- is a genuine no-op -- still worth covering the branch.
  local cappy = game.run.crew[1]
  local startOut = cappy.out
  tap('right')
  wait(0.15)
  tap('left')
  wait(0.15)
  expect(cappy.out == startOut, 'hat cycle right+left did not return to the starting outfit')

  -- Captain-leave guard: the captain must sail, so Z on their row bumps.
  expect(cappy.role == 'captain', 'expected crew row 0 to be the captain')
  local partyBefore = #game.run.party
  tap('z')
  wait(0.15)
  expect(#game.run.party == partyBefore, 'captain-leave guard should not change the party')

  -- Leave + rejoin: FIN (row 1, non-captain) can leave and come back.
  tap('down')
  wait(0.15)
  local fin = game.run.crew[2]
  tap('z')
  wait(0.15)
  expect(not game.inParty(fin), 'Z on a party member should remove them from the party')
  tap('z')
  wait(0.15)
  expect(game.inParty(fin), 'Z on a napless non-party member should rejoin the party')

  -- Party-full bump / nap-blocks-join: by this point the party already
  -- equals the whole crew (CAPPY/FIN/SPARKY -- GULLY's recruit card in
  -- loot_cards.lua's opening gallery is shown but never advanced, so GULLY
  -- never actually joins), so there is no spare crew member to bump. Add a
  -- scratch pal to exercise both branches, then remove it again.
  local testy = game.makePirate('deckhand', 'TESTY', 1)
  game.run.crew[#game.run.crew + 1] = testy
  tap('down')
  wait(0.15)
  tap('down')
  wait(0.15)
  expect(not game.inParty(testy), 'TESTY should not start in the already-full party')
  local fullPartySize = #game.run.party
  tap('z')
  wait(0.15)
  expect(#game.run.party == fullPartySize and not game.inParty(testy),
    'a full party should refuse another join')
  shot('crew-full')

  -- Nap-blocks-join: a tuckered-out pal cannot join even with room.
  testy.nap = 1
  tap('z')
  wait(0.15)
  expect(not game.inParty(testy), 'a napping pal should not be able to join the party')
  testy.nap = nil

  -- Restore the crew/party this block touched.
  game.run.crew[#game.run.crew] = nil
  game.run.party = partySnapshot

  engine.setState('tailor')
  wait(1.0)
  shot('tailor')

  -- SHOP tab (tl.tab defaults to 'shop' on enter, tailor.lua:66): buy an
  -- affordable outfit, re-tap it for the OWNED bump, then an unaffordable
  -- and a milestone-locked row. Rows are the price/mile data.OUTFITS
  -- entries in order (tailor.lua's shopItems); row 0 = bandR (15G), row 1
  -- = patch (25G), rows 2-5 = souwester/straw/tri/parrot, row 6 = bandB
  -- (mile 3, no price).
  local goldSnap = game.run.gold
  local ownedSnap = { bandR = game.run.owned.bandR, patch = game.run.owned.patch, bandB = game.run.owned.bandB }
  local hatsSnap = h.meta.data.hats.bandR
  game.run.owned.bandR, game.run.owned.patch, game.run.owned.bandB = nil, nil, nil

  -- (a) row 0, affordable: buying spends exactly its price and flags it owned.
  game.run.gold = 15
  tap('z')
  wait(0.2)
  expect(game.run.gold == 0 and game.run.owned.bandR, 'affordable outfit purchase did not spend gold and mark it owned')
  shot('tailor-shop-bought')

  -- (b) row 0 again: already OWNED, so a re-buy bumps with no gold change.
  tap('z')
  wait(0.2)
  expect(game.run.gold == 0, 'buying an already-owned outfit should not change gold')

  -- (c) row 1 (patch, 25G): NEED MORE GOLD bump, no purchase.
  tap('down')
  wait(0.15)
  game.run.gold = 0
  tap('z')
  wait(0.2)
  expect(game.run.gold == 0 and not game.run.owned.patch, 'an unaffordable purchase should not deduct gold or mark it owned')

  -- (d) row 6 (bandB, milestone-locked, no price): LOCKED bump, no purchase.
  tap('down')
  wait(0.1)
  tap('down')
  wait(0.1)
  tap('down')
  wait(0.1)
  tap('down')
  wait(0.1)
  tap('down')
  wait(0.1)
  tap('z')
  wait(0.2)
  expect(game.run.gold == 0 and not game.run.owned.bandB, 'a milestone-locked row should not be purchasable with gold')
  shot('tailor-shop-locked')

  game.run.gold = goldSnap
  game.run.owned.bandR, game.run.owned.patch, game.run.owned.bandB =
    ownedSnap.bandR, ownedSnap.patch, ownedSnap.bandB
  h.meta.data.hats.bandR = hatsSnap

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

  -- Cursor starts on row 0 (HULL). Tier 1 costs exactly the seeded 4
  -- timber, so the purchase spends it all.
  tap('z')
  wait(0.2)
  expect(game.run.fittings.hull == 1, 'HULL purchase did not apply tier 1')
  expect(game.run.salvage.timber == 0, 'HULL purchase did not deduct the tier-1 timber cost')

  -- LACK MATERIALS: tier 2 needs timber the purchase above just spent.
  tap('z')
  wait(0.2)
  expect(game.run.fittings.hull == 1, 'an unaffordable purchase should not advance the tier')
  shot('drydock-upgraded')

  -- MAXED OUT: poking straight to the tier cap refuses further purchases.
  game.run.fittings.hull = 3
  tap('z')
  wait(0.2)
  expect(game.run.fittings.hull == 3, 'a maxed-out row should refuse further purchases')
  game.run.fittings.hull = 0

  -- MAGAZINE slot cycle: row 3, seeded with chain/fire blueprints.
  tap('down')
  wait(0.15)
  tap('down')
  wait(0.15)
  tap('down')
  wait(0.15)
  tap('right')
  wait(0.15)
  expect(game.run.fittings.slot == 'chain', 'magazine cycle right did not pick the first seeded blueprint shot')
  tap('left')
  wait(0.15)
  expect(game.run.fittings.slot == nil, 'magazine cycle left did not return to NONE')

  -- Fitted-ship sprite tier matrix: pure sprite builds hitting every sails
  -- (1/2/3), guns (0/1/2/3), and hull-row branch in buildFittedShip, plus
  -- the untouched (0,0,0) baseline. Rebuilt from the run's real fittings
  -- afterwards so the registered sprite matches the run again.
  local sprites = require 'src.sprites'
  local colorId = game.colorOf('p1')
  for _, tiers in ipairs({ { 0, 0, 0 }, { 1, 1, 1 }, { 2, 2, 2 }, { 3, 3, 3 } }) do
    sprites.buildFittedShip(colorId, tiers[1], tiers[2], tiers[3])
    expect(sprites.shipSprite(colorId) == 'ship_' .. colorId .. '_fitted',
      'buildFittedShip did not register the fitted ship sprite for tiers '
      .. tiers[1] .. '/' .. tiers[2] .. '/' .. tiers[3])
  end
  sprites.buildFittedShip(colorId)

  engine.setState('log')
  wait(1.0)
  shot('log')

  -- SECRETS and DEEDS tabs: the CREW hotkey ('c') cycles TREASURE ->
  -- SECRETS -> DEEDS -> TREASURE, all sibling slot-grid tabs.
  tap('c')
  wait(0.3)
  shot('log-secrets')
  tap('c')
  wait(0.3)
  shot('log-deeds')
  tap('c')
  wait(0.2)

  -- Back key ('x') returns straight to sail.
  tap('x')
  wait(0.2)
  expect(engine.cur == 'sail', 'log back (x) did not return to sail')

  -- Voyage Log screen: opened via the real L hotkey from sail, shows
  -- the moments logged above, and B returns to sail.
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
