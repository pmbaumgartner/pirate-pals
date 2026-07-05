-- Meta save (5.1): a second save file, alongside save.lua, for progress that
-- survives across voyages — banked gold, permanent ship upgrades, owned
-- hats, and voyage-completion counters. `M.data` is plain data (same
-- constraint as game.run) so it round-trips through serialize.lua.
local serialize = require 'src.serialize'

local M = {}

M.SAVE_PATH = 'meta.lua'

-- Ship upgrades (5.2), bought at Home Port with banked gold. Costs are
-- per-tier (costs[tier+1] is the price of the next tier); `max` caps tiers.
M.UPGRADES = {
  figurehead = { name = 'FIGUREHEAD', desc = '+10 SHIP HP PER TIER', costs = { 60, 140, 260 }, max = 3 },
  sails = { name = 'BETTER SAILS', desc = 'FREE DODGE EACH FIGHT', costs = { 80, 180 }, max = 2 },
  cook = { name = "SHIP'S COOK", desc = 'PATCHES UP TUCKERED PALS', costs = { 70, 160, 300 }, max = 3 },
  steady = { name = 'STEADY HANDS', desc = 'THE WHEEL FIGHTS LESS!', costs = { 50, 120 }, max = 2 },
}

-- STEADY HANDS: a bought ship part, not a difficulty mode
-- — widens timing.cfg's good/perfect windows and, at tier 2, slows the
-- sweep. Fed straight into every timing.start/startCoop cfg() call.
local STEADY_MULT = {
  [0] = { win = 1, sweep = 1 },
  [1] = { win = 1.25, sweep = 1 },
  [2] = { win = 1.5, sweep = 1.15 },
}

function M.steadyMult()
  return STEADY_MULT[M.data.upgrades.steady or 0]
end

local function defaultData()
  return {
    version = 1,
    gold = 0,
    upgrades = { figurehead = 0, sails = 0, cook = 0, steady = 0 },
    hats = { none = true },
    voyagesWon = 0,
    tier = 0,
    golden = false,
    legends = {},
    secrets = {},
  }
end

-- A fresh default so requiring this module never leaves M.data nil, even
-- before load() runs (mirrors game.lua's newGame()-before-load ordering).
M.data = defaultData()

function M.newMeta()
  M.data = defaultData()
end

function M.hasSave()
  return love.filesystem.getInfo(M.SAVE_PATH) ~= nil
end

-- Returns true and swaps in the loaded meta on success; false leaves a fresh
-- default in M.data (caller doesn't need to branch, unlike game.load()).
function M.load()
  local text = love.filesystem.read(M.SAVE_PATH)
  if not text then M.newMeta(); return false end
  local saved = serialize.decode(text)
  if not saved then M.newMeta(); return false end
  saved.version = saved.version or 1
  saved.gold = saved.gold or 0
  saved.upgrades = saved.upgrades or {}
  saved.upgrades.figurehead = saved.upgrades.figurehead or 0
  saved.upgrades.sails = saved.upgrades.sails or 0
  saved.upgrades.cook = saved.upgrades.cook or 0
  saved.upgrades.steady = saved.upgrades.steady or 0
  saved.hats = saved.hats or { none = true }
  saved.voyagesWon = saved.voyagesWon or 0
  saved.tier = saved.tier or 0
  saved.golden = saved.golden or false
  saved.legends = saved.legends or {}
  saved.secrets = saved.secrets or {}
  M.data = saved
  return true
end

function M.save()
  love.filesystem.write(M.SAVE_PATH, serialize.encode(M.data))
end

function M.shipMaxHp()
  return 30 + (M.data.upgrades.figurehead or 0) * 10
end

function M.hasFreeDodge()
  return (M.data.upgrades.sails or 0) > 0
end

function M.cookTier()
  return M.data.upgrades.cook or 0
end

return M
