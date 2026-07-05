-- Sprite gallery (0.8): every base sprite plus every role x hat combo, for
-- instant art review (`--warp=gallery --shot`) after a sprites.lua change.
-- Dev-only: lives under src/dev/ (not src/states/) and is required lazily by
-- scenarios.lua's 'gallery' entry, never in the default require graph.
local palette = require 'src.palette'
local font = require 'src.font'
local sprites = require 'src.sprites'
local input = require 'src.input'
local engine = require 'src.engine'
local data = require 'src.data'
local CO = palette.CO
local gfx = love.graphics

local VW, VH = 320, 180

local BASE_SPRITES = {
  'shipP', 'shipE', 'shipKing', 'island', 'crate', 'chest', 'port', 'parrot', 'coinS', 'gemS', 'flagW',
  'pir_crab', 'pir_thief', 'bottleT', 'trader', 'xmark', 'rock',
  'bio_calm', 'bio_icy', 'bio_foggy', 'bio_volcano',
}
for _, t in ipairs(data.TREASURES) do BASE_SPRITES[#BASE_SPRITES + 1] = 'tr_' .. t.id end

local ROLE_ORDER = { 'captain', 'deckhand', 'strongman', 'sharpshooter', 'medic' }

engine.states.gallery = {
  update = function(dt)
    if input.jp('b') or input.jp('a') then engine.setState('title') end
  end,

  draw = function()
    gfx.setColor(CO.uiBg)
    gfx.rectangle('fill', 0, 0, VW, VH)
    font.drawText('SPRITE GALLERY', 6, 4, CO.gold, 1)

    local x, y = 6, 16
    for _, name in ipairs(BASE_SPRITES) do
      sprites.draw(name, x, y)
      x = x + 20
      if x > VW - 20 then x, y = 6, y + 20 end
    end

    -- Crew-color variants: painted ship + sash-painted captain per color.
    y = y + 24
    x = 6
    for _, c in ipairs(data.PLAYER_COLORS) do
      sprites.draw('ship_' .. c.id, x, y)
      sprites.drawPirate('captain', 'none', x + 16, y, false, 1, nil, c.id)
      x = x + 36
    end

    y = y + 20
    for _, role in ipairs(ROLE_ORDER) do
      x = 6
      for _, o in ipairs(data.OUTFITS) do
        sprites.drawPirate(role, o.id, x, y)
        x = x + 18
      end
      y = y + 16
    end

    font.drawText('X/Z BACK TO TITLE', VW / 2, VH - 8, CO.gray, 1, 'center')
  end,
}

return {}
