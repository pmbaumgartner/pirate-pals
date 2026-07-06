-- Plain-Lua unit tests for the text-readability checker
-- (src/dev/readability.lua): WCAG contrast math, glyph lit-pixel masks,
-- overlap detection, and tier-1 shadowed-contrast checks. Tier 2 (frame
-- sampling) is exercised by the smoke run, not here. Run from the project
-- root: `lua tests/readability_test.lua`.
package.path = './?.lua;' .. package.path
love = { graphics = {} }
local palette = require 'src.palette'
local CO = palette.CO
local read = require 'src.dev.readability'

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

-- Contrast math: the grayD-on-uiBg anchor pins both the WCAG formula and
-- the MIN_CONTRAST calibration (dimmest intentional pairing, must pass).
local anchor = read.ratio(CO.grayD, CO.uiBg)
ok(anchor > 2.88 and anchor < 2.92, 'grayD on uiBg is ~2.90, got ' .. anchor)
ok(anchor >= read.MIN_CONTRAST, 'anchor pairing clears MIN_CONTRAST')
ok(read.ratio(CO.white, CO.ink) > 10, 'white on ink is high contrast')
ok(read.ratio(CO.gray, CO.gray) == 1, 'a color against itself is ratio 1')
ok(read.ratio(CO.ink, CO.white) == read.ratio(CO.white, CO.ink), 'ratio is symmetric')
ok(read.ratio(CO.redD, CO.ink) < read.MIN_CONTRAST, 'redD on ink is below the threshold')

-- litAt against hand-checked glyphs. A = {'010','101','111','101','101'}.
local function rec(t)
  local base = {
    x = 0, y = 0, sc = 1, shadowed = false, layer = 'state', unit = 1,
    color = CO.white, src = 'test.lua:1', state = 'test',
  }
  for k, v in pairs(t) do base[k] = v end
  base.h = base.h or (base.shadowed and 6 or 5) * base.sc
  return base
end

local a1 = rec { s = 'A', w = 3 }
ok(not read.litAt(a1, 0, 0), 'A top-left corner is unlit')
ok(read.litAt(a1, 1, 0), 'A top-center is lit')
ok(read.litAt(a1, 0, 4), 'A bottom-left is lit')
ok(not read.litAt(a1, 1, 4), 'A bottom-center is unlit')
ok(not read.litAt(a1, -1, 0) and not read.litAt(a1, 3, 0), 'out-of-rect pixels are unlit')

-- 'AB': inter-letter gap column (x=3) is never lit; B = {'110',...} at x=4.
local ab = rec { s = 'AB', w = 7 }
for y = 0, 4 do
  ok(not read.litAt(ab, 3, y), 'inter-letter gap is unlit at row ' .. y)
end
ok(read.litAt(ab, 4, 0), 'B top-left is lit')
ok(not read.litAt(ab, 6, 0), 'B top-right is unlit')

-- sc=2 scaling: each mask cell becomes a 2x2 block.
local a2 = rec { s = 'A', w = 6, sc = 2 }
ok(not read.litAt(a2, 0, 0) and not read.litAt(a2, 1, 1), 'scaled A corner block is unlit')
ok(read.litAt(a2, 2, 0) and read.litAt(a2, 3, 1), 'scaled A center block is lit')

-- Fractional sc (floaters use 1.5): pixel-center coverage, so the '.' dot
-- (mask row 5, spanning y 6..7.5) lights only the pixel whose center 6.5
-- falls inside — not pixel 7 (center 7.5 is on the open edge).
local dot = rec { s = '.', w = 2, h = 8, sc = 1.5 }
ok(read.litAt(dot, 0, 6), 'fractional-scale dot is lit at its covered pixel')
ok(not read.litAt(dot, 0, 7), 'pixel center on the open span edge is unlit')
ok(not read.litAt(dot, 1, 6), 'x span edge is exclusive too')
ok(not read.litAt(dot, 0, 5), 'row above the dot is unlit')

-- Shadowed union: shadow pixel (+sc,+sc) of A's bottom-left (0,4) is lit.
local as = rec { s = 'A', w = 4, shadowed = true }
ok(read.litAt(as, 1, 5), 'shadow of bottom-left is lit')
ok(not read.litAt(as, 3, 0), 'top-right of shadowed rect is unlit')
ok(read.litAt(as, 1, 0), 'main pass still lit in a shadowed record')

