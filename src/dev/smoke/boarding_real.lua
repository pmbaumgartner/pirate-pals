-- Boarding battles driven to real outcomes: wins that run the whole
-- victoryLoot pipeline (salvage + blueprint drops included), the parry and
-- damage-modifier branches, the thief's grab-flee-escape arc, a genuine
-- party wipe, and the King's bar-break/hazard mechanics.
--
-- Runs on the fresh solo run left by ship_loss_dock (crew is exactly
-- CAPPY+FIN), which makes the first win's recruit card deterministic
-- (rewards.lua guarantees it while #run.crew < 3).
return function(ctx, h)
  local wait, waitUntil, shot, expect =
    ctx.wait, ctx.waitUntil, ctx.shot, ctx.expect
  local engine, game, timing, personBattle =
    h.engine, h.game, h.timing, h.personBattle
  local model, ai = h.pbModel, h.pbAi
  local bootBoarding, foeOf, teleport, freeNeighbor, freeTileAwayFrom =
    h.bootBoarding, h.foeOf, h.teleport, h.freeNeighbor, h.freeTileAwayFrom
  local palAttack, palGuard, palStay, partyPhase =
    h.palAttack, h.palGuard, h.palStay, h.partyPhase

  local run = game.run
  local cappy, fin = run.party[1], run.party[2]

  -- A1: win at sea 2 -> the full victoryLoot walk, including the sea-2
  -- blueprint_choice pick and the guaranteed recruit while the crew is 2.
  game.genSea(2, 'calm')
  local foe1 = { lv = 2, name = 'PRIZE SLOOP', class = 'sloop' }
  run.sea.enemies = { foe1 }
  run.blueprints = {}
  run.blueprintDrops = { sea2 = false, sea5 = false }
  cappy.wins = 1 -- next win is the even one: CAPPY levels
  run.bonds[game.bondKey(cappy.name, fin.name)] = 2 -- next win crosses the bond threshold
  run.bondsMade = {}

  local pb1 = bootBoarding(foe1, { 'grunt' }, 'classic')
  local grunt = foeOf(pb1, 'grunt')
  grunt.hp = 1
  local cu, fu = pb1.units[1], pb1.units[2]
  teleport(cu, freeNeighbor(pb1, grunt.x, grunt.y))
  teleport(fu, freeNeighbor(pb1, cu.x, cu.y))
  ai.planFoeIntents()

  local goldBefore = run.gold
  local winsBefore = run.wins
  local salvageBefore = run.salvage.timber + run.salvage.cloth + run.salvage.iron
  palAttack(pb1, cu, h.landTimingPerfect) -- perfect kill -> checkEnd victory
  expect(pb1.over, 'perfect hit on a 1-hp grunt did not end the battle')
  shot('boarding-win')
  local seen1 = {}
  h.walkLoot(seen1)
  expect(seen1.gold and seen1.recruit and seen1.salvage and seen1.blueprint_choice,
    'sea-2 victory loot missed an expected card type')
  expect(run.gold > goldBefore, 'victory loot did not award gold')
  expect(#run.crew == 3, 'guaranteed recruit did not join a 2-pal crew')
  expect(run.salvage.timber + run.salvage.cloth + run.salvage.iron > salvageBefore,
    'victory did not award salvage')
  expect((run.blueprints.chain or run.blueprints.grape)
    and not (run.blueprints.chain and run.blueprints.grape),
    'blueprint_choice did not award exactly one of chain/grape')
  expect(run.blueprintDrops.sea2, 'sea-2 blueprint drop flag was not set')
  expect(run.sea.cleared and run.wins == winsBefore + 1,
    'clearing the only foe did not mark the sea cleared')
  expect(run.bondsMade[game.bondKey(cappy.name, fin.name)],
    'adjacent win did not cross the bond threshold')

  -- A2: win at sea 5 with chain+grape already known -> the blueprint_single
  -- auto-award branch, plus the plain 'good' damage branch.
  game.genSea(5, 'calm')
  local foe2 = { lv = 5, name = 'POWDER BRIG', class = 'brig' }
  run.sea.enemies = { foe2 }
  run.blueprints = { chain = true, grape = true }
  run.blueprintDrops.sea5 = false

  local pb2 = bootBoarding(foe2, { 'grunt' }, 'classic')
  local grunt2 = foeOf(pb2, 'grunt')
  grunt2.hp = 1
  teleport(pb2.units[1], freeNeighbor(pb2, grunt2.x, grunt2.y))
  ai.planFoeIntents()
  palAttack(pb2, pb2.units[1], h.landTiming)
  expect(pb2.over, 'hit on a 1-hp grunt did not end the sea-5 battle')
  local seen2 = {}
  h.walkLoot(seen2)
  expect(seen2.blueprint_single, 'sea-5 win with 2 known blueprints did not show blueprint_single')
  expect(run.blueprints.fire, 'blueprint_single did not award the fire blueprint')
  shot('loot-after-blueprint')

  -- A3: parry gauntlet on the crowsnest deck (has a perch tile) against a
  -- crab: damage-miss chip, foe-hit guard halving, SHELL, PERCH, and a
  -- perfect BLOCKED parry. Not played to an end; state is forced back to
  -- sail once the branches have run.
  game.genSea(3, 'calm')
  local foe3 = { lv = 2, name = 'CRAB CLAW', class = 'sloop' }
  local pb3 = bootBoarding(foe3, { 'crab' }, 'crowsnest')
  local crab = foeOf(pb3, 'crab')
  crab.hp, crab.max = 30, 30 -- must survive the whole gauntlet
  local c3, f3 = pb3.units[1], pb3.units[2]

  -- Round 1: FIN glances (deliberate miss), CAPPY guards; the crab's hit on
  -- the guarding CAPPY runs the good-parry + guard-halving math. FIN is
  -- parked far away (and intents re-planned) before the guard confirm
  -- triggers the foe phase, so the crab's target is the adjacent guard.
  teleport(f3, freeNeighbor(pb3, crab.x, crab.y))
  teleport(c3, freeNeighbor(pb3, crab.x, crab.y))
  ai.planFoeIntents()
  local crabHp = crab.hp
  palAttack(pb3, f3, h.landTimingMiss) -- GLANCED chip hit
  expect(crab.hp < crabHp, 'missed attack did not land its chip damage')
  teleport(f3, freeTileAwayFrom(pb3, crab.x, crab.y, 3))
  ai.planFoeIntents()
  local cHp = c3.hp
  palGuard(pb3, c3)
  h.landTiming() -- good parry; guard halves what lands
  partyPhase(pb3)
  expect(c3.hp < cHp, 'guarded crab hit did not land reduced damage')

  -- Round 2: CAPPY hits the crab's shell side (att.x <= def.x — the crab
  -- always faces the player side), FIN attacks from the perch tile (+1
  -- PERCH bonus). The crab's next swing is perfect-parried: BLOCKED.
  crabHp = crab.hp
  if c3.x > crab.x then
    local placed = false
    for _, d in ipairs({ { -1, 0 }, { 0, -1 }, { 0, 1 } }) do
      local nx, ny = crab.x + d[1], crab.y + d[2]
      if model.inDeck(nx, ny) and not model.unitAt(nx, ny) then
        teleport(c3, nx, ny)
        placed = true
        break
      end
    end
    expect(placed, 'no shell-side tile next to the crab for the SHELL check')
  end
  palAttack(pb3, c3, h.landTiming)
  expect(crab.hp < crabHp, 'SHELL-halved hit did not damage the crab')
  expect(pb3.perch, 'crowsnest deck is missing its perch tile')
  expect(not model.unitAt(pb3.perch[1], pb3.perch[2]), 'perch tile is occupied')
  teleport(f3, pb3.perch[1], pb3.perch[2])
  teleport(crab, freeNeighbor(pb3, f3.x, f3.y))
  ai.planFoeIntents() -- re-target: the crab now swings at the perched FIN
  crabHp = crab.hp
  palAttack(pb3, f3, h.landTiming) -- PERCH +1
  expect(crab.hp < crabHp, 'perch attack did not damage the crab')
  local pHp1, pHp2 = c3.hp, f3.hp
  h.landTimingPerfect() -- BLOCKED!
  partyPhase(pb3)
  expect(c3.hp == pHp1 and f3.hp == pHp2, 'perfect parry did not block all damage')
  shot('boarding-parry')
  engine.setState('sail')
  wait(0.3)

  -- A4: thief parrot arc — grab 5 gold, flee east, escape with it. The
  -- escape empties the enemy side, so this is also a win with an empty
  -- recruit pool (escaped thieves are never in pb.defeated).
  run.gold = 30
  local foe4 = { lv = 2, name = 'SNEAKY WINGS', class = 'sloop' }
  run.sea.enemies = { foe4 }
  local pb4 = bootBoarding(foe4, { 'thief' }, 'classic')
  local thief = foeOf(pb4, 'thief')
  local c4, f4 = pb4.units[1], pb4.units[2]
  teleport(thief, freeNeighbor(pb4, c4.x, c4.y))
  ai.planFoeIntents()
  palStay(pb4, c4)
  palStay(pb4, f4)
  waitUntil(function() return thief.loot == 5 end, 10)
  partyPhase(pb4)
  expect(run.gold == 30, 'thief grab should not deduct gold before escaping')

  teleport(thief, math.max(0, pb4.eastEdge[thief.y] - 2), thief.y)
  palStay(pb4, c4)
  palStay(pb4, f4)
  waitUntil(function() return pb4.over end, 15)
  expect(thief.escaped, 'thief did not escape off the east edge')
  expect(run.gold == 25, 'escaped thief did not take exactly 5 gold')
  shot('thief-escape')
  h.walkLoot()

  -- A5: real loss — a lv-4 brute (parry timeout resolves 'miss' above sea
  -- 3) KOs the last standing pal while the bar is deliberately ignored.
  -- Exercises checkEnd's loss branch, resolveNaps, and the captain-wake
  -- fallback when the whole party would nap.
  local foe5 = { lv = 4, name = 'BIG BRUTE', class = 'brig' }
  local pb5 = bootBoarding(foe5, { 'brute' }, 'classic')
  local brute = foeOf(pb5, 'brute')
  local c5, f5 = pb5.units[1], pb5.units[2]
  f5.alive, f5.hp = false, 0 -- FIN already "KO'd": only CAPPY stands
  c5.hp, c5.guard = 1, false
  teleport(brute, freeNeighbor(pb5, c5.x, c5.y))
  ai.planFoeIntents()
  palStay(pb5, c5)
  waitUntil(function() return timing.on end, 10)
  waitUntil(function() return not timing.on end, 15) -- ride out the parry timeout
  waitUntil(function() return engine.cur == 'sail' and not engine.trans.on end, 10)
  expect(not c5.alive, 'unparried brute hit did not KO the 1-hp captain')
  expect(#run.party >= 1 and run.party[1].role == 'captain',
    'captain-wake fallback did not keep the captain in the party')
  shot('boarding-loss')
  -- The loss napped the crew; restore a sane party for the sections after.
  for _, p in ipairs(run.crew) do p.nap = nil end
  run.party = { run.crew[1], run.crew[2] }

  -- A6: the King's chained bars and hazard tiles. Bar break refills hp and
  -- enrages; an injected hazard detonates on the next foe phase. SLAM is
  -- RNG-gated so it gets rage stacked in its favor but no hard assert.
  local oldVoyageSea = run.voyage.sea
  run.voyage.sea = 8
  game.genSea(8)
  run.party = { run.crew[1], run.crew[2] }
  personBattle.startBoss(run.sea.enemies[1])
  expect(engine.cur == 'personBattle', 'scripted boss boarding did not start')
  wait(0.3)
  local pb6 = personBattle.pb
  pb6.crates = {}
  local king = foeOf(pb6, 'king')
  for _, u in ipairs(pb6.units) do
    if u.side == 'e' and u ~= king then u.alive, u.hp = false, 0 end
  end
  local c6, f6 = pb6.units[1], pb6.units[2]
  teleport(c6, freeNeighbor(pb6, king.x, king.y))
  ai.planFoeIntents()

  king.hp = 1
  palAttack(pb6, c6, h.landTiming)
  expect(king.bars == 2 and king.hp == king.max and king.rage == 1,
    'hit on a 1-hp King bar did not break into RAGE')
  shot('king-rage')

  pb6.hazards[#pb6.hazards + 1] = { x = c6.x, y = c6.y, turnsLeft = 1, damage = 2 }
  king.rage = 6 -- stacks the SLAM roll to 95% per turn (best effort, no assert)
  local c6Hp = c6.hp
  palStay(pb6, f6) -- last pal acts -> foe phase -> hazards resolve first
  waitUntil(function() return c6.hp < c6Hp or not c6.alive end, 10)
  expect(c6Hp - c6.hp == 2 or not c6.alive, 'injected hazard did not detonate for its damage')
  -- The King's own turn may SLAM (hazards) or swing (parry bar): block it.
  waitUntil(function() return pb6.phase == 'party' or timing.on end, 25)
  if timing.on then h.landTimingPerfect() end
  partyPhase(pb6)
  engine.setState('sail')
  wait(0.3)
  run.voyage.sea = oldVoyageSea
  game.genSea(3, 'calm')
  engine.setState('sail')
  wait(0.3)
end
