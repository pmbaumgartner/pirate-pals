-- Run state: everything that persists across game states lives in game.run
-- (gold, crew, party, current sea). Also owns sea generation and the
-- pirate/treasure helpers that operate on the run.
local util = require 'src.util'
local grid = require 'src.grid'
local data = require 'src.data'
local serialize = require 'src.serialize'
local meta = require 'src.meta'
local engine = require 'src.engine'
local audio = require 'src.audio'
local palette = require 'src.palette'
local CO = palette.CO

local M = {}
M.meta = meta

M.SAVE_PATH = 'save.lua'

-- Sea layout: SEA_W x SEA_H cells drawn below a HUD strip SEA_TOP px tall.
-- The sea is an odd-r hex grid (see grid.lua); 19 columns because odd rows
-- shift right half a cell and 19 * 16 + 8 still fits the 320 px canvas.
M.SEA_W, M.SEA_H, M.SEA_TOP = 19, 9, 20
M.T_WATER, M.T_ISLE, M.T_CHEST, M.T_PORT, M.T_EXIT = 0, 1, 2, 3, 4
-- Event tiles (4.2): message-in-a-bottle, friendly trader, and the
-- treasure-map X a bottle marks on a later sea.
M.T_BOTTLE, M.T_TRADER, M.T_X = 5, 6, 7

M.run = nil

function M.makePirate(role, name, lvl)
  return { role = role, name = name, lvl = lvl or 1, out = 'none' }
end

function M.statsOf(p)
  local r = data.ROLES[p.role]
  local st = { hp = r.hp + 2 * (p.lvl - 1), atk = r.atk + (p.lvl - 1), move = r.move, range = r.range }
  if p.perks then
    for _, pid in ipairs(p.perks) do
      local perk = data.perkById(pid)
      if perk then
        for stat, amt in pairs(perk.effects) do
          st[stat] = st[stat] + amt
        end
      end
    end
  end
  return st
end

-- Tuckered-out pals (3.1): napping is always temporary and never blocks the
-- captain from sailing (see resolveNaps in person_battle.lua).
function M.isNapping(p)
  return p.nap ~= nil and p.nap > 0
end

-- Best Mates (3.4): sorted so the pair key is order-independent.
function M.bondKey(a, b)
  if a > b then a, b = b, a end
  return a .. '|' .. b
end

function M.isBonded(a, b)
  return M.run.bondsMade[M.bondKey(a, b)] == true
end

-- Voyage Log: notable moments the game remembers, never anything
-- that went wrong. `icon` is a sprite key, `pals` a list of pal names
-- (never crew references, so identity/save-shape stays plain data). Capped
-- at 40 so the save can't bloat; once full, the oldest non-`first` entry is
-- dropped so one-time milestones (first recruit, first Best Mates) outlast
-- routine ones (another sea cleared, another dig).
function M.logMoment(icon, text, pals, first)
  local run = M.run
  local entry = { sea = run.voyage and run.voyage.sea or 1, icon = icon, text = text, pals = pals or {} }
  if first then entry.first = true end
  table.insert(run.log, entry)
  if #run.log > 40 then
    for i, e in ipairs(run.log) do
      if not e.first then table.remove(run.log, i); break end
    end
  end
end

-- Hidden delights: the one writer of meta.data.secrets.
-- No-op on a repeat find -- callers can call this every time their trigger
-- condition is true without worrying about re-showing the banner.
function M.foundSecret(id)
  if meta.data.secrets[id] then return end
  meta.data.secrets[id] = true
  meta.save()
  local secret = data.secretById(id)
  audio.sfx.fanfare()
  engine.showBanner('SECRET FOUND!', CO.gold)
  engine.addFloat(160, 100, secret and secret.name or id, CO.gold, 2)
end

function M.distinctSecrets()
  local n = 0
  for _, v in pairs(meta.data.secrets) do
    if v then n = n + 1 end
  end
  return n
end

