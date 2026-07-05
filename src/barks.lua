-- Bark delivery: a floating line + a role motif at battle beats, so
-- pals read as people rather than loadouts. Depends only on data/util/audio/
-- engine/palette -- callers (person_battle + submodules) already know a
-- unit's screen position, so they pass it in rather than barks.lua reaching
-- into person_battle.model (which would make the require graph cyclic).
local data = require 'src.data'
local util = require 'src.util'
local audio = require 'src.audio'
local engine = require 'src.engine'
local palette = require 'src.palette'
local game = require 'src.game'
local CO = palette.CO

local M = {}

local ROLE_COLOR = {
  captain = CO.gold, deckhand = CO.foam, strongman = CO.red,
  sharpshooter = CO.green, medic = CO.blue, king = CO.red,
}

local THROTTLE = 0.9
local lastAt = {}

local function unitKey(unit)
  return unit.id or unit.name
end

-- Shared plumbing for both the per-role M.say and the Pirate-King one-off
-- tables in data.BARKS_KING: throttle per unit, skip while a banner is up
-- (so boss beats like RAGE/SLAM stay readable), float a line, play a motif.
local function deliver(unit, x, y, lines, color, roleKey)
  if not lines or #lines == 0 then return false end
  local key = unitKey(unit)
  local last = lastAt[key]
  if last and engine.gt - last < THROTTLE then return false end
  if engine.banner.t < engine.banner.dur then return false end
  lastAt[key] = engine.gt
  engine.addFloat(x + 8, y - 14, util.pick(lines), color or CO.white, 1)
  audio.motif(roleKey or unit.role)
  return true
end

-- Resolve outfit -> name-override -> role table for `trigger`, then deliver
-- it at pixel position (x, y) -- the caller's own model.px(unit.x, unit.y).
-- Outfit lines (for the 'hatbark' secret) win first; landing one is the
-- secret's find condition, so it's only marked once the line actually plays
-- (not throttled/suppressed).
function M.say(unit, x, y, trigger)
  if not unit or not unit.role then return end
  local byOutfit = unit.out and data.BARKS_BY_OUTFIT[unit.out]
  local outfitLines = byOutfit and byOutfit[trigger]
  if outfitLines then
    if deliver(unit, x, y, outfitLines, ROLE_COLOR[unit.role], unit.role) then
      game.foundSecret('hatbark')
    end
    return
  end
  local byName = data.BARKS_BY_NAME[unit.name]
  local lines = byName and byName[trigger]
  if not lines then
    local roleLines = data.BARKS[unit.role]
    lines = roleLines and roleLines[trigger]
  end
  deliver(unit, x, y, lines, ROLE_COLOR[unit.role], unit.role)
end

-- Pirate-King-only barks (taunt/rage/slam) that live outside the shared
-- trigger grid -- same throttle/banner/motif plumbing, explicit line list.
function M.sayKing(unit, x, y, kind)
  deliver(unit, x, y, data.BARKS_KING[kind], ROLE_COLOR.king, 'king')
end

return M
