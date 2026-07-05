-- Boarding-battle foe AI and the co-op idle auto-act assist: hazard
-- ticking, the foe turn queue (attack/slam/thief chase), and the
-- solo-collapse auto-act for a long-idle P2's pals.
--
-- The foe turn (nextFoeCo and friends) runs as one coroutine (pb.co) pumped
-- from person_battle.lua's update(), so "attack this foe, wait for the
-- parry bar, then move to the next one" reads top-to-bottom instead of
-- chasing model.schedule(nextFoe, ...) through half a dozen closures. The
-- lone-action helpers below it (autoAct) stay plain callbacks — they're
-- only one level deep, so a coroutine would be pure overhead there.
local util = require 'src.util'
local grid = require 'src.grid'
local palette = require 'src.palette'
local audio = require 'src.audio'
local engine = require 'src.engine'
local game = require 'src.game'
local timing = require 'src.timing'
local meta = require 'src.meta'
local model = require 'src.states.person_battle.model'
local barks = require 'src.barks'
local S = require 'src.states.person_battle.state'
local CO = palette.CO
local SFX = audio.sfx
local gk = grid.gk

local M = {}

local nextFoeCo -- forward declaration (self-recursive)

local function beginCo(fn)
  S.pb.co = coroutine.create(fn)
end

-- Counts down in person_battle.lua's update() (pb.wait ticks there every
-- frame); yields until it reaches zero, same granularity model.schedule
-- always had.
local function wait(delay)
  local pb = S.pb
  pb.wait = delay
  while pb.wait > 0 do coroutine.yield() end
end

