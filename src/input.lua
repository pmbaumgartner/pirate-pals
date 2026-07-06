-- Input seam: keyboard, gamepad, and on-screen touch buttons all collapse
-- into named logical buttons with edge detection (jp), key-repeat (rp),
-- and a movement helper (moveVector). Game code never touches raw devices.
--
-- Device polling is delegated to baton (src/lib/baton.lua, vendored): each
-- player context wraps a baton player whose config is the single source of
-- truth for bindings — UI prompt strings read the bound key via
-- M.promptKey rather than hardcoding 'Z'/'N'. Hand-rolled on top of baton:
-- key-repeat (rp), the touch layer (baton has none), and the
-- moveVector/moveDir priority helpers.
--
-- Two independent player contexts (M.p1/M.p2) each carry the full API
-- (jp/rp/moveVector/moveDir). Top-level M.jp/M.rp/etc are a back-compat
-- shim delegating to P1 (OR'ing P2 for 'a'/'b' so menus/loot stay
-- advanceable by either player) — existing single-player states keep
-- working unmodified.
local palette = require 'src.palette'
local font = require 'src.font'
local baton = require 'src.lib.baton'
local CO = palette.CO
local gfx = love.graphics

local REPEAT_DELAY, REPEAT_RATE = 0.3, 0.11

