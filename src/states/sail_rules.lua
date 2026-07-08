-- Sail gameplay rules: tile triggers (chest/port/bottle/trader/X/exit),
-- biome movement rules (volcano rocks, fog visibility, icy slide/dwell),
-- movement resolution (bump/battle/move, autopilot route-following), and
-- TWO CAPTAINS co-op movement helpers (convoy auto-follow, anchor/whistle
-- rendezvous). Shared game/tile logic lives here so sail.lua stays
-- update/draw orchestration.
local util = require 'src.util'
local grid = require 'src.grid'
local palette = require 'src.palette'
local input = require 'src.input'
local audio = require 'src.audio'
local engine = require 'src.engine'
local game = require 'src.game'
local data = require 'src.data'
local coop = require 'src.coop'
local shipBattle = require 'src.states.ship_battle'
local loot = require 'src.states.loot'
local chart = require 'src.states.chart'
local sailMap = require 'src.states.sail_map'
local CO = palette.CO
local SFX = audio.sfx

local M = {}

local hexCenter, inSea = sailMap.hexCenter, sailMap.inSea

-- TWO CAPTAINS: whichever ship touched the foe pulls the other one in too —
-- one battle at a time, no split-screen, no waiting player. The sibling
-- teleports adjacent to the acting ship (falling back to sharing its hex)
-- under the same iris wipe, with its own "SAIL TOGETHER!" beat.
function M.startEncounter(foe, shipKey)
  local run = game.run
  run.enc = { foe = foe }
  -- Hidden delight (for the 'luckycoin' secret): any battle breaks an
  -- in-progress unbroken chest streak for this sea.
  if run.sea then run.sea.chestBroken = true end
  SFX.bump()
  if run.mode == 'captains' then
    local acting = shipKey == 'ship2' and run.ship2 or run.ship
    local other = shipKey == 'ship2' and run.ship or run.ship2
    other.route = nil
    local ox, oy = acting.x, acting.y
    for _, nb in ipairs(grid.hexNeighbors(acting.x, acting.y)) do
      local nx, ny = nb[1], nb[2]
      if inSea(nx, ny) and game.tileAt(nx, ny) == game.T_WATER then
        ox, oy = nx, ny
        break
      end
    end
    other.x, other.y, other.fx, other.fy, other.anim = ox, oy, ox, oy, nil
    engine.transition('SAIL TOGETHER!', function()
      shipBattle.start(foe)
    end)
    return
  end
  engine.transition("CAP'N " .. foe.name .. '!', function()
    shipBattle.start(foe)
  end)
end

-- Hidden delight (for the 'kingsniff' secret): the King has opinions about a
-- fully-matching bandana crew on his own sea. Purely a bark, no rule change.
function M.checkKingSniff()
  local run = game.run
  if not (run.sea and run.sea.boss) then return end
  if #run.party < 3 then return end
  local first = run.party[1].out
  if first ~= 'bandR' and first ~= 'bandB' then return end
  for _, p in ipairs(run.party) do
    if p.out ~= first then return end
  end
  game.foundSecret('kingsniff')
end

-- Hidden delight (for the 'seashell' secret): the only dig-anywhere verb --
-- P1 presses A next to any island hex for a small chance at a cosmetic find.
-- A miss just keeps him digging, no penalty, no rule ever touched.
function M.tryDig()
  local run = game.run
  local sh = run.ship
  local cx, cy = hexCenter(sh.x, sh.y)
  local nearIsland = false
  for _, nb in ipairs(grid.hexNeighbors(sh.x, sh.y)) do
    if inSea(nb[1], nb[2]) and game.tileAt(nb[1], nb[2]) == game.T_ISLE then
      nearIsland = true
      break
    end
  end
  if not nearIsland then
    SFX.bump()
    return
  end
  game.deedTick('digs', 20, 'digdog')
  if util.chance(0.1) then
    game.foundSecret('seashell')
    engine.addParts(cx, cy, 10, CO.foam, 40)
  else
    engine.addFloat(cx, cy - 12, 'NOTHING... YET!', CO.gray, 1)
    SFX.bump()
  end
end

