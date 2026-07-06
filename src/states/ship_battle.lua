-- Ship battle: turn-based, menu-driven, NEAR/FAR range bands. Winning
-- disables the enemy ship and hands off to the boarding (person) battle;
-- losing slips the player safely back to sail mode.
--
-- TWO CAPTAINS (C3): sb.ships is a real array (1 entry solo, 2 in fleet
-- mode) so foe-side logic (decideIntent/foeAct/impact/fireBall/shipXY) is
-- fully shared by index; only the *round structure* differs. Solo keeps the
-- classic single-turn menu (sb.turn 'you'/'foe'). Fleet mode picks both
-- captains' actions simultaneously (sb.turn 'select'), then resolves them
-- one at a time in confirm order (sb.turn 'resolve') before the foe's
-- single turn.
--
-- Round resolution (everything after a menu is confirmed: animations,
-- damage, the foe's turn, back to select) runs as one coroutine (sb.co)
-- pumped from update(). `wait(secs)`/`waitAnim()`/`waitTiming(...)` yield
-- until their condition clears, so a turn reads as a straight line instead
-- of schedule()/fireBall(after) closures. Menu/submenu navigation (reading
-- the d-pad each frame) stays outside the coroutine, same as before;
-- confirming an action is what starts sb.co. Ending the battle just
-- replaces sb.co with a short "wait, then transition" coroutine — the old
-- code's repeated `if sb.over then return end` guards are gone because an
-- abandoned coroutine (one whose sb.co has been replaced) is simply never
-- resumed again.
local util = require 'src.util'
local palette = require 'src.palette'
local font = require 'src.font'
local sprites = require 'src.sprites'
local input = require 'src.input'
local audio = require 'src.audio'
local engine = require 'src.engine'
local game = require 'src.game'
local data = require 'src.data'
local meta = require 'src.meta'
local ui = require 'src.ui'
local fleetRound = require 'src.fleet'
local coop = require 'src.coop'
local timing = require 'src.timing'
local personBattle = require 'src.states.person_battle'
local CO = palette.CO
local gfx = love.graphics
local SFX = audio.sfx

local VW = 320
local P2_AUTOFIRE_LATCHES = { { limit = 15, key = 'p2AutoFire' } }

local M = {}
local sb = nil -- current battle; exposed as M.sb for tooling/tests
local decideIntent -- forward declaration
local impact -- forward declaration
local shipDown -- forward declaration

-- Fleet mode: each ship is driven entirely by its own captain's input.
local function shipCtx(i)
  if not sb.fleet then return input.p1 end
  return sb.ships[i].owner == 'p2' and input.p2 or input.p1
end

-- Timing-bar prompt labels name the confirm key actually bound for the
-- player whose press resolves the bar (nil owner = either player, so P1's
-- binding is shown).
local function pressLabel(verb, owner)
  local ctx = owner == 'p2' and input.p2 or input.p1
  return verb .. '! PRESS ' .. input.promptKey(ctx, 'a') .. '!'
end

function M.start(foe)
  game.run.hints.foe = true
  local lv = game.scaleLv(foe.lv)
  local isBoss = foe.boss == true
  local fleet = game.run.mode == 'captains'
  local foeHp = isBoss and (foe.kraken and 190 or 96) or (18 + 7 * lv)
  local foeRepairs = isBoss and (foe.kraken and 2 or 1) or 2
  local bigshotKegs = 0
  local volleyKegs = 0
  if isBoss then
    bigshotKegs = fleet and 4 or 3
    volleyKegs = 2
  end
  -- Fleet battles land ~2x player actions per round (two captains firing
  -- instead of one); scale the foe up here, in the one place, rather than
  -- scattering an extra multiplier through decideIntent/impact.
  if fleet then
    foeHp = math.floor(foeHp * 1.6)
    foeRepairs = isBoss and (foe.kraken and 3 or 2) or 3
  end
  -- Volcano dents (4.1): rock hits on the sail map lower the starting bar
  -- for the next battle only (capped at 9, so never close to a sink), then
  -- the dents are spent. FIX patches them like any other damage.
  local hurt = 0
  if game.run.sea then
    hurt = game.run.sea.shipHurt or 0
    game.run.sea.shipHurt = 0
  end
  -- FIGUREHEAD raises max ship HP; BETTER SAILS grants one free auto-dodge
  -- per battle (reuses the existing dodge-chance field, guaranteed at 1 —
  -- the first incoming hit rolls against it and is consumed like any dodge).
  local shipMax = meta.shipMaxHp()
  local ships = {
    {
      hp = shipMax - hurt, max = shipMax, repairs = 3, maxRepairs = 3,
      dodge = meta.hasFreeDodge() and 1 or 0,
      range = 'FAR', pt = 0, owner = 'p1',
      menu = 0, subOpen = false, sub = 0, chosen = nil, confirmOrder = nil,
      patched = false, patchRounds = 0,
    },
  }
  if fleet then
    ships[2] = {
      hp = shipMax, max = shipMax, repairs = 3, maxRepairs = 3, dodge = 0,
      range = 'FAR', pt = 0, owner = 'p2',
      menu = 0, subOpen = false, sub = 0, chosen = nil, confirmOrder = nil,
      patched = false, patchRounds = 0,
    }
  end
  sb = {
    foeRef = foe,
    isBoss = isBoss,
    fleet = fleet,
    foe = {
      hp = foeHp, max = foeHp, name = foe.name, lv = lv,
      repairs = foeRepairs, maxRepairs = foeRepairs,
      dodge = 0, intent = nil, target = 1,
      bigshotKegs = bigshotKegs, maxBigshotKegs = bigshotKegs,
      volleyKegs = volleyKegs, maxVolleyKegs = volleyKegs
    },
    ships = ships,
    turn = fleet and 'select' or 'you',
    menu = 0, subOpen = false, sub = 0,
    specUsed = {}, anim = nil, wait = 0, co = nil,
    over = false, msg = fleet and 'BOTH CAPTAINS, CHOOSE!' or 'YOUR TURN! CHOOSE!',
    broadsideUsed = false,
    confirmSeq = 0, queue = {}, idleT = 0,
    perfectFireCount = 0, cannonballFx = false,
  }
  M.sb = sb
  decideIntent()
  engine.setState('shipBattle')
  if hurt > 0 then engine.showBanner('DENTED BY ROCKS!', CO.orange, 1.2) end
end

-- Creates (but does not resume) the round-resolution coroutine; update()'s
-- single `if sb.co then coroutine.resume(sb.co) end` gives it its first
-- tick, whether it was just created from a menu confirm this same frame or
-- from a timing-bar/animation callback fired earlier in this same update().
local function beginCo(fn)
  sb.co = coroutine.create(fn)
end

-- Counts down in update() (sb.wait ticks there every frame); yields until
-- it reaches zero, same granularity the old schedule(fn, delay) had.
local function wait(delay)
  sb.wait = delay
  while sb.wait > 0 do coroutine.yield() end
end

local function waitAnim()
  while sb.anim do coroutine.yield() end
end

-- Runs the timing bar and yields until it resolves; timing.update(dt, ...)
-- itself is still ticked unconditionally in update(), same as the bar's
-- visual sweep always was.
local function waitTiming(cfg, label, timeoutRes, player)
  local result
  timing.start(cfg, label, function(r) result = r end, timeoutRes, player)
  while result == nil do coroutine.yield() end
  return result
end

local function waitTimingCoop(cfg, label, timeoutRes)
  local r1, r2
  timing.startCoop(cfg, label, function(a, b) r1, r2 = a, b end, timeoutRes)
  while r1 == nil do coroutine.yield() end
  return r1, r2
end

local function laneY(i)
  if #sb.ships <= 1 then return 74 end
  return i == 1 and 60 or 92
end

-- Ship screen positions interpolate between FAR and NEAR anchors. `who` is
-- either a ship index or the string 'foe'.
local function shipXY(who)
  if who == 'foe' then
    -- The foe leans toward NEAR if any ship it's fighting has closed in.
    local t = 0
    for _, sh in ipairs(sb.ships) do t = math.max(t, util.ease(sh.pt)) end
    return util.lerp(258, 194, t), 74
  end
  local sh = sb.ships[who]
  return util.lerp(28, 82, util.ease(sh.pt)), laneY(who)
end

local function targetEnt(who)
  if who == 'foe' then return sb.foe end
  return sb.ships[who]
end

-- fromWho/toWho are each either a ship index or 'foe'. Callers follow with
-- waitAnim() to sequence the next step after the ball lands.
local function fireBall(fromWho, toWho, dmg, opts)
  local ax, ay = shipXY(fromWho)
  local bx, by = shipXY(toWho)
  SFX.shot()
  sb.anim = {
    type = 'ball', t = 0, dur = 0.5,
    x0 = ax + 16, y0 = ay + 12, x1 = bx + 16, y1 = by + 16,
    cb = function() impact(toWho, dmg, opts or {}) end,
  }
end

impact = function(who, dmg, opts)
  local tgt = targetEnt(who)
  local ex, ey = shipXY(who)
  if tgt.dodge > 0 and not opts.ignoreDodge then
    local dodged = util.chance(tgt.dodge)
    tgt.dodge = 0
    if dodged then
      SFX.splash()
      engine.addParts(ex + 16, ey + 22, 10, CO.foam, 40)
      engine.addFloat(ex + 16, ey - 14, who ~= 'foe' and 'DODGED!' or 'MISS!', CO.foam, 2)
      return
    end
  end
  tgt.hp = math.max(0, tgt.hp - dmg)
  SFX.boom()
  engine.shakeIt(2.5, 0.2)
  engine.addParts(ex + 16, ey + 14, 14, CO.orange, 55)
  engine.addParts(ex + 16, ey + 14, 8, CO.gold, 40)
  if sb.cannonballFx and who == 'foe' then
    engine.addParts(ex + 16, ey + 14, 8, util.pick({ CO.red, CO.gold, CO.green, CO.purple, CO.foam }), 55)
  end
  engine.addFloat(ex + 16, ey, '-' .. dmg, who ~= 'foe' and CO.red or CO.gold, 2)
  if tgt.hp <= 0 then
    if who == 'foe' then
      sb.over = true
      SFX.bigwin()
      sb.msg = 'SHIP DISABLED!'
      local isBoss = sb.isBoss
      local foeRef = sb.foeRef
      beginCo(function()
        wait(1.3)
        engine.transition('BOARD THE SHIP!', function()
          if isBoss then personBattle.startBoss(foeRef) else personBattle.start(foeRef) end
        end)
      end)
    else
      shipDown(who)
    end
  end
end

-- No sinking, ever: a downed fleet ship falls back to patch up instead of
-- losing outright; losing is only the normal safe loss, and only if both
-- ships are patching at the same time. Solo has one ship, so a downed ship
-- there is still the classic safe loss.
shipDown = function(i)
  if not sb.fleet then
    sb.over = true
    SFX.lose()
    sb.msg = 'YOUR SHIP SLIPS AWAY...'
    beginCo(function()
      wait(1.3)
      engine.transition('SAFE AND SOUND!', function() engine.setState('sail') end)
    end)
    return
  end
  local otherPatched = false
  for j, o in ipairs(sb.ships) do
    if j ~= i and o.patched then otherPatched = true end
  end
  local ex, ey = shipXY(i)
  if otherPatched then
    sb.over = true
    SFX.lose()
    sb.msg = 'BOTH SHIPS SLIP AWAY...'
    beginCo(function()
      wait(1.3)
      engine.transition('SAFE AND SOUND!', function() engine.setState('sail') end)
    end)
    return
  end
  local sh = sb.ships[i]
  sh.patched, sh.patchRounds, sh.hp, sh.chosen = true, 2, 0, nil
  engine.addFloat(ex + 16, ey - 18, 'FALLS BACK TO PATCH UP!', CO.orange, 2)
end

-- Dev cheat (F3 under --dev): route through the normal impact() resolution
-- so the win still plays out the transition into boarding.
function M.debugWin()
  if not sb or sb.over then return end
  impact('foe', sb.foe.hp, { ignoreDodge = true })
end

-- Decides what the foe will do (and which ship it targets) on its NEXT
-- turn, one turn before it happens, so the big telegraph icon is a real
-- answer the player(s) can react to (MOVE dodges FIRE/BIG SHOT). Runs at
-- battle start and every time control returns to the player(s). A patched
-- (falling-back) ship is never targeted.
decideIntent = function()
  local f = sb.foe
  local candidates = {}
  for i, sh in ipairs(sb.ships) do
    if not sh.patched then candidates[#candidates + 1] = i end
  end
  f.target = #candidates > 0 and util.pick(candidates) or 1
  if sb.isBoss then
    if f.hp < f.max * 0.3 and f.repairs > 0 and util.chance(0.6) then
      f.intent = 'fix'
    -- New Voyage+ tier 2 wrinkle: the King learns VOLLEY, a telegraphed
    -- back-to-back double shot (still just MOVE-dodgeable, like FIRE).
    elseif (meta.data.tier or 0) >= 2 and f.volleyKegs > 0 and util.chance(0.25) then
      f.intent = 'volley'
    elseif f.bigshotKegs > 0 and util.chance(0.35) then
      f.intent = 'bigshot'
    else
      f.intent = 'fire'
    end
    return
  end
  if f.hp < f.max * 0.35 and f.repairs > 0 and util.chance(0.8) then
    f.intent = 'fix'
  elseif util.chance(0.18) then
    f.intent = 'move'
  else
    f.intent = 'fire'
  end
end

-- Auto-repairs patched (falling-back) fleet ships a chunk each round;
-- rejoins the fight after two rounds with a guaranteed minimum hull.
local function tickPatches()
  for i, sh in ipairs(sb.ships) do
    if sh.patched then
      sh.patchRounds = sh.patchRounds - 1
      sh.hp = math.min(sh.max, sh.hp + math.floor(sh.max * 0.25))
      if sh.patchRounds <= 0 then
         sh.patched = false
         sh.hp = math.max(sh.hp, math.floor(sh.max * 0.4))
         local ex, ey = shipXY(i)
         engine.addFloat(ex + 16, ey - 18, 'BACK IN THE FIGHT!', CO.green, 2)
      end
    end
  end
end

-- Plain (non-yielding) state reset shared by the tail of every round's
-- coroutine, solo or fleet.
local function backToTurnLogic()
  if sb.fleet then
    tickPatches()
    for _, sh in ipairs(sb.ships) do sh.chosen, sh.confirmOrder = nil, nil end
    sb.turn = 'select'
    sb.msg = 'BOTH CAPTAINS, CHOOSE!'
  else
    sb.turn = 'you'
    sb.msg = 'YOUR TURN! CHOOSE!'
  end
  decideIntent()
end

-- Foe AI executes whatever decideIntent already telegraphed last turn —
-- never re-rolls here, or the telegraph would be a lie. Shared by solo and
-- fleet: `target` picks which ship (always 1 outside fleet mode) takes the
-- hit / gets repositioned against.
local function runFoeAct()
  local f = sb.foe
  local lv = f.lv
  local intent = f.intent
  local target = f.target or 1
  f.intent = nil
  if intent == 'fix' then
    f.repairs = f.repairs - 1
    f.hp = math.min(f.max, f.hp + 10 + 2 * lv)
    SFX.heal()
    local ex, ey = shipXY('foe')
    engine.addParts(ex + 16, ey + 10, 10, CO.green, 30)
    engine.addFloat(ex + 16, ey - 22, 'FIXED!', CO.green, 1)
    wait(0.7)
  elseif intent == 'move' then
    local sh = sb.ships[target]
    sh.range = sh.range == 'NEAR' and 'FAR' or 'NEAR'
    f.dodge = 0.5
    local ex, ey = shipXY('foe')
    engine.addFloat(ex + 16, ey - 22, 'REPOSITION!', CO.foam, 1)
    SFX.move()
    wait(0.7)
  elseif intent == 'bigshot' then
    f.bigshotKegs = math.max(0, f.bigshotKegs - 1)
    local dmg = sb.isBoss and 20 or (14 + lv)
    fireBall('foe', target, dmg, {})
    waitAnim()
    wait(0.6)
  elseif intent == 'volley' then
    f.volleyKegs = math.max(0, f.volleyKegs - 1)
    local dmg = 8 + lv
    fireBall('foe', target, dmg, {})
    waitAnim()
    wait(0.3)
    fireBall('foe', target, dmg, {})
    waitAnim()
    wait(0.6)
  else
    local sh = sb.ships[target]
    local dmg
    if sb.isBoss then
      local base = 3 + math.floor(lv / 2)
      if sh.range ~= 'NEAR' then base = base - 2 end
      dmg = base + util.irand(0, 2)
    else
      dmg = sh.range == 'NEAR' and (4 + lv + util.irand(0, 3)) or (2 + lv + util.irand(0, 2))
    end
    fireBall('foe', target, dmg, {})
    waitAnim()
    wait(0.6)
  end
  -- No sb.over guard here: if that last hit ended the battle, impact()
  -- already replaced sb.co with the win/loss transition coroutine, so this
  -- (abandoned) one is never resumed again and backToTurnLogic() never runs.
  backToTurnLogic()
end

local function runFoeTurn()
  sb.turn = 'foe'
  sb.msg = "CAP'N " .. sb.foe.name .. "'S TURN..."
  wait(0.8)
  runFoeAct()
end

--------------------------------------------------------------------------
-- Command resolver: one resolver parameterized by ship index, shared by
-- solo and fleet; 'spec' still forks because solo defers to a top-level
-- submenu while fleet already resolved the pal via updateSelect's per-ship
-- submenu.
--------------------------------------------------------------------------

local function capLvl()
  local c = game.partyHas('captain')
  return c and c.lvl or 1
end

local function capLvlFor(i)
  if not sb.fleet then return capLvl() end
  local owner = sb.ships[i].owner
  for _, p in ipairs(game.run.party) do
    if p.role == 'captain' and game.ownerOf(p) == owner then return p.lvl end
  end
  return 1
end

-- FIRE's timing bar is driven by each fleet ship's own captain; solo has
-- no second player to gate on.
local function fireOwner(i)
  if sb.fleet then return sb.ships[i].owner end
  return nil
end

-- Specials split by owner: fleet's SPECIAL submenu lists only pals whose
-- ownerOf matches that captain; solo has no ship owner, so every unused pal
-- qualifies.
local function specialPartyFor(i)
  local owner = sb.fleet and sb.ships[i].owner or nil
  local out = {}
  for _, p in ipairs(game.run.party) do
    if not sb.specUsed[p.name] and (not owner or game.ownerOf(p) == owner) then
      out[#out + 1] = p
    end
  end
  return out
end

local function shipMenuItems(i)
  local sh = sb.ships[i]
  if sh.patched then
    return { { id = 'patch', label = 'PATCH!', ok = true, desc = "HOLD ON, WE'RE FIXING HER!" } }
  end
  local anySpec = #specialPartyFor(i) > 0
  return {
    { id = 'fire', label = 'FIRE!', ok = true,
      desc = sh.range == 'NEAR' and 'BIG BOOM UP CLOSE!' or 'SAFE SHOT FROM AFAR' },
    { id = 'move', label = 'MOVE', ok = true,
      desc = (sb.isBoss and sb.foe.intent == 'bigshot' and sb.foe.target == i) and 'DODGE THE BIG SHOT!'
        or ((sh.range == 'NEAR' and 'SAIL AWAY' or 'SAIL CLOSER') .. ' + DODGE!') },
    { id = 'fix', label = 'FIX x' .. sh.repairs, ok = sh.repairs > 0 and sh.hp < sh.max, desc = 'PATCH THE HULL +15' },
    { id = 'spec', label = 'SPECIAL', ok = anySpec, desc = 'CREW POWERS!' },
  }
end

-- Each party member has a once-per-battle ship power keyed by role. Runs
-- inline in whichever coroutine calls it (fleet's per-ship queue loop, or
-- solo's submenu-confirm coroutine) — no "done" continuation needed.
local function resolveSpecialAction(i, p)
  local sh = sb.ships[i]
  local ex, ey = shipXY(i)
  sb.specUsed[p.name] = true
  sb.subOpen = false
  local r = p.role
  engine.addFloat(VW / 2, 52, data.ROLES[r].ship.name, CO.gold, 2)
  if r == 'captain' then
    fireBall(i, 'foe', 5 + p.lvl + util.irand(0, 2), {})
    waitAnim()
    fireBall(i, 'foe', 5 + p.lvl + util.irand(0, 2), {})
    waitAnim()
  elseif r == 'deckhand' then
    sh.dodge = 1
    SFX.move()
    wait(0.7)
  elseif r == 'strongman' then
    fireBall(i, 'foe', 12 + p.lvl + util.irand(0, 3), {})
    waitAnim()
  elseif r == 'sharpshooter' then
    fireBall(i, 'foe', 9 + p.lvl + util.irand(0, 2), { ignoreDodge = true })
    waitAnim()
  elseif r == 'medic' then
    sh.hp = math.min(sh.max, sh.hp + 12)
    SFX.heal()
    engine.addParts(ex + 16, ey + 6, 12, CO.green, 30)
    engine.addFloat(ex + 16, ey - 18, '+12', CO.green, 2)
    wait(0.7)
  end
end

-- Resolves one ship's confirmed menu action. Fleet calls this per queued
-- ship inside its round coroutine; solo wraps a single call in its own
-- coroutine from the top-level menu confirm.
local function doShipAction(i, id)
  local sh = sb.ships[i]
  if id == 'patch' then
    local res = waitTiming(timing.cfg(sb.foe.lv, false, meta.steadyMult()), pressLabel('PATCH', sh.owner), 'good', sh.owner)
    local heal = res == 'perfect' and 22 or (res == 'good' and 16 or 10)
    sh.hp = math.min(sh.max, sh.hp + heal)
    SFX.heal()
    local ex, ey = shipXY(i)
    engine.addFloat(ex + 16, ey - 18, '+' .. heal, CO.green, 2)
    wait(0.7)
  elseif id == 'fire' then
    local res = waitTiming(timing.cfg(sb.foe.lv, false, meta.steadyMult()), pressLabel('FIRE', fireOwner(i)), 'good', fireOwner(i))
    local dmg = sh.range == 'NEAR' and (9 + capLvlFor(i) + util.irand(0, 3)) or (6 + capLvlFor(i) + util.irand(0, 2))
    if res == 'perfect' then
      dmg = math.floor(dmg * 1.5)
      -- Hidden delight (for the 'cannonball' secret): three perfect FIRE
      -- shots in one battle earns a rainbow trail for the rest of it.
      sb.perfectFireCount = sb.perfectFireCount + 1
      if sb.perfectFireCount >= 3 and not sb.cannonballFx then
        sb.cannonballFx = true
        game.foundSecret('cannonball')
      end
    elseif res == 'miss' then dmg = math.max(1, math.floor(dmg * 0.6)) end
    fireBall(i, 'foe', dmg, {})
    waitAnim()
  elseif id == 'move' then
    sh.range = sh.range == 'NEAR' and 'FAR' or 'NEAR'
    local bigThreat = sb.isBoss and sb.foe.intent == 'bigshot' and sb.foe.target == i
    sh.dodge = bigThreat and 1 or 0.5
    SFX.move()
    local ex, ey = shipXY(i)
    engine.addFloat(ex + 16, ey - 18, bigThreat and 'DODGE THE BIG SHOT!' or 'DODGE READY!', CO.foam, 1)
    wait(0.5)
  elseif id == 'fix' then
    sh.repairs = sh.repairs - 1
    sh.hp = math.min(sh.max, sh.hp + 15)
    SFX.heal()
    local ex, ey = shipXY(i)
    engine.addParts(ex + 16, ey + 6, 12, CO.green, 30)
    engine.addFloat(ex + 16, ey - 18, '+15', CO.green, 2)
    wait(0.6)
  elseif id == 'spec' then
    if sb.fleet then
      resolveSpecialAction(i, sh.specPick)
    else
      sb.subOpen = true
      sb.sub = 0
      SFX.sel()
    end
  end
end

--------------------------------------------------------------------------
-- Solo (single-ship, classic alternating-turn menu)
--------------------------------------------------------------------------

local function menuItems()
  return shipMenuItems(1)
end

--------------------------------------------------------------------------
-- Fleet (TWO CAPTAINS): simultaneous pick, sequential resolve
--------------------------------------------------------------------------

-- Drains the confirm-ordered queue one ship at a time, then hands off to
-- the foe's turn. Any queued action can itself yield (timing bar via
-- doShipAction, animation via waitAnim) without needing its own callback.
local function runFleetRound()
  for _, i in ipairs(sb.queue) do
    doShipAction(i, sb.ships[i].chosen)
    sb.ships[i].chosen = nil
  end
  sb.queue = {}
  runFoeTurn()
end

-- BROADSIDE!: once per battle, both captains picking FIRE while both ships
-- are NEAR runs a single shared two-marker timing bar; landing >=good on
-- both is a bonus, never a requirement (a miss on either still fires the
-- plain shot).
local function runBroadside()
  local r1, r2 = waitTimingCoop(timing.cfg(sb.foe.lv, false, meta.steadyMult()),
    'BROADSIDE! PRESS ' .. input.promptKey(input.p1, 'a') .. ' / ' .. input.promptKey(input.p2, 'a') .. '!', 'good')
  local base1 = sb.ships[1].range == 'NEAR' and (9 + capLvlFor(1) + util.irand(0, 3)) or (6 + capLvlFor(1) + util.irand(0, 2))
  local base2 = sb.ships[2].range == 'NEAR' and (9 + capLvlFor(2) + util.irand(0, 3)) or (6 + capLvlFor(2) + util.irand(0, 2))
  local dmg = base1 + base2
  local rainbow = r1 ~= 'miss' and r2 ~= 'miss'
  if rainbow then dmg = dmg + 8 end
  fireBall(1, 'foe', dmg, {})
  waitAnim()
  if rainbow then engine.addFloat(VW / 2, 50, 'RAINBOW BROADSIDE!', CO.gold, 2) end
  runFoeTurn()
end

local function startResolution()
  sb.turn = 'resolve'
  sb.queue = {}
  if fleetRound.broadsideReady(sb.ships, sb.broadsideUsed) then
    sb.broadsideUsed = true
    sb.ships[1].chosen, sb.ships[2].chosen = nil, nil
    beginCo(runBroadside)
    return
  end
  sb.queue = fleetRound.resolveOrder(sb.ships)
  beginCo(runFleetRound)
end

local function updateSelect(dt)
  for i, sh in ipairs(sb.ships) do
    if not sh.chosen then
      local ctx = shipCtx(i)
      if sh.subOpen then
        local plist = specialPartyFor(i)
        if #plist == 0 then
          sh.subOpen = false
        else
          sh.sub = math.min(sh.sub, #plist - 1)
          if ctx.rp('up') then sh.sub = (sh.sub + #plist - 1) % #plist; SFX.move() end
          if ctx.rp('down') then sh.sub = (sh.sub + 1) % #plist; SFX.move() end
          if ctx.jp('b') then
            sh.subOpen = false
            SFX.back()
          elseif ctx.jp('a') then
            sh.subOpen = false
            sh.specPick = plist[sh.sub + 1]
            sh.chosen = 'spec'
            sb.confirmSeq = sb.confirmSeq + 1
            sh.confirmOrder = sb.confirmSeq
            SFX.sel()
          end
        end
      else
        local items = shipMenuItems(i)
        sh.menu = math.min(sh.menu, #items - 1)
        if ctx.rp('left') then sh.menu = (sh.menu + #items - 1) % #items; SFX.move() end
        if ctx.rp('right') then sh.menu = (sh.menu + 1) % #items; SFX.move() end
        if ctx.jp('a') then
          local it = items[sh.menu + 1]
          if not it.ok then
            SFX.bump()
          elseif it.id == 'spec' then
            sh.subOpen, sh.sub = true, 0
            SFX.sel()
          else
            SFX.sel()
            sh.chosen = it.id
            sb.confirmSeq = sb.confirmSeq + 1
            sh.confirmOrder = sb.confirmSeq
          end
        end
      end
    end
  end

  -- Solo-collapse: an idle second captain auto-fires each round rather
  -- than stalling the fleet — mirrors sail's convoy / boarding's p2Away.
  local ship2 = sb.ships[2]
  if ship2 and not ship2.chosen then
    coop.tickIdle(sb, dt, P2_AUTOFIRE_LATCHES)
    if sb.p2AutoFire then
      ship2.subOpen = false
      ship2.chosen = fleetRound.autoChoice(ship2)
      sb.confirmSeq = sb.confirmSeq + 1
      ship2.confirmOrder = sb.confirmSeq
    end
  end

  if fleetRound.allChosen(sb.ships) then startResolution() end
end

engine.states.shipBattle = {
  update = function(dt)
    for _, sh in ipairs(sb.ships) do
      sh.pt = util.lerp(sh.pt, sh.range == 'NEAR' and 1 or 0, util.clamp(dt * 5, 0, 1))
    end

    if sb.anim then
      sb.anim.t = sb.anim.t + dt
      if sb.anim.t >= sb.anim.dur then
        local cb = sb.anim.cb
        sb.anim = nil
        cb()
      end
    end

    if sb.wait > 0 then
      sb.wait = math.max(0, sb.wait - dt)
    end

    -- The timing bar's own sweep/press handling stays here (a per-frame
    -- input poll, same as menu navigation below); waitTiming() just yields
    -- until timing.on flips back off.
    if timing.on then
      if timing.coopMode then
        timing.updateCoop(dt, input.p1.jp('a'), input.p2.jp('a'))
      else
        local pressed
        if timing.player == 'p2' then pressed = input.p2.jp('a')
        elseif timing.player == 'p1' then pressed = input.p1.jp('a')
        else pressed = input.jp('a') end
        timing.update(dt, pressed)
      end
    end

    -- timing.on implies sb.co ~= nil (every timing.start/startCoop call in
    -- this file happens from inside a coroutine), so resuming here also
    -- covers "the bar just resolved this frame" without a separate check.
    if sb.co then
      local ok, err = coroutine.resume(sb.co)
      if not ok then error(err) end
      if coroutine.status(sb.co) == 'dead' then sb.co = nil end
      return
    end

    if sb.fleet then
      if sb.turn == 'select' then updateSelect(dt) end
      return
    end

    if sb.turn ~= 'you' then return end

    local ctx = input.p1
    local party = game.run.party
    if sb.subOpen then
      if ctx.rp('up') then sb.sub = (sb.sub + #party - 1) % #party; SFX.move() end
      if ctx.rp('down') then sb.sub = (sb.sub + 1) % #party; SFX.move() end
      if ctx.jp('b') then
        sb.subOpen = false
        SFX.back()
      elseif ctx.jp('a') then
        local p = party[sb.sub + 1]
        if not sb.specUsed[p.name] then
          SFX.sel()
          sb.subOpen = false
          beginCo(function()
            resolveSpecialAction(1, p)
            runFoeTurn()
          end)
        else SFX.bump() end
      end
      return
    end

    local items = menuItems()
    sb.menu = math.min(sb.menu, #items - 1)
    if ctx.rp('left') then sb.menu = (sb.menu + #items - 1) % #items; SFX.move() end
    if ctx.rp('right') then sb.menu = (sb.menu + 1) % #items; SFX.move() end
    local it = items[sb.menu + 1]
    if ctx.jp('a') then
      if it.ok then
        SFX.sel()
        if it.id == 'spec' then
          sb.subOpen, sb.sub = true, 0
        else
          beginCo(function()
            doShipAction(1, it.id)
            runFoeTurn()
          end)
        end
      else SFX.bump() end
    end
  end,

  draw = function()
    local gt = engine.gt

    -- Sky, clouds, sea.
    gfx.setColor(CO.sky); gfx.rectangle('fill', 0, 0, VW, 100)
    gfx.setColor(CO.skyD); gfx.rectangle('fill', 0, 84, VW, 16)
    gfx.setColor(CO.sun); gfx.rectangle('fill', 188, 12, 14, 14)
    gfx.setColor(CO.white)
    gfx.rectangle('fill', 40, 24, 26, 5); gfx.rectangle('fill', 50, 20, 14, 5)
    gfx.rectangle('fill', 210, 34, 22, 5)
    gfx.setColor(CO.sea); gfx.rectangle('fill', 0, 100, VW, 40)
    gfx.setColor(CO.seaL)
    for i = 0, VW - 1, 10 do
      gfx.rectangle('fill', i + math.floor(gt * 8) % 10, 104 + (i % 3) * 9, 6, 1)
    end

    local fpx, fpy = shipXY('foe')
    local bobF = util.round(math.sin(gt * 2.3 + 2) * 1.5)
    if sb.isBoss then
      sprites.draw('shipKing', fpx - 16, fpy + bobF - 16, true, 3)
    else
      sprites.draw('shipE', fpx, fpy + bobF, true, 2)
    end
    if sb.foe.dodge > 0 then font.drawTextO('*', fpx + 14, fpy - 4 + bobF, CO.foam, 2) end

    for i, sh in ipairs(sb.ships) do
      local ypx, ypy = shipXY(i)
      local bob = util.round(math.sin(gt * 2.3 + i) * 1.5)
      sprites.draw(sprites.shipSprite(game.colorOf(i == 1 and 'p1' or 'p2')), ypx, ypy + bob, false, 2)
      if sh.dodge > 0 then font.drawTextO('*', ypx + 14, ypy - 4 + bob, CO.foam, 2) end
      if sh.patched then font.drawTextO('~', ypx + 14, ypy - 4 + bob, CO.orange, 2) end
    end

    -- Foe telegraph: fleet mode draws it over the threatened ship (a
    -- readable "protect whose ship" answer); solo draws it over the foe,
    -- same as always.
    local pickPhase = (sb.fleet and sb.turn == 'select') or (not sb.fleet and sb.turn == 'you')
    if pickPhase and not sb.over and sb.foe.intent then
      local iconName = ({ fire = 'icon_fire', bigshot = 'icon_bigshot', volley = 'icon_volley', fix = 'icon_fix', move = 'icon_move' })[sb.foe.intent]
      local intentCol = ({ fire = CO.orange, bigshot = CO.red, volley = CO.orange, fix = CO.green, move = CO.white })[sb.foe.intent]
      local label = ({ fire = 'SHOT!', bigshot = 'BIG SHOT!', volley = 'DOUBLE SHOT!', fix = 'PATCHING!', move = 'MOVING!' })[sb.foe.intent]
      local tx, ty
      if sb.fleet and sb.foe.intent ~= 'fix' then
        tx, ty = shipXY(sb.foe.target)
      else
        tx, ty = fpx, fpy
      end
      if iconName then
        ui.drawIntentIcon(iconName, tx + 2, ty - 22 + (sb.fleet and 0 or bobF), 1, intentCol)
      end
      if label then
        -- Clamp the centered label so it never draws past the canvas edge
        -- (the scripted-run bounds invariant is absolute).
        local w = font.textWidth(label, 1)
        local lx = util.clamp(tx + 16, w / 2 + 2, VW - w / 2 - 2)
        font.drawTextO(label, lx, ty - 34, intentCol or CO.white, 1, 'center')
      end
    end

    -- Cannonball arc.
    if sb.anim and sb.anim.type == 'ball' then
      local a = sb.anim
      local t = util.clamp(a.t / a.dur, 0, 1)
      local bx = util.lerp(a.x0, a.x1, t)
      local by = util.lerp(a.y0, a.y1, t) - math.sin(math.pi * t) * 30
      gfx.setColor(CO.ink)
      gfx.rectangle('fill', util.round(bx) - 1, util.round(by) - 1, 4, 4)
    end
    engine.drawFx()

    -- HP bars.
    if sb.fleet then
      for i, sh in ipairs(sb.ships) do
        local by = i == 1 and 6 or 24
        local col = i == 1 and CO.gold or CO.green
        font.drawText((i == 1 and 'P1 SHIP' or 'P2 SHIP') .. (sh.patched and ' (PATCHING)' or ''), 6, by, col, 1)
        ui.drawBar(6, by + 7, 70, 6, sh.hp / sh.max)
        font.drawText(sh.hp .. '/' .. sh.max, 80, by + 7, CO.white, 1)
        -- Draw repair pips for fleet player ships:
        local activeW = string.rep('{', sh.repairs)
        local spentW = string.rep('{', sh.maxRepairs - sh.repairs)
        font.drawText(activeW, 6, by + 15, CO.orange, 1)
        font.drawText(spentW, 6 + sh.repairs * 4, by + 15, CO.grayD, 1)
      end
    else
      font.drawText('YOUR SHIP', 6, 6, CO.white, 1)
      ui.drawBar(6, 13, 90, 6, sb.ships[1].hp / sb.ships[1].max)
      font.drawText(sb.ships[1].hp .. '/' .. sb.ships[1].max, 100, 13, CO.white, 1)
      -- Draw repair pips for solo player ship:
      local activeW = string.rep('{', sb.ships[1].repairs)
      local spentW = string.rep('{', sb.ships[1].maxRepairs - sb.ships[1].repairs)
      font.drawText(activeW, 6, 21, CO.orange, 1)
      font.drawText(spentW, 6 + sb.ships[1].repairs * 4, 21, CO.grayD, 1)
    end
    font.drawText(sb.isBoss and sb.foe.name or ("CAP'N " .. sb.foe.name), VW - 6, 6, CO.white, 1, 'right')
    ui.drawBar(VW - 96, 13, 90, 6, sb.foe.hp / sb.foe.max)
    local hpText = sb.foe.hp .. '/' .. sb.foe.max
    local hpW = font.textWidth(hpText, 1)
    font.drawText(hpText, VW - 102, 13, CO.white, 1, 'right')
    font.drawText('LV ' .. sb.foe.lv, VW - 102 - hpW - 6, 13, CO.red, 1, 'right')

    -- Draw foe repair pips under the bar:
    local foeActiveW = string.rep('{', sb.foe.repairs)
    local foeSpentW = string.rep('{', sb.foe.maxRepairs - sb.foe.repairs)
    font.drawText(foeSpentW, VW - 6, 21, CO.grayD, 1, 'right')
    local spentWidth = (sb.foe.maxRepairs - sb.foe.repairs) * 4
    font.drawText(foeActiveW, VW - 6 - spentWidth, 21, CO.orange, 1, 'right')

    -- Draw boss powder-keg pips if boss:
    if sb.isBoss then
      local volleyActive = string.rep('}', sb.foe.volleyKegs)
      local volleySpent = string.rep('}', sb.foe.maxVolleyKegs - sb.foe.volleyKegs)
      local bigshotActive = string.rep('}', sb.foe.bigshotKegs)
      local bigshotSpent = string.rep('}', sb.foe.maxBigshotKegs - sb.foe.bigshotKegs)

      local rx = VW - 6 - sb.foe.maxRepairs * 4 - 6

      font.drawText(volleySpent, rx, 21, CO.grayD, 1, 'right')
      local spentVolleyW = (sb.foe.maxVolleyKegs - sb.foe.volleyKegs) * 4
      font.drawText(volleyActive, rx - spentVolleyW, 21, CO.orange, 1, 'right')

      local totalVolleyW = sb.foe.maxVolleyKegs * 4
      local bx = rx - totalVolleyW - 4

      font.drawText(bigshotSpent, bx, 21, CO.grayD, 1, 'right')
      local spentBigshotW = (sb.foe.maxBigshotKegs - sb.foe.bigshotKegs) * 4
      font.drawText(bigshotActive, bx - spentBigshotW, 21, CO.red, 1, 'right')
    end
    if not sb.fleet then
      font.drawTextO(sb.ships[1].range == 'NEAR' and 'CLOSE!' or 'FAR', VW / 2, 26, CO.paper, 1, 'center')
    end

    -- Message + menu panel.
    gfx.setColor(CO.uiBg)
    gfx.rectangle('fill', 0, 140, VW, 40)
    font.drawText(sb.msg, VW / 2, 144, CO.paper, 1, 'center')

    if sb.fleet then
      if sb.turn == 'select' and not sb.co then
        local halves = { { x = 4, w = VW / 2 - 6, col = CO.gold }, { x = VW / 2 + 2, w = VW / 2 - 6, col = CO.green } }
        for i, sh in ipairs(sb.ships) do
          local h = halves[i]
          font.drawText((i == 1 and 'P1: ' or 'P2: ') .. (sh.range == 'NEAR' and 'CLOSE!' or 'FAR'), h.x, 153, h.col, 1)
          if sh.chosen then
            font.drawText('WAITING...', h.x, 163, CO.gray, 1)
          elseif sh.subOpen then
            -- Only two rows fit above the canvas bottom; a window of two
            -- entries scrolls with the cursor instead of drawing past y=175.
            local plist = specialPartyFor(i)
            local first = math.max(0, math.min(sh.sub - 1, #plist - 2))
            for row = 0, 1 do
              local pi = first + row
              if pi <= #plist - 1 then
                local pp = plist[pi + 1]
                -- No spare row for a desc line here, so the special's name
                -- rides inline after the crew name instead.
                font.drawText((pi == sh.sub and '>' or ' ') .. pp.name .. ' - ' .. data.ROLES[pp.role].ship.name,
                  h.x, 163 + row * 8, pi == sh.sub and h.col or CO.white, 1)
              end
            end
          else
            -- 2x2 grid per captain: four items never fit as four 8px rows
            -- under y=163 on a 180px canvas (rows 3/4 would clip).
            local items = shipMenuItems(i)
            sh.menu = math.min(sh.menu, #items - 1)
            for ii = 0, #items - 1 do
              local it = items[ii + 1]
              local col = not it.ok and CO.grayD or (ii == sh.menu and h.col or CO.white)
              font.drawText((ii == sh.menu and '>' or ' ') .. it.label,
                h.x + (ii % 2) * 72, 163 + math.floor(ii / 2) * 8, col, 1)
            end
          end
        end
      end
    elseif sb.turn == 'you' and not sb.over and not sb.co then
      local items = menuItems()
      sb.menu = math.min(sb.menu, #items - 1)
      local iw = math.floor((VW - 8) / #items)
      for i = 0, #items - 1 do
        local bx2 = 4 + i * iw
        local sel = i == sb.menu
        gfx.setColor(sel and CO.uiBg2 or CO.ink)
        gfx.rectangle('fill', bx2, 153, iw - 4, 14)
        if sel then ui.outline(bx2, 153, iw - 4, 14, CO.gold) end
        local it = items[i + 1]
        local labelCol = not it.ok and CO.grayD or (sel and CO.gold or CO.white)
        font.drawText(it.label, bx2 + (iw - 4) / 2, 158, labelCol, 1, 'center')
      end
      font.drawText(items[sb.menu + 1].desc, VW / 2, 171, CO.gray, 1, 'center')

      if sb.subOpen then
        local party = game.run.party
        local n = #party
        local bw, bh = 170, n * 12 + 24
        local bx3, by3 = (VW - bw) / 2, 132 - bh
        gfx.setColor(CO.uiBg)
        gfx.rectangle('fill', bx3, by3, bw, bh)
        ui.outline(bx3, by3, bw, bh, CO.gold)
        font.drawText('CREW SPECIALS', bx3 + bw / 2, by3 + 4, CO.gold, 1, 'center')
        for i = 0, n - 1 do
          local pp = party[i + 1]
          local used = sb.specUsed[pp.name]
          local col = used and CO.grayD or (i == sb.sub and CO.gold or CO.white)
          font.drawText((i == sb.sub and '>' or ' ') .. pp.name .. ' - ' .. data.ROLES[pp.role].ship.name,
            bx3 + 6, by3 + 14 + i * 12, col, 1)
        end
        font.drawText(data.ROLES[party[sb.sub + 1].role].ship.desc, bx3 + 6, by3 + bh - 10, CO.gray, 1)
      end
    end
    timing.draw()
  end,
}

return M
