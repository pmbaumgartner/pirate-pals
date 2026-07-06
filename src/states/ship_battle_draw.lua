local util = require 'src.util'
local palette = require 'src.palette'
local font = require 'src.font'
local sprites = require 'src.sprites'
local engine = require 'src.engine'
local game = require 'src.game'
local data = require 'src.data'
local ui = require 'src.ui'
local timing = require 'src.timing'
local shipRules = require 'src.ship_rules'

local CO = palette.CO
local gfx = love.graphics
local VW = 320
local SUBMENU_SPECIAL = 'special'
local SUBMENU_SHOT = 'shot'

local INTENT_ICON = {
  fire = 'icon_fire',
  bigshot = 'icon_bigshot',
  volley = 'icon_volley',
  fix = 'icon_fix',
  move = 'icon_move',
  douse = 'icon_move',
}

local INTENT_COLOR = {
  fire = CO.orange,
  bigshot = CO.red,
  volley = CO.orange,
  fix = CO.green,
  move = CO.white,
  douse = CO.white,
}

local INTENT_LABEL = {
  fire = 'SHOT!',
  bigshot = 'BIG SHOT!',
  volley = 'DOUBLE SHOT!',
  fix = 'PATCHING!',
  move = 'MOVING!',
  douse = 'DOUSE FIRE!',
}

local M = {}

local function drawStatusRight(ent, x, y)
  local sails = (ent.sailsStage < 0) and string.rep('[', -ent.sailsStage) or ''
  local guns = (ent.gunsStage < 0) and string.rep('[', -ent.gunsStage) or ''
  local fire = (ent.ablaze and ent.ablaze > 0) and ']' or ''
  local curX = x
  if fire ~= '' then
    curX = curX - font.textWidth(fire, 1)
    font.drawText(fire, curX, y, CO.orange, 1)
    curX = curX - 2
  end
  if guns ~= '' then
    curX = curX - font.textWidth(guns, 1)
    font.drawText(guns, curX, y, CO.red, 1)
    curX = curX - 2
  end
  if sails ~= '' then
    curX = curX - font.textWidth(sails, 1)
    font.drawText(sails, curX, y, CO.orange, 1)
  end
end

local function drawStatusLeft(ent, x, y)
  local curX = x
  if ent.sailsStage < 0 then
    local arrows = string.rep('[', -ent.sailsStage)
    font.drawText(arrows, curX, y, CO.orange, 1)
    curX = curX + font.textWidth(arrows, 1) + 2
  end
  if ent.gunsStage < 0 then
    local arrows = string.rep('[', -ent.gunsStage)
    font.drawText(arrows, curX, y, CO.red, 1)
    curX = curX + font.textWidth(arrows, 1) + 2
  end
  if ent.ablaze and ent.ablaze > 0 then
    font.drawText(']', curX, y, CO.orange, 1)
  end
end

local function drawRepairPips(ent, x, y)
  local active = string.rep('{', ent.repairs)
  local spent = string.rep('{', ent.maxRepairs - ent.repairs)
  font.drawText(active, x, y, CO.orange, 1)
  font.drawText(spent, x + ent.repairs * 4, y, CO.grayD, 1)
end

local function drawFoeRepairPips(foe)
  local spent = string.rep('{', foe.maxRepairs - foe.repairs)
  local active = string.rep('{', foe.repairs)
  font.drawText(spent, VW - 6, 21, CO.grayD, 1, 'right')
  font.drawText(active, VW - 6 - (foe.maxRepairs - foe.repairs) * 4, 21, CO.orange, 1, 'right')
end

local function drawBossKegs(foe)
  local rx = VW - 6 - foe.maxRepairs * 4 - 6
  local volleySpent = string.rep('}', foe.maxVolleyKegs - foe.volleyKegs)
  local volleyActive = string.rep('}', foe.volleyKegs)
  font.drawText(volleySpent, rx, 21, CO.grayD, 1, 'right')
  font.drawText(volleyActive, rx - (foe.maxVolleyKegs - foe.volleyKegs) * 4, 21, CO.orange, 1, 'right')

  local bx = rx - foe.maxVolleyKegs * 4 - 4
  local bigshotSpent = string.rep('}', foe.maxBigshotKegs - foe.bigshotKegs)
  local bigshotActive = string.rep('}', foe.bigshotKegs)
  font.drawText(bigshotSpent, bx, 21, CO.grayD, 1, 'right')
  font.drawText(bigshotActive, bx - (foe.maxBigshotKegs - foe.bigshotKegs) * 4, 21, CO.red, 1, 'right')
