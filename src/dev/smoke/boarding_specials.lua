-- Boarding specials + terrain coverage, run after boarding_real: the four
-- role specials (captain rally, strongman smash, medic heal, sharpshooter
-- longshot), the COVER modifier, a real walkWithTerrain move, an ice slide,
-- a blocked shove bonk, the grape-sweep hp halving, target-stage backing
-- out, moveCursor's hole-skip, the soggy turn forfeits on both sides, and
-- the foe gunner's perch climb. Leaves crew/party/sea exactly as found
-- (a fresh solo run: crew CAPPY+FIN+one recruit, party CAPPY+FIN, sea 3 calm).
return function(ctx, h)
  local tap, wait, waitUntil, shot, expect =
    ctx.tap, ctx.wait, ctx.waitUntil, ctx.shot, ctx.expect
  local engine, game, grid = h.engine, h.game, h.grid
  local model, ai = h.pbModel, h.pbAi
  local bootBoarding, foeOf, teleport, freeNeighbor, freeTileAwayFrom =
    h.bootBoarding, h.foeOf, h.teleport, h.freeNeighbor, h.freeTileAwayFrom
  local openActMenu, palAttack, palMenuPick = h.openActMenu, h.palAttack, h.palMenuPick
  local palStay, partyPhase, timing = h.palStay, h.partyPhase, h.timing
  local gk = grid.gk

  local run = game.run
  local crewSnapshot, partySnapshot = {}, {}
  for i, p in ipairs(run.crew) do crewSnapshot[i] = p end
  for i, p in ipairs(run.party) do partySnapshot[i] = p end

  -- Scratch specialists: appended to run.crew (like menus.lua's TESTY) so
  -- run.party keeps pointing into run.crew, then dropped at the end.
  local cappy, fin = run.crew[1], run.crew[2]
  local strongman = game.makePirate('strongman', 'BRUTUS', 1)
  local medic = game.makePirate('medic', 'DOC', 1)
  local sharp = game.makePirate('sharpshooter', 'SNIPE', 1)
  run.crew[#run.crew + 1] = strongman
  run.crew[#run.crew + 1] = medic
  run.crew[#run.crew + 1] = sharp

  -- A free deck tile within [lo, hi] manhattan of (x, y) -- freeTileAwayFrom
  -- only bounds the lower edge, which isn't enough to stay inside an attack
  -- or move range.
  local function freeTileAtRange(pb, x, y, lo, hi)
    for _, t in ipairs(pb.deckList) do
      local d = grid.manhattan(t[1], t[2], x, y)
      if d >= lo and d <= hi and not model.unitAt(t[1], t[2]) and not pb.crates[gk(t[1], t[2])] then
        return t[1], t[2]
      end
    end
    expect(false, 'no free tile within ' .. lo .. '-' .. hi .. ' of ' .. x .. ',' .. y)
  end

  -- Drive a unit through pick -> move -> a chosen tile via the real
  -- walkWithTerrain path (as opposed to openActMenu's move-in-place).
  local function movePalTo(pb, u, tx, ty)
    pb.pl.p1.sel, pb.pl.p1.stage = nil, 'pick'
    pb.pl.p1.cursor.x, pb.pl.p1.cursor.y = u.x, u.y
    tap('z') -- select -> move stage
    wait(0.2)
    pb.pl.p1.cursor.x, pb.pl.p1.cursor.y = tx, ty
    tap('z') -- confirm the move -> bfsPath + walkWithTerrain
    waitUntil(function() return pb.pl.p1.stage == 'act' end, 5)
  end

  -- 1: CAPPY's rally special -- alliesOf + the +2 ATK buff on every ally
  -- (including the captain).
  local pb1 = bootBoarding({ lv = 2, name = 'RALLY FOE', class = 'sloop' }, { 'grunt' }, 'classic', { cappy, fin })
  local grunt1 = foeOf(pb1, 'grunt')
  local cappyU1, finU1 = pb1.units[1], pb1.units[2]
  teleport(grunt1, freeTileAwayFrom(pb1, cappyU1.x, cappyU1.y, 4))
  ai.planFoeIntents()
  palMenuPick(pb1, cappyU1, 2) -- SPECIAL row
  expect(cappyU1.buff == 2 and finU1.buff == 2, 'captain rally did not buff both allies +2 ATK')
  shot('boarding-rally')
  engine.setState('sail')
  wait(0.3)

  -- 2: strongman SMASH -- hits every adjacent foe and destroys adjacent
  -- crates in the same swing.
  local pb2 = bootBoarding({ lv = 2, name = 'SMASH FOE', class = 'sloop' }, { 'grunt' }, 'classic', { cappy, strongman })
  local grunt2 = foeOf(pb2, 'grunt')
  local smU2 = pb2.units[2]
  teleport(smU2, freeNeighbor(pb2, grunt2.x, grunt2.y))
  local crateX2, crateY2 = freeNeighbor(pb2, smU2.x, smU2.y)
  pb2.crates[gk(crateX2, crateY2)] = true
  ai.planFoeIntents()
  local gruntHp2 = grunt2.hp
  palMenuPick(pb2, smU2, 2) -- SPECIAL row -> opens the timing bar
  h.landTiming()
  wait(0.3)
  expect(grunt2.hp < gruntHp2, 'strongman smash did not damage the adjacent grunt')
  expect(pb2.crates[gk(crateX2, crateY2)] == nil, 'strongman smash did not destroy the adjacent crate')
  engine.setState('sail')
  wait(0.3)

  -- 3: medic PATCH UP -- heals a hurt ally +8.
  local pb3 = bootBoarding({ lv = 2, name = 'HEAL FOE', class = 'sloop' }, { 'grunt' }, 'classic', { cappy, medic })
  local grunt3 = foeOf(pb3, 'grunt')
  local capU3, medU3 = pb3.units[1], pb3.units[2]
  teleport(grunt3, freeTileAwayFrom(pb3, capU3.x, capU3.y, 4))
  ai.planFoeIntents()
  capU3.hp = math.max(1, capU3.max - 6)
  local hpBefore3 = capU3.hp
  palMenuPick(pb3, medU3, 2) -- SPECIAL row -> target stage (heal)
  expect(pb3.pl.p1.stage == 'target', 'medic special did not reach the target stage')
  tap('z') -- confirm heal on the only hurt ally
  wait(0.3)
  expect(capU3.hp == math.min(capU3.max, hpBefore3 + 8), 'medic heal did not restore +8 hp')
  engine.setState('sail')
  wait(0.3)

  -- 4: sharpshooter LONG SHOT -- ignoreCover, range 99.
  local pb4 = bootBoarding({ lv = 2, name = 'LONGSHOT FOE', class = 'sloop' }, { 'grunt' }, 'classic', { cappy, sharp })
  local grunt4 = foeOf(pb4, 'grunt')
  local ssU4 = pb4.units[2]
  teleport(grunt4, freeTileAwayFrom(pb4, ssU4.x, ssU4.y, 4))
  ai.planFoeIntents()
  local hpBefore4 = grunt4.hp
  palMenuPick(pb4, ssU4, 2) -- SPECIAL row -> target stage (longshot)
  expect(pb4.pl.p1.stage == 'target', 'sharpshooter special did not reach the target stage')
  tap('z') -- confirm target -> timing bar
  h.landTiming()
  wait(0.3)
  expect(grunt4.hp < hpBefore4, 'longshot did not damage the distant grunt')
  engine.setState('sail')
  wait(0.3)

  -- 5: COVER modifier -- a plain ranged ATTACK (not the special) at a foe
  -- that isn't adjacent but has a crate next to it halves the hit.
  local pb5 = bootBoarding({ lv = 2, name = 'COVER FOE', class = 'sloop' }, { 'grunt' }, 'classic', { cappy, sharp })
  local grunt5 = foeOf(pb5, 'grunt')
  local ssU5 = pb5.units[2]
  local sx5, sy5 = freeTileAtRange(pb5, grunt5.x, grunt5.y, 2, 3)
  teleport(ssU5, sx5, sy5)
  local crateX5, crateY5 = freeNeighbor(pb5, grunt5.x, grunt5.y)
  pb5.crates[gk(crateX5, crateY5)] = true
  ai.planFoeIntents()
  local hpBefore5 = grunt5.hp
  palAttack(pb5, ssU5, h.landTiming)
  expect(grunt5.hp < hpBefore5, 'covered attack did not chip the grunt')
  local coverNoted = false
  for _, f in ipairs(engine.floaters) do
    if f.text == 'COVER!' then coverNoted = true end
  end
  expect(coverNoted, 'covered attack did not surface the COVER modifier note')
  shot('boarding-cover')
  engine.setState('sail')
  wait(0.3)

  -- 6: real player movement -- cursor-tap a reachable tile from the move
  -- stage, exercising walkWithTerrain's normal (non-ice) path.
  local pb6 = bootBoarding({ lv = 2, name = 'WALK FOE', class = 'sloop' }, { 'grunt' }, 'classic', { cappy, fin })
  local grunt6 = foeOf(pb6, 'grunt')
  local capU6 = pb6.units[1]
  teleport(grunt6, freeTileAwayFrom(pb6, capU6.x, capU6.y, 4))
  ai.planFoeIntents()
  local tx6, ty6 = freeTileAtRange(pb6, capU6.x, capU6.y, 2, capU6.move)
  movePalTo(pb6, capU6, tx6, ty6)
  expect(capU6.x == tx6 and capU6.y == ty6, 'real movement did not land the pal on the tapped tile')
  engine.setState('sail')
  wait(0.3)

  -- 7: ice slide -- tidepool deck. adjustPathForIce continues the pal one
  -- tile past wherever it lands on ice, in the direction it was already
  -- traveling: off the deck (splash: soggy + damage) if that tile is a
  -- gap, or onto it (a further, unrequested tile) if it's open ground.
  -- Either way the pal ends up somewhere other than the tapped ice tile.
  local oldBiome = run.sea.biome
  run.sea.biome = 'icy'
  local pb7 = bootBoarding({ lv = 3, name = 'ICE FOE', class = 'sloop' }, { 'grunt' }, 'tidepool', { cappy, fin })
  run.sea.biome = oldBiome
  local grunt7 = foeOf(pb7, 'grunt')
  local capU7 = pb7.units[1]
  -- Find an (ice tile, approach direction) pair where the tile behind it
  -- (to place the pal) is free, and the tile ahead of it (the slide
  -- continuation) is either off-deck (splash) or free deck (keeps
  -- sliding) -- not blocked by a unit or crate, which would leave the pal
  -- parked on the tapped tile with no observable effect.
  local iceX, iceY, startX7, startY7
  for _, t in ipairs(pb7.deckList) do
    if not iceX and pb7.ice[gk(t[1], t[2])] then
      for _, d in ipairs(grid.DIRS4) do
        local sx, sy = t[1] - d[1], t[2] - d[2]
        local nx, ny = t[1] + d[1], t[2] + d[2]
        local aheadClear = not model.inDeck(nx, ny)
          or (not model.unitAt(nx, ny) and not pb7.crates[gk(nx, ny)])
        if model.inDeck(sx, sy) and not model.unitAt(sx, sy) and not pb7.crates[gk(sx, sy)] and aheadClear then
          iceX, iceY, startX7, startY7 = t[1], t[2], sx, sy
          break
        end
      end
    end
  end
  expect(iceX ~= nil, 'tidepool boarding did not yield a usable ice tile + approach direction')
  teleport(capU7, startX7, startY7)
  teleport(grunt7, freeTileAwayFrom(pb7, capU7.x, capU7.y, 4))
  ai.planFoeIntents()
  movePalTo(pb7, capU7, iceX, iceY)
  expect((capU7.x ~= iceX or capU7.y ~= iceY) or capU7.soggy,
    'ice slide did not push the pal past the tapped tile')
  shot('boarding-ice')
  engine.setState('sail')
  wait(0.3)

  -- 8: shove blocked by a crate -- slideTarget's 'blocked' stop, the BONK
  -- impact, and the target staying put.
  local pb8 = bootBoarding({ lv = 2, name = 'SHOVE FOE', class = 'sloop' }, { 'grunt' }, 'classic', { cappy, fin })
  local grunt8 = foeOf(pb8, 'grunt')
  local finU8 = pb8.units[2]
  teleport(finU8, 3, 2)
  teleport(grunt8, 4, 2)
  pb8.crates[gk(5, 2)] = true -- blocks the shove one tile past the target
  ai.planFoeIntents()
  local gruntHp8 = grunt8.hp
  palMenuPick(pb8, finU8, 2) -- SPECIAL row -> target stage (shove)
  expect(pb8.pl.p1.stage == 'target', 'shove special did not reach the target stage')
  tap('z') -- confirm shove on the grunt
  wait(0.3)
  expect(grunt8.x == 4 and grunt8.y == 2, 'a blocked shove should not move the target')
  expect(grunt8.hp == math.max(0, gruntHp8 - 5), 'blocked shove did not land its bonk damage')
  engine.setState('sail')
  wait(0.3)

  -- 9: Grape Shot deck sweep -- foe.gunsStage < 0 halves the first enemy's
  -- hp at boarding start.
  local pb9 = bootBoarding(
    { lv = 2, name = 'GRAPE FOE', class = 'sloop', gunsStage = -1 }, { 'grunt' }, 'classic', { cappy, fin })
  local grunt9 = foeOf(pb9, 'grunt')
  expect(grunt9.hp == math.floor(grunt9.max / 2), 'grape-shot sweep did not halve the first enemy hp')
  engine.setState('sail')
  wait(0.3)

  -- 10: target-stage B-back -- X on the target stage returns to the act menu.
  local pb10 = bootBoarding({ lv = 2, name = 'BACK FOE', class = 'sloop' }, { 'grunt' }, 'classic', { cappy, fin })
  local grunt10 = foeOf(pb10, 'grunt')
  local capU10 = pb10.units[1]
  teleport(grunt10, freeNeighbor(pb10, capU10.x, capU10.y))
  ai.planFoeIntents()
  openActMenu(pb10, capU10)
  tap('z') -- ATTACK -> target stage
  wait(0.2)
  expect(pb10.pl.p1.stage == 'target', 'attack did not reach the target stage')
  tap('x') -- back out
  wait(0.2)
  expect(pb10.pl.p1.stage == 'act', 'X on the target stage did not return to the act menu')
  engine.setState('sail')
  wait(0.3)

  -- 11: moveCursor hole-skip -- gangplank's mid-row gap, jumped in one tap.
  local pb11 = bootBoarding({ lv = 2, name = 'HOLE FOE', class = 'sloop' }, { 'grunt' }, 'gangplank', { cappy, fin })
  pb11.pl.p1.sel, pb11.pl.p1.stage = nil, 'pick'
  pb11.pl.p1.cursor.x, pb11.pl.p1.cursor.y = 4, 0
  tap('right')
  wait(0.2)
  expect(pb11.pl.p1.cursor.x == 9 and pb11.pl.p1.cursor.y == 0,
    'moveCursor did not skip the gangplank gap')
  engine.setState('sail')
  wait(0.3)

  -- 12: soggy forfeits, both sides -- a soggy foe forfeits its whole foe
  -- phase (GLUB! + flag clear), and a soggy pal starts the next player turn
  -- pre-acted with the flag cleared.
  local pb12 = bootBoarding({ lv = 2, name = 'SOGGY FOE', class = 'sloop' }, { 'grunt' }, 'classic', { cappy, fin })
  local grunt12 = foeOf(pb12, 'grunt')
  local capU12, finU12 = pb12.units[1], pb12.units[2]
  teleport(grunt12, freeTileAwayFrom(pb12, capU12.x, capU12.y, 6))
  ai.planFoeIntents()
  grunt12.soggy, finU12.soggy = true, true
  local gx12, gy12 = grunt12.x, grunt12.y
  palStay(pb12, capU12)
  palStay(pb12, finU12)
  partyPhase(pb12)
  expect(not grunt12.soggy, 'soggy foe did not clear its flag on the forfeited turn')
  expect(grunt12.x == gx12 and grunt12.y == gy12, 'a soggy foe should forfeit its move')
  expect(not finU12.soggy and finU12.acted,
    'soggy pal did not start the turn pre-acted with the flag cleared')
  engine.setState('sail')
  wait(0.3)

  -- 13: gunner perch -- walkToward's gunner fallback: a foe gunner within
  -- move range of the free crowsnest perch, whose target is shootable only
  -- with the perch's +1 range, climbs it before firing.
  local pb13 = bootBoarding({ lv = 2, name = 'PERCH FOE', class = 'sloop' }, { 'gunner' }, 'crowsnest', { cappy, fin })
  local gunner13 = foeOf(pb13, 'gunner')
  expect(pb13.perch, 'crowsnest deck is missing its perch tile')
  local capU13, finU13 = pb13.units[1], pb13.units[2]
  -- Perch at (3,3): CAPPY at (3,6) is 3 from the perch (inside its range-4
  -- shot) but 5 from the gunner at (3,1) (outside its base range 3); FIN
  -- parks further out so CAPPY stays the nearest target.
  teleport(capU13, 3, 6)
  teleport(finU13, 1, 6)
  teleport(gunner13, 3, 1)
  ai.planFoeIntents()
  local capHp13 = capU13.hp
  palStay(pb13, capU13)
  palStay(pb13, finU13)
  -- The gunner climbs, then fires from the perch: block the parry bar.
  waitUntil(function() return timing.on or pb13.phase == 'party' end, 15)
  if timing.on then h.landTiming() end
  partyPhase(pb13)
  expect(gunner13.x == pb13.perch[1] and gunner13.y == pb13.perch[2],
    'foe gunner did not climb the free perch')
  expect(capU13.hp <= capHp13, 'the perched gunner should have targeted CAPPY')
  engine.setState('sail')
  wait(0.3)

  -- 14: BIRDS OF A FEATHER -- a pal wearing PARROT PAL boards alongside the
  -- thief parrot. Fires synchronously inside personBattle.start, so it's
  -- already recorded by the time bootBoarding returns.
  local finOut = fin.out
  fin.out = 'parrot'
  bootBoarding({ lv = 4, name = 'BIRD FOE', class = 'sloop' }, { 'thief' }, 'classic', { cappy, fin })
  expect(h.meta.data.secrets.birdsquad, 'a parrot pal boarding with a thief did not find the birdsquad secret')
  fin.out = finOut
  engine.setState('sail')
  wait(0.3)

  -- By now DECK EXPLORER's 8 shapes have all been boarded at least once:
  -- classic throughout boarding_real.lua + this module, the other 7 in
  -- boarding_gallery.lua's shape gallery.
  expect(h.meta.data.deeds.deckexplorer, 'fighting on every deck shape did not earn the deckexplorer deed')

  run.crew = crewSnapshot
  run.party = partySnapshot
  expect(engine.cur == 'sail', 'boarding specials module did not leave state on sail')
end
