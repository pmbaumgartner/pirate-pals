-- input.promptKey: UI prompt strings must name the key actually bound for
-- the player they're shown to (P1 Z/X, P2 N/M), switching to pad button
-- names when that player is actively on a gamepad. Run from the project
-- root: `lua tests/input_prompt_test.lua`.
package.path = './?.lua;' .. package.path
love = { graphics = {} } -- font.lua indexes love.graphics at require time
local input = require 'src.input'

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

ok(input.promptKey(input.p1, 'a') == 'Z', "P1 confirm prompt should be Z")
ok(input.promptKey(input.p1, 'b') == 'X', "P1 back prompt should be X")
ok(input.promptKey(input.p2, 'a') == 'N', "P2 confirm prompt should be N")
ok(input.promptKey(input.p2, 'b') == 'M', "P2 back prompt should be M")
ok(input.promptKey(input.p1, 'voyage') == 'V', 'voyage hotkey prompt should be V')
ok(input.promptKey(input.p1, 'nope') == '?', 'unknown action falls back to ?')

-- Timing-bar labels built the ship_battle way embed the owner's key.
local function pressLabel(verb, owner)
  local ctx = owner == 'p2' and input.p2 or input.p1
  return verb .. '! PRESS ' .. input.promptKey(ctx, 'a') .. '!'
end
ok(pressLabel('FIRE', 'p1') == 'FIRE! PRESS Z!', 'P1 FIRE label embeds Z')
ok(pressLabel('FIRE', 'p2') == 'FIRE! PRESS N!', "P2's FIRE label must say N, not Z")
ok(pressLabel('PATCH', nil) == 'PATCH! PRESS Z!', 'unowned label defaults to P1')

-- Pad names when the player is actively on a gamepad.
input.p1.player._activeDevice = 'joy'
ok(input.promptKey(input.p1, 'a') == 'A', 'pad-active P1 confirm prompt should be A')
ok(input.promptKey(input.p1, 'b') == 'B', 'pad-active P1 back prompt should be B')
input.p1.player._activeDevice = 'none'
ok(input.promptKey(input.p1, 'a') == 'Z', 'prompt returns to Z off the pad')

-- Coop rebuild keeps P1's bindings (only the arrow aliases change).
input.setCoop(true)
ok(input.promptKey(input.p1, 'a') == 'Z', 'setCoop must not change P1 prompts')
ok(input.promptKey(input.p2, 'a') == 'N', 'setCoop must not change P2 prompts')

if fails > 0 then os.exit(1) end
print('input_prompt_test OK')
