-- Pirate Pals — LÖVE 11.x port of the web playtest prototype (v2 GDD).
-- The game renders to a fixed 320x180 canvas, scaled to the window with
-- integer snapping to keep pixel edges crisp. States live in src/states/
-- and register themselves into the engine's state registry on require.
--
-- Dev tooling (src/dev/*) is only required when its flag is present, so it
-- never enters the default require graph:
--   --seed=N            deterministic RNG (printed at boot either way)
--   --speed=N            run N logic ticks per rendered frame (default 1)
--   --warp=<name>        jump straight into a named scenario (src/dev/scenarios.lua)
--   --shot[=name] [--frames=N1,N2,...]  capture PNG(s) N frames after --warp, then quit
--   --script=path.lua    drive the game via a dev script (src/dev/script.lua)
--   --smoke [--shots]    alias for --script=src/dev/smoke_script.lua --speed=8
--   --dump                dump game.run + battle state to stdout at quit
--   --dev                 enable the F1-F10 cheat panel and Tab-hold 4x speed
--   --live                hot-reload changed source files (src/lib/lurker.lua)
--   --coverage            record LuaCov line coverage (luacov.report.out)

-- LÖVE sets the `arg` global before this file runs, so a coverage init here
-- (ahead of the requires below) sees every top-level module chunk; parsing
-- flags in love.load happens after those chunks already ran uncovered.
-- luacov: disable
local coverageOn = false
for _, a in ipairs(arg or {}) do
  if a == '--coverage' then coverageOn = true end
end
if coverageOn then
  jit.off() -- also flushes compiled traces, which never fire line hooks
  love.filesystem.setRequirePath(
    love.filesystem.getRequirePath() .. ';src/lib/?.lua;src/lib/?/init.lua')
  require('luacov.runner').init() -- reads .luacov from the repo-root cwd
end
-- luacov: enable

local util = require 'src.util'
local palette = require 'src.palette'
local font = require 'src.font'
local sprites = require 'src.sprites'
local audio = require 'src.audio'
local input = require 'src.input'
local engine = require 'src.engine'
local game = require 'src.game'
local data = require 'src.data'
local meta = require 'src.meta'
local CO = palette.CO
local gfx = love.graphics

local VW, VH = 320, 180
local canvas
local scale, ox, oy = 1, 0, 0

local flags = {}
local speedN = 1
local devScript = nil
local shotCfg = nil
local devJump = nil
local lurker = nil

local function computeScale()
  local w, h = gfx.getDimensions()
  local s = math.min(w / VW, h / VH)
  if s >= 2 then s = math.floor(s) end -- integer scale keeps pixel edges crisp
  scale = s
  ox = math.floor((w - VW * s) / 2)
  oy = math.floor((h - VH * s) / 2)
end

-- luacov: disable
local function toCanvas(x, y)
  return (x - ox) / scale, (y - oy) / scale
end
-- luacov: enable

-- `--key=value` and bare `--key` flags, e.g. {seed='7', speed='8', dev=true}.
local function parseFlags(args)
  local out = {}
  for _, a in ipairs(args or {}) do
    local k, v = a:match('^%-%-([%w_]+)=(.+)$')
    if k then
      out[k] = v
    else
      k = a:match('^%-%-([%w_]+)$')
      if k then out[k] = true end
    end
  end
  return out
end

function love.load(args)
  flags = parseFlags(args)

  local seed = tonumber(flags.seed) or os.time()
  love.math.setRandomSeed(seed)
  print('SEED ' .. seed)

  if flags.smoke then
    flags.script = flags.script or 'src/dev/smoke_script.lua'
  end
  speedN = tonumber(flags.speed) or (flags.smoke and 8) or 1

  gfx.setDefaultFilter('nearest', 'nearest')
  gfx.setLineStyle('rough')
  sprites.build()
  audio.warm()
  canvas = gfx.newCanvas(VW, VH)
  canvas:setFilter('nearest', 'nearest')
  input.scanJoysticks()
  meta.load()

  -- States register themselves into engine.states when required.
  require 'src.states.title'
  require 'src.states.colorselect'
  require 'src.states.sail'
  require 'src.states.ship_battle'
  require 'src.states.person_battle'
  require 'src.states.loot'
  require 'src.states.crew'
  require 'src.states.tailor'
  require 'src.states.log'
  require 'src.states.voyagelog'
  require 'src.states.chart'
  require 'src.states.victory'
  require 'src.states.port'
  require 'src.states.dock'
  require 'src.states.drydock'

  computeScale()
  engine.setState('title')

  -- luacov: disable
  if flags.warp then
    -- LÖVE's default error handler shows an interactive "press a key to
    -- quit" screen rather than exiting, which would hang forever under
    -- xvfb-run/CI — so a bad scenario name fails with a clean exit(1)
    -- instead of an uncaught error.
    local ok, err = pcall(function() require('src.dev.scenarios').run(flags.warp) end)
    if not ok then
      print('FAIL: ' .. tostring(err))
      love.event.quit(1)
      return
    end
  end

  if flags.live then
    lurker = require 'src.lib.lurker'
    -- The save dir is merged into love.filesystem's root, so save.lua and
    -- meta.lua (table literals, not loadable chunks) show up as changed
    -- .lua files. preswap returning true skips the swap; only reload
    -- first-party source.
    lurker.preswap = function(f)
      return not (f == 'main.lua' or (f:match('^src/') and not f:match('^src/lib/')))
    end
  end
  -- luacov: enable

  if flags.script then
    devScript = require 'src.dev.script'
    devScript.shotsOn = flags.shots and true or false
    devScript.canvas = canvas -- shot() reads back the native 320x180 canvas
    devScript.load(flags.script)
  end

  -- luacov: disable
  if flags.warp and flags.shot then
    local frames = {}
    if flags.frames then
      for numStr in tostring(flags.frames):gmatch('[^,]+') do
        frames[#frames + 1] = tonumber(numStr)
      end
    else
      frames = { 30 }
    end
    local name = (flags.shot ~= true and flags.shot) or flags.warp
    shotCfg = { name = name, frames = frames, idx = 1, count = 0 }
  end
  -- luacov: enable
end

-- One logic step; love.update calls this speedN times per rendered frame
-- (same capped dt each call, not a multiplied dt) so --speed fast-forwards
-- game time without breaking animations tuned in real seconds.
local function tick(dt)
  engine.gt = engine.gt + dt
  input.update(dt)
  if input.jp('mute') then
    audio.muted = not audio.muted
    engine.showToast(audio.muted and 'SOUND OFF' or 'SOUND ON', CO.gray, 0.8)
    if not audio.muted then audio.sfx.sel() end
  end
  if not engine.trans.on then
    engine.states[engine.cur].update(dt)
  end
  engine.updateFx(dt)
  audio.update(dt)
  if devScript then devScript.update(dt) end

  -- luacov: disable
  if shotCfg then
    shotCfg.count = shotCfg.count + 1
    if shotCfg.pendingName then
      -- captureScreenshot's write completes at end-of-frame; deferring the
      -- path print (and quit) by one tick guarantees the file is on disk.
      print('SHOT ' .. love.filesystem.getSaveDirectory() .. '/' .. shotCfg.pendingName)
      shotCfg.pendingName = nil
      shotCfg.idx = shotCfg.idx + 1
      if shotCfg.idx > #shotCfg.frames then love.event.quit(0) end
    elseif shotCfg.count == shotCfg.frames[shotCfg.idx] then
      local suffix = #shotCfg.frames > 1 and ('_f' .. shotCfg.frames[shotCfg.idx]) or ''
      local fname = shotCfg.name .. suffix .. '.png'
      gfx.captureScreenshot(fname)
      shotCfg.pendingName = fname
    end
  end
  -- luacov: enable
end

function love.update(dt)
  -- Scripted runs (--script/--smoke) use a fixed dt so a given --seed
  -- replays bit-identically: with real frame times, every timer threshold
  -- crosses at host-load-dependent tick boundaries, which let events
  -- reorder between runs of the same seed.
  if flags.script then dt = 1 / 60 else dt = math.min(0.05, dt) end
  local n = speedN
  if flags.dev and love.keyboard.isDown('tab') then n = n * 4 end
  for _ = 1, n do tick(dt) end
  if lurker then lurker.update() end
end

function love.draw()
  gfx.setCanvas(canvas)
  gfx.clear(CO.night[1], CO.night[2], CO.night[3], 1)
  local sx, sy = 0, 0
  if engine.shake.t > 0 then
    sx = util.irand(-engine.shake.mag, engine.shake.mag)
    sy = util.irand(-engine.shake.mag, engine.shake.mag)
  end
  gfx.push()
  gfx.translate(sx, sy)
  engine.states[engine.cur].draw()
  gfx.pop()
  engine.drawBanner()
  engine.drawToast()
  input.drawTouchUI()
  engine.drawTrans()

  -- luacov: disable
  if devJump then
    font.drawTextO('JUMP TO SEA LV ' .. devJump.n, VW / 2, VH - 22, CO.gold, 1, 'center')
    font.drawTextO('UP/DOWN CHANGE  Z GO  X CANCEL', VW / 2, VH - 14, CO.gray, 1, 'center')
  end
  -- luacov: enable

  gfx.setCanvas()

  gfx.clear(CO.night[1], CO.night[2], CO.night[3], 1)
  gfx.setColor(1, 1, 1, 1)
  gfx.draw(canvas, ox, oy, 0, scale, scale)

  if devScript then devScript.frame = devScript.frame + 1 end
end

function love.resize()
  computeScale()
end

-- --dev cheat panel (0.6): F1-F7 tweak the run in place, F9/F10 snapshot
-- and restore it in memory (instant "retry that battle with this crew").
-- luacov: disable
function love.keypressed(key)
  if flags.dev and devJump then
    if key == 'up' then devJump.n = devJump.n + 1
    elseif key == 'down' then devJump.n = math.max(1, devJump.n - 1)
    elseif key == 'z' or key == 'return' then
      game.genSea(devJump.n)
      engine.setState('sail')
      devJump = nil
    elseif key == 'x' or key == 'escape' then
      devJump = nil
    end
    return
  end

  if flags.dev and game.run then
    if key == 'f1' then
      game.run.gold = game.run.gold + 50
      engine.showToast('+50 GOLD', CO.gold, 0.7)
    elseif key == 'f2' then
      for _, p in ipairs(game.run.party) do p.lvl = math.min(6, p.lvl + 1) end
      engine.showToast('PARTY LEVELED UP', CO.gold, 0.7)
    elseif key == 'f3' then
      if engine.cur == 'shipBattle' then
        require('src.states.ship_battle').debugWin()
      elseif engine.cur == 'personBattle' then
        require('src.states.person_battle').debugWin()
      end
    elseif key == 'f4' then
      game.genSea(game.run.sea.lv + 1)
      engine.setState('sail')
    elseif key == 'f5' then
      if engine.cur == 'sail' then devJump = { n = game.run.sea.lv + 1 } end
    elseif key == 'f6' then
      for _, o in ipairs(data.OUTFITS) do game.unlockHat(o.id) end
      engine.showToast('ALL HATS UNLOCKED', CO.gold, 0.7)
    elseif key == 'f7' then
      local roles = { 'deckhand', 'strongman', 'sharpshooter', 'medic' }
      require('src.states.loot').start({
        { type = 'recruit', pirate = game.makePirate(util.pick(roles), util.pick(data.PAL_NAMES), 1) },
      }, 'DEV RECRUIT')
    elseif key == 'f9' then
      game.snapshot()
      engine.showToast('SNAPSHOT SAVED', CO.gold, 0.7)
    elseif key == 'f10' then
      if game.hasSnapshot() then
        game.restore()
        engine.setState('sail')
        engine.showToast('SNAPSHOT RESTORED', CO.gold, 0.7)
      end
    end
  end

  input.keypressed(key)
end

function love.keyreleased(key)
  input.keyreleased(key)
end

function love.mousepressed(x, y, button, istouch)
  if istouch then return end -- handled by touch callbacks
  local cx, cy = toCanvas(x, y)
  input.pointerDown('mouse' .. button, cx, cy, false)
end

function love.mousereleased(x, y, button, istouch)
  if istouch then return end
  input.pointerUp('mouse' .. button)
end

function love.touchpressed(id, x, y)
  local cx, cy = toCanvas(x, y)
  input.pointerDown(id, cx, cy, true)
end

function love.touchreleased(id)
  input.pointerUp(id)
end

function love.joystickadded(js)
  input.joystickadded(js)
end

function love.joystickremoved(js)
  input.joystickremoved(js)
end
-- luacov: enable

function love.quit()
  -- luacov: disable
  if flags.dump then
    require('src.dev.dump').dump()
  end
  -- luacov: enable
  if coverageOn then
    require('luacov.runner').shutdown() -- saves stats + writes report
  end
end
