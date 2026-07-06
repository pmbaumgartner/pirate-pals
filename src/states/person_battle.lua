-- Boarding (person) battle: small tactics grid on the enemy deck.
-- Player phase is a cursor-driven pick/move/act/target flow; every attack
-- and parry runs through the timing-bar minigame. Crates give cover.
--
-- Co-op: interaction state is per-player (pb.pl.p1/p2 — cursor,
-- selection, menu, stage), so both cursors are live at once, each locked to
-- its owner's pals. Authoritative battle state (units, walk, wait, queue,
-- hazards, foe turn) stays top-level and single-threaded: one resolution
-- (walk / timing bar / damage) happens on screen at a time, and the other
-- player may browse and stage but not confirm until the lock frees.
--
-- This file owns the player input FSM (updatePlayer) and battle setup
-- (M.start/M.startBoss); the battle model/queries live in
-- person_battle/model.lua, the foe AI + co-op auto-act in
-- person_battle/ai.lua, win rewards in person_battle/rewards.lua, and
-- rendering in person_battle/draw.lua — all sharing the active battle via
-- person_battle/state.lua.
local util = require 'src.util'
local grid = require 'src.grid'
local palette = require 'src.palette'
local input = require 'src.input'
local coop = require 'src.coop'
local audio = require 'src.audio'
local engine = require 'src.engine'
local game = require 'src.game'
local data = require 'src.data'
local timing = require 'src.timing'
local meta = require 'src.meta'
local barks = require 'src.barks'
local model = require 'src.states.person_battle.model'
local ai = require 'src.states.person_battle.ai'
local draw = require 'src.states.person_battle.draw'
local S = require 'src.states.person_battle.state'
local CO = palette.CO
local SFX = audio.sfx
local gk = grid.gk

local VW = 320

local M = {}

local function ctxOf(player)
  if not game.isCoop() then return input.p1 end
  return player == 'p2' and input.p2 or input.p1
end

