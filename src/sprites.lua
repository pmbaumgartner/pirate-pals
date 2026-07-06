-- Pixel sprites: ASCII string maps baked to Images at load.
-- Each character indexes DEFMAP (or a per-sprite override map); '.' is
-- transparent. New art = add a string block + a makeSprite call in build().
local palette = require 'src.palette'
local util = require 'src.util'
local data = require 'src.data'
local hex = palette.hex
local gfx = love.graphics

local M = {}

local DEFMAP = {
  K = '#221433', W = '#ffffff', w = '#cfd6e4', S = '#f2c99a', s = '#d19a66',
  B = '#96662f', b = '#6b4420', Y = '#ffcf40', y = '#c9891b', R = '#e84b4b',
  r = '#94263a', G = '#54cf62', g = '#20803a', U = '#4a90d9', u = '#2b5fa8',
  P = '#9a63e0', p = '#6a3fae', L = '#c7ccd8', l = '#8b93a6', O = '#ff9838',
  o = '#c05f1d', T = '#ecd693', t = '#c4a95f', E = '#221433', H = '#4a2f1c',
  C = '#4a90d9', c = '#2b5fa8',
  -- Interior shadow pooling: a cool dark between K (outline) and the
  -- mid-darks, so shading never reads as outline.
  N = '#3a2450',
  -- Crew-color sash band: A = accent, D = the dark checks between accent
  -- pixels (texture, so the band reads even when accent matches the coat).
  A = '#ffffff', D = '#221433',
}

local P_BASE = {
  "................",
  ".....KKKKKK.....",
  "....KHHHHHHK....",
  "....KSSSSSSK....",
  "....KSESSESK....",
  "....KSSSSSSK....",
  ".....KSSSSK.....",
  "....KKCCCCKK....",
  "...KCCCCCCCCK...",
  "...KSCCCCCCSK...",
  "...KCCCCCCCCK...",
  "....KADAADAK....",
  "....KccKKccK....",
  "....Kcc..ccK....",
  "....KKK..KKK....",
  "................" }

local function copyRows(rows)
  local out = {}
  for i, r in ipairs(rows) do out[i] = r end
  return out
end

local P_MEDIC = copyRows(P_BASE)
P_MEDIC[9]  = "...KCCCRRCCCK..."
P_MEDIC[10] = "...KSCRRRRCSK..."
P_MEDIC[11] = "...KCCCRRCCCK..."

local P_WIDE = copyRows(P_BASE)
P_WIDE[8]  = "...KKCCCCCCKK..."
P_WIDE[9]  = "..KCCCCCCCCCCK.."
P_WIDE[10] = "..KSSCCCCCCSSK.."
P_WIDE[11] = "..KCCCCCCCCCCK.."
P_WIDE[12] = "...KADAADAADK..."

local P_GUN = copyRows(P_BASE)
P_GUN[9] = "...KCCCCCCCCKbbK"

local P_KING = copyRows(P_WIDE)
P_KING[1] = "................"
P_KING[2] = "....Y.Y.Y.Y....."
P_KING[3] = "....YYYYYYYY...."
P_KING[4] = "....KHHHHHHK...."

-- Ruffled King: crown tilts at 2 bars, then is gone
-- entirely (frazzled hair) at 1 bar. Swapped in by u.bars in draw.lua.
local P_KING_2BAR = copyRows(P_WIDE)
P_KING_2BAR[1] = "................"
P_KING_2BAR[2] = ".....Y.Y.Y.Y...."
P_KING_2BAR[3] = ".....YYYYYYYY..."
P_KING_2BAR[4] = "....KHHHHHHK...."

local P_KING_1BAR = copyRows(P_WIDE)
P_KING_1BAR[1] = "................"
P_KING_1BAR[2] = "....HH.HH.HH...."
P_KING_1BAR[3] = "....HHHHHHHH...."
P_KING_1BAR[4] = "....KHHHHHHK...."

