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

  return h
end
