-- Boarding-battle rendering: deck, units, cursors, hazards, and the
-- co-op/solo bottom panel.
local util = require 'src.util'
local grid = require 'src.grid'
local palette = require 'src.palette'
local font = require 'src.font'
local sprites = require 'src.sprites'
local audio = require 'src.audio'
local input = require 'src.input'
local engine = require 'src.engine'
local game = require 'src.game'
local data = require 'src.data'
local ui = require 'src.ui'
local timing = require 'src.timing'
local model = require 'src.states.person_battle.model'
local S = require 'src.states.person_battle.state'
local CO = palette.CO
local gfx = love.graphics

local VW = 320

local M = {}

local stepAcc = 0
function M.stepSfx(dt)
  stepAcc = stepAcc + dt
  if stepAcc > 0.09 then
    stepAcc = 0
    audio.tone(150 + love.math.random() * 60, 0.03, 'square', 0.02)
  end
end

-- One player's half of the co-op bottom panel: a compact hovered-unit card
-- or the act menu, mirroring the fleet ship battle's split layout.
local function drawPlayerPanel(player, x0)
  local pb = S.pb
  local pl = pb.pl[player]
  local col = player == 'p2' and CO.green or CO.gold
  local ctx = player == 'p2' and input.p2 or input.p1
  local go, back = input.promptKey(ctx, 'a'), input.promptKey(ctx, 'b')
  font.drawText(player:upper(), x0, 136, col, 1)
  local any = false
  for _, u in ipairs(pb.units) do
    if model.canDrive(player, u) then any = true end
  end
  if pl.stage == 'act' and pl.sel then
    local items = model.actMenu(pl.sel)
    pl.menu = math.min(pl.menu, #items - 1)
    for i = 0, #items - 1 do
      local it = items[i + 1]
      local c = not it.ok and CO.grayD or (i == pl.menu and col or CO.white)
      local icon = ({ atk = 'mini_sword', grd = 'mini_shield', spc = 'mini_star', stay = 'mini_wait' })[it.id]
      if icon then sprites.draw(icon, x0 + 16, 132 + i * 10, false, 1, it.ok and 1 or 0.4) end
      font.drawText((i == pl.menu and '>' or ' ') .. it.label, x0 + 27, 134 + i * 10, c, 1)
    end
    local desc = items[pl.menu + 1].desc
    if desc then font.drawText(desc, x0, 173, CO.gray, 1) end
  elseif pl.stage == 'target' then
    font.drawText('PICK A TARGET!', x0, 148, CO.paper, 1)
    font.drawText('< > AIM  ' .. go .. ' GO  ' .. back .. ' BACK', x0, 160, CO.gray, 1)
  elseif pl.stage == 'busy' then
    font.drawText('...', x0, 148, CO.gray, 1)
  elseif not any then
    font.drawText('WAITING...', x0, 148, CO.gray, 1)
  else
    local show = pl.sel or model.unitAt(pl.cursor.x, pl.cursor.y)
    if show then
      local nameCol = show.side ~= 'p' and CO.red or (show.owner == 'p2' and CO.green or CO.gold)
      font.drawText(show.name, x0 + 16, 136, nameCol, 1)
      font.drawText('@' .. show.hp .. '/' .. show.max .. '  ATK ' .. (show.atk + (show.buff or 0)),
        x0 + 16, 146, CO.white, 1)
    end
    font.drawText(pl.stage == 'move' and (go .. ' GO / ' .. back .. ' BACK') or ('PICK A PIRATE! (' .. go .. ')'), x0, 160, CO.gray, 1)
    if pl.stage == 'pick' then font.drawText(back .. ' REST YOUR PALS', x0, 170, CO.grayD, 1) end
  end
end

-- Attack preview: deterministic atkBase per action, fed to
-- model.previewDamage so the number on screen can't drift from doAttack's
-- own math. Heal/guard/stay have nothing to preview.
local function previewParamsFor(pl)
  if pl.action == 'attack' then return pl.sel.atk + pl.sel.buff, {} end
  if pl.action == 'longshot' then return pl.sel.atk + pl.sel.buff + 1, { ignoreCover = true } end
  return nil
end

-- Read-only preview of confirmTarget's shove slide, for the destination ghost.
local function shoveDestination(u, tgt)
  return model.slideTarget(u, tgt, 2)
end

-- lo-hi(!) label plus one line per modifier note, stacked upward from
-- (cx, topY) so it never collides with the target's own sprite/HP bar.
-- Each line sits on a translucent ink strip (same trick as ui.drawBar's
-- ink backing) so the numbers stay legible over sprites and deck art.
local function inkStrip(x, y, w, alpha)
  gfx.setColor(CO.ink[1], CO.ink[2], CO.ink[3], alpha)
  gfx.rectangle('fill', x, y, w, 7)
end

local function drawDamagePreview(cx, topY, pv)
  local label = pv.lo == pv.hi and ('HITS FOR ' .. pv.lo .. '!') or (pv.lo .. '-' .. pv.hi .. '!')
  local lw = font.textWidth(label, 1)
  local tagX = cx + math.floor(lw / 2) + 10
  local tagW = font.textWidth('*x2', 1)
  local left = cx - math.floor(lw / 2) - 2
  inkStrip(left, topY - 1, (tagX + math.ceil(tagW / 2) + 2) - left, 0.65)
  font.drawTextO(label, cx, topY, CO.white, 1, 'center')
  font.drawTextO('*x2', tagX, topY, CO.gold, 1, 'center')
  local ny = topY + 8
  for _, n in ipairs(pv.notes) do
    local txt = n == '@' and '@' or (n .. '!')
    local w = font.textWidth(txt, 1)
    inkStrip(cx - math.floor(w / 2) - 2, ny - 1, w + 4, 0.65)
    font.drawTextO(txt, cx, ny, n == '@' and CO.gold or CO.foam, 1, 'center')
    ny = ny + 7
  end
end

local function drawHeatTile(x, y, active, gt)
  local hx, hy = model.px(x, y)
  if active then
    local pulse = math.floor(gt * 6) % 2 == 0
    gfx.setColor(CO.red[1], CO.red[2], CO.red[3], pulse and 0.55 or 0.25)
    gfx.rectangle('fill', hx + 1, hy + 1, 14, 14)
    ui.outline(hx + 1, hy + 1, 14, 14, CO.red)
  else
    gfx.setColor(CO.woodD)
    gfx.rectangle('fill', hx + 2, hy + 2, 12, 12)
    local dimPulse = 0.15 + 0.1 * math.sin(gt * 3)
    gfx.setColor(CO.orange[1], CO.orange[2], CO.orange[3], dimPulse)
    gfx.rectangle('fill', hx + 4, hy + 4, 8, 8)
  end
end

function M.draw()
  local pb = S.pb
  local gt = engine.gt
  local isCoop = game.isCoop()

  -- Sea backdrop.
  gfx.setColor(CO.sea)
  gfx.rectangle('fill', 0, 0, VW, 180)
  for y = 0, 11 do
    for x = 0, 19 do
      if (x * 71 + y * 53 + math.floor(gt * 2.2) * 37) % 33 == 0 then
        gfx.setColor(CO.seaL)
        gfx.rectangle('fill', x * 16 + 4, y * 16 + 7, 5, 1)
      end
    end
  end

  -- Deck planks, one tile at a time so irregular shapes leave holes showing
  -- sea underneath (drawn above) instead of a solid rectangle.
  gfx.setColor(CO.woodD)
  for _, t in ipairs(pb.deckList) do
    local tx, ty = model.px(t[1], t[2])
    gfx.rectangle('fill', tx - 2, ty - 2, 20, 20)
  end
  for _, t in ipairs(pb.deckList) do
    local tx, ty = model.px(t[1], t[2])
    local k = grid.gk(t[1], t[2])
    if pb.ice and pb.ice[k] then
      gfx.setColor(0.6, 0.8, 1.0)
    else
      gfx.setColor(CO.wood)
    end
    gfx.rectangle('fill', tx, ty, 16, 16)
  end
  gfx.setColor(CO.woodD)
  for _, t in ipairs(pb.deckList) do
    local tx, ty = model.px(t[1], t[2])
    gfx.rectangle('fill', tx, ty + 15, 16, 1)
  end

  -- Movement ranges, one tint per player.
  for _, player in ipairs({ 'p1', 'p2' }) do
    local pl = pb.pl[player]
    if pl.stage == 'move' and pl.reach and (player == 'p1' or isCoop) then
      local rc = player == 'p2' and CO.green or CO.foam
      gfx.setColor(rc[1], rc[2], rc[3], 0.3)
      for kk in pairs(pl.reach.cost) do
        local x, y = grid.parseKey(kk)
        if not model.unitAt(x, y) and not pb.crates[kk] then
          local cx, cy = model.px(x, y)
          gfx.rectangle('fill', cx + 1, cy + 1, 14, 14)
        end
      end
    end
  end

  -- Crates and surrender flags.
  if pb.perch then
    local px, py = model.px(pb.perch[1], pb.perch[2])
    sprites.draw('perch', px, py)
  end
  for kk in pairs(pb.crates) do
    local x, y = grid.parseKey(kk)
    local cx, cy = model.px(x, y)
    if kk == pb.grandmaBoxK then
      sprites.draw('giftbox', cx + util.round(math.sin(gt * 22)), cy)
    else
      sprites.draw('crate', cx, cy)
    end
  end
  if pb.grandmaAt then
    local gx, gy = model.px(pb.grandmaAt.x, pb.grandmaAt.y)
    sprites.drawPirate('grandma', 'none', gx, gy + util.round(math.sin(gt * 2.5)))
  end
  if pb.vent then
    drawHeatTile(pb.vent.x, pb.vent.y, pb.vent.cycle == 2, gt)
  end
  for i, f in ipairs(pb.flags) do
    local fx, fy = model.px(f.x, f.y)
    sprites.draw('flagW', fx + 5, fy + 5 + util.round(math.sin(gt * 3 + (i - 1))))
  end

  -- Telegraphed SLAM tiles: pulse red for the full player-turn they warn.
  for _, hz in ipairs(pb.hazards) do
    drawHeatTile(hz.x, hz.y, true, gt)
  end

  -- Target highlights + attack/shove previews on the picked target.
  -- Preview text is collected here but flushed after the units render, so
  -- sprites in the rows above can never cover the numbers.
  local previews = {}
  for _, player in ipairs({ 'p1', 'p2' }) do
    local pl = pb.pl[player]
    if pl.stage == 'target' and (player == 'p1' or isCoop) then
      for i = 0, #pl.targets - 1 do
        local tg = pl.targets[i + 1]
        local tx, ty = model.px(tg.x, tg.y)
        if i == pl.tIdx then
          if math.floor(gt * 6) % 2 == 0 then
            ui.outline(tx, ty, 16, 16, pl.action == 'heal' and CO.green or CO.gold)
          end
          local atkBase, popts = previewParamsFor(pl)
          if atkBase and not tg.isCrate then
            local pv = model.previewDamage(pl.sel, tg, atkBase, popts)
            previews[#previews + 1] = function() drawDamagePreview(tx + 8, ty - 24, pv) end
          elseif pl.action == 'shove' then
            local outcome = shoveDestination(pl.sel, tg)
            local ghx, ghy = model.px(outcome.x, outcome.y)
            ui.outline(ghx, ghy, 16, 16, CO.orange, 0.6)
            if outcome.impact.preview then
              previews[#previews + 1] = function()
                font.drawTextO(outcome.impact.preview, ghx + 8, ghy - 12, CO.orange, 1, 'center')
              end
            end
          end
        else
          ui.outline(tx, ty, 16, 16, pl.action == 'heal' and CO.green or CO.red, 0.4)
        end
      end
    elseif pl.stage == 'act' and pl.sel and pl.sel.role == 'strongman' and (player == 'p1' or isCoop) then
      -- SMASH preview: every adjacent foe gets its own number while the
      -- special is highlighted in the act menu.
      local items = model.actMenu(pl.sel)
      local it = items[math.min(pl.menu, #items - 1) + 1]
      if it and it.id == 'spc' and it.ok then
        for _, t in ipairs(model.targetsOf(pl.sel, 1)) do
          local tx, ty = model.px(t.x, t.y)
          local pv = model.previewDamage(pl.sel, t, pl.sel.atk + pl.sel.buff + 2, {})
          previews[#previews + 1] = function() drawDamagePreview(tx + 8, ty - 24, pv) end
        end
      end
    end
  end

  -- Units, y-sorted for overlap (id as stable tiebreak).
  local sorted = {}
  for i, u in ipairs(pb.units) do sorted[i] = u end
  table.sort(sorted, function(a, b)
    if a.fy ~= b.fy then return a.fy < b.fy end
    return a.id < b.id
  end)
  for _, u in ipairs(sorted) do
    if u.alive then
      local ux, uy = pb.ox + u.fx * 16, pb.oy + u.fy * 16
      local dim = u.side == 'p' and u.acted and pb.phase ~= 'foe'
      if pb.pl.p1.sel == u or pb.pl.p2.sel == u then
        local sc = pb.pl.p2.sel == u and CO.green or CO.gold
        gfx.setColor(sc[1], sc[2], sc[3], dim and 0.4 or 0.5)
        gfx.rectangle('fill', ux + 2, uy + 13, 12, 3)
      end
      -- Idle quirks: pure caller-side offsets, no frame system —
      -- one small per-role tell so a lineup of pals reads as individuals.
      local qx, qScale, qAlpha = 0, 1, dim and 0.55 or 1
      if u.side == 'p' and not pb.walk then
        local ph = gt * 3 + (u.id or 0)
        if u.role == 'deckhand' then
          qx = util.round(math.sin(ph) * 1)
        elseif u.role == 'strongman' then
          qScale = 1 + 0.05 * math.sin(ph)
        elseif u.role == 'medic' and dim then
          qAlpha = qAlpha * (0.75 + 0.25 * math.sin(ph * 0.7))
        end
        -- Reactive: any pal adjacent to a live crab shivers in place.
        for _, o in ipairs(pb.units) do
          if o.alive and o.role == 'crab' and grid.manhattan(u.x, u.y, o.x, o.y) == 1 then
            qx = qx + (math.floor(gt * 20 + (u.id or 0)) % 2 == 0 and -1 or 1)
            break
          end
        end
      end
      local tint = u.soggy and { 0.5, 0.7, 1.0 } or nil
      if u.role == 'king' then
        sprites.draw(sprites.kingSprite(u.bars), ux + qx, uy, u.side == 'e', qScale, qAlpha, tint)
      else
        sprites.drawPirate(u.role, u.side == 'p' and u.out or 'none', ux + qx, uy, u.side == 'e', qScale, qAlpha, u.color, tint)
      end
      ui.drawBar(ux + 2, uy - 3, 12, 2, u.hp / u.max)
      if u.bars then
        for bi = 1, 3 do
          gfx.setColor(bi <= u.bars and CO.red or CO.grayD)
          gfx.rectangle('fill', ux + 2 + (bi - 1) * 4, uy - 7, 3, 2)
        end
      end
      if u.guard then
        gfx.setColor(CO.foam)
        gfx.rectangle('fill', ux + 12, uy - 5, 4, 4)
        ui.outline(ux + 12, uy - 5, 4, 4, CO.ink)
      end
      if u.buff > 0 then font.drawTextO('+', ux - 2, uy - 5, CO.gold, 1) end
      if u.loot then sprites.draw('coinS', ux + 10, uy - 8) end
      if u.side == 'p' and u.ref and model.bondBonus(u) > 0 then
        font.drawTextO('@', ux + 12, uy - 5, CO.red, 1)
      end
      if u.side == 'p' and isCoop and not u.acted then
        font.drawTextO(u.owner == 'p2' and 'P2' or 'P1', ux - 3, uy + 11,
          u.owner == 'p2' and CO.green or CO.gold, 1)
      end
    end
  end

  -- Boarding intents: sword/boot over each enemy during the
  -- player's turn (never during the enemy's own turn — a planning aid, not
  -- enemy-turn noise), plus a red pulse on the threatened pal that reads
  -- identically to the SLAM hazard telegraph.
  if pb.phase == 'party' then
    local miniIcons = { attack = 'mini_sword', move = 'mini_boot', smash = 'mini_planks' }
    for _, u in ipairs(pb.units) do
      if u.alive and u.intent then
        local ux, uy = model.px(u.x, u.y)
        -- 8x8 mini badge on the enemy's own tile, top-right: it only nudges
        -- ~3px into the cell above instead of covering it, and the baked ink
        -- outline keeps it readable over adjacent sprites without an opaque
        -- badge plate.
        sprites.draw(miniIcons[u.intent.kind] or 'mini_boot', ux + 9, uy - 3)
        if u.intent.kind == 'attack' and u.intent.target and u.intent.target.alive
          and math.floor(gt * 6) % 2 == 0 then
          local tx, ty = model.px(u.intent.target.x, u.intent.target.y)
          ui.outline(tx, ty, 16, 16, CO.red)
        elseif u.intent.kind == 'smash' and u.intent.x and math.floor(gt * 6) % 2 == 0 then
          local tx, ty = model.px(u.intent.x, u.intent.y)
          ui.outline(tx, ty, 16, 16, CO.orange)
        end
      end
    end
  end

  for _, fn in ipairs(previews) do fn() end

  -- Cursors: gold for P1, green for P2, both live during the party turn.
  if pb.phase == 'party' then
    for _, player in ipairs({ 'p1', 'p2' }) do
      local pl = pb.pl[player]
      if (pl.stage == 'pick' or pl.stage == 'move') and (player == 'p1' or isCoop) then
        local cx, cy
        if pl.stage == 'move' and pl.reach and pl.reach.cost[grid.gk(pl.cursor.x, pl.cursor.y)] then
          local path = grid.bfsPath(pl.reach, pl.cursor.x, pl.cursor.y)
          if path and #path >= 2 then
            local adjustedPath = model.adjustPathForIce(path, pl.sel)
            local last = adjustedPath[#adjustedPath]
            cx, cy = model.px(last[1], last[2])
          else
            cx, cy = model.px(pl.cursor.x, pl.cursor.y)
          end
        else
          cx, cy = model.px(pl.cursor.x, pl.cursor.y)
        end
        local pulse = math.floor(gt * 5) % 2 == 0 and 0 or 1
        ui.drawCursor(cx - pulse, cy - pulse, 16 + pulse * 2, player == 'p2' and CO.green or CO.gold)
      end
    end
  end
  engine.drawFx()

  -- Top strip.
  gfx.setColor(CO.uiBg)
  gfx.rectangle('fill', 0, 0, VW, 14)
  font.drawText('BOARDING BATTLE', 5, 4, CO.paper, 1)
  font.drawText('FOES LEFT: ' .. model.alive('e'), VW - 5, 4, CO.red, 1, 'right')

  -- Bottom panel.
  gfx.setColor(CO.uiBg)
  gfx.rectangle('fill', 0, 132, VW, 48)
  if pb.phase ~= 'party' then
    font.drawText('ENEMY TURN...', VW - 6, 173, CO.paper, 1, 'right')
  elseif isCoop then
    for i, player in ipairs({ 'p1', 'p2' }) do
      drawPlayerPanel(player, i == 1 and 6 or VW / 2 + 6)
    end
    gfx.setColor(CO.ink)
    gfx.rectangle('fill', VW / 2 - 1, 132, 1, 48)
  else
    -- Solo keeps the classic full-width card + hints + action menu.
    local pl = pb.pl.p1
    local show = pl.sel or model.unitAt(pl.cursor.x, pl.cursor.y)
    if show then
      local roleLabel = show.side == 'p' and data.ROLES[show.role].label or data.EROLES[show.role].label
      font.drawText(show.name, 6, 136, show.side == 'p' and CO.gold or CO.red, 1)
      font.drawText(roleLabel .. ' LV' .. show.lvl, 6, 145, CO.gray, 1)
      font.drawText('@' .. show.hp .. '/' .. show.max, 6, 155, CO.hp, 1)
      font.drawText('ATK ' .. (show.atk + (show.buff or 0)) .. '  MOVE ' .. show.move, 6, 164, CO.white, 1)
      if show.side == 'p' then sprites.drawPirate(show.role, show.out, 92, 140, false, 2, nil, show.color) end
    end
    local go, back = input.promptKey(input.p1, 'a'), input.promptKey(input.p1, 'b')
    local hint = ''
    if pl.stage == 'pick' then hint = 'PICK A PIRATE! (' .. go .. ')'
    elseif pl.stage == 'move' then hint = 'MOVE THERE! ' .. go .. ' GO / ' .. back .. ' BACK'
    elseif pl.stage == 'target' then hint = pl.action == 'heal' and 'WHO NEEDS HELP?' or 'PICK A TARGET!' end
    font.drawText(hint, VW - 6, 173, CO.paper, 1, 'right')

    if pl.stage == 'act' and pl.sel then
      local items = model.actMenu(pl.sel)
      pl.menu = math.min(pl.menu, #items - 1)
      local mx, my = 196, 134
      gfx.setColor(CO.ink)
      gfx.rectangle('fill', mx - 6, my - 2, 124, 44)
      for i = 0, #items - 1 do
        local it = items[i + 1]
        local col = not it.ok and CO.grayD or (i == pl.menu and CO.gold or CO.white)
        local icon = ({ atk = 'mini_sword', grd = 'mini_shield', spc = 'mini_star', stay = 'mini_wait' })[it.id]
        if icon then sprites.draw(icon, mx, my + i * 10 - 2, false, 1, it.ok and 1 or 0.4) end
        font.drawText((i == pl.menu and '>' or ' ') .. it.label, mx + 11, my + i * 10, col, 1)
      end
      local desc = items[pl.menu + 1].desc
      if desc then font.drawText(desc, 6, 173, CO.gray, 1) end
    end
  end

  timing.draw()
end

return M
