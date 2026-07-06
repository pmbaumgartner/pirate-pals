-- Plain-Lua unit tests for src/fleet.lua's fleet round-resolution rules
-- Run from the project root: `lua tests/fleet_round_test.lua`.
package.path = './?.lua;' .. package.path
local fleet = require 'src.fleet'

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

-- Resolution follows confirm order, not ship index.
local ships = {
  { chosen = 'fix', confirmOrder = 2, range = 'FAR' },
  { chosen = 'fire_round', confirmOrder = 1, range = 'FAR' },
}
local order = fleet.resolveOrder(ships)
ok(order[1] == 2 and order[2] == 1, 'resolveOrder should follow confirm order')

-- A solo-length array still resolves (solo/First Mate share the code path).
ok(#fleet.resolveOrder({ { chosen = 'fire_round' } }) == 1, 'resolveOrder handles a 1-ship fleet')

-- BROADSIDE needs both FIRE, both NEAR, and to be unused.
local near = function(a, b)
  return {
    { chosen = a, range = 'NEAR' },
    { chosen = b, range = 'NEAR' },
  }
end
ok(fleet.broadsideReady(near('fire_round', 'fire_round'), false), 'both FIRE_ROUND + both NEAR should arm BROADSIDE')
ok(not fleet.broadsideReady(near('fire_round', 'fire_round'), true), 'BROADSIDE fires at most once per battle')
ok(not fleet.broadsideReady(near('fire_round', 'move'), false), 'BROADSIDE needs both captains on FIRE_ROUND')
local split = near('fire_round', 'fire_round')
split[2].range = 'FAR'
ok(not fleet.broadsideReady(split, false), 'BROADSIDE needs both ships NEAR')
ok(not fleet.broadsideReady({ { chosen = 'fire_round', range = 'NEAR' } }, false),
  'BROADSIDE never arms outside a 2-ship fleet')

-- Idle-collapse auto-choice keeps patching a downed ship, else fires.
ok(fleet.autoChoice({ patched = true }) == 'patch', 'auto-choice keeps patching a downed ship')
ok(fleet.autoChoice({ patched = false }) == 'fire_round', 'auto-choice fires when seaworthy')

-- Round gate: every ship must have chosen before resolution starts.
ok(not fleet.allChosen({ { chosen = 'fire_round' }, {} }), 'allChosen waits on the undecided captain')
ok(fleet.allChosen({ { chosen = 'fire_round' }, { chosen = 'fix' } }), 'allChosen passes once both picked')

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('fleet_round_test OK')