-- checkOverlaps: same-layer lit-pixel collision fires; layers/units/padding
-- adjacency do not.
local function pair(over)
  return {
    rec { s = 'HP 12', w = 18, unit = 1, src = 'crew.lua:88' },
    rec(over),
  }
end
local v = read.checkOverlaps(pair { s = 'LV 3', w = 14, unit = 2, src = 'crew.lua:92' })
ok(#v == 1, 'same-layer lit collision is one violation, got ' .. #v)
ok(v[1] and v[1]:find('crew.lua:88', 1, true) and v[1]:find('crew.lua:92', 1, true),
  'violation names both callsites: ' .. tostring(v[1]))

v = read.checkOverlaps(pair { s = 'LV 3', w = 14, unit = 2, layer = 'banner' })
ok(#v == 0, 'cross-layer pairs are exempt')

v = read.checkOverlaps(pair { s = 'LV 3', w = 14, unit = 1 })
ok(#v == 0, 'same-unit records never collide')

-- 'A' spans x 0..2; a neighbor at x=3 touches only by advance padding.
v = read.checkOverlaps { rec { s = 'A', w = 3, unit = 1 }, rec { s = 'A', w = 3, x = 3, unit = 2 } }
ok(#v == 0, 'labels touching only by advance padding do not collide')

-- Rects overlap but no pixel is lit by both: A's unlit column 0 under B.
v = read.checkOverlaps {
  rec { s = '.', w = 1, unit = 1 }, -- '.' lights only (0,4)
  rec { s = "'", w = 1, unit = 2 }, -- ' lights only (0,0) and (0,1)
}
ok(#v == 0, 'rect overlap without a shared lit pixel is not a violation')

-- Visibility gate: an overlap only counts when both records still show
-- their declared color in the frame — text painted over by a later panel
-- is backing, not collision. A fake all-ink frame hides white text; a fake
-- all-white frame shows it. Shadowed records sample main-pass pixels only,
-- so a shadow's own ink never counts as "visible" under an ink panel.
local inkImg = { getPixel = function() return CO.ink[1], CO.ink[2], CO.ink[3], 1 end }
local whiteImg = { getPixel = function() return 1, 1, 1, 1 end }
local function hPair()
  return { rec { s = 'H', w = 3, unit = 1 }, rec { s = 'H', w = 3, unit = 2 } }
end
ok(#read.checkOverlaps(hPair(), whiteImg) == 1, 'visible overlapping pair is flagged')
ok(#read.checkOverlaps(hPair(), inkImg) == 0, 'overdrawn records do not collide')
ok(#read.checkOverlaps(hPair()) == 1, 'no frame image treats everything as visible')
local shad = rec { s = 'H', w = 4, h = 6, shadowed = true }
ok(not read.isVisible(shad, inkImg), 'shadowed text under an ink panel is not visible')
ok(read.isVisible(rec { s = 'H', w = 3, color = { 1, 1, 1, 0.5 } }, inkImg),
  'fading text cannot be verified and stays visible')

-- Tier-1 contrast: ink-colored shadowed text is unreadable over its own
-- shadow; gray clears it. nil img skips tier 2 without erroring.
v = read.checkContrast({ rec { s = 'X', w = 3, shadowed = true, color = CO.ink } }, nil)
ok(#v == 1, 'ink-on-ink shadowed record is a tier-1 violation')
v = read.checkContrast({ rec { s = 'X', w = 3, shadowed = true, color = CO.gray } }, nil)
ok(#v == 0, 'gray shadowed record passes tier 1')
v = read.checkContrast({ rec { s = 'X', w = 3, color = CO.ink } }, nil)
ok(#v == 0, 'tier 2 is skipped when no image is supplied')

-- percentile edges.
ok(read.percentile({ 7 }, 0.25) == 7, 'percentile of a single value')
ok(read.percentile({ 3, 3, 3 }, 0.25) == 3, 'percentile of equal values')
ok(read.percentile({ 4, 1, 3, 2 }, 0.25) == 1, 'p25 of 1..4 is the first sorted value')
ok(read.percentile({ 4, 1, 3, 2 }, 0.5) == 2, 'p50 of 1..4 is the second sorted value')

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('readability_test OK')
