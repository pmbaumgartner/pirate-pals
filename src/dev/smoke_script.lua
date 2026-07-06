-- Canonical smoke script: drives every state once, exercising hex
-- tap-to-sail, ship battle, boarding, loot cards, and the menu screens.
-- `--smoke` runs this via `--script=... --speed=8`; add `--shots` to also
-- dump PNGs into the LÖVE save dir.
--
-- The walk lives in src/dev/smoke/, one module per section, run in order —
-- later sections depend on game state built by earlier ones. Each module is
-- `function(ctx, h)`: ctx carries the script-env helpers (which are only
-- globals inside this chunk, not in required files) and h the shared
-- toolkit from smoke/helpers.lua.
local ctx = {
  tap = tap, tap2 = tap2, tapCell = tapCell, wait = wait,
  waitUntil = waitUntil, shot = shot, expect = expect,
}
local h = require('src.dev.smoke.helpers')(ctx)

for _, name in ipairs({
  'title_flow',
  'sail_basics',
  'ship_battle',
  'loot_cards',
  'menus',
  'sea_biomes',
  'boarding_gallery',
  'boss_victory_port',
  'captains',
  'ship_loss_dock',
  'ship_battle_real',
  'boarding_real',
  'boarding_specials',
  'sail_triggers',
  'save_roundtrip',
  'colorselect_launch',
}) do
  require('src.dev.smoke.' .. name)(ctx, h)
end

print('SMOKE OK')
love.event.quit(0)
