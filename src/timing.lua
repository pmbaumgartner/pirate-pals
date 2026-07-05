-- Timing-bar minigame (attack + block). A marker ping-pongs across the bar
-- until the player presses A near the center for 'good'/'perfect'; after
-- MAX_SWEEPS one-way passes it auto-resolves (timeoutRes) so an unattended
-- parry prompt can never soft-lock a turn. The result is delivered to the
-- callback passed to start(). update() takes the pressed edge as a
-- parameter so the wave/window/timeout logic stays pure and testable.
local util = require 'src.util'
local palette = require 'src.palette'
local font = require 'src.font'
local engine = require 'src.engine'
local CO = palette.CO
local gfx = love.graphics

local VW = 320

local M = { on = false, coopMode = false, player = nil }

-- Tuning (design-gaps/04): the good window is a constant floor an adult
-- always reaches, not a scaling target — sweep speed carries the (mild)
-- difficulty curve and only 'perfect' tightens with sea level. Do not
-- reintroduce a per-level good-window shrink; that's the exact thing this
-- policy removed.
local SWEEP_BASE = 2.0   -- seconds per one-way sweep at level 0
local SWEEP_PER_LV = 0.03
local SWEEP_MIN = 1.5
M.MAX_SWEEPS = 6         -- one-way passes before auto-resolve (~12+ s)
local GOOD_WINDOW = 0.30
local PARRY_GOOD_WINDOW = 0.37
local PERF_BASE = 0.10
local PERF_MIN = 0.07
local PERF_PER_LV = 0.003
local MASH_MULT = 1.5   -- offset beyond good*this counts as "mashing zone"
local MASH_LOCKOUT_T = 0.4
local MASH_MAX_LOCKOUTS = 2

-- `mult` (STEADY HANDS) is an optional { win = , sweep = } table widening
-- windows and/or slowing the sweep; both default to 1 (no change).
function M.cfg(lv, parry, mult)
  mult = mult or {}
  local winMult, sweepMult = mult.win or 1, mult.sweep or 1
  local dur = math.max(SWEEP_MIN, SWEEP_BASE - lv * SWEEP_PER_LV) * sweepMult
  local good = (parry and PARRY_GOOD_WINDOW or GOOD_WINDOW) * winMult
  local perf = math.max(PERF_MIN, PERF_BASE - lv * PERF_PER_LV) * winMult
  if parry then dur = dur * 0.85 end
  return { dur = dur, good = good, perf = perf }
end

-- Triangle wave: 0 -> 1 -> 0 -> ..., one-way sweep takes dur seconds.
function M.posAt(t, dur)
  local phase = (t / dur) % 2
  return phase <= 1 and phase or 2 - phase
end

function M.classify(pos, good, perf)
  local off = math.abs(pos - 0.5)
  if off <= perf / 2 then return 'perfect' end
  if off <= good / 2 then return 'good' end
  return 'miss'
end

-- timeoutRes is the result delivered if the bar is never pressed; call
-- sites pick their own fallback ('good' for attacks, 'miss' for parries).
-- `player` ('p1'/'p2'/nil) records whose confirm button the call site
-- should read this round (2.3/2.4 co-op ownership); nil means "don't care"
-- (solo play, or an unowned actor).
function M.start(cfg, label, cb, timeoutRes, player)
  M.on = true
  M.t = 0
  M.dur, M.good, M.perf = cfg.dur, cfg.good, cfg.perf
  M.label, M.cb = label, cb
  M.timeoutRes = timeoutRes or 'miss'
  M.player = player
  M.lockT, M.lockouts = 0, 0
end

-- Returns true while the minigame owns input for this frame; pressed is
-- the confirm edge (the call site passes input.jp('a')).
-- Anti-mash tooth (design-gaps/04): pressing while the marker is way
-- outside the good window doesn't resolve, it greys the bar briefly and
-- lets the sweep continue — mashing delays the result instead of
-- harvesting random 'good's. Capped so a frustrated kid still resolves.
function M.update(dt, pressed)
  if not M.on then return false end
  if M.lockT > 0 then
    M.lockT = math.max(0, M.lockT - dt)
  elseif pressed then
    local pos = M.posAt(M.t, M.dur)
    local off = math.abs(pos - 0.5)
    if off > M.good * MASH_MULT and M.lockouts < MASH_MAX_LOCKOUTS then
      M.lockouts = M.lockouts + 1
      M.lockT = MASH_LOCKOUT_T
      engine.addFloat(VW / 2, 100, 'TOO SOON!', CO.gray, 1)
    else
      M.on = false
      M.cb(M.classify(pos, M.good, M.perf))
      return true
    end
  end
  M.t = M.t + dt
  if M.t >= M.dur * M.MAX_SWEEPS then
    M.on = false
    M.cb(M.timeoutRes)
  end
  return true
end

-- Two-player "BOTH PRESS!" mode (2.4): one shared marker, but each player's
-- press is classified from their own press time and doesn't end the round —
-- an early P1 press must not cut off P2's shot. Resolves (calling cb with
-- both results) once both have pressed, or on timeout.
function M.startCoop(cfg, label, cb, timeoutRes)
  M.on = true
  M.coopMode = true
  M.t = 0
  M.dur, M.good, M.perf = cfg.dur, cfg.good, cfg.perf
  M.label, M.cb = label, cb
  M.timeoutRes = timeoutRes or 'miss'
  M.p1Res, M.p2Res = nil, nil
  M.lockT = 0
end

-- Returns true while the minigame owns input for this frame.
function M.updateCoop(dt, p1Pressed, p2Pressed)
  if not M.on then return false end
  if p1Pressed and not M.p1Res then
    M.p1Res = M.classify(M.posAt(M.t, M.dur), M.good, M.perf)
  end
  if p2Pressed and not M.p2Res then
    M.p2Res = M.classify(M.posAt(M.t, M.dur), M.good, M.perf)
  end
  M.t = M.t + dt
  local timedOut = M.t >= M.dur * M.MAX_SWEEPS
  if timedOut or (M.p1Res and M.p2Res) then
    M.on = false
    M.coopMode = false
    M.cb(M.p1Res or M.timeoutRes, M.p2Res or M.timeoutRes)
  end
  return true
end

function M.draw()
  if not M.on then return end
  local w, h = 150, 12
  local x, y = (VW - w) / 2, 118
  gfx.setColor(CO.ink)
  gfx.rectangle('fill', x - 3, y - 12, w + 6, h + 18)
  font.drawText(M.label, VW / 2, y - 9, CO.paper, 1, 'center')
  gfx.setColor(CO.grayD)
  gfx.rectangle('fill', x, y, w, h)
  local gw, pw = util.round(M.good * w), util.round(M.perf * w)
  gfx.setColor(CO.gold)
  gfx.rectangle('fill', x + (w - gw) / 2, y, gw, h)
  gfx.setColor(CO.green)
  gfx.rectangle('fill', x + (w - pw) / 2, y, pw, h)
  local mx = x + util.round(M.posAt(M.t, M.dur) * (w - 2))
  gfx.setColor(M.lockT > 0 and CO.gray or CO.white)
  gfx.rectangle('fill', mx, y - 2, 2, h + 4)
  if M.coopMode then
    if M.p1Res then font.drawText('P1 ' .. M.p1Res:upper() .. '!', x, y + h + 8, CO.gold, 1) end
    if M.p2Res then font.drawText('P2 ' .. M.p2Res:upper() .. '!', x + w, y + h + 8, CO.green, 1, 'right') end
  end
end

return M
