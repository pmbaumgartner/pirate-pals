-- Dev script runner: `--script=path.lua` drives the game across
-- frames via a coroutine, so `waitUntil` can block script execution on a
-- predicate instead of the brittle fixed timestamps the old smoke.lua used.
-- `--smoke` is an alias for `--script=src/dev/smoke_script.lua --speed=8`.
--
-- A script file is plain Lua that calls the helpers below directly (they're
-- injected into the chunk's environment, alongside read access to every
-- normal global so `require`/`love`/etc. still work): tap(key), tapCell(x,y),
-- wait(secs), waitUntil(pred, timeout), shot(name), expect(cond, msg),
-- dump(). Loaded with io.open/load (not love.filesystem) so scripts can live
-- anywhere on disk, e.g. a scratch dir outside the game's source tree.
local input = require 'src.input'
local bounds = require 'src.dev.bounds'
local readability = require 'src.dev.readability'

local M = { t = 0, dt = 0, shotsOn = false, frame = 0, readabilityMode = nil }

-- Baton (src/input.lua) polls love.keyboard.isDown instead of consuming
-- key events, so tap() injects presses by ORing a set of scripted-held
-- keys into isDown; this wrapper only ever exists in script runs (this
-- module is never in the default require graph).
local scriptKeys = {}
local realIsDown = love.keyboard.isDown
love.keyboard.isDown = function(...)
  for i = 1, select('#', ...) do
    if scriptKeys[select(i, ...)] then return true end
  end
  return realIsDown(...)
end

-- LÖVE's default error handler shows an interactive "press a key to quit"
-- screen rather than exiting, which would hang forever under xvfb-run/CI.
-- Every script-driven failure path routes through here instead, so --smoke
-- and --script always exit(1) cleanly with a FAIL: line.
local function fail(msg)
  print('FAIL: ' .. msg)
  love.event.quit(1)
end

local function tap(key)
  scriptKeys[key] = true
  coroutine.yield()
  scriptKeys[key] = nil
  coroutine.yield()
end

-- Injects into P2's context directly by logical name (up/down/left/right/
-- a/b), regardless of coop state or keymap — unlike tap(), which only
-- reaches P2 for arrows/n/m and only once coop is on.
local P2_KEYS = { up = 'up', down = 'down', left = 'left', right = 'right', a = 'n', b = 'm' }
local function tap2(name)
  local key = P2_KEYS[name] or name
  tap(key)
end

-- Mirrors sail_map.lua's hex layout (SEA_OX 4, row pitch 13, row-0 centers at
-- y 40) to aim a canvas tap at a cell; update if that layout changes.
local function tapCell(x, y)
  local cx = 4 + x * 16 + (y % 2) * 8 + 8
  local cy = 40 + y * 13
  input.pointerDown('script', cx, cy, false)
  coroutine.yield()
  input.pointerUp('script')
  coroutine.yield()
end

local function wait(secs)
  local t = 0
  while t < secs do
    coroutine.yield()
    t = t + M.dt
  end
end

-- On timeout, fails the run (print + quit) rather than erroring — an
-- uncaught error would otherwise hit LÖVE's interactive error screen.
local function waitUntil(pred, timeout)
  local waited = 0
  while not pred() do
    coroutine.yield()
    waited = waited + M.dt
    if timeout and waited >= timeout then
      fail('waitUntil timed out after ' .. timeout .. 's')
      return
    end
  end
end

-- Under --speed=N, love.update runs N ticks (and thus N script-coroutine
-- resumes) per love.draw. Yielding until M.frame ticks over (incremented
-- once per love.draw, in main.lua) guarantees a frame reflecting this
-- script line has actually been drawn; only then is the native 320x180
-- canvas (handed over by main.lua) read back — scale-independent, unlike
-- capturing the scaled window backbuffer.
local function shot(name)
  if not M.shotsOn then return end
  local frameAtCapture = M.frame
  while M.frame == frameAtCapture do
    coroutine.yield()
  end
  local fname = name .. '.png'
  M.canvas:newImageData():encode('png', fname)
  print('SHOT ' .. love.filesystem.getSaveDirectory() .. '/' .. fname)
end

local function expect(cond, msg)
  if not cond then fail(msg) end
end

local function dump()
  return require('src.dev.dump').dump()
end

local ENV_FUNCS = {
  tap = tap, tap2 = tap2, tapCell = tapCell, wait = wait, waitUntil = waitUntil,
  shot = shot, expect = expect, dump = dump,
}

function M.load(path)
  local f, err = io.open(path, 'r')
  if not f then return fail('cannot open script: ' .. tostring(err)) end
  local src = f:read('a')
  f:close()

  local env = setmetatable({ shotsOn = M.shotsOn }, { __index = _G })
  for k, v in pairs(ENV_FUNCS) do env[k] = v end
  local chunk, cerr = load(src, '@' .. path, 't', env)
  if not chunk then return fail('script error: ' .. cerr) end

  M.co = coroutine.create(chunk)
end

-- Per-callsite minimum contrast seen so far; --readability=log prints a
-- READABILITY-MIN line on each new minimum, so one smoke run yields a
-- greppable census of the dimmest text in the game.
local minRatios = {}

-- Records were produced during the last love.draw and the native canvas
-- still holds exactly that frame (it isn't cleared until the next draw), so
-- the tier-2 readback matches the records. Under --speed=N records are
-- non-empty on at most one tick in N.
local function checkReadability()
  local records = bounds.takeRecords()
  if #records == 0 then return end
  local img
  if M.canvas and (#records > 1 or readability.needsPixels(records)) then
    img = M.canvas:newImageData()
  end
  local viols = readability.checkOverlaps(records, img)
  local stats = M.readabilityMode == 'log' and {} or nil
  local cviols = readability.checkContrast(records, img, stats)
  for _, v in ipairs(cviols) do viols[#viols + 1] = v end
  if stats then
    for _, st in ipairs(stats) do
      if not minRatios[st.src] or st.ratio < minRatios[st.src] then
        minRatios[st.src] = st.ratio
        print(string.format('READABILITY-MIN %s ratio=%.2f "%s"', st.src, st.ratio, st.s))
      end
    end
  end
  if #viols > 0 then
    if M.readabilityMode == 'log' then
      print('READABILITY: ' .. table.concat(viols, '; '))
    else
      fail('text readability: ' .. table.concat(viols, '; '))
      return true
    end
  end
end

function M.update(dt)
  M.t = M.t + dt
  M.dt = dt
  -- Violations were recorded during the last love.draw; failing here (the
  -- next tick) still names every offender from that frame in one line.
  local offenders = bounds.flush()
  if #offenders > 0 then
    fail('text out of bounds: ' .. table.concat(offenders, '; '))
    return
  end
  if checkReadability() then return end
  if M.co and coroutine.status(M.co) ~= 'dead' then
    local ok, err = coroutine.resume(M.co)
    if not ok then fail(tostring(err)) end
  end
end

return M