local SHIP = {
  "................",
  "....K...........",
  "....KRRRR.......",
  "....KRR.........",
  "....K...........",
  "...KWWWWWK......",
  "...KWWWWWWWK....",
  "...KWWWWWWWWWK..",
  "...KWWWWWWWK....",
  "....K...........",
  "KKKKKKKKKKKKKKK.",
  "KBBBBBBBBBBBBBK.",
  ".KBBYBBYBBYBBK..",
  ".KbbbbbbbbbbbK..",
  "..KKKKKKKKKKK...",
  "................" }

-- Enemy ship: same 16x16 footprint as SHIP so every draw site is untouched,
-- but its own silhouette — ragged sail edges, holes, a patch, and a black
-- flag with a white skull — so foes read by shape, freeing every sail color
-- (purple included) for players.
local E_SHIP = {
  "................",
  "....K...........",
  "....KKKKKK......",
  "....KwwwwK......",
  "....KwKKwK......",
  "...KWW.WWK......",
  "...KWWWWWW.K....",
  "...KWWBBWWWWK...",
  "...KW.WWWBW.K...",
  "....K...........",
  "KKKKKKKKKKKKKKK.",
  "KBBBBBBBBBBBBBK.",
  ".KBBYBBYBBYBBK..",
  ".KbbbbbbbbbbbK..",
  "..KKKKKKKKKKK...",
  "................" }

-- King's ship: the player hull with a gold crown emblem on the sail — the
-- boss reads by its emblem (same shape language as hat_crown), not paleness.
local SHIP_KING = copyRows(SHIP)
SHIP_KING[7] = "...KWYWYWYWK...."
SHIP_KING[8] = "...KWWYYYYYWWK.."

local ISLAND = {
  "................",
  "....GG.G.GG.....",
  "...GGGGGGGGG....",
  "....GGgbgGG.....",
  ".......b........",
  ".......b........",
  ".......b........",
  "....TTTTTTTT....",
  "..TTTTTTTTTTTT..",
  ".TTTTTTTTTTTTTT.",
  ".TTTTtTTTTtTTTT.",
  ".tTTTTTTTTTTTTt.",
  "..ttTTTTTTTTtt..",
  "....tttttttt....",
  "................",
  "................" }

-- X-brace dithered to every other row (solid diagonals were near-noise at
-- 1x), top outline broken for a lit edge, N pooled in the lower corners.
local CRATE = {
  "................",
  ".KKKKBBBBBBKKKK.",
  ".KBbBBBBBBBBbBK.",
  ".KBBBBBBBBBBBBK.",
  ".KBBBbBBBBbBBBK.",
  ".KBBBBBBBBBBBBK.",
  ".KBBBBBbbBBBBBK.",
  ".KBBBBBBBBBBBBK.",
  ".KBBBBbBBbBBBBK.",
  ".KBBBBBBBBBBBBK.",
  ".KBBbBBBBBBbBBK.",
  ".KNbBBBBBBBBbNK.",
  ".KNNBBBBBBBBNNK.",
  ".KKKKKKKKKKKKKK.",
  "................",
  "................" }

local PERCH = {
  "................",
  "....KKKKKKKK....",
  "...KbBBBBBBbK...",
  "..KbBYYBYYBYbK..",
  "..KbBYYBYYBYbK..",
  "..KbBBBBBBBBbK..",
  ".KbBBBBBBBBBBbK.",
  "KbBYYBYYBYYBYYbK",
  "KbBYYBYYBYYBYYbK",
  "KbBBBBBBBBBBBBbK",
  "KbBYYBYYBYYBYYbK",
  "KbBYYBYYBYYBYYbK",
  "KbBBBBBBBBBBBBbK",
  ".KbbbbbbbbbbbbK.",
  "..KKKKKKKKKKKK..",
  "................"
}