-- WASD+ZX are always P1. Arrow keys are P1-aliased (the "WASD and arrows
-- are aliases" behavior) until P2 joins; N/M are always P2's a/b.
local function p1Controls(withArrows)
  local c = {
    up = { 'key:w', 'button:dpup', 'axis:lefty-' },
    down = { 'key:s', 'button:dpdown', 'axis:lefty+' },
    left = { 'key:a', 'button:dpleft', 'axis:leftx-' },
    right = { 'key:d', 'button:dpright', 'axis:leftx+' },
    a = { 'key:z', 'key:space', 'key:return', 'key:kpenter', 'button:a' },
    b = { 'key:x', 'key:escape', 'key:backspace', 'button:b' },
    crew = { 'key:c' }, log = { 'key:t' }, mute = { 'key:m' },
    voyage = { 'key:v' }, vlog = { 'key:l' },
  }
  if withArrows then
    table.insert(c.up, 2, 'key:up')
    table.insert(c.down, 2, 'key:down')
    table.insert(c.left, 2, 'key:left')
    table.insert(c.right, 2, 'key:right')
  end
  return c
end

local function p2Controls()
  return {
    up = { 'key:up', 'button:dpup', 'axis:lefty-' },
    down = { 'key:down', 'button:dpdown', 'axis:lefty+' },
    left = { 'key:left', 'button:dpleft', 'axis:leftx-' },
    right = { 'key:right', 'button:dpright', 'axis:leftx+' },
    a = { 'key:n', 'button:a' },
    b = { 'key:m', 'button:b' },
  }
end

local function newCtx(names, controls, joystick)
  local ctx = {
    touch = {},
    held = {}, prev = {}, pressed = {},
    ht = {}, rep = {},
    names = names,
    player = baton.new({ controls = controls, joystick = joystick }),
  }

  function ctx.jp(n) return ctx.pressed[n] and true or false end -- just pressed
  function ctx.rp(n) return ctx.rep[n] and true or false end     -- pressed or repeating

  function ctx.moveVector(useRepeat)
    local f = useRepeat and ctx.rep or ctx.pressed
    if f.left then return { -1, 0 } end
    if f.right then return { 1, 0 } end
    if f.up then return { 0, -1 } end
    if f.down then return { 0, 1 } end
    return nil
  end

  -- Like moveVector but returns the direction name; callers that translate
  -- presses into non-square steps (hex sailing) need the intent, not a delta.
  function ctx.moveDir(useRepeat)
    local f = useRepeat and ctx.rep or ctx.pressed
    if f.left then return 'left' end
    if f.right then return 'right' end
    if f.up then return 'up' end
    if f.down then return 'down' end
    return nil
  end

  return ctx
end

local P1_NAMES = { 'up', 'down', 'left', 'right', 'a', 'b', 'crew', 'log', 'mute', 'voyage', 'vlog' }
local P2_NAMES = { 'up', 'down', 'left', 'right', 'a', 'b' }

local M = {
  touchUI = false,
  coop = false,
  jsSlot = {}, -- [1]/[2] = assigned joystick objects
}
M.p1 = newCtx(P1_NAMES, p1Controls(true))
M.p2 = newCtx(P2_NAMES, p2Controls())

-- The bound-key display string for a context's action ('Z', 'N', 'M', ...),
-- or the pad button name when that player is actively on a gamepad. UI
-- prompt strings must build from this, never from hardcoded key letters.
function M.promptKey(ctx, action)
  local player = ctx.player
  local sources = player.config.controls[action]
  if not sources then return '?' end
  -- luacov: disable
  if player:getActiveDevice() == 'joy' then
    for _, src in ipairs(sources) do
      local b = src:match('^button:(.+)$')
      if b then return b:upper() end
    end
  end
  -- luacov: enable
  for _, src in ipairs(sources) do
    local k = src:match('^key:(.+)$')
    if k then return k:upper() end
  end
  return '?'
end

-- On-screen buttons, in virtual-canvas coordinates. Touch stays P1-only.
local TBTN = {
  { n = 'up',    x = 19,  y = 126, w = 22, h = 17 },
  { n = 'down',  x = 19,  y = 161, w = 22, h = 17 },
  { n = 'left',  x = 1,   y = 143, w = 17, h = 19 },
  { n = 'right', x = 42,  y = 143, w = 17, h = 19 },
  { n = 'a',     x = 286, y = 138, w = 29, h = 29 },
  { n = 'b',     x = 256, y = 152, w = 23, h = 23 },
}
local pointerMap = {}
local pendingTap = nil

-- Toggling coop rebuilds P1's baton player without the arrow-key sources,
-- so a held arrow at the moment of joining drops off P1 cleanly (the fresh
-- player starts with no down state).
function M.setCoop(v)
  M.coop = v and true or false
  M.p1.player = baton.new({ controls = p1Controls(not M.coop), joystick = M.jsSlot[1] })
end

-- Baton polls love.keyboard.isDown each frame, so these are no longer part
-- of the input path; kept because main.lua (and dev scripts) still call
-- them, and so a future event-driven need has its seam.
function M.keypressed(_key) end
function M.keyreleased(_key) end

-- (cx, cy) are virtual-canvas coordinates; anywhere off a button acts as 'a'
-- and is also reported as a positional tap (M.tap) for one frame.
function M.pointerDown(id, cx, cy, isTouch)
  if isTouch then M.touchUI = true end
  local hit = nil
  -- luacov: disable
  for _, t in ipairs(TBTN) do
    if cx >= t.x and cx < t.x + t.w and cy >= t.y and cy < t.y + t.h then
      hit = t.n
      break
    end
  end
  -- luacov: enable
  if not hit then
    hit = 'a'
    pendingTap = { x = cx, y = cy }
  end
  pointerMap[id] = hit
  M.p1.touch[hit] = true
end

function M.pointerUp(id)
  local n = pointerMap[id]
  if n then
    M.p1.touch[n] = false
    pointerMap[id] = nil
  end
end

-- Device assignment: first joystick connected -> P1, second -> P2. Wired
-- from main.lua's love.joystickadded/removed so slots survive an
-- unrelated pad's getJoysticks() index shifting on removal.
-- luacov: disable
function M.joystickadded(js)
  if M.jsSlot[1] == nil then M.jsSlot[1] = js
  elseif M.jsSlot[2] == nil then M.jsSlot[2] = js end
  M.p1.player.config.joystick = M.jsSlot[1]
  M.p2.player.config.joystick = M.jsSlot[2]
end

function M.joystickremoved(js)
  if M.jsSlot[1] == js then M.jsSlot[1] = nil end
  if M.jsSlot[2] == js then M.jsSlot[2] = nil end
  M.p1.player.config.joystick = M.jsSlot[1]
  M.p2.player.config.joystick = M.jsSlot[2]
end

-- Joysticks already connected before love.load runs don't fire
-- joystickadded, so main.lua calls this once at boot to pick them up.
function M.scanJoysticks()
  for _, js in ipairs(love.joystick.getJoysticks()) do
    M.joystickadded(js)
  end
end
-- luacov: enable

local function updateCtx(ctx, dt)
  ctx.player:update()
  for _, n in ipairs(ctx.names) do
    local h = (ctx.player:down(n) or ctx.touch[n]) and true or false
    ctx.pressed[n] = h and not ctx.prev[n]
    ctx.held[n] = h
    ctx.prev[n] = h
    if h then ctx.ht[n] = (ctx.ht[n] or 0) + dt else ctx.ht[n] = 0 end
    local r = false
    if ctx.pressed[n] then
      r = true
    elseif h and ctx.ht[n] > REPEAT_DELAY then
      local q = ctx.ht[n] - REPEAT_DELAY
      if math.floor(q / REPEAT_RATE) ~= math.floor((q - dt) / REPEAT_RATE) then r = true end
    end
    ctx.rep[n] = r
  end
end

function M.update(dt)
  -- Positional taps live for exactly one frame; states read M.tap directly.
  M.tap = pendingTap
  pendingTap = nil
  updateCtx(M.p1, dt)
  updateCtx(M.p2, dt)
end

function M.jp(n)
  if M.p1.pressed[n] then return true end
  if (n == 'a' or n == 'b') and M.p2.pressed[n] then return true end
  return false
end

function M.rp(n)
  if M.p1.rep[n] then return true end
  if (n == 'a' or n == 'b') and M.p2.rep[n] then return true end
  return false
end

function M.moveVector(useRepeat) return M.p1.moveVector(useRepeat) end
function M.moveDir(useRepeat) return M.p1.moveDir(useRepeat) end

-- luacov: disable
function M.drawTouchUI()
  if not M.touchUI then return end
  for _, t in ipairs(TBTN) do
    local c = M.p1.held[t.n] and CO.gold or CO.uiBg
    gfx.setColor(c[1], c[2], c[3], 0.45)
    gfx.rectangle('fill', t.x, t.y, t.w, t.h)
    gfx.setColor(CO.white[1], CO.white[2], CO.white[3], 0.45)
    gfx.rectangle('fill', t.x, t.y, t.w, 1)
    gfx.rectangle('fill', t.x, t.y + t.h - 1, t.w, 1)
    gfx.rectangle('fill', t.x, t.y, 1, t.h)
    gfx.rectangle('fill', t.x + t.w - 1, t.y, 1, t.h)
  end
  font.drawText('<', TBTN[3].x + 6, TBTN[3].y + 7, CO.white, 1)
  font.drawText('>', TBTN[4].x + 6, TBTN[4].y + 7, CO.white, 1)
  gfx.setColor(CO.white)
  local tcx = TBTN[1].x + 11
  for tr = 0, 3 do
    gfx.rectangle('fill', tcx - tr, TBTN[1].y + 6 + tr, tr * 2 + 1, 1)
    gfx.rectangle('fill', tcx - tr, TBTN[2].y + 10 - tr, tr * 2 + 1, 1)
  end
  font.drawText('A', TBTN[5].x + 12, TBTN[5].y + 12, CO.white, 1)
  font.drawText('B', TBTN[6].x + 9, TBTN[6].y + 9, CO.white, 1)
end
-- luacov: enable

return M
