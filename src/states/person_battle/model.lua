-- Boarding-battle model: deck geometry, unit queries, the damage/KO
-- pipeline, and the win/loss check. Everything here is a pure query or
-- mutation over the shared `pb` battle table (src.states.person_battle.state);
-- the input FSM (person_battle.lua), foe AI (ai.lua), and draw (draw.lua)
-- all build on top of it.
local util = require 'src.util'
local grid = require 'src.grid'
local palette = require 'src.palette'
local audio = require 'src.audio'
local engine = require 'src.engine'
local game = require 'src.game'
local data = require 'src.data'
local meta = require 'src.meta'
local barks = require 'src.barks'
local rewards = require 'src.states.person_battle.rewards'
local S = require 'src.states.person_battle.state'
local CO = palette.CO
local SFX = audio.sfx
local gk = grid.gk

local M = {}

M.TILE = 16
local TILE = M.TILE
local VW, PLAY_TOP, PLAY_BOT = 320, 14, 132

function M.px(x, y)
  local pb = S.pb
  return pb.ox + x * TILE, pb.oy + y * TILE
end

function M.inDeck(x, y)
  return S.pb.deck[gk(x, y)] ~= nil
end

-- Stable sort (decorate/undo) by distance from the deck's vertical center,
-- ties broken by original scan order — spreads a spawn band middle-out
-- instead of clustering it at one scan corner.
local function centerSort(list, h)
  local centerY = (h - 1) / 2
  local decorated = {}
  for i, p in ipairs(list) do
    decorated[i] = { d = math.abs(p[2] - centerY), i = i, p = p }
  end
  table.sort(decorated, function(a, b)
    if a.d ~= b.d then return a.d < b.d end
    return a.i < b.i
  end)
  local out = {}
  for i, d in ipairs(decorated) do out[i] = d.p end
  return out
end

