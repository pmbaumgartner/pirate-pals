-- Shared toolkit for the smoke modules: common requires plus the battle
-- helpers, built against the script env's injected functions (ctx). Each
-- smoke module is `function(ctx, h)`; the injected helpers are NOT globals
-- inside required files, so everything flows through these two tables.
return function(ctx)
  local h = {}

  h.engine = require 'src.engine'
  h.game = require 'src.game'
  h.data = require 'src.data'
  h.meta = require 'src.meta'
  h.grid = require 'src.grid'
  h.input = require 'src.input'
  h.timing = require 'src.timing'
  h.shipBattle = require 'src.states.ship_battle'
  h.personBattle = require 'src.states.person_battle'
  h.loot = require 'src.states.loot'
  h.chart = require 'src.states.chart'
  h.palette = require 'src.palette'
  h.CO = h.palette.CO

  local engine, game, timing, shipBattle = h.engine, h.game, h.timing, h.shipBattle
  local tap, tap2, waitUntil = ctx.tap, ctx.tap2, ctx.waitUntil

  function h.shipBattleReady(sbNow, turn, timeout)
    waitUntil(function()
      return engine.cur == 'shipBattle'
        and shipBattle.sb == sbNow
        and (not turn or sbNow.turn == turn)
        and not engine.trans.on
        and not sbNow.co
        and not sbNow.anim
        and sbNow.wait <= 0
        and not timing.on
    end, timeout or 10)
  end

  function h.landTiming(owner)
    waitUntil(function() return timing.on end, 5)
    waitUntil(function()
      return not timing.on
        or math.abs(timing.posAt(timing.t, timing.dur) - 0.5) <= (timing.good or 0.3) / 4
    end, 5)
    if timing.on then
      if owner == 'p2' then tap2('a') else tap('z') end
    end
    waitUntil(function() return not timing.on end, 5)
  end

  function h.startSmokeShipBattle(foe, slot)
    game.run.fittings.slot = slot
    shipBattle.start(foe)
    local sbNow = shipBattle.sb
    h.shipBattleReady(sbNow, 'select', 5)
    return sbNow
  end

  function h.fireSoloShot(sbNow, shotId)
    local sh = sbNow.ships[1]
    sh.menu = 0
    sh.submenu = nil
    tap('z')
    waitUntil(function() return sh.submenu == 'shot' end, 3)
    if shotId ~= 'round' then tap('down') end
    tap('z')
    h.landTiming('p1')
  end

  function h.chooseSoloShipAction(sbNow, menuIndex)
    local sh = sbNow.ships[1]
    sh.menu = menuIndex
    sh.submenu = nil
    tap('z')
  end

  -- The iris transition swallows input for its full 1.2s (main.lua skips
  -- state updates while it plays), so wait it out before tapping a card that
  -- was started on its heels.
  function h.settle()
    waitUntil(function() return not engine.trans.on end, 5)
  end

  -- landTiming variants with a forced grade. Under the script's fixed dt the
  -- marker steps ~1% of the bar per tick, so waiting for a specific offset
  -- band then tapping is deterministic (one tick of press latency, ~0.013 of
  -- the bar, is budgeted into each band's margins).
  local function landInBand(pred, owner)
    waitUntil(function() return timing.on end, 5)
    waitUntil(function() return not timing.on or pred() end, 30)
    if timing.on then
      if owner == 'p2' then tap2('a') else tap('z') end
    end
    waitUntil(function() return not timing.on end, 20)
  end

  function h.landTimingPerfect(owner)
    landInBand(function()
      return math.abs(timing.posAt(timing.t, timing.dur) - 0.5)
        <= math.max(0.005, timing.perf / 2 - 0.02)
    end, owner)
  end

  -- Lands in the miss band but under the anti-mash threshold (good*1.5), so
  -- the press resolves 'miss' instead of a TOO SOON lockout.
  function h.landTimingMiss(owner)
    landInBand(function()
      local off = math.abs(timing.posAt(timing.t, timing.dur) - 0.5)
      return off >= timing.good / 2 + 0.08 and off <= timing.good * 1.5 - 0.12
    end, owner)
  end

  -- Advances every loot card until the run is back on sail, recording card
  -- types in `seen` (optional). blueprint_choice picks the SECOND option so
  -- the pick logic (not just the default) executes.
  function h.walkLoot(seen)
    local loot, wait = h.loot, ctx.wait
    waitUntil(function() return engine.cur == 'loot' end, 10)
    h.settle()
    for _ = 1, 30 do
      if engine.cur ~= 'loot' then break end
      local L = loot.loot
      local part = L and L.parts[L.i + 1]
      if part then
        if seen then seen[part.type] = true end
        if part.type == 'blueprint_choice' and #part.options > 1 then
          tap('right')
          wait(0.15)
        end
      end
      tap('z')
      wait(0.35)
    end
    waitUntil(function() return engine.cur == 'sail' and not engine.trans.on end, 10)
  end

  return h
end
