-- Sail mode: hop the ship around a hex sea (odd-r offset grid, pointy-top
-- hexes — see grid.lua). Bumping an enemy ship starts the encounter chain
-- (ship battle -> boarding battle -> loot); chests, the port (tailor), and
-- the whirlpool exit are tile triggers. Movement is d-pad (up/down pick the
-- NE/NW or SE/SW diagonal based on the ship's facing, with an on-map
-- preview) or tap/click a hex to auto-sail there.
--
-- Update/draw orchestration only: hex geometry lives in sail_map.lua, tile
-- triggers / biome rules / co-op movement helpers live in sail_rules.lua.
local util = require 'src.util'
local grid = require 'src.grid'
local palette = require 'src.palette'
local font = require 'src.font'
local sprites = require 'src.sprites'
local input = require 'src.input'
local audio = require 'src.audio'
local engine = require 'src.engine'
local game = require 'src.game'
local data = require 'src.data'
local chart = require 'src.states.chart'
local sailMap = require 'src.states.sail_map'
local rules = require 'src.states.sail_rules'
local CO = palette.CO
local gfx = love.graphics
local SFX = audio.sfx

local VW = 320
local SEA_W, SEA_H, SEA_TOP = game.SEA_W, game.SEA_H, game.SEA_TOP
local SEA_BAND = sailMap.SEA_BAND
local hexCenter, sailPx, hexAt, hexStep, inSea = sailMap.hexCenter, sailMap.sailPx, sailMap.hexAt, sailMap.hexStep, sailMap.inSea
local drawHexOutline, drawChevron, drawWhirl = sailMap.drawHexOutline, sailMap.drawChevron, sailMap.drawWhirl

-- Biome palettes: each biome recolors the water so a kid clocks the
-- sea type at a glance before reading anything. Twist rules stay flag-driven
-- off run.sea.biome below — no biome-plugin abstraction until there are >=5.
local hexc = palette.hex
local BIOME_SEA = {
  calm    = { sea = CO.sea, seaD = CO.seaD, seaL = CO.seaL },
  icy     = { sea = hexc '#4f93c9', seaD = hexc '#3a70ad', seaL = hexc '#8fd0e8' },
  foggy   = { sea = hexc '#4a6584', seaD = hexc '#3a5068', seaL = hexc '#6d87a3' },
  volcano = { sea = hexc '#50395a', seaD = hexc '#3a2842', seaL = hexc '#7a5670' },
}

local function seaCols()
  return BIOME_SEA[game.run.sea.biome] or BIOME_SEA.calm
end

local function drawMovePreview(sh, playerColor, gt)
  if not sh.anim and not sh.route then
    local pulse = 0.3 + 0.18 * math.sin(gt * 4)
    for _, dir in ipairs({ 'left', 'right', 'up', 'down' }) do
      local tx, ty = hexStep(sh.x, sh.y, dir, sh.face)
      if inSea(tx, ty) and game.tileAt(tx, ty) ~= game.T_ISLE then
        local cx, cy = hexCenter(tx, ty)
        gfx.setColor(playerColor[1], playerColor[2], playerColor[3], pulse)
        drawHexOutline(cx, cy)
        drawChevron(cx, cy, dir)
      end
    end
  end
end