function M.distinctTreasures()
  local n = 0
  for _, cnt in pairs(M.run.treas) do
    if cnt > 0 then n = n + 1 end
  end
  return n
end

-- Higher seas shift the roll toward rarer tiers.
function M.rollTreasure(lv)
  local wE = math.min(30, 6 + 3 * lv)
  local wR = 28 + 2 * lv
  local wC = math.max(28, 66 - 4 * lv)
  local roll = love.math.random() * (wC + wR + wE)
  local tier = roll < wC and 0 or (roll < wC + wR and 1 or 2)
  local pool = {}
  for _, t in ipairs(data.TREASURES) do
    if t.tier == tier then pool[#pool + 1] = t end
  end
  return util.pick(pool)
end

-- Banks a rolled treasure and checks milestone unlocks: the one canonical
-- path for treasure gain, shared by chest/quest/boarding/trader rewards so
-- the increment-then-unlock-check logic lives in exactly one place. Returns
-- the loot card for the treasure plus any unlock cards it triggered (empty
-- if none), since callers differ on where those cards land in their list.
function M.awardTreasure(tr)
  local run = M.run
  run.treas[tr.id] = (run.treas[tr.id] or 0) + 1
  local unlocks = {}
  for _, m in ipairs(data.MILESTONES) do
    if M.distinctTreasures() >= m.n and not run.owned[m.id] then
      M.unlockHat(m.id)
      unlocks[#unlocks + 1] = { type = 'unlock', id = m.id }
    end
  end
  return { type = 'treasure', id = tr.id }, unlocks
end

function M.tileAt(x, y)
  if x < 0 or y < 0 or x >= M.SEA_W or y >= M.SEA_H then return M.T_ISLE end
  return M.run.sea.t[y][x]
end

function M.setTile(x, y, v)
  M.run.sea.t[y][x] = v
end

function M.enemyAt(x, y)
  return M.enemyAtList(M.run.sea.enemies, x, y)
end

function M.enemyAtList(list, x, y)
  for _, e in ipairs(list) do
    if e.x == x and e.y == y then return e end
  end
  return nil
end

-- Enemy scaling never reads past the voyage length, so future Voyage+ tiers
-- (Phase 5) that push sea numbers beyond it don't quietly keep buffing foes.
function M.scaleLv(lv)
  if M.run and M.run.voyage then return math.min(lv, M.run.voyage.length) end
  return lv
end

-- Biome for a fresh sea (4.1): sea 1 and the boss sea are always calm;
-- everything between draws from the pool (calm included, so plain seas keep
-- showing up). The chart pre-rolls this via run.nextBiome so the twist can
-- be announced before the sea exists.
function M.rollBiome(lv)
  if lv <= 1 or (M.run and M.run.voyage and lv >= M.run.voyage.length) then return 'calm' end
  return util.pick(data.BIOME_POOL)
end

-- Every new sea is one fewer sea of napping (3.1); this is the one place
-- "entering a new sea" happens for both normal play and --warp jumps.
local function ageCrewNaps()
  for _, p in ipairs(M.run.crew) do
    if p.nap and p.nap > 0 then
      p.nap = p.nap - 1
      if p.nap <= 0 then p.nap = nil end
    end
  end
end

-- `biome` overrides the roll (dev warps/tests); otherwise a chart pre-roll
-- (run.nextBiome) or rollBiome decides. Always 'calm' on the boss sea.
local function resolveSeaBiome(lv, boss, biome)
  if not biome and M.run.nextBiome and M.run.nextBiome.sea == lv then
    biome = M.run.nextBiome.biome
  end
  M.run.nextBiome = nil
  return (boss and 'calm') or biome or M.rollBiome(lv)
end

-- Preferred hex gap between placed sea features (chests, port, specials,
-- enemies); freeTile relaxes it to 2 and finally to "any open water", so
-- crowded maps degrade to mild adjacency rather than failing generation.
local SEA_SPACING = 3

local function freeTile(t, spawn, minX, placed)
  local function pick()
    local fx, fy = util.irand(minX, M.SEA_W - 2), util.irand(0, M.SEA_H - 1)
    if t[fy][fx] == M.T_WATER and grid.hexDistance(fx, fy, spawn.x, spawn.y) > 2 then
      return fx, fy
    end
  end
  local function accept(fx, fy)
    local p = { x = fx, y = fy }
    placed[#placed + 1] = p
    return p
  end

  for d = SEA_SPACING, 2, -1 do
    for _ = 1, 40 do
      local fx, fy = pick()
      if fx then
        local ok = true
        for _, p in ipairs(placed) do
          if grid.hexDistance(fx, fy, p.x, p.y) < d then
            ok = false
            break
          end
        end
        if ok then return accept(fx, fy) end
      end
    end
  end

  for _ = 1, 60 do
    local fx, fy = pick()
    if fx then return accept(fx, fy) end
  end
  return nil
end

local function placeIslands(t, spawn, exit)
  for _ = 1, util.irand(4, 6) do
    local ix, iy = util.irand(3, M.SEA_W - 3), util.irand(0, M.SEA_H - 1)
    if grid.hexDistance(ix, iy, spawn.x, spawn.y) >= 3 then
      local bx, by = ix, iy
      for _ = 1, util.irand(1, 3) do
        if bx >= 2 and bx < M.SEA_W - 1 and by >= 0 and by < M.SEA_H
          and t[by][bx] == M.T_WATER
          and (not exit or grid.hexDistance(bx, by, exit.x, exit.y) > 1) then
          t[by][bx] = M.T_ISLE
        end
        local nb = util.pick(grid.hexNeighbors(bx, by))
        bx, by = nb[1], nb[2]
      end
    end
  end
end

-- Sea events (4.2): the quest X (if a bottle marked this sea) plus at most
-- one bottle/trader tile. Never on the boss sea. `questPlaced` tells the
-- caller whether an outstanding quest X found a home this attempt.
local function placeSpecials(t, spawn, lv, boss, placed)
  local specials, questPlaced = {}, false
  if not boss and M.run.quest and M.run.quest.sea == lv then
    local q = freeTile(t, spawn, 4, placed)
    if q then
      t[q.y][q.x] = M.T_X
      questPlaced = true
      specials[#specials + 1] = q
    end
  end
  local last = (M.run.voyage and M.run.voyage.length or 8) - 1
  if not boss and lv >= 2 and (lv == last or util.chance(0.6)) then
    local ev = freeTile(t, spawn, 3, placed)
    if ev then
      -- Bottles only where a "later sea" exists and no map is already held.
      local pool = { M.T_TRADER }
      if lv == last and not M.run.gossipShown then
        pool = { M.T_BOTTLE }
      else
        if lv <= 6 and not M.run.quest then pool[#pool + 1] = M.T_BOTTLE end
      end
      t[ev.y][ev.x] = util.pick(pool)
      specials[#specials + 1] = ev
    end
  end
  return specials, questPlaced
end

local function placeEnemies(t, spawn, lv, boss, placed, biome)
  local enemies = {}
  if boss then
    local bp = freeTile(t, spawn, 10, placed)
    if bp then
      -- Golden Compass (5.3): a completed 12/12 treasure log permanently
      -- extends the voyage to sea 9, a tougher rematch (see ship_battle's
      -- foeHp/startBoss scaling) closing the collection promise.
      local kraken = M.run.voyage and lv >= 9
      enemies[1] = {
        x = bp.x, y = bp.y, lv = lv, name = kraken and 'THE KRAKEN' or 'THE PIRATE KING', boss = true,
        kraken = kraken, t = 0, fx = bp.x, fy = bp.y,
      }
    end
  else
    for _ = 1, math.min(2 + math.floor(lv / 2), 4) do
      local e = freeTile(t, spawn, 8, placed)
      if e and not M.enemyAtList(enemies, e.x, e.y) then
        local pool
        if biome == 'calm' then
          pool = { 'brig', 'brig', 'brig', 'sloop', 'sloop', 'fireship', 'manowar' }
        elseif biome == 'foggy' then
          pool = { 'sloop', 'sloop', 'sloop', 'brig', 'fireship', 'manowar' }
        elseif biome == 'volcano' then
          pool = { 'fireship', 'fireship', 'fireship', 'brig', 'sloop', 'manowar' }
        elseif biome == 'icy' then
          pool = { 'manowar', 'manowar', 'brig', 'sloop', 'fireship' }
        else
          pool = { 'brig', 'sloop', 'fireship', 'manowar' }
        end
        local cls = util.pick(pool)
        enemies[#enemies + 1] = {
          x = e.x, y = e.y, lv = lv, name = util.pick(data.FOE_CAPTAINS),
          t = love.math.random() * 2, fx = e.x, fy = e.y,
          class = cls,
        }
      end
    end
  end
  return enemies
end

-- Reachability check from spawn (islands block); every generated waypoint
-- must be walkable from the ship's start hex, or this attempt is discarded.
local function seaReachable(t, spawn, exit, port, chests, specials, enemies, boss)
  local flood = grid.bfsFlood(spawn.x, spawn.y, 999, function(fx, fy)
    return fx >= 0 and fy >= 0 and fx < M.SEA_W and fy < M.SEA_H and t[fy][fx] ~= M.T_ISLE
  end, grid.hexNeighbors)
  local function reached(p) return flood.cost[grid.gk(p.x, p.y)] ~= nil end
  if exit and not reached(exit) then return false end
  if port and not reached(port) then return false end
  for _, c in ipairs(chests) do if not reached(c) then return false end end
  for _, s in ipairs(specials) do if not reached(s) then return false end end
  for _, e in ipairs(enemies) do if not reached(e) then return false end end
  return #enemies >= (boss and 1 or 2)
end

-- Icy twist (4.1): mark slick water hexes; entering one slides the ship an
-- extra hex (see sail.lua). Sparse "x,y"-keyed set, plain data.
local function buildSlick(t, spawn, biome)
  local slick = {}
  if biome ~= 'icy' then return slick end
  for sy = 0, M.SEA_H - 1 do
    for sx = 0, M.SEA_W - 1 do
      if t[sy][sx] == M.T_WATER and not (sx == spawn.x and sy == spawn.y)
        and util.chance(0.14) then
        slick[grid.gk(sx, sy)] = true
      end
    end
  end
  return slick
end

-- If the quest X found no home this sea, kindly slide it forward one sea
-- (or forget it near the boss) — the map is never silently lost while its
-- sea is still ahead.
local function rescheduleUnplacedQuest(lv, questPlaced)
  if not (M.run.quest and M.run.quest.sea == lv and not questPlaced) then return end
  local last = (M.run.voyage and M.run.voyage.length or 8) - 1
  if lv + 1 <= last then M.run.quest.sea = lv + 1 else M.run.quest = nil end
end

-- TWO CAPTAINS: ship2 spawns on the nearest sailable hex next to ship's
-- spawn; sharing a hex is fine (ships never block each other), so any open
-- neighbor works, falling back to spawn itself.
local function spawnShips(t, spawn)
  local sh = M.run.ship
  sh.x, sh.y = spawn.x, spawn.y
  sh.fx, sh.fy = spawn.x, spawn.y
  sh.face, sh.anim, sh.route = 1, nil, nil
  if not M.run.ship2 then return end
  local sh2 = M.run.ship2
  local sx, sy = spawn.x, spawn.y
  for _, nb in ipairs(grid.hexNeighbors(spawn.x, spawn.y)) do
    local nx, ny = nb[1], nb[2]
    if nx >= 0 and ny >= 0 and nx < M.SEA_W and ny < M.SEA_H and t[ny][nx] == M.T_WATER then
      sx, sy = nx, ny
      break
    end
  end
  sh2.x, sh2.y = sx, sy
  sh2.fx, sh2.fy = sx, sy
  sh2.face, sh2.anim, sh2.route = 1, nil, nil
end

-- Generate one screen of sea: islands, a port, chests, enemy ships, and a
-- whirlpool exit — retried until everything is reachable from spawn. Sea 8
-- (voyage.length) special-cases into the Pirate King's sea: no whirlpool
-- exit, his galleon is the only enemy.
function M.genSea(lv, biome)
  ageCrewNaps()
  local boss = M.run.voyage and lv >= M.run.voyage.length
  biome = resolveSeaBiome(lv, boss, biome)
  for _ = 1, 40 do
    local t = {}
    for y = 0, M.SEA_H - 1 do
      t[y] = {}
      for x = 0, M.SEA_W - 1 do t[y][x] = M.T_WATER end
    end
    local spawn = { x = 1, y = 4 }
    local exit = nil
    local placed = {}
    if not boss then
      exit = { x = M.SEA_W - 1, y = util.irand(2, 6) }
      t[exit.y][exit.x] = M.T_EXIT
      placed[#placed + 1] = exit
    end

    placeIslands(t, spawn, exit)

    local port = freeTile(t, spawn, 3, placed)
    if port then t[port.y][port.x] = M.T_PORT end

    local chests = {}
    if not boss then
      for _ = 1, util.irand(2, 3) do
        local c = freeTile(t, spawn, 2, placed)
        if c then
          t[c.y][c.x] = M.T_CHEST
          chests[#chests + 1] = c
        end
      end
    end

    local specials, questPlaced = placeSpecials(t, spawn, lv, boss, placed)
    local enemies = placeEnemies(t, spawn, lv, boss, placed, biome)

    if seaReachable(t, spawn, exit, port, chests, specials, enemies, boss) then
      M.run.sea = {
        lv = lv, t = t, enemies = enemies, exit = exit, port = port, cleared = false, boss = boss,
        biome = biome, slick = buildSlick(t, spawn, biome), rocks = {}, rockT = 2.5, shipHurt = 0,
        -- Hidden delight (for the 'luckycoin' secret): every chest this sea
        -- opened without a battle in between. chestOpened/chestBroken reset
        -- fresh with every new sea, same as the rest of run.sea.
        chestTotal = #chests, chestOpened = 0, chestBroken = false,
      }
      rescheduleUnplacedQuest(lv, questPlaced)
      spawnShips(t, spawn)
      if M.run.voyage then M.run.voyage.sea = lv end
      return
    end
  end
  error('sea generation failed')
end

-- Hats are meta-owned (5.1): buying/unlocking one persists across voyages.
-- run.owned stays the live table every draw/purchase call site already
-- reads, kept in sync with meta.data.hats rather than replacing it.
function M.unlockHat(id)
  M.run.owned[id] = true
  meta.data.hats[id] = true
end

-- TWO CAPTAINS is the only co-op mode: a second player is active exactly
-- when `run.mode == 'captains'` (M.isCoop()), decided at new-game since it
-- needs a second captain and ship from the start.
function M.newGame(mode, colors)
  mode = mode or 'solo'
  M.run = {
    version = 1,
    mode = mode,
    colors = colors or { p1 = 'white', p2 = mode == 'captains' and 'green' or nil },
    gold = 0, treas = {}, owned = { none = true },
    crew = {}, party = {},
    ship = { x = 1, y = 4, fx = 1, fy = 4, face = 1, anim = nil },
    ship2 = nil,
    sea = nil,
    voyage = { sea = 1, length = meta.data.golden and 9 or 8 },
    hints = {}, wins = 0,
    owners = {},
    bonds = {}, bondsMade = {}, log = {},
    metaTier = meta.data.tier or 0,
    seenDecks = {},
    salvage = { timber = 0, cloth = 0, iron = 0 },
    fittings = { hull = 0, sails = 0, guns = 0, slot = nil },
    blueprints = {},
    blueprintDrops = { sea2 = false, sea5 = false },
    bossFlotsam = {},
    gossipShown = false,
  }
  for id, owned in pairs(meta.data.hats) do
    if owned then M.run.owned[id] = true end
  end
  local cap = M.makePirate('captain', 'CAPPY', 1)
  local mate = M.makePirate('deckhand', 'FIN', 1)
  M.run.crew[1], M.run.crew[2] = cap, mate
  M.run.party[1], M.run.party[2] = cap, mate
  M.run.owners[cap.name] = 'p1'
  if mode == 'captains' then
    -- Distinct name/hat so "which one is mine" reads instantly; a second
    -- deckhand rounds the starting party out to 2+2.
    local cap2 = M.makePirate('captain', 'CASS', 1)
    cap2.out = 'tri'
    M.run.owned.tri = true
    local mate2 = M.makePirate('deckhand', 'RUE', 1)
    M.run.crew[3], M.run.crew[4] = cap2, mate2
    M.run.party[3], M.run.party[4] = cap2, mate2
    M.run.owners[cap2.name] = 'p2'
    M.run.owners[mate2.name] = 'p2'
    M.run.ship2 = { x = 1, y = 4, fx = 1, fy = 4, face = 1, anim = nil }
  end
  M.genSea(1)
end

-- New Voyage+ (5.3): a fresh run that keeps meta (upgrades/hats persist via
-- newGame() itself) but re-seeds the crew from whoever sailed the finished
-- voyage — same names/roles, back to level 1 (attachment carries, power
-- doesn't) — and carries their Best Mates bonds forward.
function M.newGamePlus()
  local prevCrew = {}
  for _, p in ipairs(M.run.crew) do
    prevCrew[#prevCrew + 1] = { role = p.role, name = p.name }
  end
  local prevBonds = M.run.bondsMade
  meta.data.tier = meta.data.tier + 1
  meta.save()
  M.newGame()
  if #prevCrew > 0 then
    M.run.crew, M.run.party = {}, {}
    for i, pc in ipairs(prevCrew) do
      M.run.crew[i] = M.makePirate(pc.role, pc.name, 1)
    end
    for _, p in ipairs(M.run.crew) do
      if p.role == 'captain' then M.run.party[1] = p end
    end
    if not M.run.party[1] then M.run.party[1] = M.run.crew[1] end
    for _, p in ipairs(M.run.crew) do
      if p ~= M.run.party[1] and #M.run.party < M.partyCap() then
        M.run.party[#M.run.party + 1] = p
      end
    end
  end
  M.run.bondsMade = prevBonds or {}
  M.run.metaTier = meta.data.tier
  M.save()
end

function M.partyHas(role)
  for _, p in ipairs(M.run.party) do
    if p.role == role then return p end
  end
  return nil
end

function M.crewHasRole(role)
  for _, p in ipairs(M.run.crew) do
    if p.role == role then return true end
  end
  return false
end

-- TWO CAPTAINS is the only co-op mode.
function M.isCoop()
  return M.run.mode == 'captains'
end

-- Party cap is 3 solo, 4 in co-op (2.3) so P2 always has a pal of their own.
function M.partyCap()
  return M.isCoop() and 4 or 3
end

-- Every pal has an owner (P1/P2) once co-op is on; defaults to P1 so solo
-- saves and pre-co-op crew need no migration.
function M.ownerOf(p)
  return M.run.owners[p.name] or 'p1'
end

-- Crew colors: draw sites go through these two rather than run.colors, so
-- the "default to classic white" fallback lives in exactly one place.
function M.colorOf(player)
  return (M.run.colors and M.run.colors[player or 'p1']) or 'white'
end

function M.palColor(p)
  return M.colorOf(M.ownerOf(p))
end

-- New pals alternate P1/P2 by default so a fresh co-op party splits evenly.
-- nextOwner is the pure "who would get the next pal" read, so recruit cards
-- can show the receiving captain before the player says yes.
function M.nextOwner()
  local p1n, p2n = 0, 0
  for _, q in ipairs(M.run.party) do
    if M.ownerOf(q) == 'p2' then p2n = p2n + 1 else p1n = p1n + 1 end
  end
  return (p2n < p1n) and 'p2' or 'p1'
end

function M.assignOwner(p)
  M.run.owners[p.name] = M.nextOwner()
end

function M.inParty(p)
  for _, q in ipairs(M.run.party) do
    if q == p then return true end
  end
  return false
end

function M.ownedOutfitList()
  local out = {}
  for _, o in ipairs(data.OUTFITS) do
    if M.run.owned[o.id] then out[#out + 1] = o.id end
  end
  return out
end

-- Enemy boarding-party composition scales with sea level. New gimmick
-- enemies (4.3) enter the pool one at a time so "new guy!" is the
-- difficulty beat: crab at sea 3 (twice as likely on icy seas), thief
-- parrot at sea 4 (at most one — one chase per fight is plenty).
-- New Voyage+ (5.3): each meta tier shifts the comp thresholds one sea
-- earlier (capped at +2), so "new guy!" beats land sooner on later voyages.
function M.compFor(lv, biome)
  lv = M.scaleLv(lv) + math.min(2, meta.data.tier or 0)
  local n = math.min(2 + math.floor((lv + 1) / 2), 4)
  local out = { 'grunt' }
  local hasThief = false
  for _ = 2, n do
    local pool = { 'grunt' }
    if lv >= 2 then pool[#pool + 1] = 'gunner' end
    if lv >= 3 then
      pool[#pool + 1] = 'brute'
      pool[#pool + 1] = 'gunner'
      pool[#pool + 1] = 'crab'
      if biome == 'icy' then pool[#pool + 1] = 'crab' end
    end
    if lv >= 4 and not hasThief then pool[#pool + 1] = 'thief' end
    local roleKey = util.pick(pool)
    if roleKey == 'thief' then hasThief = true end
    out[#out + 1] = roleKey
  end
  return out
end

-- run.party holds direct references into run.crew (see M.newGame); the
-- serializer can't preserve object identity, so party is saved as crew
-- indices and rebuilt into references on load. Shared by file save/load
-- and the in-memory snapshot/restore pair (0.6 dev cheat panel).
local function partyToIndices(run)
  local idx = {}
  for i, p in ipairs(run.party) do
    for ci, c in ipairs(run.crew) do
      if c == p then idx[i] = ci; break end
    end
  end
  return idx
end

local function shapeRun(run)
  local shaped = {}
  for k, v in pairs(run) do shaped[k] = v end
  shaped.party = partyToIndices(run)
  return shaped
end

local function unshapeRun(saved)
  local party = {}
  for i, ci in ipairs(saved.party) do party[i] = saved.crew[ci] end
  saved.party = party
  return saved
end

function M.save()
  love.filesystem.write(M.SAVE_PATH, serialize.encode(shapeRun(M.run)))
end

function M.hasSave()
  return love.filesystem.getInfo(M.SAVE_PATH) ~= nil
end

-- Returns true and swaps in the loaded run on success; false leaves M.run
-- untouched (caller falls back to M.newGame()).
function M.load()
  local text = love.filesystem.read(M.SAVE_PATH)
  if not text then return false end
  local saved = serialize.decode(text)
  if not saved or not saved.crew or not saved.party then return false end
  saved.version = saved.version or 1
  saved.voyage = saved.voyage or { sea = (saved.sea and saved.sea.lv) or 1, length = 8 }
  saved.mode = saved.mode or (saved.coop and 'mates' or 'solo')
  saved.owners = saved.owners or {}
  -- First Mate is gone: old 'mates' saves fold into solo, and any pal
  -- owned by P2 reassigns to P1 (the sole remaining captain).
  if saved.mode == 'mates' then
    saved.mode = 'solo'
    for name in pairs(saved.owners) do saved.owners[name] = 'p1' end
  end
  saved.coop = nil
  saved.parrot = nil
  -- A captains save missing ship2 (older field shape) rebuilds it from the
  -- ship's current spot rather than losing the second fleet entirely.
  if saved.mode == 'captains' and not saved.ship2 then
    local sh = saved.ship
    saved.ship2 = { x = sh.x, y = sh.y, fx = sh.x, fy = sh.y, face = 1, anim = nil }
  end
  -- Pre-color-selector saves keep their old look: white sails, and the
  -- green P2 sails shipP2's hull tint used to provide.
  saved.colors = saved.colors or { p1 = 'white', p2 = saved.ship2 and 'green' or nil }
  -- The recruit bench was removed; merge any benched pals from old saves
  -- into the crew (up to the 10 cap) so they aren't stranded.
  if saved.bench then
    for _, p in ipairs(saved.bench) do
      if #saved.crew < 10 then saved.crew[#saved.crew + 1] = p end
    end
    saved.bench = nil
  end
  saved.bonds = saved.bonds or {}
  saved.bondsMade = saved.bondsMade or {}
  saved.log = saved.log or {}
  saved.metaTier = saved.metaTier or 0
  saved.salvage = saved.salvage or {}
  saved.salvage.timber = saved.salvage.timber or 0
  saved.salvage.cloth = saved.salvage.cloth or 0
  saved.salvage.iron = saved.salvage.iron or 0

  saved.fittings = saved.fittings or {}
  saved.fittings.hull = saved.fittings.hull or 0
  saved.fittings.sails = saved.fittings.sails or 0
  saved.fittings.guns = saved.fittings.guns or 0

  saved.blueprints = saved.blueprints or {}
  saved.bossFlotsam = saved.bossFlotsam or {}
  saved.gossipShown = saved.gossipShown or false
  -- One-time migration (5.1): hats used to live only in the per-run save;
  -- fold any already-owned hat into meta so it survives into New Voyage+,
  -- then merge meta's hats back down so hats bought at Home Port show up
  -- on an old run too.
  saved.owned = saved.owned or { none = true }
  for id, owned in pairs(saved.owned) do
    if owned then meta.data.hats[id] = true end
  end
  for id, owned in pairs(meta.data.hats) do
    if owned then saved.owned[id] = true end
  end
  meta.save()
  -- Phase 4 fields: quest/nextBiome legitimately default to nil; the
  -- per-sea biome state needs concrete defaults for pre-biome saves.
  if saved.sea then
    saved.sea.biome = saved.sea.biome or 'calm'
    saved.sea.slick = saved.sea.slick or {}
    saved.sea.rocks = saved.sea.rocks or {}
    saved.sea.rockT = saved.sea.rockT or 2.5
    saved.sea.shipHurt = saved.sea.shipHurt or 0
  end
  saved.blueprintDrops = saved.blueprintDrops or {}
  saved.blueprintDrops.sea2 = saved.blueprintDrops.sea2 or false
  saved.blueprintDrops.sea5 = saved.blueprintDrops.sea5 or false

  M.run = unshapeRun(saved)
  local ok, sprites = pcall(require, 'src.sprites')
  if ok and sprites.buildFittedShip then
    sprites.buildFittedShip(M.colorOf('p1'))
    if M.isCoop() then
      sprites.buildFittedShip(M.colorOf('p2'))
    end
  end
  return true
end

-- In-memory snapshot/restore for the --dev F9/F10 cheat (instant "retry that
-- battle with the same crew"). Round-trips through encode/decode so restore
-- can be pressed repeatedly without the run and the snapshot aliasing.
function M.snapshot()
  M.snap = serialize.encode(shapeRun(M.run))
end

function M.hasSnapshot()
  return M.snap ~= nil
end

function M.restore()
  if not M.snap then return false end
  M.run = unshapeRun(serialize.decode(M.snap))
  return true
end

return M
