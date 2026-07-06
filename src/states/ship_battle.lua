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
local input = require 'src.input'
local audio = require 'src.audio'
local engine = require 'src.engine'
local game = require 'src.game'
local data = require 'src.data'
local meta = require 'src.meta'
local fleetRound = require 'src.fleet'
local coop = require 'src.coop'
local timing = require 'src.timing'
local personBattle = require 'src.states.person_battle'
local shipRules = require 'src.ship_rules'
local shipRewards = require 'src.ship_rewards'
local shipBattleDraw = require 'src.states.ship_battle_draw'
local CO = palette.CO
local SFX = audio.sfx

local VW = 320
local P2_AUTOFIRE_LATCHES = { { limit = 15, key = 'p2AutoFire' } }
local SUBMENU_SPECIAL = 'special'
local SUBMENU_SHOT = 'shot'

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
  -- Volcano dents (4.1): rock hits on the sail map lower the starting bar
  -- for the next battle only (capped at 9, so never close to a sink), then
  -- the dents are spent. FIX patches them like any other damage.
  local hurt = 0
  if game.run.sea then
    hurt = game.run.sea.shipHurt or 0
    game.run.sea.shipHurt = 0
  end

  local isFoggy = game.run.sea and game.run.sea.biome == 'foggy'
  local startSailsStage = isFoggy and 1 or 0

  -- FIGUREHEAD raises max ship HP; BETTER SAILS grants one free auto-dodge
  -- per battle (reuses the existing dodge-chance field, guaranteed at 1 —
  -- the first incoming hit rolls against it and is consumed like any dodge).
  local ships = {
    shipRules.buildPlayerShip(game.run, 1, {
      hurt = hurt,
      dodge = meta.hasFreeDodge() and 1 or 0,
      sailsStage = startSailsStage,
      owner = 'p1',
    }),
  }
  if fleet then
    ships[2] = shipRules.buildPlayerShip(game.run, 2, { sailsStage = startSailsStage, owner = 'p2' })
  end
  sb = {
    foeRef = foe,
    isBoss = isBoss,
    fleet = fleet,
    foe = shipRules.buildFoeState(foe, lv, fleet, startSailsStage),
    ships = ships,
    turn = fleet and 'select' or 'you',
    menu = 0, submenu = nil, sub = 0,
    specUsed = {}, anim = nil, wait = 0, co = nil,
    over = false, msg = fleet and 'BOTH CAPTAINS, CHOOSE!' or 'YOUR TURN! CHOOSE!',
    broadsideUsed = false,
    confirmSeq = 0, queue = {}, idleT = 0,
    perfectFireCount = 0, cannonballFx = false,
    announcedPhase = 1,
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
  if who == 'foe' then
    if opts.isWeak then
      engine.addFloat(ex + 16, ey - 14, 'IT TEARS THROUGH!', CO.gold, 1.2)
    elseif opts.isResisted then
      engine.addFloat(ex + 16, ey - 14, 'IT GLANCES OFF...', CO.gray, 1.2)
    end

    if opts.res and opts.shotId then
      local effect = shipRules.applyShotEffect(tgt, opts.shotId, opts.res)
      if effect == 'sails_down' then
        if tgt.intent == 'move' then tgt.intent = nil end
        sb.msg = "HER SAILS HANG IN RIBBONS!"
        engine.addFloat(ex + 16, ey - 24, 'SAILS DOWN!', CO.orange, 1.5)
      elseif effect == 'guns_down' then
        sb.msg = "YOU SWEPT HER DECK!"
        engine.addFloat(ex + 16, ey - 24, 'GUNS DOWN!', CO.orange, 1.5)
      elseif effect == 'immune_ablaze' then
        sb.msg = "THE FIRE IS IMMEDIATELY EXTINGUISHED!"
        engine.addFloat(ex + 16, ey - 24, 'IMMUNE!', CO.gray, 1.5)
      elseif effect == 'ablaze' then
        sb.msg = "SHE IS ABLAZE!"
        engine.addFloat(ex + 16, ey - 24, 'ABLAZE!', CO.orange, 1.5)
      end
    end
  else
    -- Player ship took hit:
    if opts.isFireShot then
      tgt.ablaze = 3
      engine.addFloat(ex + 16, ey - 24, 'ABLAZE!', CO.orange, 1.5)
    end
  end

  if tgt.hp <= 0 then
    if who == 'foe' then
      sb.over = true
      SFX.bigwin()
      sb.msg = 'SHIP DISABLED!'
      local isBoss = sb.isBoss
      local foeRef = sb.foeRef
      foeRef.gunsStage = sb.foe.gunsStage
      foeRef.sailsStage = sb.foe.sailsStage
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

local function safeEscape(defaultMsg)
  local gotFlotsam = shipRewards.awardFlotsam(game.run, sb.foeRef, sb.isBoss)
  if sb.isBoss then
    sb.msg = "HER HULL SHRUGGED OFF OUR SHOTS - WE NEED HEAVIER GUNS OR HOTTER SHOT."
    engine.showBanner("SLIPPED AWAY!", CO.orange, 1.3)
    if gotFlotsam then
      local px, py = shipXY(1)
      engine.addFloat(px + 16, py - 18, '+1 TIMBER', CO.gold, 1.5)
    end
  elseif gotFlotsam then
    sb.msg = "FISHED WRECKAGE FROM YOUR WAKE! (+1 TIMBER)"
    engine.showBanner("SLIPPED AWAY!", CO.orange, 1.3)
  else
    sb.msg = defaultMsg
  end

  beginCo(function()
    wait(1.3)
    engine.transition('SAFE AND SOUND!', function() engine.setState('sail') end)
  end)
end

-- No sinking, ever: a downed fleet ship falls back to patch up instead of
-- losing outright; losing is only the normal safe loss, and only if both
-- ships are patching at the same time. Solo has one ship, so a downed ship
-- there is still the classic safe loss.
shipDown = function(i)
  if not sb.fleet then
    sb.over = true
    SFX.lose()
    safeEscape('YOUR SHIP SLIPS AWAY...')
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
    safeEscape('BOTH SHIPS SLIP AWAY...')
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

  if sb.isBoss and f.class ~= 'kraken' and not (f.ablaze and f.ablaze > 0) then
    local phase = shipRules.foePhase(f)
    if phase > (sb.announcedPhase or 1) then
      sb.announcedPhase = phase
      if phase == 2 then
        sb.msg = "SHE RUNS OUT HER LOWER GUNS!"
        engine.showBanner("SHE RUNS OUT HER LOWER GUNS!", CO.red, 1.5)
      elseif phase == 3 then
        sb.msg = "THE KING BELLOWS - RAMMING SPEED!"
        engine.showBanner("THE KING BELLOWS - RAMMING SPEED!", CO.red, 1.5)
      end
    end
  end
  f.intent = shipRules.chooseFoeIntent(f, {
    isBoss = sb.isBoss,
    tier = meta.data.tier or 0,
    chance = util.chance,
  })
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
  for i, sh in ipairs(sb.ships) do
    sh.movedThisTurn = false
  end

  local isIcy = game.run.sea and game.run.sea.biome == 'icy'
  if sb.fleet and not isIcy then
    local anyAblaze = false
    for _, sh in ipairs(sb.ships) do
      if sh.ablaze and sh.ablaze > 0 then anyAblaze = true end
    end
    if anyAblaze then
      if sb.ships[1].range == 'NEAR' and sb.ships[2].range == 'NEAR' then
        for _, sh in ipairs(sb.ships) do
          if not sh.ablaze or sh.ablaze == 0 then
            sh.ablaze = 3
            local px, py = shipXY(sh.owner == 'p1' and 1 or 2)
            engine.addFloat(px + 16, py - 18, 'FIRE SPREADS!', CO.orange, 1.5)
          end
        end
      end
    end
  end

  -- Player Ablaze Tick:
  for i, sh in ipairs(sb.ships) do
    if sh.ablaze and sh.ablaze > 0 then
      sh.hp = math.max(0, sh.hp - 4)
      local px, py = shipXY(i)
      engine.addFloat(px + 16, py - 18, '-4 FIRE!', CO.orange, 1.5)
      SFX.hit()
      sh.ablaze = sh.ablaze - 1
      if sh.hp <= 0 then
        shipDown(i)
        if sb.over then return end
      end
      wait(0.6)
    end
  end

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
  elseif intent == 'douse' then
    f.ablaze = nil
    local ex, ey = shipXY('foe')
    engine.addFloat(ex + 16, ey - 22, 'DOUSED!', CO.foam, 1)
    sb.msg = "SHE DOUSE THE FLAMES!"
    SFX.move()
    wait(0.7)
  elseif intent == 'move' then
    local sh = sb.ships[target]
    sh.range = sh.range == 'NEAR' and 'FAR' or 'NEAR'
    f.dodge = shipRules.getDodgeChance(f.sails, f.sailsStage, false)
    local ex, ey = shipXY('foe')
    engine.addFloat(ex + 16, ey - 22, 'REPOSITION!', CO.foam, 1)
    SFX.move()
    wait(0.7)
  elseif intent == 'bigshot' then
    f.bigshotKegs = math.max(0, f.bigshotKegs - 1)
    local sh = sb.ships[target]
    local dmg = shipRules.foeAttackDamage(f, intent, sh.range, sb.isBoss, lv, 0)
    fireBall('foe', target, dmg, {})
    waitAnim()
    wait(0.6)
  elseif intent == 'volley' then
    f.volleyKegs = math.max(0, f.volleyKegs - 1)
    local sh = sb.ships[target]
    local dmg = shipRules.foeAttackDamage(f, intent, sh.range, sb.isBoss, lv, 0)
    fireBall('foe', target, dmg, {})
    waitAnim()
    wait(0.3)
    fireBall('foe', target, dmg, {})
    waitAnim()
    wait(0.6)
  elseif intent == 'ram' then
    local sh = sb.ships[target]
    local dodged = sh.movedThisTurn == true
    if dodged then
      f.hp = math.max(0, f.hp - data.KING.ramRecoil)
      sb.msg = "YOU DODGED! THE GALLEON SCRAPES PAST AND TAKES " .. data.KING.ramRecoil .. " RECOIL!"
      SFX.bump()
      local ex, ey = shipXY('foe')
      engine.addFloat(ex + 16, ey - 22, 'RAM DODGED! -' .. data.KING.ramRecoil .. ' HULL', CO.green, 2)
      if f.hp <= 0 then
        sb.over = true
        SFX.bigwin()
        sb.msg = 'SHIP DISABLED!'
        local foeRef = sb.foeRef
        foeRef.gunsStage = f.gunsStage
        foeRef.sailsStage = f.sailsStage
        beginCo(function()
          wait(1.3)
          engine.transition('BOARD THE SHIP!', function()
            personBattle.startBoss(foeRef)
          end)
        end)
        return
      end
      wait(1.0)
    else
      sh.hp = math.max(0, sh.hp - data.KING.ramDmg)
      sb.msg = "THE GALLEON RAMS YOUR SHIP FOR " .. data.KING.ramDmg .. " DAMAGE!"
      SFX.explode()
      local px, py = shipXY(target)
      engine.addFloat(px + 16, py - 18, '-' .. data.KING.ramDmg .. ' HULL', CO.red, 2)
      if sh.hp <= 0 then
        shipDown(target)
        if sb.over then return end
      end
      wait(1.0)
    end
  else
    local sh = sb.ships[target]
    local dmg = shipRules.foeAttackDamage(f, intent or 'fire', sh.range, sb.isBoss, lv, util.irand(0, 2))
    fireBall('foe', target, dmg, { isFireShot = (f.class == 'fireship') })
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

  if sb.foe.ablaze and sb.foe.ablaze > 0 then
    sb.foe.hp = math.max(0, sb.foe.hp - 4)
    local ex, ey = shipXY('foe')
    engine.addFloat(ex + 16, ey - 18, '-4 FIRE!', CO.orange, 1.5)
    SFX.hit()
    if sb.foe.hp <= 0 then
      sb.over = true
      SFX.bigwin()
      sb.msg = 'SHIP DISABLED!'
      local isBoss = sb.isBoss
      local foeRef = sb.foeRef
      foeRef.gunsStage = sb.foe.gunsStage
      foeRef.sailsStage = sb.foe.sailsStage
      beginCo(function()
        wait(1.3)
        engine.transition('BOARD THE SHIP!', function()
          if isBoss then personBattle.startBoss(foeRef) else personBattle.start(foeRef) end
        end)
      end)
      return
    end
    sb.foe.ablaze = sb.foe.ablaze - 1
    wait(0.8)
  end

  runFoeAct()
end

--------------------------------------------------------------------------
-- Command resolver: one resolver parameterized by ship index, shared by
-- solo and fleet; 'spec' still forks because solo defers to a top-level
-- submenu while fleet already resolved the pal via updateSelect's per-ship
-- submenu.
--------------------------------------------------------------------------


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
  local minDmg, maxDmg = shipRules.getShotPreview(sh, sb.foe, 'round')
  return {
    { id = 'fire', label = 'FIRE!', ok = true,
      desc = (sh.range == 'NEAR' and 'NEAR: ' or 'FAR: ') .. 'ROUND ' .. minDmg .. '-' .. maxDmg },
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
  sb.submenu = nil
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
  elseif id == 'fire' or id:sub(1, 5) == 'fire_' then
    local shotId = (id == 'fire') and 'round' or id:sub(6)
    if shotId ~= 'round' then
      sh.powder[shotId] = math.max(0, sh.powder[shotId] - 1)
    end
    local res = waitTiming(timing.cfg(sb.foe.lv, false, meta.steadyMult()), pressLabel('FIRE', fireOwner(i)), 'good', fireOwner(i))
    if res == 'perfect' then
      sb.perfectFireCount = sb.perfectFireCount + 1
      if sb.perfectFireCount >= 3 and not sb.cannonballFx then
        sb.cannonballFx = true
        game.foundSecret('cannonball')
      end
    end
    local outcome = shipRules.resolveShotDamage(sh, sb.foe, shotId, res, util.irand(0, 2))
    fireBall(i, 'foe', outcome.damage, {
      isWeak = outcome.isWeak,
      isResisted = outcome.isResisted,
      shotId = shotId,
      res = res
    })
    waitAnim()
  elseif id == 'move' then
    sh.movedThisTurn = true
    sh.range = sh.range == 'NEAR' and 'FAR' or 'NEAR'
    local bigThreat = sb.isBoss and (sb.foe.intent == 'bigshot' or sb.foe.intent == 'ram') and sb.foe.target == i
    sh.dodge = shipRules.getDodgeChance(sh.sails, sh.sailsStage, bigThreat)
    SFX.move()
    local ex, ey = shipXY(i)
    engine.addFloat(ex + 16, ey - 18, bigThreat and (sb.foe.intent == 'ram' and 'DODGE RAM!' or 'DODGE THE BIG SHOT!') or 'DODGE READY!', CO.foam, 1)
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
      sb.submenu = SUBMENU_SPECIAL
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
  local outcome = shipRules.resolveBroadsideDamage(
    sb.ships[1], sb.ships[2], sb.foe, r1, r2, util.irand(0, 2), util.irand(0, 2))
  fireBall(1, 'foe', outcome.damage, { isWeak = outcome.isWeak, isResisted = outcome.isResisted })
  waitAnim()
  if outcome.rainbow then engine.addFloat(VW / 2, 50, 'RAINBOW BROADSIDE!', CO.gold, 2) end
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
      if sh.submenu == SUBMENU_SPECIAL then
        local plist = specialPartyFor(i)
        if #plist == 0 then
          sh.submenu = nil
        else
          sh.sub = math.min(sh.sub, #plist - 1)
          if ctx.rp('up') then sh.sub = (sh.sub + #plist - 1) % #plist; SFX.move() end
          if ctx.rp('down') then sh.sub = (sh.sub + 1) % #plist; SFX.move() end
          if ctx.jp('b') then
            sh.submenu = nil
            SFX.back()
          elseif ctx.jp('a') then
            sh.submenu = nil
            sh.specPick = plist[sh.sub + 1]
            sh.chosen = 'spec'
            sb.confirmSeq = sb.confirmSeq + 1
            sh.confirmOrder = sb.confirmSeq
            SFX.sel()
          end
        end
      elseif sh.submenu == SUBMENU_SHOT then
        local shots = shipRules.getKnownShots()
        sh.sub = math.min(sh.sub, #shots - 1)
        if ctx.rp('up') then sh.sub = (sh.sub + #shots - 1) % #shots; SFX.move() end
        if ctx.rp('down') then sh.sub = (sh.sub + 1) % #shots; SFX.move() end
        if ctx.jp('b') then
          sh.submenu = nil
          SFX.back()
        elseif ctx.jp('a') then
          local shotId = shots[sh.sub + 1]
          local ppPowder = sh.powder[shotId]
          if ppPowder > 0 then
            sh.submenu = nil
            sh.chosen = 'fire_' .. shotId
            sb.confirmSeq = sb.confirmSeq + 1
            sh.confirmOrder = sb.confirmSeq
            SFX.sel()
          else
            SFX.bump()
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
            sh.submenu, sh.sub = SUBMENU_SPECIAL, 0
            SFX.sel()
          elseif it.id == 'fire' then
            sh.submenu, sh.sub = SUBMENU_SHOT, 0
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
      ship2.submenu = nil
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
    if sb.submenu == SUBMENU_SPECIAL then
      if ctx.rp('up') then sb.sub = (sb.sub + #party - 1) % #party; SFX.move() end
      if ctx.rp('down') then sb.sub = (sb.sub + 1) % #party; SFX.move() end
      if ctx.jp('b') then
        sb.submenu = nil
        SFX.back()
      elseif ctx.jp('a') then
        local p = party[sb.sub + 1]
        if not sb.specUsed[p.name] then
          SFX.sel()
          sb.submenu = nil
          beginCo(function()
            resolveSpecialAction(1, p)
            runFoeTurn()
          end)
        else SFX.bump() end
      end
      return
    elseif sb.submenu == SUBMENU_SHOT then
      local shots = shipRules.getKnownShots()
      if ctx.rp('up') then sb.sub = (sb.sub + #shots - 1) % #shots; SFX.move() end
      if ctx.rp('down') then sb.sub = (sb.sub + 1) % #shots; SFX.move() end
      if ctx.jp('b') then
        sb.submenu = nil
        SFX.back()
      elseif ctx.jp('a') then
        local shotId = shots[sb.sub + 1]
        local ppPowder = sb.ships[1].powder[shotId]
        if ppPowder > 0 then
          SFX.sel()
          sb.submenu = nil
          beginCo(function()
            doShipAction(1, 'fire_' .. shotId)
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
          sb.submenu, sb.sub = SUBMENU_SPECIAL, 0
        elseif it.id == 'fire' then
          sb.submenu, sb.sub = SUBMENU_SHOT, 0
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
    shipBattleDraw.draw(sb, {
      shipXY = shipXY,
      shipMenuItems = shipMenuItems,
      specialPartyFor = specialPartyFor,
    })
  end,
}

return M
