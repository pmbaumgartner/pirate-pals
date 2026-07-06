-- Ship battle outcomes the other ship-battle modules don't reach: a real
-- win/loss for both plain and boss foes, the foe's self-inflicted ablaze
-- death, every forced foe intent (ram both ways, volley, douse), graded
-- (perfect/miss) landings against armor, a FIRESHIP setting the player
-- ablaze, non-captain crew ship SPECIALs, menu-guard edges, and a direct
-- chooseFoeIntent matrix. Runs on the fresh solo run (crew = CAPPY+FIN)
-- ship_loss_dock leaves behind, and must hand boarding_real back the same:
-- solo, on sail, crew/party untouched.
return function(ctx, h)
  local tap, wait, waitUntil, shot, expect =
    ctx.tap, ctx.wait, ctx.waitUntil, ctx.shot, ctx.expect
  local engine, game, data, meta, personBattle = h.engine, h.game, h.data, h.meta, h.personBattle
  local shipRules = require 'src.ship_rules'

  -- 1: real ship WIN -> boarding transition (BOARD THE SHIP!).
  local sb1 = h.startSmokeShipBattle({ lv = 2, name = 'PRIZE SLOOP', class = 'sloop' })
  sb1.foe.hp = 1
  h.fireSoloShot(sb1, 'round')
  waitUntil(function() return sb1.over end, 10)
  waitUntil(function() return engine.cur == 'personBattle' end, 10)
  expect(not personBattle.pb.isBoss, 'a plain ship win should hand off to a non-boss boarding')
  shot('ship-win-board')
  engine.setState('sail')
  h.settle()

  -- 2: boss ship WIN -> the boss boarding (personBattle.startBoss).
  local sb2 = h.startSmokeShipBattle({ lv = 8, name = 'SMOKE KING', boss = true })
  sb2.foe.hp = 1
  h.fireSoloShot(sb2, 'round')
  waitUntil(function() return sb2.over end, 10)
  waitUntil(function() return engine.cur == 'personBattle' end, 10)
  expect(personBattle.pb.isBoss, 'a boss ship win should hand off to the boss boarding')
  shot('ship-win-board-boss')
  engine.setState('sail')
  h.settle()

  -- 3: boss ship LOSS -> safeEscape's isBoss branch awards boss flotsam
  -- (bossFlotsam[seaLv] + salvage.timber), same ablaze-tick recipe as
  -- ship_loss_dock's real-loss section, but with an isBoss foe.
  -- awardFlotsam keys bossFlotsam by run.sea.lv when a sea exists, only
  -- falling back to the foe's lv without one.
  local seaLvBoss = (game.run.sea and game.run.sea.lv) or 8
  local bossFlotsamBefore = (game.run.bossFlotsam and game.run.bossFlotsam[seaLvBoss]) or 0
  local timberBefore = game.run.salvage.timber
  local sb3 = h.startSmokeShipBattle({ lv = seaLvBoss, name = 'KING DRILL', boss = true })
  local sh3 = sb3.ships[1]
  sh3.ablaze, sh3.hp, sh3.dodge = 1, 4, 0
  sb3.foe.intent = 'fix'
  h.chooseSoloShipAction(sb3, 1) -- MOVE
  waitUntil(function() return sb3.over end, 10)
  expect(sh3.hp == 0, 'ablaze tick did not zero the boss-battle player hull')
  waitUntil(function() return engine.cur == 'sail' and not engine.trans.on end, 10)
  expect(game.run.salvage.timber == timberBefore + 1, 'boss loss did not award +1 timber flotsam')
  expect((game.run.bossFlotsam[seaLvBoss] or 0) == bossFlotsamBefore + 1,
    'boss loss did not record bossFlotsam for this sea level')
  shot('boss-loss-flotsam')

  -- 4: foe self-immolates on its own turn (runFoeTurn's ablaze block, ahead
  -- of runFoeAct) -> normal win -> boarding.
  local sb4 = h.startSmokeShipBattle({ lv = 2, name = 'SMOLDERING SLOOP', class = 'sloop' })
  sb4.foe.ablaze, sb4.foe.hp = 3, 2
  h.chooseSoloShipAction(sb4, 1) -- MOVE: no timing bar, so the round runs straight to the foe's turn
  waitUntil(function() return sb4.over end, 10)
  waitUntil(function() return engine.cur == 'personBattle' end, 10)
  expect(not personBattle.pb.isBoss, 'foe ablaze self-death should hand off to a plain boarding')
  shot('ship-ablaze-selfkill')
  engine.setState('sail')
  h.settle()

  -- 5: forced foe intents on boss battles (decideIntent's roll is
  -- overwritten by poking sb.foe.intent directly, same trick ship_battle.lua
  -- already uses for bigshot/fix telegraphs).
  --
  -- 5a: RAM while dodging -> the recoil arm; a 1-hp foe dies to its own
  -- recoil (data.KING.ramRecoil) instead of ever landing the ram.
  local sb5a = h.startSmokeShipBattle({ lv = 8, name = 'RAM KING', boss = true })
  sb5a.foe.target, sb5a.foe.hp = 1, 1
  sb5a.foe.intent = 'ram'
  h.chooseSoloShipAction(sb5a, 1) -- MOVE: sets movedThisTurn, so the ram resolves as dodged
  waitUntil(function() return sb5a.over end, 10)
  waitUntil(function() return engine.cur == 'personBattle' end, 10)
  expect(personBattle.pb.isBoss, 'a ram recoil-kill should still hand off to the boss boarding')
  shot('ship-ram-recoil-kill')
  engine.setState('sail')
  h.settle()

  -- 5b: RAM without dodging -> the hit arm; flat data.KING.ramDmg damage.
  local sb5b = h.startSmokeShipBattle({ lv = 8, name = 'RAM KING TWO', boss = true })
  sb5b.foe.target = 1
  sb5b.foe.intent = 'ram'
  local hullBefore5b = sb5b.ships[1].hp
  h.fireSoloShot(sb5b, 'round') -- FIRE, not MOVE, so movedThisTurn stays false: no dodge
  waitUntil(function()
    return sb5b.over or (sb5b.turn == 'select' and not sb5b.co and not engine.trans.on)
  end, 10)
  expect(sb5b.over or sb5b.ships[1].hp == hullBefore5b - data.KING.ramDmg,
    'an un-dodged RAM did not deal its flat ram damage')
  shot('ship-ram-hit')

  -- 5c: VOLLEY -> two back-to-back cannonballs, one volley keg spent.
  local sb5c = h.startSmokeShipBattle({ lv = 8, name = 'VOLLEY KING', boss = true })
  sb5c.foe.target, sb5c.foe.volleyKegs = 1, 1
  sb5c.foe.intent = 'volley'
  local hullBefore5c = sb5c.ships[1].hp
  h.fireSoloShot(sb5c, 'round')
  waitUntil(function()
    return sb5c.over or (sb5c.turn == 'select' and not sb5c.co and not engine.trans.on)
  end, 10)
  expect(sb5c.over or sb5c.ships[1].hp < hullBefore5c, 'a forced VOLLEY did not damage the ship')
  expect(sb5c.over or sb5c.foe.volleyKegs == 0, 'VOLLEY did not spend a volley keg')
  shot('ship-volley')

  -- 5d: DOUSE -> extinguishes the foe's own fire.
  local sb5d = h.startSmokeShipBattle({ lv = 8, name = 'DOUSE KING', boss = true })
  sb5d.foe.ablaze = 1
  sb5d.foe.intent = 'douse'
  h.chooseSoloShipAction(sb5d, 1) -- MOVE
  waitUntil(function()
    return sb5d.over or (sb5d.turn == 'select' and not sb5d.co and not engine.trans.on)
  end, 10)
  expect(sb5d.over or not sb5d.foe.ablaze, 'a forced DOUSE did not clear the foe ablaze status')
  shot('ship-douse')
  engine.setState('sail')
  h.settle()

  -- 6: graded landings vs armor. MAN-O-WAR has armor 1 and is weak to FIRE,
  -- so a ROUND shot is always resisted ("GLANCES OFF") regardless of grade.
  local function fireGraded(sbNow, shotId, lander)
    local sh = sbNow.ships[1]
    sbNow.foe.dodge = 0 -- a dodged impact would skip the armor/streak lines under test
    sh.menu, sh.submenu = 0, nil
    tap('z')
    waitUntil(function() return sh.submenu == 'shot' end, 3)
    if shotId ~= 'round' then tap('down') end
    tap('z')
    lander('p1')
  end

  local function hasFloatText(sub)
    for _, f in ipairs(engine.floaters) do
      if f.text:find(sub, 1, true) then return true end
    end
    return false
  end

  local sb6 = h.startSmokeShipBattle({ lv = 3, name = 'ARMORED MANOWAR', class = 'manowar' })
  fireGraded(sb6, 'round', h.landTimingPerfect)
  waitUntil(function() return hasFloatText('GLANCES') end, 3)
  expect(hasFloatText('GLANCES'), 'a perfect ROUND shot into armor did not show the resisted GLANCES OFF line')
  shot('ship-perfect-resisted')
  h.shipBattleReady(sb6, 'select', 12)

  fireGraded(sb6, 'round', h.landTimingMiss)
  waitUntil(function() return hasFloatText('GLANCES') end, 3)
  expect(hasFloatText('GLANCES'), 'a missed ROUND shot into armor did not show the resisted GLANCES OFF line')
  h.shipBattleReady(sb6, 'select', 12)

  -- Three consecutive perfect ROUND fires flips on the cannonballFx streak.
  local sb6b = h.startSmokeShipBattle({ lv = 20, name = 'STREAK DRILL', class = 'sloop' })
  for _ = 1, 3 do
    fireGraded(sb6b, 'round', h.landTimingPerfect)
    h.shipBattleReady(sb6b, 'select', 12)
    sb6b.ships[1].hp = sb6b.ships[1].max -- the foe's counter-fire shouldn't end the streak early
  end
  expect(sb6b.perfectFireCount >= 3 and sb6b.cannonballFx, 'three perfect fires did not flip on cannonballFx')
  expect(meta.data.secrets.cannonball, 'the cannonball secret was not recorded')
  shot('ship-cannonball-streak')

  -- 7: FIRESHIP always telegraphs FIRE, and opts.isFireShot (keyed off foe
  -- class) sets the player ship ablaze on an unblocked hit.
  local sb7 = h.startSmokeShipBattle({ lv = 2, name = 'HELLBURNER', class = 'fireship' })
  sb7.foe.hp, sb7.foe.max = 60, 60 -- must survive the player's shot to get its own turn
  sb7.ships[1].dodge = 0
  h.fireSoloShot(sb7, 'round') -- FIRE keeps ships[1].dodge at 0 so the incoming hit can't dodge away
  waitUntil(function() return sb7.ships[1].ablaze end, 10)
  expect(sb7.ships[1].ablaze == 3, 'a hit from a FIRESHIP foe did not set the player ship ablaze')
  shot('ship-player-ablaze')
  engine.setState('sail')
  h.settle()

  -- 8: non-captain ship SPECIALs. specialPartyFor lists the whole party
  -- regardless of ship index in solo mode, and the (never-used) captain
  -- always occupies submenu slot 0, so each freshly-added pal always lands
  -- on slot 1 -- one 'down' tap reaches it every round.
  local crewSnapshot, partySnapshot = {}, {}
  for i, p in ipairs(game.run.crew) do crewSnapshot[i] = p end
  for i, p in ipairs(game.run.party) do partySnapshot[i] = p end

  local strongman = game.makePirate('strongman', 'T_STRONG', 2)
  local sharpshooter = game.makePirate('sharpshooter', 'T_SHARP', 2)
  local medic = game.makePirate('medic', 'T_MEDIC', 2)
  for _, p in ipairs({ strongman, sharpshooter, medic }) do
    game.run.crew[#game.run.crew + 1] = p
    game.run.party[#game.run.party + 1] = p
  end

  local sb8 = h.startSmokeShipBattle({ lv = 1, name = 'SPECIAL DRILL', class = 'sloop' })
  local sh8 = sb8.ships[1]

  -- Trigger the special, then watch for its effect predicate BEFORE the
  -- round finishes: the foe's counterattack in the same round can undo the
  -- observable effect (e.g. impact() consumes the deckhand's fresh dodge),
  -- so the sighting is captured the frame it appears.
  local function useSpecial(sbNow, palName, effectPred, effectMsg)
    local sh = sbNow.ships[1]
    sbNow.foe.dodge = 0 -- the foe's per-round dodge roll could eat a special's cannonball
    h.chooseSoloShipAction(sbNow, 3) -- SPECIAL
    waitUntil(function() return sh.submenu == 'special' end, 3)
    tap('down') -- skip past the captain's always-present, never-used slot 0
    tap('z')
    waitUntil(function() return sbNow.specUsed[palName] end, 5)
    local seen = false
    waitUntil(function()
      seen = seen or effectPred()
      return seen
    end, 8)
    expect(seen, effectMsg)
    h.shipBattleReady(sbNow, 'select', 12)
  end

  useSpecial(sb8, 'FIN', function() return sh8.dodge > 0 end,
    'FIN (deckhand) SPECIAL did not grant a dodge') -- FULL SAILS
  shot('ship-special-deckhand')
  sb8.foe.hp = sb8.foe.max

  local foeHpBefore = sb8.foe.hp
  useSpecial(sb8, 'T_STRONG', function() return sb8.foe.hp < foeHpBefore end,
    'T_STRONG (strongman) SPECIAL did not damage the foe') -- HEAVY BALL
  shot('ship-special-strongman')
  sb8.foe.hp, sh8.hp = sb8.foe.max, sh8.max

  foeHpBefore = sb8.foe.hp
  useSpecial(sb8, 'T_SHARP', function() return sb8.foe.hp < foeHpBefore end,
    'T_SHARP (sharpshooter) SPECIAL did not damage the foe') -- TRUE SHOT
  shot('ship-special-sharpshooter')
  sb8.foe.hp = sb8.foe.max
  sh8.hp = math.max(1, sh8.max - 10) -- stage medic's precondition: a damaged hull
  local hullBefore8 = sh8.hp
  useSpecial(sb8, 'T_MEDIC', function() return sh8.hp > hullBefore8 end,
    'T_MEDIC (medic) SPECIAL did not repair the hull') -- PATCH SHIP
  shot('ship-special-medic')

  engine.setState('sail')
  h.settle()
  game.run.crew, game.run.party = crewSnapshot, partySnapshot

  -- 9: menu edges. B-cancel out of the shot submenu, a zero-powder shot
  -- bump, a disabled-row (FIX at full hp) bump, and a disabled SPECIAL
  -- (every party member already used) bump plus its forced-open self-clear.
  local sb9 = h.startSmokeShipBattle({ lv = 2, name = 'MENU DRILL', class = 'sloop' }, 'chain')
  local sh9 = sb9.ships[1]

  sh9.menu, sh9.submenu = 0, nil
  tap('z')
  waitUntil(function() return sh9.submenu == 'shot' end, 3)
  tap('x')
  waitUntil(function() return sh9.submenu == nil end, 3)
  expect(sh9.menu == 0, 'shot submenu cancel should leave the main menu selected')

  sh9.powder.chain = 0
  tap('z')
  waitUntil(function() return sh9.submenu == 'shot' end, 3)
  tap('down') -- CHAIN
  tap('z')
  wait(0.2)
  expect(sh9.submenu == 'shot', 'firing a shot type with zero powder should not close the submenu')
  tap('x')
  waitUntil(function() return sh9.submenu == nil end, 3)

  sh9.menu = 2 -- FIX: disabled at full hp
  tap('z')
  wait(0.2)
  expect(sh9.menu == 2 and not sh9.chosen and not sb9.co, 'a disabled FIX row should bump, not confirm')

  for _, p in ipairs(game.run.party) do sb9.specUsed[p.name] = true end
  sh9.menu = 3 -- SPECIAL: disabled once every pal has been used
  tap('z')
  wait(0.2)
  expect(sh9.submenu == nil, 'SPECIAL with no eligible pals should bump instead of opening')
  sh9.submenu, sh9.sub = 'special', 0 -- force it open to exercise the self-clearing guard directly
  wait(0.2)
  expect(sh9.submenu == nil, 'an empty forced-open SPECIAL submenu should self-clear on the next tick')
  shot('ship-menu-edges')

  engine.setState('sail')
  h.settle()
  game.run.fittings.slot = nil

  -- 10: chooseFoeIntent direct matrix -- no battle needed. `chance` is the
  -- injectable seam near the top of ship_rules.lua's chooseFoeIntent; fixed
  -- true/false (or a p-matching) function makes every branch deterministic.
  local function chanceTrue() return true end
  local function chanceFalse() return false end

  local cases = {
    { desc = 'ablaze foe on a boss always douses, regardless of class',
      foe = { ablaze = 1, hp = 50, max = 100, class = 'sloop' },
      opts = { isBoss = true, chance = chanceTrue }, want = 'douse' },
    { desc = 'ablaze FIRESHIP douses even off-boss',
      foe = { ablaze = 2, hp = 50, max = 100, class = 'fireship' },
      opts = { isBoss = false, chance = chanceFalse }, want = 'douse' },
    { desc = 'ablaze on a plain non-fireship foe does not force douse',
      foe = { ablaze = 1, hp = 50, max = 100, class = 'sloop' },
      opts = { isBoss = false, chance = chanceTrue }, want = 'move' },
    { desc = 'boss kraken always fires',
      foe = { class = 'kraken', hp = 80, max = 100, repairs = 1 },
      opts = { isBoss = true, chance = chanceTrue }, want = 'fire' },
    { desc = 'boss low hp with repairs fixes',
      foe = { class = 'king', hp = 20, max = 100, repairs = 1 },
      opts = { isBoss = true, chance = chanceTrue }, want = 'fix' },
    { desc = 'boss phase 3 (no repairs) rams',
      foe = { class = 'king', hp = 20, max = 100, repairs = 0, bigshotKegs = 0 },
      opts = { isBoss = true, chance = chanceTrue }, want = 'ram' },
    { desc = 'boss phase 3, ram roll fails, bigshot roll succeeds',
      foe = { class = 'king', hp = 20, max = 100, repairs = 0, bigshotKegs = 2 },
      opts = { isBoss = true, chance = function(p) return p == 0.35 end }, want = 'bigshot' },
    { desc = 'boss phase 3, both rolls fail, no kegs -> fire fallback',
      foe = { class = 'king', hp = 20, max = 100, repairs = 0, bigshotKegs = 0 },
      opts = { isBoss = true, chance = chanceFalse }, want = 'fire' },
    { desc = 'boss phase 2, high tier + kegs + roll -> volley',
      foe = { class = 'king', hp = 50, max = 100, repairs = 0, volleyKegs = 1, bigshotKegs = 0 },
      opts = { isBoss = true, tier = 2, chance = function(p) return p == 0.25 end }, want = 'volley' },
    { desc = 'boss phase 2, low tier skips volley -> bigshot',
      foe = { class = 'king', hp = 50, max = 100, repairs = 0, volleyKegs = 1, bigshotKegs = 1 },
      opts = { isBoss = true, tier = 1, chance = function(p) return p == 0.35 end }, want = 'bigshot' },
    { desc = 'boss phase 2, no kegs -> fire fallback',
      foe = { class = 'king', hp = 50, max = 100, repairs = 0, volleyKegs = 0, bigshotKegs = 0 },
      opts = { isBoss = true, tier = 3, chance = chanceFalse }, want = 'fire' },
    { desc = 'boss phase 1 with kegs + roll -> bigshot',
      foe = { class = 'king', hp = 90, max = 100, repairs = 0, bigshotKegs = 1 },
      opts = { isBoss = true, chance = function(p) return p == 0.35 end }, want = 'bigshot' },
    { desc = 'boss phase 1, no kegs -> fire fallback',
      foe = { class = 'king', hp = 90, max = 100, repairs = 0, bigshotKegs = 0 },
      opts = { isBoss = true, chance = chanceTrue }, want = 'fire' },
    { desc = 'non-boss SLOOP low hp + repairs fixes',
      foe = { class = 'sloop', hp = 20, max = 100, repairs = 1 },
      opts = { isBoss = false, chance = chanceTrue }, want = 'fix' },
    { desc = 'non-boss SLOOP high hp rolls move',
      foe = { class = 'sloop', hp = 80, max = 100, repairs = 1 },
      opts = { isBoss = false, chance = chanceTrue }, want = 'move' },
    { desc = 'non-boss SLOOP high hp, move roll fails -> fire fallback',
      foe = { class = 'sloop', hp = 80, max = 100, repairs = 1 },
      opts = { isBoss = false, chance = chanceFalse }, want = 'fire' },
    { desc = 'non-boss MAN-O-WAR low hp + repairs fixes',
      foe = { class = 'manowar', hp = 20, max = 100, repairs = 1 },
      opts = { isBoss = false, chance = chanceTrue }, want = 'fix' },
    { desc = 'non-boss MAN-O-WAR high hp + kegs -> bigshot',
      foe = { class = 'manowar', hp = 80, max = 100, repairs = 1, bigshotKegs = 1 },
      opts = { isBoss = false, chance = chanceTrue }, want = 'bigshot' },
    { desc = 'non-boss MAN-O-WAR high hp, no kegs -> fire fallback',
      foe = { class = 'manowar', hp = 80, max = 100, repairs = 1, bigshotKegs = 0 },
      opts = { isBoss = false, chance = chanceTrue }, want = 'fire' },
    { desc = 'non-boss FIRESHIP (no ablaze) always fires',
      foe = { class = 'fireship', hp = 80, max = 100, repairs = 1 },
      opts = { isBoss = false, chance = chanceFalse }, want = 'fire' },
    { desc = 'other class, low hp + repairs fixes',
      foe = { class = 'brig', hp = 20, max = 100, repairs = 1 },
      opts = { isBoss = false, chance = chanceTrue }, want = 'fix' },
    { desc = 'other class, high hp rolls move',
      foe = { class = 'brig', hp = 80, max = 100, repairs = 1 },
      opts = { isBoss = false, chance = chanceTrue }, want = 'move' },
    { desc = 'other class, high hp, move roll fails -> fire fallback',
      foe = { class = 'brig', hp = 80, max = 100, repairs = 1 },
      opts = { isBoss = false, chance = chanceFalse }, want = 'fire' },
  }

  for _, c in ipairs(cases) do
    local got = shipRules.chooseFoeIntent(c.foe, c.opts)
    expect(got == c.want, c.desc .. ': expected ' .. c.want .. ' but got ' .. tostring(got))
  end

  -- Leave the run exactly as boarding_real expects it: solo, on sail, crew
  -- and party untouched by any of the above.
  expect(engine.cur == 'sail' and not engine.trans.on, 'ship_battle_real must end on a settled sail state')
  expect(#game.run.crew == 2, 'ship_battle_real must not leave permanent crew growth for boarding_real')
  game.run.party = { game.run.crew[1], game.run.crew[2] }
end