local CHEST = {
  "................",
  "................",
  "................",
  "................",
  "...KKKKKKKKKK...",
  "..KBBBBYYBBBBK..",
  "..KBBBBYYBBBBK..",
  "..KKKKKKKKKKKK..",
  "..KBBBBYYBBBBK..",
  "..KHBBByyBBBHK..",
  "..KNHHHHHHHHNK..",
  "..KKKKKKKKKKKK..",
  "................",
  "................",
  "................",
  "................" }

local PORT = {
  "................",
  "....RRRRRRRR....",
  "...RRRRRRRRRR...",
  "...KBBBBBBBBK...",
  "...KBBKKKKBBK...",
  "...KBBKyKKBBK...",
  "...KBBKKKKBBK...",
  "..bbbbbbbbbbbb..",
  ".bbbbbbbbbbbbbb.",
  "..b..b....b..b..",
  "..b..b....b..b..",
  "................",
  "................",
  "................",
  "................",
  "................" }

local HATS = {
  straw = {"................",".....YYYYYY.....",".....YYYYYY.....","..yYYYYYYYYYYy..","................","................"},
  tri   = {"................",".....KKKKKK.....","....KKKKKKKK....","...KKyyyyyyKK...","................","................"},
  cap   = {"...W............","..WW.UUUUUU.....","..W.UUUUUUUU....","....yyyyyyyy....","................","................"},
  crown = {"................","....Y..Y..Y.....","....YYYYYYY.....","....yRyGyRy.....","................","................"},
  band  = {"................",".....CCCCCC.....","....CCCCCCCC....","...........cC...","................","................"},
  patch = {"................","................","................","....KKKKKKK.....",".....KKK........","................"},
}

-- Ship-battle foe telegraph icons: bomb (fire), wrench (fix), sail (move).
local ICON_FIRE = {
  "....Y.......",
  ".....YY.....",
  "....KKKK....",
  "...KKKKKK...",
  "..KKKKKKKK..",
  "..KKKKKKKK..",
  "..KKKKKKKK..",
  "...KKKKKK...",
  "....KKKK....",
  "............",
  "............",
  "............",
}

local ICON_FIX = {
  "............",
  "............",
  ".......LL...",
  "......LLLL..",
  ".....LLLL...",
  "....LLLL....",
  "...LLLL.....",
  "..LLLL......",
  ".LLLL.......",
  "LL..........",
  "............",
  "............",
}

local ICON_MOVE = {
  "............",
  "....WW......",
  "....WW......",
  "...WWWW.....",
  "...WWWW.....",
  "..WWWWWW....",
  "..WWWWWW....",
  ".WWWWWWWW...",
  "....WW......",
  "..BBBBBB....",
  "............",
  "............",
}

-- Boarding intent icon: crossed hilt, mirrors icon_fire/fix/move's
-- 12x12 footprint so it drops into the same draw call.
local ICON_SWORD = {
  "............",
  ".......WW...",
  "......WW....",
  ".....WW.....",
  "....WW......",
  "...WW.......",
  "..WW........",
  ".WW.........",
  ".YY.........",
  "YYYY........",
  ".YY.........",
  "............",
}

local ICON_PLANKS = {
  "............",
  ".bB......Bb.",
  "..bB....Bb..",
  "...bB..Bb...",
  "....bBBb....",
  ".....bB.....",
  "....bBBb....",
  "...bB..Bb...",
  "..bB....Bb..",
  ".bB......Bb.",
  "............",
  "............",
}

-- Boarding-telegraph minis: 8x8 so they tuck into a tile corner instead of
-- covering the cell above. The ink outline is baked into the sprite — it
-- replaces the badge plate for separation — and each intent gets its own
-- silhouette + color so they read apart at a glance.
local MINI_SWORD = {
  ".....KK.",
  "....KRRK",
  "...KRRK.",
  "..KRRK..",
  "KKKRK...",
  "KYYKK...",
  "KYYYK...",
  "KKKKK...",
}