local function openChest(x, y)
  game.setTile(x, y, game.T_WATER)
  SFX.coin()
  game.deedTick('chestsOpened', 30, 'chestchaser')
  local run = game.run
  local sea = run.sea
  local lv = sea.lv
  local goldN = 6 + 4 * lv + util.irand(0, 3)
  run.gold = run.gold + goldN
  local partsList = { { type = 'gold', n = goldN } }
  if util.chance(0.8) then
    local tr = game.rollTreasure(lv)
    local treasurePart, unlocks = game.awardTreasure(tr)
    partsList[#partsList + 1] = treasurePart
    for _, u in ipairs(unlocks) do partsList[#partsList + 1] = u end
  end
  -- Hidden delight (for the 'luckycoin' secret): clearing every chest this
  -- sea holds with no battle in between sprays extra confetti and a trivial
  -- bonus coin on the last one -- never a rule, just a nice streak to spot.
  sea.chestOpened = (sea.chestOpened or 0) + 1
  if not sea.chestBroken and sea.chestTotal and sea.chestTotal > 0 and sea.chestOpened >= sea.chestTotal then
    game.foundSecret('luckycoin')
    run.gold = run.gold + 1
    partsList[#partsList + 1] = { type = 'gold', n = 1 }
    local cx, cy = hexCenter(x, y)
    engine.addParts(cx, cy, 16, util.pick({ CO.gold, CO.red, CO.foam, CO.green, CO.purple }), 55)
  end
  loot.start(partsList, 'A CHEST!')
end

-- Shared by foundBottle and the port arrival: on the final sea, the first
-- visit hands over the gossip (and the 'fire' blueprint, once).
local function tryGossip(run, nextState)
  local last = (run.voyage and run.voyage.length or 8) - 1
  if run.sea.lv ~= last or run.gossipShown then return false end
  run.gossipShown = true
  local parts = { { type = 'gossip' } }
  if not run.blueprints['fire'] then
    parts[#parts + 1] = { type = 'blueprint_single', id = 'fire' }
    run.blueprints['fire'] = true
  end
  loot.start(parts, 'GOSSIP!', nextState)
  return true
end

-- Sea events. A bottle marks an X on a later sea; the X digs up a
-- guaranteed tier-2 treasure; the trader offers one fair 2-way swap (or a
-- plain gift when the player can afford neither side).
local function foundBottle(x, y)
  game.setTile(x, y, game.T_WATER)
  local run = game.run
  if tryGossip(run, 'sail') then return end
  local last = (run.voyage and run.voyage.length or 8) - 1
  local target = math.min(last, run.sea.lv + util.irand(1, 2))
  run.quest = { sea = target }
  SFX.fanfare()
  loot.start({ { type = 'bottle', sea = target } }, 'A BOTTLE!')
end

local function digQuest(x, y)
  game.setTile(x, y, game.T_WATER)
  game.earnDeed('xmarks')
  local run = game.run
  run.quest = nil
  local pool = {}
  for _, t in ipairs(data.TREASURES) do
    if t.tier == 2 then pool[#pool + 1] = t end
  end
  local tr = util.pick(pool)
  SFX.bigwin()
  local treasurePart, unlocks = game.awardTreasure(tr)
  local parts = { treasurePart }
  for _, u in ipairs(unlocks) do parts[#parts + 1] = u end
  game.logMoment('tr_' .. tr.id, 'SEA ' .. run.sea.lv .. ': DUG UP THE ' .. tr.name .. '!', {})
  loot.start(parts, 'X MARKS THE SPOT!')
end

local function meetTrader(x, y)
  game.setTile(x, y, game.T_WATER)
  local run = game.run
  local sellId = nil
  -- Only spare (count >= 2) treasures are tradeable, so the log never loses
  -- a collected kind.
  for _, t in ipairs(data.TREASURES) do
    if (run.treas[t.id] or 0) >= 2 then sellId = t.id; break end
  end
  local buyOk = run.gold >= 15
  SFX.sel()
  if not buyOk and not sellId then
    run.gold = run.gold + 10
    -- Hidden delight (for the 'kindtrader' secret): the free-gift path only
    -- exists when the player is broke and has nothing spare to trade.
    game.foundSecret('kindtrader')
    loot.start({ { type = 'gold', n = 10 } }, 'A KIND TRADER!')
    return
  end
  loot.start({ {
    type = 'trade', choice = buyOk and 1 or 2,
    options = {
      { id = 'buy', name = 'GET A SHINY', desc = 'PAY 15 GOLD', ok = buyOk },
      { id = 'sell', name = 'SWAP A SPARE', desc = 'GET 25 GOLD', ok = sellId ~= nil, tid = sellId },
    },
  } }, 'A FRIENDLY TRADER!')
end

-- Oliver's island (Grandma questline): the parrot begs for help and the
-- quest flag goes up before the card shows, so the beat is one-time even if
-- the game dies mid-card. The box itself is seeded by genSea from sea 5 on.
local function meetOliver(x, y)
  game.setTile(x, y, game.T_WATER)
  local run = game.run
  run.grandmaQuest = true
  SFX.fanfare()
  game.logMoment('oliver', 'SEA ' .. run.sea.lv .. ': OLIVER ASKED FOR HELP!', {})
  loot.start({ { type = 'oliver' } }, 'A LONELY PARROT!')
end

-- Hidden delight (for the 'hotfoot' secret): crossed a volcano sea with
-- rocks landing (guaranteed on any normal crossing) but never a hit. Exposed
-- (rather than folded into the local nextSea below) so it's testable without
-- driving the chart/engine sea-advance machinery.
function M.checkHotfoot(sea)
  if sea.biome == 'volcano' and (sea.rocksLanded or 0) >= 5 and (sea.rockBonks or 0) == 0 then
    game.foundSecret('hotfoot')
  end
end

local function nextSea()
  M.checkHotfoot(game.run.sea)
  game.run.hints.sea2 = true
  chart.startAdvance()
end

-- Volcano twist: rocks telegraph on a hex near the ship (pulsing
-- outline), then land ~2s later. A hit dents the ship — the next ship
-- battle starts with a lower bar (capped well above sinking) — and misses
-- just splash. Rock state lives in run.sea so it serializes.
function M.updateRocks(dt)
  local run = game.run
  local sea = run.sea
  if sea.biome ~= 'volcano' then return end
  local sh = run.ship
  sea.rockT = sea.rockT - dt
  if sea.rockT <= 0 then
    sea.rockT = 2.6 + love.math.random() * 2
    for _ = 1, 12 do
      local SEA_W, SEA_H = game.SEA_W, game.SEA_H
      local rx = util.clamp(sh.x + util.irand(-2, 2), 0, SEA_W - 1)
      local ry = util.clamp(sh.y + util.irand(-2, 2), 0, SEA_H - 1)
      if game.tileAt(rx, ry) == game.T_WATER and grid.hexDistance(rx, ry, sh.x, sh.y) <= 2 then
        sea.rocks[#sea.rocks + 1] = { x = rx, y = ry, t = 2.2 }
        break
      end
    end
  end
  for i = #sea.rocks, 1, -1 do
    local rk = sea.rocks[i]
    rk.t = rk.t - dt
    if rk.t <= 0 then
      table.remove(sea.rocks, i)
      local cx, cy = hexCenter(rk.x, rk.y)
      engine.shakeIt(2, 0.2)
      engine.addParts(cx, cy, 12, CO.orange, 50)
      sea.rocksLanded = (sea.rocksLanded or 0) + 1
      if sh.x == rk.x and sh.y == rk.y then
        sea.shipHurt = math.min(9, sea.shipHurt + 3)
        sea.rockBonks = (sea.rockBonks or 0) + 1
        SFX.hit()
        engine.addFloat(cx, cy - 12, 'BONK! SHIP -3', CO.red, 2)
      else
        SFX.splash()
      end
    end
  end
end

-- Foggy twist: enemies beyond 3 hexes hide behind a "?" splash.
-- Countered by the SPYGLASS treasure (first treasure with a job!), which
-- reveals everything.
function M.enemyVisible(e)
  local run = game.run
  if run.sea.biome ~= 'foggy' then return true end
  if (run.treas.spy or 0) > 0 then return true end
  local sh = run.ship
  if grid.hexDistance(e.x, e.y, sh.x, sh.y) <= 3 then return true end
  return false
end

-- Hidden delight (for the 'echobark' secret): both players hitting their own
-- B ("bark") within 0.3s of each other, purely cosmetic -- no other job for
-- P1's B at sail, and P2's B (squawk) still fires independently alongside it.
local echoP1T, echoP2T = nil, nil
local ECHO_WINDOW = 0.3

function M.checkEchoBark(sh)
  local run = game.run
  if not game.isCoop() then return end
  local gt = engine.gt
  if input.p1.jp('b') then echoP1T = gt end
  if input.p2.jp('b') then echoP2T = gt end
  if echoP1T and echoP2T and math.abs(echoP1T - echoP2T) <= ECHO_WINDOW then
    echoP1T, echoP2T = nil, nil
    game.foundSecret('echobark')
    local cx, cy = hexCenter(sh.x, sh.y)
    engine.addFloat(cx, cy - 14, 'ARRR!', CO.gold, 1)
    if run.mode == 'captains' and run.ship2 then
      local cx2, cy2 = hexCenter(run.ship2.x, run.ship2.y)
      engine.addFloat(cx2, cy2 - 14, 'ARRR!', CO.gold, 1)
    end
    audio.motif('captain')
  end
end

-- Hidden delight (for the 'bootsong' secret): nobody touches either pad for
-- a full minute at sail and the crew hums to fill the quiet.
local BOOTSONG_IDLE = 60
local bootIdleT = 0

local function anyoneActive(run)
  local p1 = input.p1
  local active = p1.held.up or p1.held.down or p1.held.left or p1.held.right
    or p1.pressed.a or p1.pressed.b or input.tap ~= nil
  if run.mode == 'captains' then
    local p2 = input.p2
    active = active or p2.held.up or p2.held.down or p2.held.left or p2.held.right
      or p2.pressed.a or p2.pressed.b
  end
  return active
end

function M.updateBootsong(dt, run, sh)
  local busy = anyoneActive(run) or sh.anim ~= nil or sh.route ~= nil
    or (run.mode == 'captains' and (run.ship2.anim ~= nil or run.ship2.route ~= nil))
  if busy then
    bootIdleT = 0
    return
  end
  bootIdleT = bootIdleT + dt
  if bootIdleT >= BOOTSONG_IDLE then
    bootIdleT = 0
    game.foundSecret('bootsong')
    local cx, cy = hexCenter(sh.x, sh.y)
    engine.addFloat(cx, cy - 14, 'HMMM HMM HMMMM...', CO.foam, 1)
    audio.motif('deckhand')
  end
end

-- Hidden delight (for the 'fishfriend' secret): holding the same icy hex for
-- a few seconds straight earns a little fish visitor for the rest of the sea.
function M.updateFishFriend(dt, run, sh)
  local sea = run.sea
  if sea.biome ~= 'icy' or sh.anim or sh.route then
    sea.dwellT = 0
    return
  end
  if sea.dwellX == sh.x and sea.dwellY == sh.y then
    sea.dwellT = (sea.dwellT or 0) + dt
    if sea.dwellT >= 3 and not sea.fishFound then
      sea.fishFound = true
      game.foundSecret('fishfriend')
      local cx, cy = hexCenter(sh.x, sh.y)
      engine.addParts(cx, cy, 8, CO.foam, 30)
      engine.addFloat(cx, cy - 12, 'BLUB!', CO.foam, 1)
    end
  else
    sea.dwellX, sea.dwellY, sea.dwellT = sh.x, sh.y, 0
  end
end

-- Try to enter (tx, ty): bump on islands/edges, battle on enemies,
-- otherwise start the hop. Returns 'bump', 'battle', or 'move'.
local function tryMove(sh, tx, ty, shipKey)
  if not inSea(tx, ty) or game.tileAt(tx, ty) == game.T_ISLE then
    SFX.bump()
    engine.shakeIt(1, 0.1)
    -- Hidden delight (for the 'sorryisland' secret): 5 bumps in a row from
    -- the same hex (any successful move resets the streak below).
    sh.bumpStreak = (sh.bumpStreak or 0) + 1
    if sh.bumpStreak >= 5 then
      sh.bumpStreak = 0
      game.foundSecret('sorryisland')
      local cx, cy = hexCenter(sh.x, sh.y)
      engine.addFloat(cx, cy - 12, 'THE ISLAND FORGIVES YE!', CO.foam, 1)
    end
    return 'bump'
  end
  local foe = game.enemyAt(tx, ty)
  if foe then
    sh.route = nil
    M.startEncounter(foe, shipKey)
    return 'battle'
  end
  sh.bumpStreak = 0
  -- Remember the hop's hex direction so an icy slide can continue it, and
  -- reset the continuation count: this is a fresh hop, not a slide chain.
  sh.slideDir = grid.hexDirIndex(sh.x, sh.y, tx, ty)
  sh.slideChain = 0
  sh.anim = { x0 = sh.x, y0 = sh.y, t = 0 }
  sh.x, sh.y = tx, ty
  SFX.move()
  return 'move'
end

-- Advance the route one hop. Interrupted if any foe (other than the one
-- being hunted) has drifted next to the ship, so battles never start on
-- autopilot without the player seeing the threat first.
local function routeStep(sh, shipKey)
  local rt = sh.route
  for _, e in ipairs(game.run.sea.enemies) do
    if e ~= rt.foe and grid.hexDistance(e.x, e.y, sh.x, sh.y) <= 1 then
      sh.route = nil
      return 'interrupted'
    end
  end
  local nxt = table.remove(rt.steps, 1)
  if #rt.steps == 0 then sh.route = nil end
  local res = tryMove(sh, nxt[1], nxt[2], shipKey)
  if res == 'bump' then sh.route = nil end
  return res
end

-- TWO CAPTAINS: whichever ship touched the exit only fires once both ships
-- are on or adjacent to it. First arrival drops anchor and waits;
-- updateAnchor() below handles the "whistle" pull once it's been waiting a
-- while. Solo keeps the old single-ship exit.
local function tryEnterExit(sh, shipKey)
  local run = game.run
  if run.mode ~= 'captains' then
    nextSea()
    return true
  end
  local other = shipKey == 'ship2' and run.ship or run.ship2
  local ex = run.sea.exit
  if grid.hexDistance(other.x, other.y, ex.x, ex.y) <= 1 then
    run.sea.anchor = nil
    nextSea()
    return true
  end
  if not run.sea.anchor or run.sea.anchor.who ~= shipKey then
    run.sea.anchor = { who = shipKey, t = 0, pullT = 0 }
    engine.showBanner('ANCHORED! WAITING FOR YOUR MATE!', CO.gold, 1.1)
  end
  return false
end

-- Tile-trigger dispatch, shared by both ships. Returns true if a
-- state-changing trigger fired (chest/port/bottle/trader/X/exit-into-nextSea)
-- so tickShip's caller aborts the rest of this frame's sail update.
local function handleArrival(sh, shipKey)
  local tl = game.tileAt(sh.x, sh.y)
  if tl ~= game.T_WATER then sh.route = nil end
  if tl == game.T_CHEST then openChest(sh.x, sh.y); return true end
  if tl == game.T_PORT then
    if tryGossip(game.run, 'dock') then return true end
    engine.setState('dock')
    return true
  end
  if tl == game.T_EXIT then return tryEnterExit(sh, shipKey) end
  if tl == game.T_BOTTLE then foundBottle(sh.x, sh.y); return true end
  if tl == game.T_TRADER then meetTrader(sh.x, sh.y); return true end
  if tl == game.T_X then digQuest(sh.x, sh.y); return true end
  if tl == game.T_OLIVER then meetOliver(sh.x, sh.y); return true end
  return false
end

-- One ship's per-frame movement: hop animation + arrival triggers, or
-- manual d-pad steering / autopilot route-following. `ctx` is that ship's
-- input context (input.p1 for the ship, input.p2 for ship2). Returns
-- 'stop' when a battle or other state transition fired this frame.
function M.tickShip(sh, ctx, shipKey, dt)
  if sh.anim then
    sh.anim.t = sh.anim.t + dt / 0.15
    local a = util.clamp(sh.anim.t, 0, 1)
    sh.fx = util.lerp(sh.anim.x0, sh.x, util.ease(a))
    sh.fy = util.lerp(sh.anim.y0, sh.y, util.ease(a))
    if a >= 1 then
      sh.anim = nil
      -- Icy slide: landing on a slick hex carries the ship one more
      -- hex the same way. Bump-safe: blocked/enemy-occupied ends the slide.
      local slid = false
      local sea = game.run.sea
      if sea.biome == 'icy' and sh.slideDir and sea.slick[grid.gk(sh.x, sh.y)] then
        local nb = grid.hexNeighbors(sh.x, sh.y)[sh.slideDir]
        local nx, ny = nb[1], nb[2]
        if inSea(nx, ny) and game.tileAt(nx, ny) ~= game.T_ISLE and not game.enemyAt(nx, ny) then
          local cx, cy = hexCenter(sh.x, sh.y)
          engine.addFloat(cx, cy - 10, 'WHEE!', CO.foam, 1)
          sh.route = nil
          sh.anim = { x0 = sh.x, y0 = sh.y, t = 0 }
          sh.x, sh.y = nx, ny
          SFX.move()
          slid = true
          -- Hidden delight (for the 'wheee' secret): two continuations
          -- chained onto one hop is a 3-hex slide.
          sh.slideChain = (sh.slideChain or 0) + 1
          if sh.slideChain == 2 then
            game.foundSecret('wheee')
            engine.addFloat(cx, cy - 10, 'WHEEEEE!', CO.foam, 2)
          end
        end
      end
      if not slid and handleArrival(sh, shipKey) then return 'stop' end
    end
    return nil
  end
  if shipKey == 'ship2' and sh.convoy then return nil end
  local dir = ctx.moveDir(true)
  if dir then
    sh.route = nil -- manual steering overrides autopilot
    if dir == 'left' then sh.face = -1 elseif dir == 'right' then sh.face = 1 end
    game.run.hints.move = true
    local tx, ty = sailMap.hexStep(sh.x, sh.y, dir, sh.face)
    if tryMove(sh, tx, ty, shipKey) == 'battle' then return 'stop' end
  elseif sh.route then
    if routeStep(sh, shipKey) == 'battle' then return 'stop' end
  end
  return nil
end

-- TWO CAPTAINS: which ship is closer to (x, y) — used to pick an enemy's
-- chase target. Falls back to the lone ship outside captains mode.
function M.nearestShipTo(x, y)
  local run = game.run
  if run.mode ~= 'captains' or not run.ship2 then return run.ship, 'ship' end
  local d1 = grid.hexDistance(x, y, run.ship.x, run.ship.y)
  local d2 = grid.hexDistance(x, y, run.ship2.x, run.ship2.y)
  if d2 < d1 then return run.ship2, 'ship2' end
  return run.ship, 'ship'
end

-- Solo-collapse (TWO CAPTAINS): P2 idle for ~10s -> ship2 raises a little
-- pennant and auto-follows one hex behind ship1, avoiding enemies entirely
-- (so a convoying ship never starts a fight on its own). Any P2 input
-- instantly retakes the helm.
local CONVOY_LATCHES = { { limit = 10, key = 'convoy' } }

function M.updateConvoy(dt)
  local run = game.run
  local sh2 = run.ship2
  coop.tickIdle(sh2, dt, CONVOY_LATCHES)
  if not sh2.convoy or sh2.anim then return end
  sh2.stepT = (sh2.stepT or 0) + dt
  if sh2.stepT < 0.35 then return end
  sh2.stepT = 0
  local sh1 = run.ship
  local d0 = grid.hexDistance(sh2.x, sh2.y, sh1.x, sh1.y)
  if d0 <= 1 then return end
  local bestNb, bestD = nil, d0
  for _, nb in ipairs(grid.hexNeighbors(sh2.x, sh2.y)) do
    local nx, ny = nb[1], nb[2]
    if inSea(nx, ny) and game.tileAt(nx, ny) == game.T_WATER and not game.enemyAt(nx, ny) then
      local d = grid.hexDistance(nx, ny, sh1.x, sh1.y)
      if d < bestD then bestD, bestNb = d, { nx, ny } end
    end
  end
  if bestNb then
    sh2.slideDir = grid.hexDirIndex(sh2.x, sh2.y, bestNb[1], bestNb[2])
    sh2.anim = { x0 = sh2.x, y0 = sh2.y, t = 0 }
    sh2.x, sh2.y = bestNb[1], bestNb[2]
    SFX.move()
  end
end

-- Whistle (TWO CAPTAINS): once anchored 10s, the waiting captain can hold A
-- to pull the other ship one hex/sec toward the whirlpool. Cancelled by any
-- input from the other ship's own player, or once they're close enough.
function M.updateAnchor(dt)
  local run = game.run
  local anc = run.sea.anchor
  if not anc then return end
  anc.t = anc.t + dt
  local other = anc.who == 'ship2' and run.ship or run.ship2
  local ex = run.sea.exit
  if grid.hexDistance(other.x, other.y, ex.x, ex.y) <= 1 then
    run.sea.anchor = nil
    nextSea()
    return
  end
  if anc.t < 10 then return end
  local otherCtx = anc.who == 'ship2' and input.p1 or input.p2
  local otherActive = otherCtx.held.up or otherCtx.held.down or otherCtx.held.left or otherCtx.held.right
  if otherActive then
    anc.pullT = 0
    return
  end
  local waitingCtx = anc.who == 'ship2' and input.p2 or input.p1
  if not waitingCtx.held.a then
    anc.pullT = 0
    return
  end
  anc.pullT = anc.pullT + dt
  if anc.pullT < 1.0 or other.anim then return end
  anc.pullT = anc.pullT - 1.0
  local bd = grid.hexDistance(other.x, other.y, ex.x, ex.y)
  local bestNb, bestD = nil, bd
  for _, nb in ipairs(grid.hexNeighbors(other.x, other.y)) do
    local nx, ny = nb[1], nb[2]
    if inSea(nx, ny) and game.tileAt(nx, ny) == game.T_WATER and not game.enemyAt(nx, ny) then
      local d = grid.hexDistance(nx, ny, ex.x, ex.y)
      if d < bestD then bestD, bestNb = d, { nx, ny } end
    end
  end
  if bestNb then
    other.slideDir = grid.hexDirIndex(other.x, other.y, bestNb[1], bestNb[2])
    other.anim = { x0 = other.x, y0 = other.y, t = 0 }
    other.x, other.y = bestNb[1], bestNb[2]
    SFX.move()
  end
end

-- Hidden delight (for the 'raftup' secret, TWO CAPTAINS only): both ships
-- parked on the same hex a couple seconds straight. Ships never block each
-- other (see startEncounter/tryMove), so this is purely a delight, no rule.
function M.updateRaftUp(dt, run)
  local sh, sh2 = run.ship, run.ship2
  if sh.anim or sh2.anim or sh.route or sh2.route then
    run.sea.raftT = 0
    return
  end
  if sh.x == sh2.x and sh.y == sh2.y then
    run.sea.raftT = (run.sea.raftT or 0) + dt
    if run.sea.raftT >= 2 and not run.sea.raftFound then
      run.sea.raftFound = true
      game.foundSecret('raftup')
      local cx, cy = hexCenter(sh.x, sh.y)
      engine.addFloat(cx, cy - 14, 'RAFT-UP!', CO.foam, 1)
    end
  else
    run.sea.raftT = 0
  end
end

-- Enemy ships drift, chasing whichever ship is nearest when close. Returns
-- true if an encounter started this frame (caller must stop its update).
function M.driftEnemies(dt)
  local run = game.run
  for _, e in ipairs(run.sea.enemies) do
    e.fx = util.lerp(e.fx, e.x, util.clamp(dt * 9, 0, 1))
    e.fy = util.lerp(e.fy, e.y, util.clamp(dt * 9, 0, 1))
    e.t = e.t - dt
    if e.t <= 0 then
      e.t = 1.6 + love.math.random() * 1.8
      local target, targetKey = M.nearestShipTo(e.x, e.y)
      local tx, ty = nil, nil
      if grid.hexDistance(e.x, e.y, target.x, target.y) <= 4 then
        -- Chase: step to the passable neighbor closest to the target ship.
        local bd = 999
        for _, nb in ipairs(grid.hexNeighbors(e.x, e.y)) do
          local nx, ny = nb[1], nb[2]
          local open = (nx == target.x and ny == target.y)
            or (inSea(nx, ny) and game.tileAt(nx, ny) == game.T_WATER and not game.enemyAt(nx, ny))
          if open then
            local d = grid.hexDistance(nx, ny, target.x, target.y)
            if d < bd then bd, tx, ty = d, nx, ny end
          end
        end
      elseif util.chance(0.55) then
        local nb = util.pick(grid.hexNeighbors(e.x, e.y))
        tx, ty = nb[1], nb[2]
      end
      if tx then
        if tx == target.x and ty == target.y then
          if not target.anim then
            M.startEncounter(e, targetKey)
            return true
          end
        elseif inSea(tx, ty) and game.tileAt(tx, ty) == game.T_WATER
          and not game.enemyAt(tx, ty) then
          e.x, e.y = tx, ty
        end
      end
    end
  end
  return false
end

return M
