-- Visual invariants (dev-only, loaded by script.lua): no text may draw
-- outside the 320x180 canvas, and every text call is recorded per frame so
-- script.lua can run the readability checks (src/dev/readability.lua).
-- Every text call site flows through font.drawText (drawTextO included — it
-- calls drawText twice), so wrapping that one function covers all of them.
-- Violations/records are collected here and flushed by script.lua once per
-- tick, so a failing frame reports every offender at once through the
-- FAIL:-and-exit path (never LÖVE's interactive error screen). Intentional
-- transients (slide-ins etc.) must be clamped in game code, not allowlisted
-- here — the invariants are absolute.
local font = require 'src.font'
local engine = require 'src.engine'
local input = require 'src.input'
local gfx = love.graphics

local VW, VH = 320, 180

local M = { violations = {}, records = {} }

-- Overlay layers are entered by wrapping their draw entry points (drawFx is
-- called from inside each state's draw, so a main.lua phase flag couldn't
-- tag floaters). Cross-layer text overlap is exempt by design: layer order
-- is fixed and each later layer paints its own ink backing.
local curLayer = 'state'
local function wrapLayer(mod, key, name)
  local orig = mod[key]
  mod[key] = function(...)
    local prev = curLayer
    curLayer = name
    orig(...)
    curLayer = prev
  end
end
wrapLayer(engine, 'drawFx', 'floaters')
wrapLayer(engine, 'drawBanner', 'banner')
wrapLayer(engine, 'drawToast', 'toast')
wrapLayer(engine, 'drawTrans', 'trans')
wrapLayer(input, 'drawTouchUI', 'touch')

-- First frame above bounds.lua/font.lua is the real callsite (drawTextO
-- routes game code through font.lua and back through the wrapper here).
local function callsite()
  for lvl = 3, 12 do
    local info = debug.getinfo(lvl, 'Sl')
    if not info then break end
    local src = info.short_src
    if not (src:find('src/font%.lua$') or src:find('src/dev/bounds%.lua$')) then
      return (src:match('([^/\\]+%.lua)$') or src) .. ':' .. info.currentline
    end
  end
  return '?'
end

local unitCounter = 0
local oActive, oCall = false, 0

local origDrawText = font.drawText

font.drawText = function(s, x, y, color, sc, align)
  sc = sc or 1
  local str = tostring(s)
  if #str > 0 then
    local w = font.textWidth(str, sc)
    local bx = x
    if align == 'center' then bx = x - math.floor(w / 2) end
    if align == 'right' then bx = x - w end
    if bx < 0 or y < 0 or bx + w > VW or y + 5 * sc > VH then
      M.violations[#M.violations + 1] = string.format(
        '"%s" at (%s,%s) in state %s', str, tostring(bx), tostring(y), tostring(engine.cur))
    end

    -- One record per logical text draw. For a drawTextO pair, skip the
    -- shadow pass and record the main pass with its rect grown (+sc right/
    -- bottom) to the union of both — shadow-under-own-text is exempt
    -- structurally, and the shadow guarantees an ink background (tier-1
    -- contrast). Coords are device (canvas) space via transformPoint, so
    -- rects stay honest under the screen-shake translate.
    local record, shadowed = true, false
    if oActive then
      oCall = oCall + 1
      if oCall == 1 then record = false else shadowed = true end
    end
    if record then
      unitCounter = unitCounter + 1
      local dx, dy = gfx.transformPoint(bx, y)
      -- Exact width/height can be fractional (sc=1.5 floaters); x/y are
      -- floored to ints for mask indexing and w/h ceiled to cover the exact
      -- span, with fx/fy carrying the fractional draw offset.
      local ew = shadowed and w + sc or w
      local eh = shadowed and 6 * sc or 5 * sc
      local ix, iy = math.floor(dx), math.floor(dy)
      M.records[#M.records + 1] = {
        x = ix, y = iy, fx = dx - ix, fy = dy - iy,
        w = math.ceil(dx + ew) - ix,
        h = math.ceil(dy + eh) - iy,
        sc = sc, s = str,
        color = { color[1], color[2], color[3], color[4] or 1 },
        layer = curLayer, unit = unitCounter, shadowed = shadowed,
        src = callsite(), state = engine.cur,
      }
    end
  end
  return origDrawText(s, x, y, color, sc, align)
end

local origDrawTextO = font.drawTextO
font.drawTextO = function(s, x, y, color, sc, align)
  oActive, oCall = true, 0
  origDrawTextO(s, x, y, color, sc, align)
  oActive = false
end

-- Returns (and clears) everything recorded since the last flush.
function M.flush()
  local v = M.violations
  M.violations = {}
  return v
end

function M.takeRecords()
  local r = M.records
  M.records = {}
  return r
end

return M