-- Two random party pals bark on the way in, not the whole crew, so the
-- deck doesn't turn into a wall of floating text.
local function battleStartBarks(units)
  local pool = {}
  for _, u in ipairs(units) do
    if u.side == 'p' then pool[#pool + 1] = u end
  end
  for _ = 1, math.min(2, #pool) do
    local i = util.irand(1, #pool)
    local u = table.remove(pool, i)
    local ux, uy = model.px(u.x, u.y)
    barks.say(u, ux, uy, 'battleStart')
  end
end

local function finishUnit(player, u)
  local pb = S.pb
  u.acted = true
  local pl = pb.pl[player]
  pl.sel, pl.reach, pl.origin = nil, nil, nil
  pl.stage = 'pick'
  if model.checkEnd() then return end
  if model.allActed() then
    ai.startFoePhase()
    return
  end
  model.cursorToNext(player)
end

-- End your own turn early: rests only your own pals, so there is no
-- END-TURN griefing — an eager sibling can't burn the other's moves.
local function endOwnTurn(player)
  local pb = S.pb
  local marked = false
  for _, u in ipairs(pb.units) do
    if u.side == 'p' and u.alive and not u.acted and (u.owner or 'p1') == player then
      u.acted = true
      marked = true
    end
  end
  if not marked then return end
  SFX.back()
  engine.addFloat(VW / 2, 60, (player == 'p2' and 'P2' or 'P1') .. ' PALS REST!', CO.foam, 1)
  for _, pl in pairs(pb.pl) do
    if pl.sel and pl.sel.acted then
      pl.sel, pl.reach, pl.origin = nil, nil, nil
      pl.stage = 'pick'
    end
  end
  if model.allActed() then ai.startFoePhase() end
end

local function doAttack(player, u, tgt, opts)
  local pb = S.pb
  pb.pl[player].stage = 'busy'
  timing.start(timing.cfg(pb.lv, false, meta.steadyMult()), 'PRESS Z NOW!', function(res)
    model.damage(u, tgt, u.atk + u.buff + util.irand(0, 1) + ((opts and opts.bonus) or 0), res, opts)
    finishUnit(player, u)
  end, 'good', model.ownerPlayer(u))
end

-- Specials that go to target selection are only marked used on confirm
-- (see the 'target' stage), so backing out with X refunds the special.
local function useSpecial(player, u)
  local pb = S.pb
  local pl = pb.pl[player]
  local r = u.role
  local ux, uy = model.px(u.x, u.y)
  engine.addFloat(ux + 8, uy - 12, data.ROLES[r].spec.name, CO.gold, 1)
  if r == 'captain' then
    u.specUsed = true
    SFX.fanfare()
    barks.say(u, ux - 8, uy, 'special')
    for _, al in ipairs(model.alliesOf(u, false)) do
      al.buff = al.buff + 2
      local ax, ay = model.px(al.x, al.y)
      engine.addParts(ax + 8, ay + 4, 8, CO.gold, 35)
      engine.addFloat(ax + 8, ay - 4, '+2 ATK', CO.gold, 1)
    end
    finishUnit(player, u)
  elseif r == 'strongman' then
    u.specUsed = true
    barks.say(u, ux - 8, uy, 'special')
    pl.stage = 'busy'
    timing.start(timing.cfg(pb.lv, false, meta.steadyMult()), 'SMASH! PRESS Z!', function(res)
      engine.shakeIt(3, 0.25)
      for _, t in ipairs(model.targetsOf(u, 1)) do
        model.damage(u, t, u.atk + u.buff + 2, res, {})
      end
      for _, cr in ipairs(model.adjacentCrates(u)) do
        model.smashCrate(u, cr.x, cr.y)
      end
      finishUnit(player, u)
    end, 'good', model.ownerPlayer(u))
  elseif r == 'medic' then
    pl.action, pl.targets, pl.tIdx, pl.stage = 'heal', model.alliesOf(u, true), 0, 'target'
  elseif r == 'sharpshooter' then
    pl.action, pl.targets, pl.tIdx, pl.stage = 'longshot', model.targetsOf(u, 99), 0, 'target'
  elseif r == 'deckhand' then
    pl.action, pl.targets, pl.tIdx, pl.stage = 'shove', model.targetsOf(u, 1), 0, 'target'
  end
end

local function confirmTarget(player)
  local pb = S.pb
  local pl = pb.pl[player]
  local u = pl.sel
  local tgt = pl.targets[pl.tIdx + 1]
  if pl.action == 'attack' then
    if tgt.isCrate then
      model.smashCrate(u, tgt.x, tgt.y)
      finishUnit(player, u)
    else
      doAttack(player, u, tgt, {})
    end
  elseif pl.action == 'heal' then
    tgt.hp = math.min(tgt.max, tgt.hp + 8)
    SFX.heal()
    local hx, hy = model.px(tgt.x, tgt.y)
    engine.addParts(hx + 8, hy + 4, 10, CO.green, 35)
    engine.addFloat(hx + 8, hy - 6, '+8', CO.green, 2)
    finishUnit(player, u)
  elseif pl.action == 'longshot' then
    local ux, uy = model.px(u.x, u.y)
    barks.say(u, ux - 8, uy, 'special')
    pl.stage = 'busy'
    timing.start(timing.cfg(pb.lv, false, meta.steadyMult()), 'AIM... PRESS Z!', function(res)
      SFX.shot()
      model.damage(u, tgt, u.atk + u.buff + 1, res, { ignoreCover = true })
      finishUnit(player, u)
    end, 'good', model.ownerPlayer(u))
  elseif pl.action == 'shove' then
    local outcome = model.slideTarget(u, tgt, 2)
    SFX.push()
    pl.stage = 'busy'
    model.walk(tgt, outcome.path, function()
      model.applySlideImpact(tgt, outcome.impact)
      finishUnit(player, u)
    end)
  end
end

-- One player's slice of the party turn. `locked` = a resolution (walk /
-- timing bar / scheduled wait) is on screen: browsing and staging stay
-- live, but confirms that would start another resolution bump until free.
local function updatePlayer(player, locked, barOwner)
  if barOwner == 'both' or barOwner == player then return end
  local pb = S.pb
  local pl = pb.pl[player]
  local ctx = ctxOf(player)
  local other = pb.pl[player == 'p1' and 'p2' or 'p1']
  local cu = pl.cursor
  if pl.stage == 'pick' then
    local d = ctx.moveVector(true)
    if d then
      local nx, ny = model.moveCursor(cu.x, cu.y, d[1], d[2])
      if nx ~= cu.x or ny ~= cu.y then
        cu.x, cu.y = nx, ny
        SFX.move()
      end
    end
    if ctx.jp('a') then
      local u = model.unitAt(cu.x, cu.y)
      if u and model.canDrive(player, u) and other.sel ~= u then
        SFX.sel()
        pl.sel = u
        pl.origin = { x = u.x, y = u.y }
        pl.reach = model.reachFor(u)
        pl.stage = 'move'
      else
        SFX.bump()
      end
    elseif game.isCoop() and not locked and ctx.jp('b') then
      endOwnTurn(player)
    end
  elseif pl.stage == 'move' then
    local d = ctx.moveVector(true)
    if d then
      local nx, ny = model.moveCursor(cu.x, cu.y, d[1], d[2])
      if nx ~= cu.x or ny ~= cu.y then
        cu.x, cu.y = nx, ny
        SFX.move()
      end
    end
    if ctx.jp('b') then
      SFX.back()
      pl.sel, pl.reach, pl.origin = nil, nil, nil
      pl.stage = 'pick'
      return
    end
    if ctx.jp('a') then
      local su = pl.sel
      if cu.x == su.x and cu.y == su.y then
        SFX.sel()
        pl.stage = 'act'
        pl.menu = 0
      elseif locked then
        SFX.bump()
      elseif pl.reach.cost[gk(cu.x, cu.y)] ~= nil
        and not model.unitAt(cu.x, cu.y) and not pb.crates[gk(cu.x, cu.y)] then
        SFX.sel()
        local path = grid.bfsPath(pl.reach, cu.x, cu.y)
        pl.stage = 'busy'
        model.walkWithTerrain(su, path, function()
          pl.stage = 'act'
          pl.menu = 0
        end)
      else
        SFX.bump()
      end
    end
  elseif pl.stage == 'act' then
    local items = model.actMenu(pl.sel)
    if ctx.rp('up') then pl.menu = (pl.menu + #items - 1) % #items; SFX.move() end
    if ctx.rp('down') then pl.menu = (pl.menu + 1) % #items; SFX.move() end
    if ctx.jp('b') then
      -- Undo the move: snap back to where the unit started this turn.
      SFX.back()
      local su = pl.sel
      su.x, su.y = pl.origin.x, pl.origin.y
      su.fx, su.fy = su.x, su.y
      cu.x, cu.y = su.x, su.y
      pl.reach = model.reachFor(su)
      pl.stage = 'move'
      return
    end
    if ctx.jp('a') then
      local it = items[pl.menu + 1]
      if not it.ok or locked then
        SFX.bump()
        return
      end
      if it.id == 'atk' then
        SFX.sel()
        local tgts = model.targetsOf(pl.sel)
        for _, c in ipairs(model.adjacentCrates(pl.sel)) do
          tgts[#tgts + 1] = c
        end
        pl.action, pl.targets, pl.tIdx = 'attack', tgts, 0
        pl.stage = 'target'
      elseif it.id == 'grd' then
        SFX.sel()
        pl.sel.guard = true
        local gx, gy = model.px(pl.sel.x, pl.sel.y)
        engine.addFloat(gx + 8, gy - 6, 'GUARD!', CO.foam, 1)
        finishUnit(player, pl.sel)
      elseif it.id == 'spc' then
        SFX.sel()
        useSpecial(player, pl.sel)
      else
        SFX.sel()
        finishUnit(player, pl.sel)
      end
    end
  elseif pl.stage == 'target' then
    local n = #pl.targets
    if ctx.jp('left') or ctx.jp('up') then pl.tIdx = (pl.tIdx + n - 1) % n; SFX.move() end
    if ctx.jp('right') or ctx.jp('down') then pl.tIdx = (pl.tIdx + 1) % n; SFX.move() end
    if ctx.jp('b') then
      SFX.back()
      pl.stage = 'act'
      return
    end
    if ctx.jp('a') then
      if locked then
        SFX.bump()
        return
      end
      if pl.action ~= 'attack' then pl.sel.specUsed = true end
      confirmTarget(player)
    end
  end
end

local function mkPl(x, y)
  return {
    cursor = { x = x, y = y }, sel = nil, reach = nil, origin = nil,
    menu = 0, action = '', targets = {}, tIdx = 0, stage = 'pick',
  }
end

local function newPb(units, crates, lv, foe, isBoss, deckInfo)
  local ox, oy = model.deckOrigin(deckInfo.w, deckInfo.h)
  S.pb = {
    units = units, crates = crates, lv = lv, foeRef = foe, isBoss = isBoss,
    phase = 'party',
    deck = deckInfo.deck, deckList = deckInfo.deckList, eastEdge = deckInfo.eastEdge,
    deckId = deckInfo.id, w = deckInfo.w, h = deckInfo.h, ox = ox, oy = oy,
    ice = deckInfo.ice, vent = deckInfo.vent, perch = deckInfo.perch,
    pl = { p1 = mkPl(0, 0), p2 = mkPl(0, 0) },
    walk = nil, wait = 0, next = nil, co = nil, queue = {}, hazards = {},
    flags = {}, over = false, defeated = {},
    idleT = 0, p2Away = false, p2Auto = false,
  }
  -- Hidden delight (for the 'tightrope' secret): on the gangplank deck, mark
  -- which columns are only walkable along the middle row (the narrow bridge
  -- over the gap) so model.walk can flag a crossing.
  if S.pb.deckId == 'gangplank' then
    local waistY = math.floor(S.pb.h / 2)
    local waistCols = {}
    for x = 0, S.pb.w - 1 do
      if S.pb.deck[gk(x, waistY)] and not S.pb.deck[gk(x, waistY - 1)] and not S.pb.deck[gk(x, waistY + 1)] then
        waistCols[x] = true
      end
    end
    S.pb.waistY, S.pb.waistCols, S.pb.wobbled = waistY, waistCols, false
  end
  M.pb = S.pb
  model.cursorToNext('p1')
  if game.isCoop() then model.cursorToNext('p2') end
  ai.planFoeIntents()
end

-- Dev cheat (F3 under --dev): KO every enemy through the normal ko()/
-- checkEnd() path so the win still plays into the loot transition.
function M.debugWin()
  local pb = S.pb
  if not pb or pb.over then return end
  for _, u in ipairs(pb.units) do
    if u.side == 'e' and u.alive then model.ko(u) end
  end
  model.checkEnd()
end

-- compOverride (dev warps/smoke) skips the level/biome roll for a fixed
-- enemy lineup. deckOverride (dev warps) skips the weighted shape draw for a
-- fixed src.data.DECKS id.
function M.start(foe, compOverride, deckOverride)
  local lv = foe.lv
  local deckInfo = model.buildDeck(deckOverride or model.pickDeckId(lv), game.run.sea and game.run.sea.biome)
  local units = {}
  local partyCap = game.partyCap()
  local pSpawns = deckInfo.pSpawns
  for i, pr in ipairs(game.run.party) do
    if i > partyCap then break end
    local sp = pSpawns[(i - 1) % #pSpawns + 1]
    local st = game.statsOf(pr)
    units[#units + 1] = {
      side = 'p', role = pr.role, name = pr.name, lvl = pr.lvl, out = pr.out, ref = pr,
      owner = game.ownerOf(pr), color = game.palColor(pr),
      x = sp[1], y = sp[2], fx = sp[1], fy = sp[2],
      hp = st.hp, max = st.hp, atk = st.atk, move = st.move, range = st.range,
      acted = false, guard = false, buff = 0, alive = true, specUsed = false,
    }
  end
  local comp = compOverride or game.compFor(lv, game.run.sea and game.run.sea.biome)
  local compCopy = {}
  for _, r in ipairs(comp) do compCopy[#compCopy + 1] = r end
  if deckInfo.choke and lv >= 2 then
    local hasRanged = false
    for _, roleKey in ipairs(compCopy) do
      local er = data.EROLES[roleKey]
      if er and er.range > 1 then hasRanged = true; break end
    end
    if not hasRanged then
      for i, roleKey in ipairs(compCopy) do
        if roleKey == 'grunt' then
          compCopy[i] = 'gunner'
          break
        end
      end
    end
  end
  local eSpawns = deckInfo.eSpawns
  for i, roleKey in ipairs(compCopy) do
    local er = data.EROLES[roleKey]
    local sp = eSpawns[(i - 1) % #eSpawns + 1]
    units[#units + 1] = {
      side = 'e', role = roleKey, name = er.label, lvl = lv,
      x = sp[1], y = sp[2], fx = sp[1], fy = sp[2],
      hp = er.hp + er.hpLv * (lv - 1), max = er.hp + er.hpLv * (lv - 1),
      atk = er.atk + er.atkLv * (lv - 1), move = er.move, range = er.range,
      acted = false, guard = false, buff = 0, alive = true,
    }
  end
  -- Apply Grape Shot deck sweep effect:
  if foe.gunsStage and foe.gunsStage < 0 then
    for _, u in ipairs(units) do
      if u.side == 'e' then
        u.hp = math.max(1, math.floor(u.max / 2))
        break
      end
    end
  end
  for i, u in ipairs(units) do u.id = i end
  local crates = model.scatterCrates(deckInfo)
  -- Story hook: the first-ever battle on a
  -- non-classic shape gets its own Voyage Log line.
  if deckInfo.logText and not game.run.seenDecks[deckInfo.id] then
    game.run.seenDecks[deckInfo.id] = true
    game.logMoment('flagW', 'SEA ' .. lv .. ': ' .. deckInfo.logText, {})
  end
  newPb(units, crates, lv, foe, false, deckInfo)
  engine.setState('personBattle')
  battleStartBarks(units)
  engine.showBanner('DEFEAT THE CREW!', CO.gold, 1.2)
end

-- The Pirate King: a chained 3-bar boss unit plus two minion grunts. Losing
-- is a normal safe loss — this rebuilds fresh every time, so no damage or
-- rage persists between attempts.
function M.startBoss(foe)
  local lv = foe.lv
  local units = {}
  -- The boss deck stays a fixed shape: SLAM tile
  -- choreography and minion placement keep their tuned classic-box feel.
  local deckInfo = model.buildDeck('classic')
  local partyCap = game.partyCap()
  local pSpawns = deckInfo.pSpawns
  for i, pr in ipairs(game.run.party) do
    if i > partyCap then break end
    local sp = pSpawns[(i - 1) % #pSpawns + 1]
    local st = game.statsOf(pr)
    units[#units + 1] = {
      side = 'p', role = pr.role, name = pr.name, lvl = pr.lvl, out = pr.out, ref = pr,
      owner = game.ownerOf(pr), color = game.palColor(pr),
      x = sp[1], y = sp[2], fx = sp[1], fy = sp[2],
      hp = st.hp, max = st.hp, atk = st.atk, move = st.move, range = st.range,
      acted = false, guard = false, buff = 0, alive = true, specUsed = false,
    }
  end
  -- Golden Compass rematch: sea 9's kraken reuses the King's fight
  -- with a stat bump, no new art required yet — the treasure-log payoff is
  -- "tougher, named differently", not a whole new boss kit.
  local kr = data.EROLES.king
  local krHp = foe.kraken and math.floor(kr.hp * 1.25) or kr.hp
  local krAtk = foe.kraken and kr.atk + 2 or kr.atk
  local eSpawns = deckInfo.eSpawns
  local kingSpawn = eSpawns[1]
  local kingUnit = {
    side = 'e', role = 'king', name = foe.name or kr.label, lvl = lv, boss = true,
    x = kingSpawn[1], y = kingSpawn[2], fx = kingSpawn[1], fy = kingSpawn[2],
    hp = krHp, max = krHp, atk = krAtk, move = kr.move, range = kr.range,
    bars = 3, rage = 0,
    acted = false, guard = false, buff = 0, alive = true,
  }
  units[#units + 1] = kingUnit
  local minionRoles = { 'grunt', 'brute' }
  for i, roleKey in ipairs(minionRoles) do
    local er = data.EROLES[roleKey]
    local sp = eSpawns[i % #eSpawns + 1]
    units[#units + 1] = {
      side = 'e', role = roleKey, name = er.label, lvl = lv,
      x = sp[1], y = sp[2], fx = sp[1], fy = sp[2],
      hp = er.hp + er.hpLv * (lv - 1), max = er.hp + er.hpLv * (lv - 1),
      atk = er.atk + er.atkLv * (lv - 1), move = er.move, range = er.range,
      acted = false, guard = false, buff = 0, alive = true,
    }
  end
  -- Apply Grape Shot deck sweep effect:
  if foe.gunsStage and foe.gunsStage < 0 then
    local targetUnit
    for _, u in ipairs(units) do
      if u.side == 'e' then
        if not u.boss then
          targetUnit = u
          break
        end
      end
    end
    if not targetUnit then
      for _, u in ipairs(units) do
        if u.side == 'e' then
          targetUnit = u
          break
        end
      end
    end
    if targetUnit then
      targetUnit.hp = math.max(1, math.floor(targetUnit.max / 2))
    end
  end
  for i, u in ipairs(units) do u.id = i end
  local crates = model.scatterCrates(deckInfo)
  newPb(units, crates, lv, foe, true, deckInfo)
  engine.setState('personBattle')
  battleStartBarks(units)
  local kx, ky = model.px(kingUnit.x, kingUnit.y)
  barks.sayKing(kingUnit, kx, ky, 'taunt')
  engine.showBanner((foe.name or kr.label) .. '!', CO.red, 1.2)
end

local PB_IDLE_LATCHES = { { limit = 20, key = 'p2Away' }, { limit = 40, key = 'p2Auto' } }

engine.states.personBattle = {
  update = function(dt)
    local pb = S.pb
    if game.isCoop() then
      coop.tickIdle(pb, dt, PB_IDLE_LATCHES)
    end

    -- The action lock: at most one of the timing bar, a walk, or a
    -- scheduled wait resolves per frame; party-phase browsing stays live
    -- underneath it (updatePlayer blocks only the confirms). The foe-turn
    -- coroutine (pb.co, see ai.lua) is what usually drives these three —
    -- it only ever has one of them active at a time, same invariant.
    local locked = false
    local barOwner = timing.on and (timing.player or 'both') or nil
    do
      local pressed
      if timing.player == 'p2' then pressed = input.p2.jp('a')
      elseif timing.player == 'p1' then pressed = input.p1.jp('a')
      else pressed = input.jp('a') end
      if timing.update(dt, pressed) then locked = true end
    end

    if not locked and pb.walk then
      local w = pb.walk
      w.t = w.t + dt * 11
      local seg = math.floor(w.t)
      if seg >= #w.path - 1 then
        w.u.fx, w.u.fy = w.u.x, w.u.y
        pb.walk = nil
        if w.after then w.after() end
      else
        local fr = w.t - seg
        w.u.fx = util.lerp(w.path[seg + 1][1], w.path[seg + 2][1], fr)
        w.u.fy = util.lerp(w.path[seg + 1][2], w.path[seg + 2][2], fr)
        draw.stepSfx(dt)
      end
      locked = true
    end

    if not locked and pb.wait > 0 then
      pb.wait = pb.wait - dt
      if pb.wait <= 0 and pb.next then
        local fn = pb.next
        pb.next = nil
        fn()
      end
      locked = true
    end

    if pb.co then
      local ok, err = coroutine.resume(pb.co)
      if not ok then error(err) end
      if coroutine.status(pb.co) == 'dead' then pb.co = nil end
    end

    if pb.over or pb.phase ~= 'party' then return end

    updatePlayer('p1', locked, barOwner)
    if game.isCoop() then updatePlayer('p2', locked, barOwner) end

    if not locked and game.isCoop() and pb.p2Auto and not pb.over then
      for _, u in ipairs(pb.units) do
        if u.side == 'p' and u.alive and not u.acted and (u.owner or 'p1') == 'p2'
          and pb.pl.p1.sel ~= u and pb.pl.p2.sel ~= u then
          model.schedule(function() ai.autoAct(u) end, 0.5)
          break
        end
      end
    end
  end,

  draw = draw.draw,
}

return M
