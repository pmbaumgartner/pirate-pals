-- Text-readability analysis (dev-only, loaded by script.lua): pure
-- functions over the per-frame text records that bounds.lua collects.
-- Two invariants, enforced on every scripted frame:
--   (A) overlap — two same-layer text draws may not light the same pixel;
--   (B) contrast — text must clear MIN_CONTRAST against its background
--       (WCAG relative-luminance ratio).
-- No allowlists: intentional cases are handled by structural rules
-- (drawTextO shadows guarantee an ink background; later overlay layers
-- paint their own backing strips) or fixed in game code.
-- Requires only font/palette so plain-Lua unit tests can load it with a
-- stubbed `love` (see tests/readability_test.lua).
local font = require 'src.font'
local palette = require 'src.palette'
local CO = palette.CO

local VW, VH = 320, 180

local M = {}

-- Below the dimmest intentional pairing (grayD on uiBg, ratio ~2.89) with
-- margin, above genuinely unreadable pairs (redD on ink ~2.1).
M.MIN_CONTRAST = 2.5

local function linear(c)
  if c <= 0.03928 then return c / 12.92 end
  return ((c + 0.055) / 1.055) ^ 2.4
end

function M.luminance(c)
  return 0.2126 * linear(c[1]) + 0.7152 * linear(c[2]) + 0.0722 * linear(c[3])
end

function M.ratio(c1, c2)
  local l1, l2 = M.luminance(c1), M.luminance(c2)
  if l1 < l2 then l1, l2 = l2, l1 end
  return (l1 + 0.05) / (l2 + 0.05)
end