local MINI_BOOT = {
  "..KKK...",
  ".KWWK...",
  ".KWWK...",
  ".KWWKK..",
  ".KWWWWK.",
  ".KWlllK.",
  ".KllllK.",
  "..KKKKK.",
}

local MINI_PLANKS = {
  "KK....KK",
  "KOK..KOK",
  ".KOKKOK.",
  "..KOOK..",
  "..KOOK..",
  ".KOKKOK.",
  "KOK..KOK",
  "KK....KK",
}

-- Ship-telegraph variants: bigshot is one oversized ball (red glint),
-- volley two small offset balls, so shape — not scale — tells them apart
-- from the plain icon_fire cannonball.
local ICON_BIGSHOT = {
  "....YY......",
  "...KKKKKK...",
  "..KKKKKKKK..",
  ".KKRRKKKKKK.",
  ".KKRKKKKKKK.",
  ".KKKKKKKKKK.",
  ".KKKKKKKKKK.",
  ".KKKKKKKKKK.",
  "..KKKKKKKK..",
  "...KKKKKK...",
  "............",
  "............",
}

local ICON_VOLLEY = {
  "............",
  "....KKKK....",
  "...KKKKKK...",
  "...KWKKKK...",
  "...KKKKKK...",
  "....KKKK....",
  "..KKKK......",
  ".KKKKKK.....",
  ".KWKKKK.....",
  ".KKKKKK.....",
  "..KKKK......",
  "............",
}

-- Boss chart marker: an ominous crowned silhouette, drawn at the end of the
-- voyage chart's path and reused nowhere else (the ship phase uses shipKing).
local KING_SIL = {
  "................",
  "......YYY.......",
  ".....YYYYY......",
  "....KKKKKKK.....",
  "...KKPPPPPKK....",
  "...KPPPPPPPK....",
  "...KPPPPPPPK....",
  "....KPPPPPK.....",
  ".....KKKKK......",
  "......KKK.......",
  "................",
  "................",
  "................",
  "................",
  "................",
  "................",
}

-- Phase 4 gimmick enemies. The crab's shell/claws face left (toward the
-- players) so "hit it from behind" reads on the sprite itself; the thief
-- parrot wears a bandit mask.
-- Outline broken (K -> fill) at the claw apexes and shell top so light
-- reads as hitting the edge; O pips = lit claw tissue. The claw/shell
-- silhouette is a "hit it from behind" telegraph — shape must not change.
local CRAB = {
  "................",
  "..RR........RR..",
  ".KORK......KROK.",
  ".KRRK......KRRK.",
  "..KRRK.KK.KRRK..",
  "...KKRRRRRRKK...",
  "...KRRRRRRRRK...",
  "..KRRWRRRRWRRK..",
  "..KRRRRRRRRRRK..",
  "..KRrRrRrRrRrK..",
  "...KRRRRRRRRK...",
  "....KKKKKKKK....",
  "...KrK....KrK...",
  "..Kr.K....K.rK..",
  "................",
  "................" }

local THIEF = {
  "................",
  "......KKK.......",
  ".....KGGGK......",
  "....KGGGGGK.....",
  "....KKKKKKK.....",
  "...KKWKKKWKK....",
  "....KKKKKKK.....",
  "..YYKGGGGGK.....",
  "...YKGGGGGK.....",
  "....KGGgGGK.....",
  "....KGGgGGK.....",
  "....KGgGgGK.....",
  ".....KGGGK......",
  ".....KRRK.......",
  "......KK........",
  "................" }

-- Sea-event tiles (4.2): message in a bottle, the friendly trader's stall
-- boat, and the treasure-map X.
local BOTTLE_T = {
  "................",
  "................",
  "......yy........",
  "......KK........",
  ".....KWUK.......",
  ".....KwTUK......",
  ".....KwTUK......",
  ".....KUUUK......",
  ".....KKKK.......",
  "..WW........WW..",
  ".WWWWWWWWWWWWWW.",
  "................",
  "................",
  "................",
  "................",
  "................" }

