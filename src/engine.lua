-- Engine core: state registry + shared juice (floating text, particles,
-- screen shake, banner, iris transition). Each state is a table with
-- optional enter(arg), plus update(dt) and draw(); states register
-- themselves into engine.states at require time.
local util = require 'src.util'
local palette = require 'src.palette'
local font = require 'src.font'
local CO = palette.CO
local gfx = love.graphics

local VW, VH = 320, 180

local M = {
  states = {},
  cur = 'title',
  gt = 0, -- global clock, drives all idle animation
  floaters = {},
  parts = {},
  shake = { t = 0, mag = 0 },
  trans = { on = false, t = 0, text = '', cb = nil, called = true },
  banner = { text = '', t = 9, dur = 0, color = CO.white },
  toast = { text = '', t = 9, dur = 0, color = CO.white },
}

function M.setState(name, arg)
  M.floaters = {}
  M.parts = {}
  M.banner = { text = '', t = 9, dur = 0, color = CO.white }
  M.cur = name
  local st = assert(M.states[name], 'unknown state: ' .. tostring(name))
  if st.enter then st.enter(arg) end
end

-- Iris wipe: closes, fires cb at the midpoint (swap states there), reopens.
function M.transition(text, cb)
  M.trans = { on = true, t = 0, text = text or '', cb = cb, called = false }
end

function M.showBanner(text, color, dur)
  M.banner = { text = text, t = 0, dur = dur or 1.1, color = color or CO.gold }
end

-- Small top-right corner notice for system feedback (mute toggle, dev
-- cheats) that shouldn't cover the playfield the way showBanner does.
function M.showToast(text, color, dur)
  M.toast = { text = text, t = 0, dur = dur or 1.1, color = color or CO.gold }
end

function M.addFloat(x, y, text, color, sc)
  -- Bump up past any live floater nearby so stacked spawns ("-5" then
  -- "+XP" on the same unit) never pile onto each other. Floor at y=16: a
  -- floater rises ~13px over its life and text may never leave the canvas
  -- (the scripted-run bounds invariant), so a tall stack re-overlaps at the
  -- ceiling instead of drawing above y=0.
  -- Same invariant horizontally: a floater near a canvas edge (e.g. a bark
  -- over a ship on the leftmost sea column) slides inward instead of
  -- clipping. +-2 covers the outline pass and the backing strip.
  local w = font.textWidth(text, sc or 1)
  local half = math.floor(w / 2)
  x = math.max(half + 2, math.min(x, VW - (w - half) - 2))
  local bumped = true
  while bumped do
    bumped = false
    for _, f in ipairs(M.floaters) do
      if y > 16 and math.abs(f.x - x) < 10 and math.abs(f.y - y) < 7 then
        y = math.max(f.y - 7, 16)
        bumped = true
      end
    end
  end
  M.floaters[#M.floaters + 1] = { x = x, y = y, text = text, color = color or CO.white, sc = sc or 1, t = 0, dur = 0.9 }
end

function M.addParts(x, y, n, color, spd, grav)
  for _ = 1, n do
    local a = love.math.random() * math.pi * 2
    local v = (0.3 + love.math.random()) * (spd or 30)
    M.parts[#M.parts + 1] = {
      x = x, y = y, vx = math.cos(a) * v, vy = math.sin(a) * v,
      t = 0, dur = 0.35 + love.math.random() * 0.3,
      color = color or CO.gold, grav = grav or 0,
    }
  end
end

function M.shakeIt(mag, dur)
  M.shake.mag = mag
  M.shake.t = dur
end

function M.updateFx(dt)
  for i = #M.floaters, 1, -1 do
    local f = M.floaters[i]
    f.t = f.t + dt
    f.y = f.y - dt * 14
    if f.t > f.dur then table.remove(M.floaters, i) end
  end
  for i = #M.parts, 1, -1 do
    local p = M.parts[i]
    p.t = p.t + dt
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    p.vy = p.vy + p.grav * dt
    if p.t > p.dur then table.remove(M.parts, i) end
  end
  if M.shake.t > 0 then M.shake.t = M.shake.t - dt end
  if M.banner.t < M.banner.dur + 0.4 then M.banner.t = M.banner.t + dt end
  if M.toast.t < M.toast.dur + 0.4 then M.toast.t = M.toast.t + dt end
  local tr = M.trans
  if tr.on then
    tr.t = tr.t + dt
    if tr.t >= 0.32 and not tr.called then
      tr.called = true
      if tr.cb then tr.cb() end
    end
    if tr.t >= 1.2 then tr.on = false end
  end
end

function M.drawFx()
  for _, p in ipairs(M.parts) do
    gfx.setColor(p.color)
    local s = (p.t / p.dur < 0.6) and 2 or 1
    gfx.rectangle('fill', util.round(p.x), util.round(p.y), s, s)
  end
  local FLOAT_BACKING = true -- ink strip behind floaters; toggle off if it reads too heavy
  for _, f in ipairs(M.floaters) do
    local fx, fy = util.round(f.x), util.round(f.y)
    if FLOAT_BACKING then
      local w = font.textWidth(f.text, f.sc)
      gfx.setColor(CO.ink[1], CO.ink[2], CO.ink[3], 0.5)
      gfx.rectangle('fill', fx - math.floor(w / 2) - 2, fy - 1, w + 4, 5 * f.sc + 2)
    end
    font.drawTextO(f.text, fx, fy, f.color, f.sc, 'center')
  end
end

function M.drawBanner()
  local b = M.banner
  if b.t >= b.dur then return end
  local a
  if b.t < 0.15 then a = b.t / 0.15
  elseif b.t > b.dur - 0.25 then a = (b.dur - b.t) / 0.25
  else a = 1 end
  a = util.clamp(a, 0, 1)
  gfx.setColor(CO.ink[1], CO.ink[2], CO.ink[3], a * 0.85)
  gfx.rectangle('fill', 0, 66, VW, 26)
  local c = b.color
  font.drawText(b.text, VW / 2, 74, { c[1], c[2], c[3], a }, 2, 'center')
end

function M.drawToast()
  local b = M.toast
  if b.t >= b.dur then return end
  local a
  if b.t < 0.15 then a = b.t / 0.15
  elseif b.t > b.dur - 0.25 then a = (b.dur - b.t) / 0.25
  else a = 1 end
  a = util.clamp(a, 0, 1)
  local c = b.color
  font.drawTextO(b.text, VW - 4, 22, { c[1], c[2], c[3], a }, 1, 'right')
end

function M.drawTrans()
  local tr = M.trans
  if not tr.on then return end
  local t = tr.t
  local a
  if t < 0.32 then a = t / 0.32
  elseif t < 0.82 then a = 1
  else a = 1 - (t - 0.82) / 0.38 end
  a = util.clamp(a, 0, 1)
  local h = util.round(util.ease(a) * (VH / 2 + 2))
  gfx.setColor(CO.ink)
  gfx.rectangle('fill', 0, 0, VW, h)
  gfx.rectangle('fill', 0, VH - h, VW, h)
  if a > 0.9 and tr.text ~= '' then
    font.drawText(tr.text, VW / 2, VH / 2 - 5, CO.gold, 2, 'center')
  end
end

return M
