-- Plain-Lua unit tests for src/timing.lua's two-player "BOTH PRESS!" mode
-- (2.4). Run from the project root: `lua tests/timing_coop_test.lua`.
package.path = './?.lua;' .. package.path
love = { graphics = {} } -- font.lua indexes love.graphics at require time
local timing = require 'src.timing'

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

-- An early P1 press must not resolve the round or cut off P2's shot: the
-- bar keeps running (classifying against each player's own press time)
-- until both have pressed.
local r1, r2 = nil, nil
timing.startCoop({ dur = 1, good = 0.3, perf = 0.1 }, 'T', function(a, b) r1, r2 = a, b end)
for _ = 1, 10 do timing.updateCoop(0.05, false, false) end -- t = 0.5 -> pos 0.5 (perfect zone)
ok(timing.updateCoop(0, true, false), 'still on after only P1 presses')
ok(r1 == nil and r2 == nil, 'round does not resolve until both have pressed')
ok(timing.p1Res == 'perfect', "P1's own press time is classified immediately")
for _ = 1, 10 do timing.updateCoop(0.05, false, false) end -- t = 1.0 -> pos 0 (miss zone)
timing.updateCoop(0, false, true)
ok(r1 == 'perfect' and r2 == 'miss', 'each result reflects its own press time, got ' .. tostring(r1) .. '/' .. tostring(r2))
ok(timing.on == false, 'coop bar closes once both have pressed')
ok(timing.coopMode == false, 'coopMode clears on resolve')

-- Timeout: whoever never pressed gets the caller's fallback, not stuck open.
r1, r2 = nil, nil
timing.startCoop({ dur = 0.5, good = 0.3, perf = 0.1 }, 'T', function(a, b) r1, r2 = a, b end, 'good')
local elapsed = 0
while r1 == nil and elapsed < 60 do
  timing.updateCoop(0.05, true, false) -- P1 presses every tick; P2 never does
  elapsed = elapsed + 0.05
end
ok(r2 == 'good', 'P2 gets the timeout fallback when they never press, got ' .. tostring(r2))
ok(r1 == 'miss', "P1's immediate press at t=0 (bar start) classifies as miss, got " .. tostring(r1))
ok(timing.on == false, 'coop bar closes after timeout')

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('timing_coop_test OK')
