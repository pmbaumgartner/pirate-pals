-- Title screen.
local util = require 'src.util'
local palette = require 'src.palette'
local font = require 'src.font'
local sprites = require 'src.sprites'
local input = require 'src.input'
local audio = require 'src.audio'
local engine = require 'src.engine'
local game = require 'src.game'
local meta = require 'src.meta'
local ui = require 'src.ui'
local CO = palette.CO
local gfx = love.graphics
local SFX = audio.sfx

local VW, VH = 320, 180

-- New Voyage picks a mode first: NEW VOYAGE always opens this two-option,
-- picture-first pick (guardrail: <=2 choices, both good) rather than
-- defaulting into either. CONTINUE (an existing save) skips straight to
-- sail, unaffected — mode only matters for a fresh run.
local MODES = {
  { id = 'solo', label = 'SOLO VOYAGE', desc = 'ONE SHIP, ONE CAPTAIN' },
  { id = 'captains', label = 'TWO CAPTAINS', desc = 'TWO SHIPS, TWO CAPTAINS' },
}

engine.states.title = {
  update = function(dt)
    local hasSave = game.hasSave()
    if hasSave and input.jp('a') then
      SFX.fanfare()
      engine.transition('WELCOME BACK!', function()
        if not game.load() then game.newGame() end
        engine.setState('sail')
      end)
    elseif input.jp(hasSave and 'b' or 'a') then
      SFX.sel()
      engine.setState('modeSelect')
    elseif meta.data.voyagesWon > 0 and input.jp('voyage') then
      SFX.sel()
      engine.setState('port')
    end
  end,

  draw = function()
    local gt = engine.gt
    gfx.setColor(CO.sky); gfx.rectangle('fill', 0, 0, VW, 92)
    gfx.setColor(CO.sun); gfx.rectangle('fill', 252, 14, 16, 16)
    gfx.setColor(CO.sea); gfx.rectangle('fill', 0, 92, VW, VH - 92)
    gfx.setColor(CO.seaL)
    for x = 0, VW - 1, 8 do
      local wy = 92 + util.round(math.sin(gt * 2 + x * 0.11) * 2)
      gfx.rectangle('fill', x, wy, 5, 2)
    end
    local bob = util.round(math.sin(gt * 2.2) * 2)
    sprites.draw('shipP', 148, 76 + bob, false, 2)
    font.drawTextO('PIRATE', VW / 2 - 1, 21, CO.gold, 4, 'center')
    font.drawTextO('PALS', VW / 2 - 1, 46, CO.paper, 4, 'center')
    font.drawTextO('A CO-OP ADVENTURE PROTOTYPE', VW / 2, 72, CO.white, 1, 'center')
    local k1a, k1b = input.promptKey(input.p1, 'a'), input.promptKey(input.p1, 'b')
    local k2a, k2b = input.promptKey(input.p2, 'a'), input.promptKey(input.p2, 'b')
    do
      local a = 0.5 + 0.5 * math.sin(gt * 4)
      font.drawTextO(game.hasSave() and ('PRESS ' .. k1a .. ' TO CONTINUE!') or ('PRESS ' .. k1a .. ' OR TAP TO SET SAIL!'),
        VW / 2, 130, { CO.gold[1], CO.gold[2], CO.gold[3], a }, 1, 'center')
    end
    if game.hasSave() then
      font.drawTextO(k1b .. ' FOR A NEW VOYAGE', VW / 2, 141, CO.foam, 1, 'center')
    end
    if meta.data.voyagesWon > 0 then
      font.drawTextO(input.promptKey(input.p1, 'voyage') .. ' FOR HOME PORT', VW / 2, 151, CO.gold, 1, 'center')
    end
    font.drawTextO('WASD MOVE - ' .. k1a .. ' GO - ' .. k1b .. ' BACK', VW / 2, 161, CO.foam, 1, 'center')
    font.drawTextO('P2: ARROWS MOVE - ' .. k2a .. ' GO - ' .. k2b .. ' BACK', VW / 2, 171, CO.foam, 1, 'center')
  end,
}

local ms = { i = 0 }

local CARD_W, CARD_H, CARD_GAP = 130, 96, 12

-- Which card (0/1) a tap lands on, or nil if it misses both.
local function cardAt(tx, ty)
  local ox = (VW - (CARD_W * 2 + CARD_GAP)) / 2
  if ty < 46 or ty > 46 + CARD_H then return nil end
  for i = 0, 1 do
    local cx = ox + i * (CARD_W + CARD_GAP)
    if tx >= cx and tx < cx + CARD_W then return i end
  end
  return nil
end

engine.states.modeSelect = {
  enter = function() ms.i = 0 end,

  update = function(dt)
    if input.jp('left') or input.jp('right') then
      ms.i = 1 - ms.i
      SFX.move()
    end
    if input.tap then
      local hit = cardAt(input.tap.x, input.tap.y)
      if hit then ms.i = hit end
    end
    if input.jp('a') then
      SFX.sel()
      require('src.states.colorselect').start(MODES[ms.i + 1].id)
    elseif input.jp('b') then
      SFX.back()
      engine.setState('title')
    end
  end,

  draw = function()
    gfx.setColor(CO.sky); gfx.rectangle('fill', 0, 0, VW, VH)
    gfx.setColor(CO.sea); gfx.rectangle('fill', 0, 130, VW, VH - 130)
    font.drawTextO('NEW VOYAGE', VW / 2, 14, CO.gold, 2, 'center')
    font.drawTextO('SAIL SOLO OR TEAM UP!', VW / 2, 32, CO.paper, 1, 'center')

    local cardW, cardH, gap = CARD_W, CARD_H, CARD_GAP
    local totalW = cardW * 2 + gap
    local ox = (VW - totalW) / 2
    for i, m in ipairs(MODES) do
      local cx = ox + (i - 1) * (cardW + gap)
      local sel = i - 1 == ms.i
      gfx.setColor(sel and CO.uiBg2 or CO.uiBg)
      gfx.rectangle('fill', cx, 46, cardW, cardH)
      ui.outline(cx, 46, cardW, cardH, sel and CO.gold or CO.grayD)
      if m.id == 'solo' then
        sprites.draw('shipP', cx + cardW / 2 - 8, 62, false, 1.5)
      else
        sprites.draw('shipP', cx + cardW / 2 - 22, 62, false, 1.2)
        sprites.draw('shipP', cx + cardW / 2 + 6, 66, true, 1.2)
      end
      font.drawText(m.label, cx + cardW / 2, 108, sel and CO.gold or CO.white, 1, 'center')
      font.drawText(m.desc, cx + cardW / 2, 120, CO.gray, 1, 'center')
    end
    font.drawTextO('< > PICK - ' .. input.promptKey(input.p1, 'a') .. ' SAIL - '
      .. input.promptKey(input.p1, 'b') .. ' BACK', VW / 2, 168, CO.foam, 1, 'center')
  end,
}

return {}