local TRADER_T = {
  "................",
  "....YYYYYYYY....",
  "...YRYYRYYRY....",
  "....K......K....",
  "....K......K....",
  "..KKKKKKKKKKKK..",
  ".KBBBBBBBBBBBBK.",
  "..KBBYBBYBBYBK..",
  "...KKKKKKKKKK...",
  "................",
  "................",
  "................",
  "................",
  "................",
  "................",
  "................" }

local XMARK = {
  "................",
  "..RR........RR..",
  "..RRR......RRR..",
  "...RRR....RRR...",
  "....RRR..RRR....",
  ".....RRRRRR.....",
  "......RRRR......",
  "......RRRR......",
  ".....RRRRRR.....",
  "....RRR..RRR....",
  "...RRR....RRR...",
  "..RRR......RRR..",
  "..RR........RR..",
  "................",
  "................",
  "................" }

-- Volcano rock (falls on telegraphed sail hexes).
local ROCK = {
  "..lll...",
  ".lLLll..",
  "lLLOLll.",
  "lLOLLLl.",
  ".lLLOll.",
  "..llll..",
  "........",
  "........" }

-- Biome HUD/chart icons (4.1): sun, snowflake, fog cloud, volcano.
local BIO_CALM = {
  "............",
  ".....Y......",
  "..Y..Y..Y...",
  "...YYYYY....",
  "...YYYYY....",
  ".YYYYYYYYY..",
  "...YYYYY....",
  "...YYYYY....",
  "..Y..Y..Y...",
  ".....Y......",
  "............",
  "............" }

local BIO_ICY = {
  "............",
  ".....W......",
  "..W..W..W...",
  "...W.W.W....",
  "....WWW.....",
  ".WWWWWWWWW..",
  "....WWW.....",
  "...W.W.W....",
  "..W..W..W...",
  ".....W......",
  "............",
  "............" }

local BIO_FOGGY = {
  "............",
  "............",
  "....LLL.....",
  "...LLLLL....",
  "..LLLLLLLL..",
  ".LLLLLLLLLL.",
  ".LLLLLLLLLL.",
  "..LLLLLLLL..",
  "............",
  "............",
  "............",
  "............" }

local BIO_VOLCANO = {
  "............",
  ".....OO.....",
  "....OOOO....",
  "....KOOK....",
  "...KKOOKK...",
  "...KKKKKK...",
  "..KKKKKKKK..",
  ".KKKKKKKKKK.",
  "KKKKKKKKKKKK",
  "............",
  "............",
  "............" }

-- Secrets log checkmark: drawn over a found slot in
-- src/states/log.lua's SECRETS tab.
local CHECK = {
  "................",
  "................",
  "................",
  "................",
  "...........YY...",
  "..........YY....",
  ".........YY.....",
  "Y........YY.....",
  "YY......YY......",
  ".YY....YY.......",
  "..YY..YY........",
  "...YYYY.........",
  "................",
  "................",
  "................",
  "................" }

local PARROT = {
  "...KK...",
  "..KGGK..",
  ".YKGEGK.",
  ".YKGGGK.",
  "..KGGGK.",
  "..KGgGK.",
  "..KRRK..",
  "...KK..." }

