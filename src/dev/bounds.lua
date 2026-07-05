-- Visual invariant (dev-only, loaded by script.lua): no text may draw
-- outside the 320x180 canvas. Every text call site flows through
-- font.drawText (drawTextO included — it calls drawText twice), so wrapping
-- that one function covers all of them. Violations are collected here and
-- flushed by script.lua once per tick, so a failing frame reports every
-- offender at once through the FAIL:-and-exit path (never LÖVE's
-- interactive error screen). Intentional transients (slide-ins etc.) must
-- be clamped in game code, not allowlisted here — the invariant is absolute.
local font = require 'src.font'
local engine = require 'src.engine'

local VW, VH = 320, 180

local M = { violations = {} }

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
  end
  return origDrawText(s, x, y, color, sc, align)
end

-- Returns (and clears) everything recorded since the last flush.
function M.flush()
  local v = M.violations
  M.violations = {}
  return v
end

return M