end

local function foeHeader(foe, isBoss)
  if isBoss then return foe.name .. " - WEAK: " .. foe.weak:upper() end
  local className = foe.class:upper()
  if className == 'MANOWAR' then className = 'MAN-O-WAR' end
  return "CAP'N " .. foe.name .. " - " .. className .. " - WEAK: " .. foe.weak:upper()
end

local function shotPowder(sh, shotId)
  if shotId == 'round' then return 'oo' end
  return tostring(sh.powder[shotId])
end

local function drawShotMenu(sb, sh, h)
  local shots = shipRules.getKnownShots()
  if h.full then
    local bw, bh = 170, #shots * 12 + 24
    local bx, by = (VW - bw) / 2, 132 - bh
    gfx.setColor(CO.uiBg)
    gfx.rectangle('fill', bx, by, bw, bh)
    ui.outline(bx, by, bw, bh, CO.gold)
    font.drawText('SELECT SHOT', bx + bw / 2, by + 4, CO.gold, 1, 'center')
    for i = 0, #shots - 1 do
      local shotId = shots[i + 1]
      local minDmg, maxDmg = shipRules.getShotPreview(sh, sb.foe, shotId)
      local label = data.SHOTS[shotId].label .. ' x' .. shotPowder(sh, shotId)
      local col = (sh.powder[shotId] <= 0) and CO.grayD or (i == sh.sub and CO.gold or CO.white)
      font.drawText((i == sh.sub and '>' or ' ') .. label, bx + 6, by + 14 + i * 12, col, 1)
      font.drawText(minDmg .. '-' .. maxDmg, bx + bw - 6, by + 14 + i * 12, col, 1, 'right')
    end
    local desc = ({
      round = 'PLAIN HULL DAMAGE',
      chain = 'FOE SAILS -1 (CANCELS MOVE)',
      grape = 'FOE GUNS -1 (BOARDING SETUP)',
      fire = 'ABLAZE: 4 DMG/TURN',
    })[shots[sh.sub + 1]] or ''
    font.drawText(desc, bx + 6, by + bh - 10, CO.gray, 1)
    return
  end

  local first = math.max(0, math.min(sh.sub - 1, #shots - 2))
  for row = 0, 1 do
    local pi = first + row
    if pi <= #shots - 1 then
      local shotId = shots[pi + 1]
      local shotData = data.SHOTS[shotId]
      local minDmg, maxDmg = shipRules.getShotPreview(sh, sb.foe, shotId)
      local col = (sh.powder[shotId] <= 0) and CO.grayD or (pi == sh.sub and h.col or CO.white)
      font.drawText((pi == sh.sub and '>' or ' ') .. shotData.label .. ' x' .. shotPowder(sh, shotId) .. ' ' .. minDmg .. '-' .. maxDmg,
        h.x, 163 + row * 8, col, 1)
    end
  end
end

local function drawSpecialMenu(sh, h, specialPartyFor)
  local plist = specialPartyFor()
  if h.full then
    local n = #plist
    if n == 0 then return end
    local bw, bh = 170, n * 12 + 24
    local bx, by = (VW - bw) / 2, 132 - bh
    gfx.setColor(CO.uiBg)
    gfx.rectangle('fill', bx, by, bw, bh)
    ui.outline(bx, by, bw, bh, CO.gold)
    font.drawText('CREW SPECIALS', bx + bw / 2, by + 4, CO.gold, 1, 'center')
    for i = 0, n - 1 do
      local pp = plist[i + 1]
      local col = i == sh.sub and CO.gold or CO.white
      font.drawText((i == sh.sub and '>' or ' ') .. pp.name .. ' - ' .. data.ROLES[pp.role].ship.name,
        bx + 6, by + 14 + i * 12, col, 1)
    end
    font.drawText(data.ROLES[plist[sh.sub + 1].role].ship.desc, bx + 6, by + bh - 10, CO.gray, 1)
    return
  end

  local first = math.max(0, math.min(sh.sub - 1, #plist - 2))
  for row = 0, 1 do
    local pi = first + row
    if pi <= #plist - 1 then
      local pp = plist[pi + 1]
      font.drawText((pi == sh.sub and '>' or ' ') .. pp.name .. ' - ' .. data.ROLES[pp.role].ship.name,
        h.x, 163 + row * 8, pi == sh.sub and h.col or CO.white, 1)
    end
  end
end

local function drawShipCommandMenu(sb, view, i, h)
  local sh = sb.ships[i]
  local itemY = h.itemY or 163
  if h.title then
    font.drawText(h.title .. (sh.range == 'NEAR' and 'CLOSE!' or 'FAR'), h.x, 153, h.col, 1)
  end

  if sh.chosen then
    font.drawText('WAITING...', h.x, itemY, CO.gray, 1)
  elseif sh.submenu == SUBMENU_SPECIAL then
    drawSpecialMenu(sh, h, function() return view.specialPartyFor(i) end)
  elseif sh.submenu == SUBMENU_SHOT then
    drawShotMenu(sb, sh, h)
  else
    local items = view.shipMenuItems(i)
    sh.menu = math.min(sh.menu, #items - 1)
    if h.full then
      local iw = math.floor((VW - 8) / #items)
      for ii = 0, #items - 1 do
        local bx = 4 + ii * iw
        local sel = ii == sh.menu
        gfx.setColor(sel and CO.uiBg2 or CO.ink)
        gfx.rectangle('fill', bx, 153, iw - 4, 14)
        if sel then ui.outline(bx, 153, iw - 4, 14, CO.gold) end
        local it = items[ii + 1]
        local labelCol = not it.ok and CO.grayD or (sel and CO.gold or CO.white)
        font.drawText(it.label, bx + (iw - 4) / 2, 158, labelCol, 1, 'center')
      end
      font.drawText(items[sh.menu + 1].desc, VW / 2, 171, CO.gray, 1, 'center')
    else
      for ii = 0, #items - 1 do
        local it = items[ii + 1]
        local col = not it.ok and CO.grayD or (ii == sh.menu and h.col or CO.white)
        font.drawText((ii == sh.menu and '>' or ' ') .. it.label,
          h.x + (ii % 2) * 72, itemY + math.floor(ii / 2) * 8, col, 1)
      end
    end
  end
end

local function drawCommandMenus(sb, view)
  if sb.turn ~= 'select' or sb.over or sb.co then return end
  if not sb.fleet then
    drawShipCommandMenu(sb, view, 1, { x = 4, col = CO.gold, full = true })
    return
  end

  local halves = { { x = 4, col = CO.gold }, { x = VW / 2 + 2, col = CO.green } }
  for i, sh in ipairs(sb.ships) do
    local h = halves[i]
    drawShipCommandMenu(sb, view, i, { x = h.x, col = h.col, title = i == 1 and 'P1: ' or 'P2: ' })
  end
end

local function drawSea(gt)
  gfx.setColor(CO.sky); gfx.rectangle('fill', 0, 0, VW, 100)
  gfx.setColor(CO.skyD); gfx.rectangle('fill', 0, 84, VW, 16)
  gfx.setColor(CO.sun); gfx.rectangle('fill', 188, 12, 14, 14)
  gfx.setColor(CO.white)
  gfx.rectangle('fill', 40, 24, 26, 5); gfx.rectangle('fill', 50, 20, 14, 5)
  gfx.rectangle('fill', 210, 34, 22, 5)
  gfx.setColor(CO.sea); gfx.rectangle('fill', 0, 100, VW, 40)
  gfx.setColor(CO.seaL)
  for i = 0, VW - 1, 10 do
    gfx.rectangle('fill', i + math.floor(gt * 8) % 10, 104 + (i % 3) * 9, 6, 1)
  end
end

local function drawShips(sb, shipXY, gt)
  local fpx, fpy = shipXY('foe')
  local bobF = util.round(math.sin(gt * 2.3 + 2) * 1.5)
  if sb.isBoss then
    sprites.draw('shipKing', fpx - 16, fpy + bobF - 16, true, 3)
  else
    local spriteName = 'ship' .. sb.foe.class:sub(1, 1):upper() .. sb.foe.class:sub(2)
    sprites.draw(spriteName, fpx, fpy + bobF, true, 2)
  end
  if sb.foe.dodge > 0 then font.drawTextO('*', fpx + 14, fpy - 4 + bobF, CO.foam, 2) end

  for i, sh in ipairs(sb.ships) do
    local x, y = shipXY(i)
    local bob = util.round(math.sin(gt * 2.3 + i) * 1.5)
    sprites.draw(sprites.shipSprite(game.colorOf(i == 1 and 'p1' or 'p2')), x, y + bob, false, 2)
    if sh.dodge > 0 then font.drawTextO('*', x + 14, y - 4 + bob, CO.foam, 2) end
    if sh.patched then font.drawTextO('~', x + 14, y - 4 + bob, CO.orange, 2) end
  end
  return fpx, fpy, bobF
end

local function drawIntent(sb, shipXY, fpx, fpy, bobF)
  local pickPhase = sb.turn == 'select'
  if not (pickPhase and not sb.over and sb.foe.intent) then return end
  local iconName = INTENT_ICON[sb.foe.intent]
  local intentCol = INTENT_COLOR[sb.foe.intent]
  local label = INTENT_LABEL[sb.foe.intent]
  local tx, ty
  if sb.fleet and sb.foe.intent ~= 'fix' and sb.foe.intent ~= 'douse' then
    tx, ty = shipXY(sb.foe.target)
  else
    tx, ty = fpx, fpy
  end
  if iconName then ui.drawIntentIcon(iconName, tx + 2, ty - 22 + (sb.fleet and 0 or bobF), 1, intentCol) end
  if label then
    local w = font.textWidth(label, 1)
    local lx = util.clamp(tx + 16, w / 2 + 2, VW - w / 2 - 2)
    font.drawTextO(label, lx, ty - 34, intentCol or CO.white, 1, 'center')
  end
end

local function drawBall(sb)
  if not (sb.anim and sb.anim.type == 'ball') then return end
  local a = sb.anim
  local t = util.clamp(a.t / a.dur, 0, 1)
  local bx = util.lerp(a.x0, a.x1, t)
  local by = util.lerp(a.y0, a.y1, t) - math.sin(math.pi * t) * 30
  gfx.setColor(CO.ink)
  gfx.rectangle('fill', util.round(bx) - 1, util.round(by) - 1, 4, 4)
end

local function drawPlayerBars(sb)
  if sb.fleet then
    for i, sh in ipairs(sb.ships) do
      local by = i == 1 and 6 or 24
      local col = i == 1 and CO.gold or CO.green
      local hpText = sh.hp .. '/' .. sh.max
      font.drawText((i == 1 and 'P1 SHIP' or 'P2 SHIP') .. (sh.patched and ' (PATCHING)' or ''), 6, by, col, 1)
      ui.drawBar(6, by + 7, 70, 6, sh.hp / sh.max)
      font.drawText(hpText, 80, by + 7, CO.white, 1)
      drawRepairPips(sh, 6, by + 15)
      drawStatusLeft(sh, 80 + font.textWidth(hpText, 1) + 4, by + 7)
    end
  else
    local sh = sb.ships[1]
    local hpText = sh.hp .. '/' .. sh.max
    font.drawText('YOUR SHIP', 6, 6, CO.white, 1)
    ui.drawBar(6, 13, 90, 6, sh.hp / sh.max)
    font.drawText(hpText, 100, 13, CO.white, 1)
    drawRepairPips(sh, 6, 21)
    drawStatusLeft(sh, 100 + font.textWidth(hpText, 1) + 4, 13)
  end
end

local function drawFoeBar(sb)
  font.drawText(foeHeader(sb.foe, sb.isBoss), VW - 6, 6, CO.white, 1, 'right')
  ui.drawBar(VW - 96, 13, 90, 6, sb.foe.hp / sb.foe.max)
  local hpText = sb.foe.hp .. '/' .. sb.foe.max
  local hpW = font.textWidth(hpText, 1)
  font.drawText(hpText, VW - 102, 13, CO.white, 1, 'right')
  local lvText = 'LV ' .. sb.foe.lv
  local lvX = VW - 102 - hpW - 6
  font.drawText(lvText, lvX, 13, CO.red, 1, 'right')
  drawFoeRepairPips(sb.foe)
  if sb.isBoss then drawBossKegs(sb.foe) end
  drawStatusRight(sb.foe, lvX - font.textWidth(lvText, 1) - 6, 13)
end

function M.draw(sb, view)
  local gt = engine.gt
  drawSea(gt)
  local fpx, fpy, bobF = drawShips(sb, view.shipXY, gt)
  drawIntent(sb, view.shipXY, fpx, fpy, bobF)
  drawBall(sb)
  engine.drawFx()
  drawPlayerBars(sb)
  drawFoeBar(sb)

  if not sb.fleet then
    font.drawTextO(sb.ships[1].range == 'NEAR' and 'CLOSE!' or 'FAR', VW / 2, 26, CO.paper, 1, 'center')
  end

  gfx.setColor(CO.uiBg)
  gfx.rectangle('fill', 0, 140, VW, 40)
  font.drawText(sb.msg, VW / 2, 144, CO.paper, 1, 'center')
  drawCommandMenus(sb, view)
  timing.draw()
end

return M