-- Parse a src.data.DECKS template into deck geometry: the walkable mask, a
-- flat list of its tiles (for random sampling), spawn bands, crate-eligible
-- tiles, and the per-row east edge the thief chases toward.
function M.buildDeck(tplId)
  local tpl
  for _, t in ipairs(data.DECKS) do
    if t.id == tplId then tpl = t; break end
  end
  tpl = tpl or data.DECKS[1]
  local rows = tpl.rows
  local h = #rows
  local w = #rows[1]
  local deck, deckList, pSpawns, eSpawns, crateCand = {}, {}, {}, {}, {}
  for y = 0, h - 1 do
    local row = rows[y + 1]
    for x = 0, w - 1 do
      local ch = row:sub(x + 1, x + 1)
      if ch ~= '.' then
        deck[gk(x, y)] = true
        deckList[#deckList + 1] = { x, y }
        if ch == 'P' then pSpawns[#pSpawns + 1] = { x, y }
        elseif ch == 'E' then eSpawns[#eSpawns + 1] = { x, y }
        elseif ch == 'c' then crateCand[#crateCand + 1] = { x, y } end
      end
    end
  end
  local eastEdge = {}
  for y = 0, h - 1 do
    for x = w - 1, 0, -1 do
      if deck[gk(x, y)] then eastEdge[y] = x; break end
    end
  end
  return {
    id = tpl.id, logText = tpl.logText, w = w, h = h, deck = deck, deckList = deckList,
    pSpawns = centerSort(pSpawns, h), eSpawns = centerSort(eSpawns, h),
    crateCand = crateCand, eastEdge = eastEdge,
  }
end

-- Weighted shape draw (design-gaps/05): classic alone on seas 1-2, then the
-- full weighted pool (classic included) so it stays common but not forced.
function M.pickDeckId(lv)
  if lv < 3 then return 'classic' end
  local pool = {}
  for _, t in ipairs(data.DECKS) do
    for _ = 1, t.weight do pool[#pool + 1] = t.id end
  end
  return util.pick(pool)
end

-- Centers a w x h deck within the fixed 320x180 canvas, between the top
-- status strip and the bottom panel.
function M.deckOrigin(w, h)
  local ox = math.floor((VW - w * TILE) / 2)
  local oy = PLAY_TOP + math.floor(((PLAY_BOT - PLAY_TOP) - h * TILE) / 2)
  return ox, oy
end

-- Random crate scatter (Gap 6): only ever lands on 'c'-marked tiles, never
-- on a spawn band or plain '#' deck.
function M.scatterCrates(deckInfo)
  local crates = {}
  local cand = deckInfo.crateCand
  if #cand == 0 then return crates end
  local n = math.min(util.irand(4, 6), #cand)
  local tries, count = 0, 0
  while count < n and tries < n * 20 do
    tries = tries + 1
    local t = cand[util.irand(1, #cand)]
    local k = gk(t[1], t[2])
    if not crates[k] then
      crates[k] = true
      count = count + 1
    end
  end
  return crates
end

-- Cursor step that skips holes: scans up to the deck's own bounding box in
-- direction (dx, dy) for the next in-mask tile, or snaps back to (cx, cy).
function M.moveCursor(cx, cy, dx, dy)
  local pb = S.pb
  local nx, ny = cx, cy
  for _ = 1, math.max(pb.w, pb.h) do
    nx, ny = nx + dx, ny + dy
    if nx < 0 or ny < 0 or nx >= pb.w or ny >= pb.h then return cx, cy end
    if pb.deck[gk(nx, ny)] then return nx, ny end
  end
  return cx, cy
end

-- Shared shove-slide resolution (Gap 6): how far a shoved target travels
-- from its own tile before the deck edge, a hole, a crate, or another unit
-- stops it. Read-only — the path includes every intermediate tile so both
-- the real move (person_battle.lua) and the preview ghost (draw.lua) render
-- identically.
function M.slideTarget(u, tgt, maxSteps)
  local dx, dy = tgt.x - u.x, tgt.y - u.y
  local path = { { tgt.x, tgt.y } }
  local ex, ey, slid = tgt.x, tgt.y, 0
  for _ = 1, maxSteps do
    local nx, ny = ex + dx, ey + dy
    if not M.inDeck(nx, ny) or S.pb.crates[gk(nx, ny)] or M.unitAt(nx, ny) then break end
    ex, ey, slid = nx, ny, slid + 1
    path[#path + 1] = { nx, ny }
  end
  return ex, ey, slid, path
end

function M.unitAt(x, y)
  for _, u in ipairs(S.pb.units) do
    if u.alive and u.x == x and u.y == y then return u end
  end
  return nil
end

function M.alive(side)
  local n = 0
  for _, u in ipairs(S.pb.units) do
    if u.alive and u.side == side then n = n + 1 end
  end
  return n
end

function M.schedule(fn, delay)
  S.pb.wait = delay
  S.pb.next = fn
end

-- Which player owns a party-side unit's timing bars (2.3). Solo play or a
-- unit with no owned pirate behind it resolves to nil ("either player").
-- p2Away is the solo-collapse latch: once P2 has been idle a full round,
-- P1 drives everyone, so bars stop gating on P2's button.
function M.ownerPlayer(u)
  if not game.isCoop() or S.pb.p2Away then return nil end
  return u and u.ref and game.ownerOf(u.ref)
end

-- May `player` select/drive this unit? Own pals only, except P1 inherits an
-- idle-collapsed P2's pals so co-op never soft-locks.
function M.canDrive(player, u)
  if u.side ~= 'p' or not u.alive or u.acted then return false end
  if not game.isCoop() then return player == 'p1' end
  local owner = u.owner or 'p1'
  if owner == player then return true end
  return player == 'p1' and S.pb.p2Away
end

function M.cursorToNext(player)
  local pb = S.pb
  local pl = pb.pl[player]
  for _, u in ipairs(pb.units) do
    if M.canDrive(player, u) then
      pl.cursor.x, pl.cursor.y = u.x, u.y
      return u
    end
  end
  return nil
end

function M.allActed()
  for _, u in ipairs(S.pb.units) do
    if u.side == 'p' and u.alive and not u.acted then return false end
  end
  return true
end

function M.reachFor(u)
  return grid.bfsFlood(u.x, u.y, u.move, function(x, y)
    if not M.inDeck(x, y) or S.pb.crates[gk(x, y)] then return false end
    local o = M.unitAt(x, y)
    return not o or o.side == u.side
  end)
end

function M.targetsOf(u, range)
  local out = {}
  for _, o in ipairs(S.pb.units) do
    if o.alive and o.side ~= u.side and grid.manhattan(u.x, u.y, o.x, o.y) <= range then
      out[#out + 1] = o
    end
  end
  return out
end

function M.alliesOf(u, hurtOnly)
  local out = {}
  for _, o in ipairs(S.pb.units) do
    if o.alive and o.side == u.side and (not hurtOnly or o.hp < o.max) then
      out[#out + 1] = o
    end
  end
  return out
end

-- Adjacent crates grant cover against non-adjacent attackers.
function M.hasCover(def, att)
  if grid.manhattan(def.x, def.y, att.x, att.y) <= 1 then return false end
  for i = 1, 4 do
    if S.pb.crates[gk(def.x + grid.DIRS4[i][1], def.y + grid.DIRS4[i][2])] then return true end
  end
  return false
end

-- Logical position updates immediately; fx/fy animate along the path.
function M.walk(u, path, after)
  if not path or #path < 2 then
    if after then after() end
    return
  end
  local pb = S.pb
  -- Hidden delight (design-gaps/06 `tightrope`): any pal's path crossing the
  -- gangplank's narrow waist trips the "somebody wobbled" flag pb.checkEnd
  -- reads at the victory beat.
  if u.side == 'p' and pb.waistCols then
    for _, step in ipairs(path) do
      if pb.waistCols[step[1]] and step[2] == pb.waistY then
        pb.wobbled = true
        break
      end
    end
  end
  pb.walk = { u = u, path = path, t = 0, after = after }
  u.x, u.y = path[#path][1], path[#path][2]
end

function M.ko(u)
  local pb = S.pb
  u.alive = false
  SFX.poof()
  local ux, uy = M.px(u.x, u.y)
  barks.say(u, ux, uy, 'ko')
  -- Defeat gag (Gap 1, item 5): the crown visibly pops off the King's KO poof.
  if u.role == 'king' then
    engine.addParts(ux + 8, uy - 2, 10, CO.gold, 55, 20)
  end
  engine.addParts(ux + 8, uy + 8, 14, CO.white, 40)
  -- Gold only leaves with an escaped thief (4.3); a KO drops it on the spot.
  if u.loot then
    u.loot = nil
    engine.addFloat(ux + 8, uy - 12, 'GOT THE GOLD BACK!', CO.gold, 2)
  end
  pb.flags[#pb.flags + 1] = { x = u.x, y = u.y }
  if u.side == 'e' then pb.defeated[#pb.defeated + 1] = u end
end

-- The King has chained HP bars: breaking one refills the next and enrages
-- him instead of KO-ing him outright. Every hp<=0 check should route
-- through this so his bars aren't bypassed by shove/hazard damage.
function M.breakOrKo(u)
  if u.bars and u.bars > 1 then
    u.bars = u.bars - 1
    u.hp = u.max
    u.rage = (u.rage or 0) + 1
    u.atk = u.atk + 2
    SFX.bigwin()
    engine.shakeIt(3, 0.3)
    local ux, uy = M.px(u.x, u.y)
    barks.sayKing(u, ux - 8, uy, 'rage')
    engine.addParts(ux + 8, uy + 8, 20, CO.red, 60)
    engine.addFloat(ux + 8, uy - 12, 'RAGE!', CO.red, 2)
    game.logMoment('kingSil', 'SEA ' .. (game.run.voyage and game.run.voyage.sea or 1) .. ": KING'S BAR BROKE!", {})
    return
  end
  M.ko(u)
end

-- Best Mates (3.4): +1 ATK while adjacent to your bonded pal.
function M.bondBonus(att)
  if att.side ~= 'p' or not att.ref then return 0 end
  for _, u in ipairs(S.pb.units) do
    if u ~= att and u.side == 'p' and u.alive and u.ref
      and grid.manhattan(att.x, att.y, u.x, u.y) == 1
      and game.isBonded(att.ref.name, u.ref.name) then
      return 1
    end
  end
  return 0
end

-- Shared modifier chain (Gap 4): crab shell / guard, then cover, each
-- halving. `damage()` and `previewDamage()` both run through this so the
-- preview can never drift from what actually lands.
-- Crab shell (4.3): frontal hits are halved like a permanent guard; only
-- attacks from strictly behind (attacker right of the crab, which always
-- faces the player side) land full damage. Teaches flanking by reward.
function M.applyMods(dmg, att, def, opts)
  opts = opts or {}
  local notes = {}
  local shell = def.role == 'crab' and att.x <= def.x
  if def.guard or shell then
    dmg = math.ceil(dmg / 2)
    notes[#notes + 1] = shell and 'SHELL' or 'GUARD'
  end
  if not opts.ignoreCover and M.hasCover(def, att) then
    dmg = math.ceil(dmg / 2)
    notes[#notes + 1] = 'COVER'
  end
  return dmg, notes
end

-- Deterministic preview of a 'good'-result hit, for the target-phase HUD:
-- lo/hi bracket the +0/+1 timing-bar roll; notes name every modifier that
-- fired, so the crab flank teaches itself before the whiff instead of after.
function M.previewDamage(att, def, atkBase, opts)
  local bond = M.bondBonus(att)
  local lo, notes = M.applyMods(atkBase + bond, att, def, opts)
  local hi = (M.applyMods(atkBase + 1 + bond, att, def, opts))
  if bond > 0 then table.insert(notes, 1, '@') end
  return { lo = math.max(1, util.round(lo)), hi = math.max(1, util.round(hi)), notes = notes }
end

function M.damage(att, def, base, res, opts)
  opts = opts or {}
  local dx, dy = M.px(def.x, def.y)
  -- A miss still lands as a rare, cheap chip hit (design-gaps/04): a
  -- whiffed turn used to do zero, the most punishing outcome in the game.
  if res == 'miss' then
    local dmg = math.max(1, math.ceil(base / 3))
    def.hp = math.max(0, def.hp - dmg)
    SFX.miss()
    engine.addFloat(dx + 8, dy - 4, 'GLANCED! -' .. dmg, CO.gray, 1)
    if def.hp <= 0 then M.breakOrKo(def) end
    return
  end
  local dmg = base + M.bondBonus(att)
  if res == 'perfect' then
    dmg = dmg * 2
    SFX.perfect()
    engine.addParts(dx + 8, dy + 4, 12, CO.gold, 60)
    engine.addFloat(dx + 8, dy - 12, 'PERFECT!', CO.gold, 2)
    local ax, ay = M.px(att.x, att.y)
    barks.say(att, ax, ay, 'perfect')
  else
    SFX.good()
  end
  local notes
  dmg, notes = M.applyMods(dmg, att, def, opts)
  for _, n in ipairs(notes) do
    engine.addFloat(dx + 8, dy + 4, n .. '!', CO.foam, 1)
  end
  dmg = math.max(1, util.round(dmg))
  def.hp = math.max(0, def.hp - dmg)
  SFX.hit()
  engine.shakeIt(1.5, 0.12)
  engine.addParts(dx + 8, dy + 8, 8, CO.red, 45)
  engine.addFloat(dx + 8, dy - 4, '-' .. dmg, def.side == 'p' and CO.red or CO.white, 2)
  if def.hp <= 0 then M.breakOrKo(def) end
end

-- Tuckered-out pals (3.1): any party pal KO'd this battle naps next sea and
-- steps out of the party. If that would leave the party empty, wake the
-- captain instead — he's already party-mandatory (crew.lua), so this is the
-- only "never a soft-lock" case worth special-casing.
-- SHIP'S COOK (5.2): chance per tier to patch a KO'd pal up before the nap
-- even starts, guaranteed at the top tier ("naps last 0 seas").
function M.resolveNaps()
  local run = game.run
  local cookTier = meta.cookTier()
  for _, u in ipairs(S.pb.units) do
    if u.side == 'p' and not u.alive and u.ref then
      if cookTier < 3 and not util.chance(cookTier * 0.3) then
        u.ref.nap = 1
      end
    end
  end
  local function awake()
    local out = {}
    for _, p in ipairs(run.party) do
      if not game.isNapping(p) then out[#out + 1] = p end
    end
    return out
  end
  local newParty = awake()
  if #newParty == 0 then
    for _, p in ipairs(run.party) do
      if p.role == 'captain' then p.nap = nil end
    end
    newParty = awake()
  end
  run.party = newParty
end

-- Two random surviving party pals bark at the victory beat, mirroring
-- battleStartBarks (person_battle.lua) so the cast feels present at both ends.
local function victoryBarks()
  local pool = {}
  for _, u in ipairs(S.pb.units) do
    if u.side == 'p' and u.alive then pool[#pool + 1] = u end
  end
  for _ = 1, math.min(2, #pool) do
    local i = util.irand(1, #pool)
    local u = table.remove(pool, i)
    local ux, uy = M.px(u.x, u.y)
    barks.say(u, ux, uy, 'victory')
  end
end

function M.checkEnd()
  local pb = S.pb
  if pb.over then return true end
  if M.alive('e') == 0 then
    pb.over = true
    pb.phase = 'done'
    M.resolveNaps()
    SFX.bigwin()
    victoryBarks()
    if pb.isBoss then
      local bossName = (pb.foeRef and pb.foeRef.name) or 'THE PIRATE KING'
      engine.showBanner(bossName .. ' IS DEFEATED!', CO.gold, 1.3)
      M.schedule(function()
        engine.transition('VICTORY!', function() require('src.states.victory').start() end)
      end, 1.4)
      return true
    end
    -- Hidden delight (design-gaps/06 `tightrope`): the gangplank deck, won
    -- with no pal ever setting foot on its narrow waist.
    if pb.deckId == 'gangplank' and pb.waistCols and not pb.wobbled then
      game.foundSecret('tightrope')
      engine.addFloat(VW / 2, 60, 'NOBODY WOBBLED!', CO.gold, 2)
    end
    engine.showBanner('VICTORY!', CO.gold, 1.3)
    M.schedule(function()
      engine.transition('TREASURE!', rewards.victoryLoot)
    end, 1.4)
    return true
  end
  if M.alive('p') == 0 then
    pb.over = true
    pb.phase = 'done'
    M.resolveNaps()
    SFX.lose()
    engine.showBanner('SWIM HOME, CREW!', CO.foam, 1.3)
    M.schedule(function()
      engine.transition('EVERYONE IS OK!', function()
        engine.setState('sail')
      end)
    end, 1.4)
    return true
  end
  return false
end

function M.actMenu(u)
  local items = {
    { id = 'atk', label = 'ATTACK', ok = #M.targetsOf(u, u.range) > 0 },
    { id = 'grd', label = 'GUARD', ok = true },
  }
  local sd = data.ROLES[u.role].spec
  local sOk = not u.specUsed
  if sOk then
    if u.role == 'medic' then sOk = #M.alliesOf(u, true) > 0 end
    if u.role == 'strongman' or u.role == 'deckhand' then sOk = #M.targetsOf(u, 1) > 0 end
    if u.role == 'sharpshooter' then sOk = #M.targetsOf(u, 99) > 0 end
  end
  items[#items + 1] = { id = 'spc', label = sd.name, ok = sOk, desc = sd.desc }
  items[#items + 1] = { id = 'stay', label = 'STAY', ok = true }
  return items
end

return M