-- Hazards are marked a full player-turn ahead (turnsLeft=1) so the player
-- always gets one turn's warning before they resolve; each foe-phase start
-- ticks them down and detonates any that hit zero.
local function resolveHazards()
  local pb = S.pb
  local remaining = {}
  for _, hz in ipairs(pb.hazards) do
    hz.turnsLeft = hz.turnsLeft - 1
    if hz.turnsLeft <= 0 then
      model.applyTileDamage(hz.x, hz.y, hz.damage or 6)
    else
      remaining[#remaining + 1] = hz
    end
  end
  pb.hazards = remaining

  if pb.vent then
    pb.vent.cycle = pb.vent.cycle + 1
    if pb.vent.cycle > 2 then
      pb.vent.cycle = 1
      model.applyTileDamage(pb.vent.x, pb.vent.y, pb.vent.damage or 3)
    end
  end
end

-- Test-only: the real game pumps pb.co one resume per frame from
-- person_battle.lua's update(), driven by real dt and real animation/input
-- ticks. Headless tests have no such loop, so this drains pb.co in one
-- call, treating every wait(delay) as instant; it stops (leaving pb.co
-- dangling, same as a real frame that hasn't ticked yet) the moment the
-- coroutine blocks on something only a real update() loop can resolve
-- (a walk animation or the timing bar) — exactly mirroring how those
-- continuations simply never fired in the old callback-based headless tests.
function M.pumpForTest()
  local pb = S.pb
  while pb.co do
    if pb.walk or timing.on then break end
    pb.wait = 0
    local ok, err = coroutine.resume(pb.co)
    if not ok then error(err) end
    if coroutine.status(pb.co) == 'dead' then pb.co = nil end
  end
end

function M.startFoePhase()
  local pb = S.pb
  pb.phase = 'foe'
  for _, pl in pairs(pb.pl) do
    pl.sel, pl.reach, pl.origin = nil, nil, nil
    pl.stage = 'pick'
  end
  resolveHazards()
  if model.checkEnd() then return end
  engine.showBanner('ENEMY TURN', CO.red, 0.9)
  pb.queue = {}
  for _, u in ipairs(pb.units) do
    if u.side == 'e' and u.alive then pb.queue[#pb.queue + 1] = u end
  end
  beginCo(function()
    wait(0.9)
    nextFoeCo()
  end)
end

-- Shared foe/pal movement: flood from target, walk down decreasing cost
-- toward it (never crossing a unit), stopping once within stopRange, then
-- call `after`. `after` re-checks distance itself since a blocked path may
-- not actually close to stopRange.
local function walkToward(u, target, stopRange, after)
  local pb = S.pb
  if u.side == 'e' and u.role == 'gunner' and pb.perch then
    local px, py = pb.perch[1], pb.perch[2]
    local o = model.unitAt(px, py)
    if not o or o == u then
      local reach = grid.bfsFlood(u.x, u.y, u.move, function(x, y)
        if not model.inDeck(x, y) or pb.crates[gk(x, y)] then return false end
        local ou = model.unitAt(x, y)
        return not ou or ou == u
      end)
      if reach.cost[gk(px, py)] ~= nil then
        local targetRange = model.attackRangeAt(u, px, py)
        if grid.manhattan(px, py, target.x, target.y) <= targetRange then
          local pPath = grid.bfsPath(reach, px, py)
          if pPath then
            model.walkWithTerrain(u, pPath, after)
            return
          end
        end
      end
    end
  end

  local field = grid.bfsFlood(target.x, target.y, 99, function(x, y)
    return model.inDeck(x, y) and not pb.crates[gk(x, y)]
  end)
  local path = { { u.x, u.y } }
  local cx, cy = u.x, u.y
  for _ = 1, u.move do
    local bd = field.cost[gk(cx, cy)]
    if bd == nil then break end
    local stepped = false
    for k = 1, 4 do
      local nx, ny = cx + grid.DIRS4[k][1], cy + grid.DIRS4[k][2]
      local nd = field.cost[gk(nx, ny)]
      if nd ~= nil and nd < bd and not model.unitAt(nx, ny) then
        cx, cy = nx, ny
        path[#path + 1] = { cx, cy }
        stepped = true
        break
      end
    end
    if not stepped then break end
    if grid.manhattan(cx, cy, target.x, target.y) <= stopRange then break end
  end

  model.walkWithTerrain(u, path, after)
end

-- Coroutine-blocking wrapper around walkToward, for the foe-turn chain
-- below: yields until the walk (if any) finishes.
local function walkTowardCo(u, target, stopRange)
  local done = false
  walkToward(u, target, stopRange, function() done = true end)
  while not done do coroutine.yield() end
end

-- King special: marks 3 random open deck tiles as hazards, telegraphed one
-- full player-turn ahead of resolveHazards() detonating them.
local function doSlamCo(foe)
  local pb = S.pb
  local fx, fy = model.px(foe.x, foe.y)
  barks.sayKing(foe, fx - 8, fy, 'slam')
  engine.addFloat(fx + 8, fy - 10, 'SLAM!', CO.orange, 2)
  SFX.bump()
  engine.shakeIt(2, 0.2)
  local tiles = {}
  for _ = 1, 3 do
    for _try = 1, 10 do
      local dt = pb.deckList[util.irand(1, #pb.deckList)]
      local x, y = dt[1], dt[2]
      if not pb.crates[gk(x, y)] then
        local dup = false
        for _, t in ipairs(tiles) do if t.x == x and t.y == y then dup = true end end
        if not dup then
          tiles[#tiles + 1] = { x = x, y = y }
          break
        end
      end
    end
  end
  for _, t in ipairs(tiles) do
    pb.hazards[#pb.hazards + 1] = { x = t.x, y = t.y, turnsLeft = 1 }
  end
  wait(0.8)
  nextFoeCo()
end

-- Runs the parry timing bar and yields until it resolves.
local function waitTiming(cfg, label, timeoutRes, player)
  local result
  timing.start(cfg, label, function(r) result = r end, timeoutRes, player)
  while result == nil do coroutine.yield() end
  return result
end

local function foeAttackCo(foe, tgt)
  local fx, fy = model.px(foe.x, foe.y)
  engine.addFloat(fx + 8, fy - 6, '!', CO.red, 2)
  SFX.bump()
  wait(0.45)
  if not tgt.alive then
    wait(0.2)
    nextFoeCo()
    return
  end
  local pb = S.pb
  local res
  -- Kind auto-resolve (C4): a fully idle P2's pal blocks at 'good'
  -- automatically instead of leaving a bar nobody will press.
  if game.isCoop() and pb.p2Auto and tgt.ref and game.ownerOf(tgt.ref) == 'p2' then
    res = 'good'
  else
    pb.phase = 'parry'
    -- Softened parry timeout (4.4, widened by design-gaps/04): on seas 1-3
    -- a frozen, overwhelmed kid who never presses eats half damage
    -- ('good'), not full ('miss').
    res = waitTiming(timing.cfg(pb.lv, true, meta.steadyMult()), 'BLOCK! PRESS Z!',
      pb.lv <= 3 and 'good' or 'miss', model.ownerPlayer(tgt))
  end
  local base = foe.atk + util.irand(0, 1)
  local tx, ty = model.px(tgt.x, tgt.y)
  if res == 'perfect' then
    SFX.block()
    engine.addParts(tx + 8, ty + 4, 10, CO.foam, 50)
    engine.addFloat(tx + 8, ty - 10, 'BLOCKED!', CO.foam, 2)
  else
    local dmg = res == 'good' and math.ceil(base / 2) or base
    if tgt.guard then dmg = math.ceil(dmg / 2) end
    if model.hasCover(tgt, foe) then dmg = math.ceil(dmg / 2) end
    dmg = math.max(1, dmg)
    tgt.hp = math.max(0, tgt.hp - dmg)
    SFX.hit()
    engine.shakeIt(1.5, 0.12)
    engine.addParts(tx + 8, ty + 8, 8, CO.red, 45)
    engine.addFloat(tx + 8, ty - 4, '-' .. dmg, CO.red, 2)
    if res == 'good' then engine.addFloat(tx + 8, ty + 6, 'HALF!', CO.foam, 1) end
    if tgt.hp <= 0 then model.ko(tgt) end
  end
  pb.phase = 'foe'
  if not model.checkEnd() then
    wait(0.5)
    nextFoeCo()
  end
end

-- Thief parrot (4.3): never attacks. Chases the nearest pal, grabs 5 gold
-- when adjacent, then flees toward the right deck edge; reaching it while
-- carrying escapes with the gold (small, visible, never treasures or pals'
-- stuff). KO-ing him first drops the gold — combat becomes a chase.
local function thiefEscapeCo(foe)
  local fx, fy = model.px(foe.x, foe.y)
  foe.alive = false
  foe.escaped = true
  local took = math.min(foe.loot or 0, game.run.gold)
  game.run.gold = game.run.gold - took
  SFX.poof()
  engine.addParts(fx + 8, fy + 8, 10, CO.foam, 40)
  engine.addFloat(fx + 8, fy - 6,
    took > 0 and ('HE GOT ' .. took .. ' GOLD!') or 'HE GOT NOTHING!', CO.orange, 2)
  if not model.checkEnd() then
    wait(0.6)
    nextFoeCo()
  end
end

local function thiefGrabCo(foe)
  foe.loot = 5
  SFX.coin()
  local fx, fy = model.px(foe.x, foe.y)
  engine.addFloat(fx + 8, fy - 6, 'YOINK! 5 GOLD!', CO.orange, 2)
  wait(0.6)
  nextFoeCo()
end

local function thiefActCo(foe)
  local pb = S.pb
  if foe.loot then
    if foe.x >= pb.eastEdge[foe.y] then
      thiefEscapeCo(foe)
      return
    end
    -- Flee: greedy steps that prefer straight toward the right edge.
    local path = { { foe.x, foe.y } }
    local cx, cy = foe.x, foe.y
    for _ = 1, foe.move do
      local nxt = nil
      for _, c in ipairs({ { cx + 1, cy }, { cx, cy - 1 }, { cx, cy + 1 } }) do
        if model.inDeck(c[1], c[2]) and not pb.crates[gk(c[1], c[2])] and not model.unitAt(c[1], c[2]) then
          nxt = c
          break
        end
      end
      if not nxt then break end
      cx, cy = nxt[1], nxt[2]
      path[#path + 1] = { cx, cy }
      if cx >= pb.eastEdge[cy] then break end
    end
    local done = false
    model.walkWithTerrain(foe, path, function() done = true end)
    while not done do coroutine.yield() end
    if not foe.alive then
      if not model.checkEnd() then wait(0.3); nextFoeCo() end
      return
    end
    if foe.x >= pb.eastEdge[foe.y] then thiefEscapeCo(foe)
    else wait(0.3); nextFoeCo() end
    return
  end
  local best, bestD = nil, 999
  for _, t in ipairs(pb.units) do
    if t.side == 'p' and t.alive then
      local d = grid.manhattan(foe.x, foe.y, t.x, t.y)
      if d < bestD then best, bestD = t, d end
    end
  end
  if not best then
    wait(0.2)
    nextFoeCo()
    return
  end
  if bestD <= 1 then
    thiefGrabCo(foe)
    return
  end
  walkTowardCo(foe, best, 1)
  if grid.manhattan(foe.x, foe.y, best.x, best.y) <= 1 then thiefGrabCo(foe)
  else wait(0.3); nextFoeCo() end
end

-- Target pick shared by execution (nextFoeCo) and planning (planFoeIntents),
-- so a telegraphed intent can never drift from what actually happens:
-- nearest living player, tie broken by lowest HP.
local function pickTarget(foe)
  local best, bestD = nil, 999
  for _, t in ipairs(S.pb.units) do
    if t.side == 'p' and t.alive then
      local d = grid.manhattan(foe.x, foe.y, t.x, t.y)
      if d < bestD or (d == bestD and best and t.hp < best.hp) then
        best, bestD = t, d
      end
    end
  end
  return best, bestD
end

-- Honest boarding intents: tells the player next turn's move/attack
-- before they commit, mirroring ship battle's decideIntent. The King's SLAM
-- keeps its own tile telegraph (doSlam) instead of an icon here, and the
-- thief never attacks, so both are left without an intent.
function M.planFoeIntents()
  for _, u in ipairs(S.pb.units) do
    u.intent = nil
    if u.side == 'e' and u.alive and not u.boss and u.role ~= 'thief' then
      local best, bestD = pickTarget(u)
      if best then
        local uRange = model.attackRange(u)
        if bestD <= uRange then
          u.intent = { kind = 'attack', target = best }
        else
          local field = grid.bfsFlood(best.x, best.y, 99, function(x, y)
            return model.inDeck(x, y) and not S.pb.crates[gk(x, y)]
          end)
          local canMove = false
          local bd = field.cost[gk(u.x, u.y)]
          if bd ~= nil then
            for k = 1, 4 do
              local nx, ny = u.x + grid.DIRS4[k][1], u.y + grid.DIRS4[k][2]
              local nd = field.cost[gk(nx, ny)]
              if nd ~= nil and nd < bd and not model.unitAt(nx, ny) then
                canMove = true
                break
              end
            end
          end
          if not canMove then
            local cx, cy = model.findBlockedCrateStep(u, best)
            if cx then
              u.intent = { kind = 'smash', target = best, x = cx, y = cy }
            else
              u.intent = { kind = 'move', target = best }
            end
          else
            u.intent = { kind = 'move', target = best }
          end
        end
      end
    end
  end
end

-- Foe AI: follows the intent planFoeIntents already telegraphed when it's
-- still legal (target alive); falls back to a fresh pick otherwise — an
-- honest intent, not a clairvoyant one. No sb.over-style re-checks needed:
-- if a step above ended the battle, the callback that ends it (model.ko /
-- checkEnd's transition) never resumes this coroutine again.
nextFoeCo = function()
  local pb = S.pb
  if model.checkEnd() then return end
  local foe = nil
  while #pb.queue > 0 and not foe do
    local c = table.remove(pb.queue, 1)
    if c.alive then foe = c end
  end
  if not foe then
    for _, u in ipairs(pb.units) do
      if u.side == 'p' then
        u.acted = false
        u.guard = false
        if u.soggy and u.alive then
          u.acted = true
          u.soggy = false
          local ux, uy = model.px(u.x, u.y)
          engine.addFloat(ux + 8, uy - 12, 'GLUB!', CO.blue, 1.5)
        end
      end
    end
    pb.phase = 'party'
    engine.showBanner('YOUR TURN!', CO.gold, 0.9)
    model.cursorToNext('p1')
    if game.isCoop() then model.cursorToNext('p2') end
    M.planFoeIntents()
    return
  end

  if foe.soggy then
    foe.soggy = false
    local fx, fy = model.px(foe.x, foe.y)
    engine.addFloat(fx + 8, fy - 12, 'GLUB!', CO.blue, 1.5)
    wait(0.6)
    nextFoeCo()
    return
  end

  if foe.boss and util.chance(0.35 + 0.1 * (foe.rage or 0)) then
    doSlamCo(foe)
    return
  end

  if foe.role == 'thief' then
    thiefActCo(foe)
    return
  end

  local best, bestD
  if foe.intent and foe.intent.target and foe.intent.target.alive then
    best, bestD = foe.intent.target, grid.manhattan(foe.x, foe.y, foe.intent.target.x, foe.intent.target.y)
  else
    best, bestD = pickTarget(foe)
  end
  if not best then
    nextFoeCo()
    return
  end
  local fRange = model.attackRange(foe)
  if bestD <= fRange then
    foeAttackCo(foe, best)
    return
  end

  local sx, sy = foe.x, foe.y
  walkTowardCo(foe, best, fRange)

  if foe.x == sx and foe.y == sy and not model.canAttack(foe, best) then
    local cx, cy = model.findBlockedCrateStep(foe, best)
    if cx then
      model.smashCrate(foe, cx, cy)
      wait(0.5)
      nextFoeCo()
      return
    end
  end

  if model.canAttack(foe, best) then
    foeAttackCo(foe, best)
  else
    wait(0.3)
    nextFoeCo()
  end
end

-- Kind auto-act (C4 solo-collapse, stage 2): after P2 has been idle well
-- past the p2Away latch, their pals act on their own each round — step
-- toward the nearest foe and attack with auto-'good' timing — so a half-
-- abandoned co-op run flows exactly like solo play. Only one callback deep
-- (walkToward's `after`), so this stays plain rather than its own coroutine.
function M.autoAct(u)
  local pb = S.pb
  if pb.over or not u.alive or u.acted then return end
  if pb.pl.p1.sel == u or pb.pl.p2.sel == u then return end
  local function finishAuto()
    u.acted = true
    if model.checkEnd() then return end
    if model.allActed() then M.startFoePhase() end
  end
  local best, bestD = nil, 999
  for _, t in ipairs(pb.units) do
    if t.side == 'e' and t.alive then
      local d = grid.manhattan(u.x, u.y, t.x, t.y)
      if d < bestD then best, bestD = t, d end
    end
  end
  if not best then
    finishAuto()
    return
  end
  local ux, uy = model.px(u.x, u.y)
  engine.addFloat(ux + 8, uy - 10, 'AUTO!', CO.green, 1)
  local function strike()
    if model.canAttack(u, best) then
      model.damage(u, best, u.atk + u.buff + util.irand(0, 1), 'good', {})
    end
    finishAuto()
  end
  if model.canAttack(u, best) then
    strike()
    return
  end
  walkToward(u, best, model.attackRange(u), strike)
end

return M