local TREASURE_ART = {
  coin   = {"............","....yyyy....","..yyYYYYyy..",".yYYYYYYYYy.",".yYYYWYYYYy.",".yYYYYYYYYy.",".yYYYYYYYYy.",".yYYYYYYYYy.","..yyYYYYyy..","....yyyy....","............","............"},
  ring   = {"............",".....WW.....","....LLLL....","...LL..LL...","...L....L...","...LL..LL...","....LLLL....","............","............","............","............","............"},
  glass  = {"............","............","...UUUU.....","..UUUUUU....","..UWUUUUU...","..UUUUUUU...","...UUUUU....","....UUU.....","............","............","............","............"},
  map    = {"............","............",".TTTTTTTTTT.",".TtTTTTTTtT.",".TTTuuTTTTT.",".TTTTTuuTTT.",".TTTTTTRTRT.",".TTTTTTTRTT.",".TTTTTTRTRT.",".TTTTTTTTTT.",".tttttttttt.","............"},
  pearl  = {"............","............","....WWWW....","...WWWWWW...","...WWwWWW...","...WWWWWW...","....WWWW....","..OOOOOOOO..","...OoOoOo...","............","............","............"},
  ruby   = {"............","............","....RRRR....","...RRRRRR...","..RRWRRRRR..","..RRRRRRRR..","...RRRRRR...","....RRRR....",".....RR.....","............","............","............"},
  spy    = {"............","............","............","........yy..",".......yYy..","......yYy...",".....yYy....","...bbYy.....","...bb.......","............","............","............"},
  anchor = {"............",".....LL.....","....LLLL....",".....LL.....",".....LL.....","...LLLLLL...",".....LL.....",".L...LL...L.",".LL..LL..LL.","..LLLLLLLL..","............","............"},
  ban    = {"............","............","..YY........","..YYY.......","...YYY......","....YYYY....",".....YYYYY..",".......yYYY.",".........yy.","............","............","............"},
  tooth  = {"............","............","....WWW.....","....WWWW....","....WWWW....",".....WWW....",".....WW.....","......W.....","............","............","............","............"},
  bottle = {"............","............","............","..LLLLLLLL..",".LuuWuuuuLL.",".LuuWWuuuLLy",".LuubuuuuLL.","..LLLLLLLL..","............","............","............","............"},
  star   = {"............",".....OO.....",".....OO.....",".OOOOOOOOOO.","..OOOOOOOO..","...OOOOOO...","...OO..OO...","..OO....OO..","............","............","............","............"},
}

-- Perk pick icons (3.3): small, shown on the loot perk card only.
local PERK_ART = {
  boots  = {"........", "..BB.BB.", "..BB.BB.", "..bb.bb.", "bbbb.bbb", "........"},
  belly  = {"........", "..RRRR..", ".RRWWRR.", ".RWWWWR.", "..RRRR..", "........"},
  arms   = {"S......S", "SS....SS", ".SS..SS.", "..SSSS..", "..SSSS..", "........"},
  muscle = {"........", "..SSSS..", ".SSSSSS.", "SSSSSSSS", ".SSSSSS.", "..SSSS.."},
}

local COIN_S = {".yyyy..","yYYYYy.","yYWYYy.","yYYYYy.",".yyyy.."}
local GEM_S  = {".PPPPP.","PPWPPPP",".PPPPP.","..PPP..","...P..."}
local FLAG_W = {"KWWWWW.","KWWWW..","KWWWWW.","K......","K......","K......"}

-- Coat/hair recolors per pirate role (override chars in DEFMAP).
local ROLE_COAT = {
  captain      = { C = '#d23c3c', c = '#8f2430' },
  deckhand     = { C = '#4a90d9', c = '#2b5fa8' },
  strongman    = { C = '#54cf62', c = '#20803a' },
  sharpshooter = { C = '#9a63e0', c = '#6a3fae' },
  medic        = { C = '#f2f2f2', c = '#b9c2cf' },
  -- Enemies override the sash chars to their coat color so the crew-color
  -- band disappears and they render exactly as before.
  grunt        = { C = '#6a7488', c = '#454d5c', H = '#94263a', A = '#6a7488', D = '#6a7488' },
  gunner       = { C = '#5a4a72', c = '#3c3050', H = '#94263a', A = '#5a4a72', D = '#5a4a72' },
  brute        = { C = '#8a3448', c = '#5c1e30', H = '#94263a', A = '#8a3448', D = '#8a3448' },
  king         = { C = '#9a63e0', c = '#6a3fae', H = '#94263a', A = '#9a63e0', D = '#9a63e0' },
}