engine.states.sail = {
  -- Every path back to sail mode (new game, next sea, port, crew/log menus,
  -- battle win/loss) routes through here, so this is the one autosave point.
  enter = function()
    input.setCoop(game.run.mode == 'captains')
    -- Announce the biome twist once, on first entry to a fresh sea (the
    -- `announced` latch rides in run.sea so battles/menus don't re-trigger it).
    local sea = game.run.sea
    if sea and not sea.announced then
      sea.announced = true
      local b = data.BIOMES[sea.biome or 'calm']
      if sea.biome and sea.biome ~= 'calm' and b then
        engine.showBanner(b.name .. '! ' .. b.twist, CO.foam, 1.6)
      end
    end
    rules.checkKingSniff()
    game.save()
  end,

  update = function(dt)
    local run = game.run
    local sh = run.ship
    local fleet = run.mode == 'captains'
    if input.jp('crew') then SFX.sel(); engine.setState('crew'); return end
    if input.jp('log') then SFX.sel(); engine.setState('log'); return end
    if input.jp('voyage') then SFX.sel(); chart.startView(); return end
    if input.jp('vlog') then SFX.sel(); engine.setState('voyagelog', 'sail'); return end

    -- A has no other job at sea, so P1 pressing it is always the dig-anywhere
    -- verb (for the 'seashell' secret) rather than something to disambiguate.
    if input.p1.jp('a') and not sh.anim and not sh.route then rules.tryDig() end

    -- Taps plan a route from the ship's logical cell, even mid-hop. Touch
    -- is P1-only by design, so this always routes ship (not ship2).
    if input.tap then
      local tx, ty = hexAt(input.tap.x, input.tap.y)
      if tx and not (tx == sh.x and ty == sh.y) then
        local route = sailMap.planRoute(sh, tx, ty)
        if route then
          sh.route = route
          run.hints.move = true
          SFX.sel()
        else
          SFX.bump()
        end
      end
    end

    rules.checkEchoBark(sh)
    rules.updateBootsong(dt, run, sh)
    rules.updateFishFriend(dt, run, sh)

    if rules.tickShip(sh, input.p1, 'ship', dt) == 'stop' then return end

    if fleet then
      rules.updateConvoy(dt)
      if rules.tickShip(run.ship2, input.p2, 'ship2', dt) == 'stop' then return end
      rules.updateAnchor(dt)
    end
    rules.updateRocks(dt)

    if rules.driftEnemies(dt) then return end
  end,

  draw = function()
    local gt = engine.gt
    local run = game.run

    -- Sea with a drifting shimmer pattern, tinted by the biome palette.
    local bc = seaCols()
    gfx.setColor(bc.sea)
    gfx.rectangle('fill', 0, SEA_TOP, VW, SEA_BAND)
    for y = 0, SEA_H - 1 do
      for x = 0, SEA_W - 1 do
        local h = (x * 71 + y * 53 + math.floor(gt * 2.2) * 37) % 31
        if h == 0 then
          local px, py = sailPx(x, y)
          gfx.setColor(bc.seaL)
          gfx.rectangle('fill', px + 4, py + 9, 5, 1)
        elseif h == 8 then
          local px, py = sailPx(x, y)
          gfx.setColor(bc.seaD)
          gfx.rectangle('fill', px + 8, py + 4, 4, 1)
        end
      end
    end

    -- Visible hex grid on sailable cells, under the tile sprites.
    gfx.setColor(bc.seaL[1], bc.seaL[2], bc.seaL[3], 0.28)
    for y = 0, SEA_H - 1 do
      for x = 0, SEA_W - 1 do
        if run.sea.t[y][x] ~= game.T_ISLE then
          local cx, cy = hexCenter(x, y)
          drawHexOutline(cx, cy)
        end
      end
    end

    -- Slick sheen on icy hexes: white streaks so "the slidey ones" are
    -- readable before the first surprise ride.
    if run.sea.biome == 'icy' then
      gfx.setColor(CO.white[1], CO.white[2], CO.white[3], 0.4)
      for k in pairs(run.sea.slick) do
        local x, y = grid.parseKey(k)
        local cx, cy = hexCenter(x, y)
        gfx.rectangle('fill', cx - 4, cy + 1, 6, 1)
        gfx.rectangle('fill', cx - 1, cy - 3, 6, 1)
      end
    end

    for y = 0, SEA_H - 1 do
      for x = 0, SEA_W - 1 do
        local t = run.sea.t[y][x]
        local px, py = sailPx(x, y)
        if t == game.T_ISLE then sprites.draw('island', px, py)
        elseif t == game.T_CHEST then sprites.draw('chest', px, py + util.round(math.sin(gt * 2.5 + x)))
        elseif t == game.T_PORT then sprites.draw('port', px, py)
        elseif t == game.T_EXIT then drawWhirl(px, py, gt, CO, util)
        elseif t == game.T_BOTTLE then sprites.draw('bottleT', px, py + util.round(math.sin(gt * 2.5 + x)))
        elseif t == game.T_TRADER then sprites.draw('trader', px, py + util.round(math.sin(gt * 2 + x)))
        elseif t == game.T_X then sprites.draw('xmark', px, py) end
      end
    end

    -- Foggy biome: 2-3 drifting horizontal fog bands, stepped low alphas
    -- with a coarse dithered edge. Draw-layer only (no lights/shaders), and
    -- under the movement previews so telegraphs stay fully readable.
    if run.sea.biome == 'foggy' then
      for _, band in ipairs({
        { y = SEA_TOP + 18, h = 12, a = 0.10, spd = 5 },
        { y = SEA_TOP + 62, h = 14, a = 0.18, spd = -3 },
        { y = SEA_TOP + 108, h = 12, a = 0.26, spd = 2 },
      }) do
        gfx.setColor(CO.gray[1], CO.gray[2], CO.gray[3], band.a)
        gfx.rectangle('fill', 0, band.y, VW, band.h)
        local off = math.floor(gt * band.spd)
        for x = 0, VW - 2, 2 do
          local even = (x / 2 + off) % 2 == 0
          if even then gfx.rectangle('fill', x, band.y - 2, 2, 2)
          else gfx.rectangle('fill', x, band.y + band.h, 2, 2) end
        end
      end
    end

    -- Telegraphed volcano rocks: pulsing hex, rock drops in at the end.
    if run.sea.biome == 'volcano' then
      for _, rk in ipairs(run.sea.rocks) do
        local cx, cy = hexCenter(rk.x, rk.y)
        local pulse = math.floor(gt * 6) % 2 == 0
        gfx.setColor(CO.orange[1], CO.orange[2], CO.orange[3], pulse and 0.75 or 0.35)
        drawHexOutline(cx, cy)
        if rk.t < 0.5 then
          sprites.draw('rock', cx - 4, cy - 4 - rk.t * 90)
        end
      end
    end

    local sh = run.ship

    drawMovePreview(sh, CO.foam, gt)
    if run.mode == 'captains' and run.ship2 and not run.ship2.convoy then
      -- P2's preview matches their green ship/convoy accents so the two
      -- captains can tell whose chevrons are whose.
      drawMovePreview(run.ship2, CO.green, gt)
    end

    -- Route breadcrumbs while the autopilot is sailing.
    if sh.route then
      gfx.setColor(CO.foam[1], CO.foam[2], CO.foam[3], 0.55)
      for _, s in ipairs(sh.route.steps) do
        local cx, cy = hexCenter(s[1], s[2])
        gfx.rectangle('fill', cx - 1, cy - 1, 2, 2)
      end
    end

    -- Labels near landmarks.
    if run.sea.port and grid.hexDistance(sh.x, sh.y, run.sea.port.x, run.sea.port.y) <= 2 then
      local cx, cy = hexCenter(run.sea.port.x, run.sea.port.y)
      local w = font.textWidth('TAILOR', 1)
      cx = util.clamp(cx, w / 2 + 2, VW - w / 2 - 2)
      font.drawTextO('TAILOR', cx, cy - 15, CO.paper, 1, 'center')
    end
    if run.sea.exit and grid.hexDistance(sh.x, sh.y, run.sea.exit.x, run.sea.exit.y) <= 3 then
      local cx, cy = hexCenter(run.sea.exit.x, run.sea.exit.y)
      local w = font.textWidth('NEXT SEA', 1)
      cx = util.clamp(cx, w / 2 + 2, VW - w / 2 - 2)
      font.drawTextO('NEXT SEA', cx, cy - 15, CO.foam, 1, 'center')
    end

    for i, e in ipairs(run.sea.enemies) do
      local px, py = sailPx(e.fx, e.fy)
      local bobE = util.round(math.sin(gt * 2.4 + (i - 1) * 1.7))
      if not rules.enemyVisible(e) then
        gfx.setColor(CO.foam[1], CO.foam[2], CO.foam[3], 0.6)
        gfx.rectangle('fill', px + 4, py + 10 + bobE, 8, 2)
        font.drawTextO('?', px + 8, py + bobE, CO.paper, 1, 'center')
      elseif e.boss then
        sprites.draw('shipKing', px - 4, py + bobE - 4, e.fx > sh.fx, 1.5)
        local w = font.textWidth('THE KING', 1)
        local labelX = util.clamp(px + 8, w / 2 + 2, VW - w / 2 - 2)
        font.drawTextO('THE KING', labelX, py - 10, CO.red, 1, 'center')
      else
        sprites.draw('shipE', px, py + bobE, e.fx > sh.fx)
        local label = 'LV ' .. e.lv
        local w = font.textWidth(label, 1)
        local labelX = util.clamp(px + 8, w / 2 + 2, VW - w / 2 - 2)
        font.drawTextO(label, labelX, py - 10, CO.gold, 1, 'center')
      end
    end

    local px, py = sailPx(sh.fx, sh.fy)
    sprites.draw(sprites.shipSprite(game.colorOf('p1')), px, py + util.round(math.sin(gt * 2.6)), sh.face < 0)
    if run.mode == 'captains' then
      local sh2 = run.ship2
      local p2x, p2y = sailPx(sh2.fx, sh2.fy)
      -- Sharing a hex is fine (ships never block each other); nudge the
      -- sprite so they're still both visible rather than one hiding it.
      if sh2.x == sh.x and sh2.y == sh.y then p2x, p2y = p2x + 4, p2y + 4 end
      sprites.draw(sprites.shipSprite(game.colorOf('p2')), p2x, p2y + util.round(math.sin(gt * 2.6 + 1)), sh2.face < 0)
      if sh2.convoy then
        font.drawTextO('~', p2x + 8, p2y - 10 + util.round(math.sin(gt * 5)), CO.green, 1, 'center')
      end
      if run.sea.anchor then
        local anc = run.sea.anchor
        local waitingSh = anc.who == 'ship2' and sh2 or sh
        local otherSh = anc.who == 'ship2' and sh or sh2
        local wx, wy = sailPx(waitingSh.fx, waitingSh.fy)
        if math.floor(gt * 3) % 2 == 0 then
          font.drawTextO('!', wx + 8, wy - 12, CO.gold, 1, 'center')
        end
        local dx = otherSh.fx >= waitingSh.fx and 1 or -1
        font.drawTextO(dx > 0 and '>>' or '<<', wx + 8 + dx * 10, wy, CO.gold, 1, 'center')
      end
    end
    engine.drawFx()

    -- HUD.
    gfx.setColor(CO.uiBg)
    gfx.rectangle('fill', 0, 0, VW, SEA_TOP)
    font.drawText('SEA ' .. run.sea.lv, 5, 7, CO.foam, 1)
    if run.sea.biome and run.sea.biome ~= 'calm' then
      sprites.draw(data.BIOMES[run.sea.biome].icon, 34, 4)
    end
    sprites.draw('coinS', 52, 7)
    font.drawText('' .. run.gold, 62, 7, CO.gold, 1)
    sprites.draw('gemS', 96, 7)
    font.drawText(game.distinctTreasures() .. '/12', 106, 7, CO.purple, 1)
    font.drawText('CREW ' .. #run.crew, 146, 7, CO.paper, 1)
    local ip = input.promptKey
    font.drawText(ip(input.p1, 'crew') .. ' CREW  ' .. ip(input.p1, 'log') .. ' LOG  '
      .. ip(input.p1, 'voyage') .. ' CHART  ' .. ip(input.p1, 'vlog') .. ' VOYAGE',
      VW - 5, 7, CO.gray, 1, 'right')

    -- Bottom hint bar.
    gfx.setColor(CO.uiBg)
    gfx.rectangle('fill', 0, SEA_TOP + SEA_BAND, VW, 16)
    local hint = ''
    if not run.hints.move then hint = 'SAIL WITH ARROWS OR TAP THE SEA!'
    elseif not run.hints.foe then hint = 'BUMP A SPOOKY SHIP TO BATTLE!'
    elseif not run.hints.sea2 and run.sea.exit then hint = 'RIDE THE WHIRLPOOL TO THE NEXT SEA!'
    elseif run.sea.boss then hint = 'THE PIRATE KING AWAITS!'
    elseif run.quest and run.quest.sea == run.sea.lv then hint = 'FIND THE X AND DIG!'
    elseif run.quest then hint = 'X MARKS SEA ' .. run.quest.sea .. '!'
    elseif run.sea.biome and run.sea.biome ~= 'calm' then
      hint = data.BIOMES[run.sea.biome].twist
    end
    font.drawText(hint, VW / 2, SEA_TOP + SEA_BAND + 5, CO.paper, 1, 'center')
  end,
}

return {}
