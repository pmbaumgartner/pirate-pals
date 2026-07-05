-- Plain-Lua unit tests for src/timing.lua's pure core (triangle wave,
-- window classification, timeout policy). timing.lua only touches LÖVE
-- inside draw(), so a stub love table is enough to require it. Run from
-- the project root: `lua tests/timing_test.lua` (texlua works).
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
local function near(a, b) return math.abs(a - b) < 1e-9 end

-- Triangle wave: rises 0 -> 1 over one dur, falls back, and repeats.
ok(near(timing.posAt(0, 2), 0), 'posAt starts at 0')
ok(near(timing.posAt(1, 2), 0.5), 'posAt midway up')
ok(near(timing.posAt(2, 2), 1), 'posAt peak at dur')
ok(near(timing.posAt(3, 2), 0.5), 'posAt midway down')
ok(near(timing.posAt(4, 2), 0), 'posAt back to 0 at 2*dur')
ok(near(timing.posAt(5, 2), 0.5), 'posAt repeats')
local prev = -1
for i = 0, 20 do -- monotonic up then down within one round trip
  local p = timing.posAt(i * 0.1, 1)
  if i <= 10 then ok(p >= prev, 'rising leg monotonic') else ok(p <= prev, 'falling leg monotonic') end
  prev = p
end

-- Window classification, inclusive at both edges.
ok(timing.classify(0.5, 0.3, 0.1) == 'perfect', 'center is perfect')
ok(timing.classify(0.549, 0.3, 0.1) == 'perfect', 'inside perfect window')
ok(timing.classify(0.56, 0.3, 0.1) == 'good', 'just past perfect is good')
ok(timing.classify(0.649, 0.3, 0.1) == 'good', 'inside good window')
ok(timing.classify(0.66, 0.3, 0.1) == 'miss', 'outside good is miss')
ok(timing.classify(0.0, 0.3, 0.1) == 'miss', 'bar end is miss')

-- cfg: sweeps slow and floored; the good window is a constant floor across
-- all sea levels (design-gaps/04) — only 'perfect' tightens with level, and
-- only a STEADY HANDS widen multiplier changes windows.
ok(timing.cfg(0).dur == 2.0, 'base sweep 2.0s')
ok(timing.cfg(99).dur == 1.5, 'sweep floor 1.5s')
ok(timing.cfg(2, true).good > timing.cfg(2, false).good, 'parry widens good window')
ok(timing.cfg(5).good == timing.cfg(1).good, 'good window is constant across levels')
ok(timing.cfg(5).perf < timing.cfg(1).perf, 'perfect window still tightens with level')
ok(timing.cfg(0, false, { win = 1.25 }).good == timing.cfg(0).good * 1.25,
  'widen multiplier scales the good window')
ok(timing.cfg(0, false, { sweep = 1.15 }).dur == timing.cfg(0).dur * 1.15,
  'sweep multiplier slows the sweep')

-- Press path: pressing at the peak (pos 1.0) classifies from the live pos.
local got = nil
timing.start({ dur = 1, good = 0.3, perf = 0.1 }, 'T', function(r) got = r end)
for _ = 1, 10 do timing.update(0.05, false) end -- t = 0.5 -> pos 0.5
timing.update(0, true)
ok(got == 'perfect', 'press at center resolves perfect, got ' .. tostring(got))
ok(timing.on == false, 'bar closes after press')

-- Anti-mash lockout: pressing far outside the good window doesn't resolve,
-- it greys the marker for a beat instead. Capped at 2 per bar so a
-- frustrated kid still gets a result soon.
-- A long dur keeps the marker near 0 (deep in the mash zone) through the
-- brief waits used to clear each lockout below.
got = nil
timing.start({ dur = 10, good = 0.3, perf = 0.1 }, 'T', function(r) got = r end)
timing.update(0, true) -- press at t=0 (pos 0, off 0.5) is deep in the mash zone
ok(got == nil, 'mash-zone press does not resolve')
ok(timing.lockT > 0, 'mash-zone press starts a lockout')
ok(timing.lockouts == 1, 'first lockout counted')
timing.update(0, true) -- pressing again mid-lockout is simply ignored
ok(got == nil and timing.lockouts == 1, 'press during lockout is a no-op')
for _ = 1, 9 do timing.update(0.05, false) end -- wait out the 0.4s lockout (t=0.45)
timing.update(0, true) -- second mash-zone press: another lockout, still capped
ok(got == nil and timing.lockouts == 2, 'second lockout counted, still capped at 2')
for _ = 1, 9 do timing.update(0.05, false) end
timing.update(0, true) -- lockouts exhausted: this press finally resolves (as a miss)
ok(got == 'miss', 'press resolves once lockout cap is spent, got ' .. tostring(got))
ok(timing.on == false, 'bar closes after the resolving press')

-- Timeout path: with no presses the bar oscillates MAX_SWEEPS one-way
-- passes then auto-resolves with the caller's fallback.
got = nil
local elapsed = 0
timing.start({ dur = 0.5, good = 0.3, perf = 0.1 }, 'T', function(r) got = r end, 'good')
while got == nil and elapsed < 60 do
  timing.update(0.05, false)
  elapsed = elapsed + 0.05
end
ok(got == 'good', 'timeout delivers caller fallback, got ' .. tostring(got))
ok(near(elapsed, 0.5 * timing.MAX_SWEEPS + 0.05) or elapsed <= 0.5 * timing.MAX_SWEEPS + 0.1,
  'timeout after MAX_SWEEPS sweeps, took ' .. elapsed)
ok(timing.on == false, 'bar closes after timeout')

-- Default fallback is 'miss' (safe for parries that omit the argument).
got = nil
timing.start({ dur = 0.2, good = 0.3, perf = 0.1 }, 'T', function(r) got = r end)
for _ = 1, 200 do timing.update(0.05, false) end
ok(got == 'miss', 'default timeout is miss, got ' .. tostring(got))

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('timing_test OK')