function M.percentile(vals, p)
  local s = {}
  for i, v in ipairs(vals) do s[i] = v end
  table.sort(s)
  return s[math.max(1, math.ceil(#s * p))]
end

-- Lit-pixel grid for a record, built once on first litAt and cached on the
-- record (records live one frame). A shadowed record (one drawTextO) is the
-- union of the main pass and the same mask shifted (+sc,+sc). Scales can be
-- fractional (floaters use sc=1.5), so each mask cell is a fractional span
-- rasterized the way GL rasterizes rectangle('fill'): a pixel is lit iff
-- its center falls inside the span. rec.fx/fy carry the fractional part of
-- the draw position (rec.x/y are floored to ints for grid indexing).
local function litSpan(mask, h, sx, ex, sy, ey)
  local py1, py2 = math.ceil(sy - 0.5), math.ceil(ey - 0.5) - 1
  local px1, px2 = math.ceil(sx - 0.5), math.ceil(ex - 0.5) - 1
  for py = math.max(0, py1), math.min(h - 1, py2) do
    local row = mask[py]
    for px = px1, px2 do row[px] = true end
  end
end

local function buildMasks(rec)
  local full, main = {}, nil
  for ry = 0, rec.h - 1 do full[ry] = {} end
  if rec.shadowed then
    main = {}
    for ry = 0, rec.h - 1 do main[ry] = {} end
  end
  local sc = rec.sc
  local fx, fy = rec.fx or 0, rec.fy or 0
  local cx = 0
  for i = 1, #rec.s do
    local g = font.glyph(rec.s:sub(i, i))
    for r = 1, 5 do
      local row = g[r]
      for c = 1, #row do
        if row:sub(c, c) == '1' then
          local sx = fx + cx + (c - 1) * sc
          local sy = fy + (r - 1) * sc
          litSpan(full, rec.h, sx, sx + sc, sy, sy + sc)
          if rec.shadowed then
            litSpan(main, rec.h, sx, sx + sc, sy, sy + sc)
            litSpan(full, rec.h, sx + sc, sx + 2 * sc, sy + sc, sy + 2 * sc)
          end
        end
      end
    end
    cx = cx + (#g[1] + 1) * sc
  end
  rec._mask = full
  rec._main = main or full
end

function M.litAt(rec, px, py)
  local rx, ry = px - rec.x, py - rec.y
  if rx < 0 or ry < 0 or rx >= rec.w or ry >= rec.h then return false end
  if not rec._mask then buildMasks(rec) end
  return rec._mask[ry][rx] or false
end

-- Lit by the main pass only (excludes a drawTextO shadow) — visibility
-- sampling must not accept the shadow's ink, or text hidden under an ink
-- panel would read as visible.
local function mainLitAt(rec, px, py)
  local rx, ry = px - rec.x, py - rec.y
  if rx < 0 or ry < 0 or rx >= rec.w or ry >= rec.h then return false end
  if not rec._mask then buildMasks(rec) end
  return rec._main[ry][rx] or false
end

-- True when the record's glyphs still show their declared color in the
-- frame — i.e. nothing painted over them later. Overdrawn text is not
-- visible text, so it can neither garble nor be garbled (a menu panel
-- covering a playfield marker is backing, not collision). Fading records
-- (a < 1) blend with the background and can't be verified; treat as
-- visible. Without a frame image everything is treated as visible.
function M.isVisible(rec, img)
  if not img or (rec.color[4] or 1) < 1 then return true end
  if rec._vis ~= nil then return rec._vis end
  local lit = {}
  for py = math.max(0, rec.y), math.min(VH - 1, rec.y + rec.h - 1) do
    for px = math.max(0, rec.x), math.min(VW - 1, rec.x + rec.w - 1) do
      if mainLitAt(rec, px, py) then lit[#lit + 1] = { px, py } end
    end
  end
  local vis = #lit == 0 -- fully off-canvas is bounds' problem, not ours
  local stride = math.max(1, math.floor(#lit / 32))
  for i = 1, #lit, stride do
    local r, g, b = img:getPixel(lit[i][1], lit[i][2])
    if math.abs(r - rec.color[1]) <= 0.02 and math.abs(g - rec.color[2]) <= 0.02
      and math.abs(b - rec.color[3]) <= 0.02 then
      vis = true
      break
    end
  end
  rec._vis = vis
  return vis
end

-- Rule (A): same-layer, distinct-unit records whose rects intersect AND
-- share at least one lit pixel, when both are still visible in the frame
-- (see isVisible). Cross-layer pairs are exempt on principle: layer order
-- is fixed and every later layer paints its own ink backing. Strict rect
-- inequalities mean advance padding that merely touches never triggers.
function M.checkOverlaps(records, img)
  local out = {}
  for i = 1, #records do
    local a = records[i]
    for j = i + 1, #records do
      local b = records[j]
      if a.layer == b.layer and a.unit ~= b.unit then
        local x1, y1 = math.max(a.x, b.x), math.max(a.y, b.y)
        local x2 = math.min(a.x + a.w, b.x + b.w)
        local y2 = math.min(a.y + a.h, b.y + b.h)
        if x1 < x2 and y1 < y2 then
          local hx, hy
          for py = y1, y2 - 1 do
            for px = x1, x2 - 1 do
              if M.litAt(a, px, py) and M.litAt(b, px, py) then
                hx, hy = px, py
                break
              end
            end
            if hx then break end
          end
          if hx and M.isVisible(a, img) and M.isVisible(b, img) then
            out[#out + 1] = string.format(
              '"%s" (%s) overlaps "%s" (%s) at (%d,%d) in state %s',
              a.s, a.src, b.s, b.src, hx, hy, tostring(a.state))
          end
        end
      end
    end
  end
  return out
end

-- True when checkContrast would want a frame readback (any tier-2 record).
function M.needsPixels(records)
  for _, rec in ipairs(records) do
    if not rec.shadowed and (rec.color[4] or 1) >= 1 then return true end
  end
  return false
end

-- Tier 2: sample the actual frame around a bare drawText record.
-- Returns the 25th-percentile background contrast ratio, or nil when the
-- record can't be judged (painted over later, or fully off-canvas).
local function sampledRatio(rec, img)
  local lit = {}
  for py = math.max(0, rec.y), math.min(VH - 1, rec.y + rec.h - 1) do
    for px = math.max(0, rec.x), math.min(VW - 1, rec.x + rec.w - 1) do
      if M.litAt(rec, px, py) then lit[#lit + 1] = { px, py } end
    end
  end
  if #lit == 0 then return nil end

  -- Overdraw guard: if any sampled glyph pixel no longer holds the declared
  -- color, something painted over this text after it drew — text-over-text
  -- is rule (A)'s job, and panel overdraw means the text isn't visible.
  local stride = math.max(1, math.floor(#lit / 32))
  for i = 1, #lit, stride do
    local px, py = lit[i][1], lit[i][2]
    local r, g, b = img:getPixel(px, py)
    if math.abs(r - rec.color[1]) > 0.02 or math.abs(g - rec.color[2]) > 0.02
      or math.abs(b - rec.color[3]) > 0.02 then
      return nil
    end
  end

  local x1, y1 = math.max(0, rec.x - 1), math.max(0, rec.y - 1)
  local x2 = math.min(VW - 1, rec.x + rec.w)
  local y2 = math.min(VH - 1, rec.y + rec.h)
  local total = (x2 - x1 + 1) * (y2 - y1 + 1)
  local step = math.max(1, math.floor(total / 256))
  local ratios, idx = {}, 0
  for py = y1, y2 do
    for px = x1, x2 do
      idx = idx + 1
      if idx % step == 0 and not M.litAt(rec, px, py) then
        local r, g, b = img:getPixel(px, py)
        ratios[#ratios + 1] = M.ratio(rec.color, { r, g, b })
      end
    end
  end
  if #ratios == 0 then return nil end
  return M.percentile(ratios, 0.25)
end

-- Rule (B). Tier 1 (shadowed records, static): the drop shadow guarantees
-- every glyph pixel an ink diagonal neighbor, so worst-case background is
-- ink — no pixel read needed. Tier 2 (bare drawText, full alpha): sample
-- the frame; pass img = nil to skip tier 2. Fading records (a < 1) are
-- skipped in tier 2 — the same callsite draws at a == 1 on plateau frames.
-- `stats` (optional) collects every evaluated {src, s, ratio} for
-- calibration logging.
function M.checkContrast(records, img, stats)
  local out = {}
  for _, rec in ipairs(records) do
    local r, kind
    if rec.shadowed then
      r, kind = M.ratio(rec.color, CO.ink), 'vs shadow ink'
    elseif img and (rec.color[4] or 1) >= 1 then
      r, kind = sampledRatio(rec, img), 'p25 vs background'
    end
    if r then
      if stats then stats[#stats + 1] = { src = rec.src, s = rec.s, ratio = r } end
      if r < M.MIN_CONTRAST then
        out[#out + 1] = string.format(
          'low contrast "%s" (%s) ratio %.2f %s in state %s',
          rec.s, rec.src, r, kind, tostring(rec.state))
      end
    end
  end
  return out
end

return M