-- Player-role body art, for baking one sash-colored variant per crew color.
local PLAYER_BODY = {
  captain = P_BASE, deckhand = P_BASE, strongman = P_WIDE,
  sharpshooter = P_GUN, medic = P_MEDIC,
}

local function withAccent(coat, accent)
  local map = { A = accent }
  for k, v in pairs(coat) do map[k] = v end
  return map
end

local SPR = {}

local function makeSprite(name, rows, map)
  local w, h = #rows[1], #rows
  for i = 1, h do
    assert(#rows[i] == w,
      ('sprite %s row %d len %d != %d'):format(name, i, #rows[i], w))
  end
  local pixels = love.image.newImageData(w, h)
  for y = 1, h do
    for x = 1, w do
      local ch = rows[y]:sub(x, x)
      if ch ~= '.' then
        local col = (map and map[ch]) or DEFMAP[ch]
        if col then
          local c = hex(col)
          pixels:setPixel(x - 1, y - 1, c[1], c[2], c[3], 1)
        end
      end
    end
  end
  local img = gfx.newImage(pixels)
  img:setFilter('nearest', 'nearest')
  SPR[name] = img
end

function M.build()
  makeSprite('shipP', SHIP)
  makeSprite('shipE', E_SHIP, { W = '#463d5c', B = '#5a4a63', b = '#3c3147', Y = '#8f2430', w = '#ffffff' })
  makeSprite('shipKing', SHIP_KING, { W = '#e8d4ff', R = '#ffcf40', B = '#4a2f5c', b = '#301f3c', Y = '#ffcf40', K = '#150b1f' })
  makeSprite('island', ISLAND)
  makeSprite('icon_fire', ICON_FIRE)
  makeSprite('icon_fix', ICON_FIX)
  makeSprite('icon_move', ICON_MOVE)
  makeSprite('icon_sword', ICON_SWORD)
  makeSprite('icon_planks', ICON_PLANKS)
  makeSprite('icon_bigshot', ICON_BIGSHOT)
  makeSprite('icon_volley', ICON_VOLLEY)
  makeSprite('mini_sword', MINI_SWORD)
  makeSprite('mini_boot', MINI_BOOT)
  makeSprite('mini_planks', MINI_PLANKS)
  makeSprite('kingSil', KING_SIL)
  makeSprite('crate', CRATE)
  makeSprite('perch', PERCH)
  makeSprite('chest', CHEST)
  makeSprite('port', PORT)
  makeSprite('bottleT', BOTTLE_T)
  makeSprite('trader', TRADER_T)
  makeSprite('xmark', XMARK)
  makeSprite('rock', ROCK)
  makeSprite('bio_calm', BIO_CALM)
  makeSprite('bio_icy', BIO_ICY)
  makeSprite('bio_foggy', BIO_FOGGY)
  makeSprite('bio_volcano', BIO_VOLCANO)
  makeSprite('parrot', PARROT)
  makeSprite('secretCheck', CHECK)
  makeSprite('coinS', COIN_S)
  makeSprite('gemS', GEM_S)
  makeSprite('flagW', FLAG_W)
  makeSprite('pir_captain', P_BASE, ROLE_COAT.captain)
  makeSprite('pir_deckhand', P_BASE, ROLE_COAT.deckhand)
  makeSprite('pir_strongman', P_WIDE, ROLE_COAT.strongman)
  makeSprite('pir_sharpshooter', P_GUN, ROLE_COAT.sharpshooter)
  makeSprite('pir_medic', P_MEDIC, ROLE_COAT.medic)
  makeSprite('pir_grunt', P_BASE, ROLE_COAT.grunt)
  makeSprite('pir_gunner', P_GUN, ROLE_COAT.gunner)
  makeSprite('pir_brute', P_WIDE, ROLE_COAT.brute)
  makeSprite('pir_crab', CRAB)
  makeSprite('pir_thief', THIEF)
  makeSprite('pir_king', P_KING, ROLE_COAT.king)
  makeSprite('pir_king2', P_KING_2BAR, ROLE_COAT.king)
  makeSprite('pir_king1', P_KING_1BAR, ROLE_COAT.king)
  makeSprite('hat_straw', HATS.straw)
  makeSprite('hat_tri', HATS.tri)
  makeSprite('hat_cap', HATS.cap)
  makeSprite('hat_crown', HATS.crown)
  makeSprite('hat_bandR', HATS.band, { C = '#e84b4b', c = '#94263a' })
  makeSprite('hat_bandB', HATS.band, { C = '#4a90d9', c = '#2b5fa8' })
  makeSprite('hat_patch', HATS.patch)
  for id, art in pairs(TREASURE_ART) do makeSprite('tr_' .. id, art) end
  for id, art in pairs(PERK_ART) do makeSprite('perk_' .. id, art) end
  -- Crew-color variants: one sail/flag-painted ship and one sash-painted
  -- body per player role per color. The unsuffixed shipP / pir_<role> bakes
  -- above stay as the classic fallback (title screen, previews, enemies).
  for _, c in ipairs(data.PLAYER_COLORS) do
    makeSprite('ship_' .. c.id, SHIP, { W = c.sail, R = c.flag })
    for role, art in pairs(PLAYER_BODY) do
      makeSprite('pir_' .. role .. '_' .. c.id, art, withAccent(ROLE_COAT[role], c.accent))
    end
  end
end

function M.draw(name, x, y, flip, scale, alpha, tint)
  local s = SPR[name]
  if not s then return end
  scale = scale or 1
  x, y = util.round(x), util.round(y)
  local r, g, b = 1, 1, 1
  if tint then r, g, b = tint[1], tint[2], tint[3] end
  gfx.setColor(r, g, b, alpha or 1)
  if flip then
    gfx.draw(s, x + s:getWidth() * scale, y, 0, -scale, scale)
  else
    gfx.draw(s, x, y, 0, scale, scale)
  end
end

-- Outfit overlay ids -> hat sprite + optional side-companion.
local OUTFIT_DRAW = {
  none = nil,
  bandR = { hat = 'hat_bandR' },
  bandB = { hat = 'hat_bandB' },
  patch = { hat = 'hat_patch' },
  straw = { hat = 'hat_straw' },
  tri   = { hat = 'hat_tri' },
  cap   = { hat = 'hat_cap' },
  crown = { hat = 'hat_crown' },
  parrot = { side = 'parrot' },
}

-- Ruffled King: which body art to draw for the Pirate King at his
-- current bar count -- crown tilts at 2, is gone (frazzled) at 1 or fewer.
function M.kingSprite(bars)
  if bars and bars <= 1 then return 'pir_king1' end
  if bars and bars <= 2 then return 'pir_king2' end
  return 'pir_king'
end

-- Sail sprite for a crew color; falls back to classic shipP when the color
-- is unset or unknown.
function M.shipSprite(colorId)
  local name = colorId and ('ship_' .. colorId)
  if name and SPR[name] then return name end
  return 'shipP'
end

function M.drawPirate(roleKey, outfit, x, y, flip, scale, alpha, colorId, tint)
  scale = scale or 1
  local body = 'pir_' .. roleKey
  if colorId and SPR[body .. '_' .. colorId] then body = body .. '_' .. colorId end
  M.draw(body, x, y, flip, scale, alpha, tint)
  local od = OUTFIT_DRAW[outfit]
  if od then
    if od.hat then M.draw(od.hat, x, y, flip, scale, alpha, tint) end
    if od.side then
      M.draw(od.side, flip and (x - 3 * scale) or (x + 11 * scale), y + 3 * scale, flip, scale, alpha, tint)
    end
  end
end

return M
