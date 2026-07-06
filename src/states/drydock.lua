local palette = require 'src.palette'
local font = require 'src.font'
local sprites = require 'src.sprites'
local input = require 'src.input'
local audio = require 'src.audio'
local engine = require 'src.engine'
local game = require 'src.game'
local data = require 'src.data'
local ui = require 'src.ui'
local CO = palette.CO
local gfx = love.graphics
local SFX = audio.sfx

local VW, VH = 320, 180

local M = {}
local dd = nil

local ROWS = { 'hull', 'sails', 'guns', 'magazine' }
local ROW_NAMES = {
  hull = 'HULL PLATES',
  sails = 'SAIL RIG',
  guns = 'GUN DECK',
  magazine = 'MAGAZINE'
}

local FITTING_COSTS = {
  hull = {
    [1] = { timber = 4 },
    [2] = { timber = 6, iron = 3 },
    [3] = { timber = 8, iron = 6 }
  },
  sails = {
    [1] = { cloth = 4 },
    [2] = { cloth = 7 },
    [3] = { cloth = 9, timber = 4 }
  },
  guns = {
    [1] = { iron = 4 },
    [2] = { iron = 7 },
    [3] = { iron = 9, timber = 4 }
  }
}

local function canAfford(cost)
  for mat, amt in pairs(cost) do
    if (game.run.salvage[mat] or 0) < amt then return false end
  end
  return true
end

local function deductCost(cost)
  for mat, amt in pairs(cost) do
    game.run.salvage[mat] = game.run.salvage[mat] - amt
  end
end

local function getMagazineOptions()
  local list = { 'none' }
  if game.run and game.run.blueprints then
    if game.run.blueprints.chain then list[#list + 1] = 'chain' end
    if game.run.blueprints.grape then list[#list + 1] = 'grape' end
    if game.run.blueprints.fire then list[#list + 1] = 'fire' end
  end
  return list
end

engine.states.drydock = {
  enter = function()
    dd = { i = 0 }
  end,

  update = function(dt)
    local n = #ROWS
    if input.rp('up') then dd.i = (dd.i + n - 1) % n; SFX.move() end
    if input.rp('down') then dd.i = (dd.i + 1) % n; SFX.move() end

    local rowKey = ROWS[dd.i + 1]
    if rowKey == 'magazine' then
      local opts = getMagazineOptions()
      local curIdx = 1
      local currentSlot = game.run.fittings.slot or 'none'
      for idx, val in ipairs(opts) do
        if val == currentSlot then curIdx = idx end
      end
      if input.rp('left') then
        curIdx = (curIdx - 2 + #opts) % #opts + 1
        game.run.fittings.slot = (opts[curIdx] == 'none') and nil or opts[curIdx]
        SFX.move()
      elseif input.rp('right') then
        curIdx = (curIdx) % #opts + 1
        game.run.fittings.slot = (opts[curIdx] == 'none') and nil or opts[curIdx]
        SFX.move()
      end
    else
      if input.jp('a') then
        local curTier = game.run.fittings[rowKey] or 0
        local y = 35 + dd.i * 26
        if curTier >= 3 then
          SFX.bump()
          engine.addFloat(180, y, 'MAXED OUT!', CO.gray, 1)
        else
          local nextTier = curTier + 1
          local cost = FITTING_COSTS[rowKey][nextTier]
          if canAfford(cost) then
            deductCost(cost)
            game.run.fittings[rowKey] = nextTier
            sprites.buildFittedShip(game.colorOf('p1'))
            if game.isCoop() then
              sprites.buildFittedShip(game.colorOf('p2'))
            end
            SFX.buy()
            engine.addParts(180, y + 10, 8, CO.gold, 30)
            engine.addFloat(180, y, 'UPGRADED!', CO.gold, 1)
          else
            SFX.bump()
            engine.addFloat(180, y, 'LACK MATERIALS!', CO.red, 1)
          end
        end
      end
    end

    if input.jp('b') then
      SFX.back()
      engine.setState('dock')
    end
  end,

  draw = function()
    gfx.setColor(CO.woodD)
    gfx.rectangle('fill', 0, 0, VW, VH)
    gfx.setColor(CO.wood)
    gfx.rectangle('fill', 4, 4, VW - 8, VH - 8)

    font.drawTextO('DRY DOCK', VW / 2, 8, CO.gold, 2, 'center')

    -- Draw upgrade rows
    for idx, key in ipairs(ROWS) do
      local y = 35 + (idx - 1) * 26
      local sel = dd.i == idx - 1
      if sel then
        gfx.setColor(CO.uiBg)
        gfx.rectangle('fill', 8, y - 2, 192, 24)
        ui.outline(8, y - 2, 192, 24, CO.gold)
      end

      local label = ROW_NAMES[key]
      font.drawText(label, 12, y, sel and CO.gold or CO.white, 1)

      if key == 'magazine' then
        local currentSlot = game.run.fittings.slot
        local slotText = currentSlot and data.SHOTS[currentSlot].label or 'NONE'
        font.drawText('< ' .. slotText .. ' >', 12, y + 10, CO.paper, 1)
      else
        local tier = game.run.fittings[key] or 0
        local pips = ''
        for t = 1, 3 do pips = pips .. (t <= tier and '*' or '.') end
        font.drawText(pips, 12, y + 10, CO.gold, 1)

        if tier >= 3 then
          font.drawText('MAX', 80, y + 10, CO.gray, 1)
        else
          local cost = FITTING_COSTS[key][tier + 1]
          local cx = 80
          for mat, amt in pairs(cost) do
            sprites.draw('sal_' .. mat, cx, y + 8, false, 1)
            font.drawText(tostring(amt), cx + 14, y + 10, CO.white, 1)
            cx = cx + 32
          end
        end
      end
    end

    -- Draw ships on the right side
    if game.isCoop() then
      sprites.draw(sprites.shipSprite(game.colorOf('p1')), 210, 45, false, 4)
      sprites.draw(sprites.shipSprite(game.colorOf('p2')), 260, 65, false, 4)
      font.drawText('FLEET', 255, 125, CO.paper, 1, 'center')
    else
      sprites.draw(sprites.shipSprite(game.colorOf('p1')), 225, 45, false, 5)
      font.drawText('YOUR SHIP', 265, 125, CO.paper, 1, 'center')
    end

    -- Draw resources summary at the bottom
    local rx = 10
    local ry = 145
    gfx.setColor(CO.uiBg)
    gfx.rectangle('fill', rx, ry, VW - 2 * rx, 25)
    ui.outline(rx, ry, VW - 2 * rx, 25, CO.gold)

    -- Draw gold
    sprites.draw('coinS', rx + 10, ry + 9)
    font.drawTextO('' .. game.run.gold, rx + 20, ry + 10, CO.gold, 1)

    -- Draw salvage
    sprites.draw('sal_timber', rx + 75, ry + 5)
    font.drawTextO('' .. game.run.salvage.timber, rx + 90, ry + 10, CO.white, 1)

    sprites.draw('sal_cloth', rx + 145, ry + 5)
    font.drawTextO('' .. game.run.salvage.cloth, rx + 160, ry + 10, CO.white, 1)

    sprites.draw('sal_iron', rx + 215, ry + 5)
    font.drawTextO('' .. game.run.salvage.iron, rx + 230, ry + 10, CO.white, 1)
  end
}

return M
