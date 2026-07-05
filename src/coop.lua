-- Shared co-op solo-collapse policy: P2 idle detection and idle-timer
-- latches, used by sail (ship2 convoy), ship battle (fleet ship2
-- auto-pick), and boarding (p2Away / p2Auto) so each state asks for intent
-- instead of re-deriving its own timer bookkeeping.
local input = require 'src.input'

local M = {}

function M.p2Active()
  local p2 = input.p2
  return p2.held.up or p2.held.down or p2.held.left or p2.held.right
    or p2.pressed.a or p2.pressed.b
end

-- `state.idleT` tracks seconds since P2 last acted; any input resets it to
-- 0 and clears every latch. Each latch is `{ limit = seconds, key = name }`;
-- once idleT crosses `limit`, `state[key]` flips true and stays true until
-- the next reset.
function M.tickIdle(state, dt, latches)
  if M.p2Active() then
    state.idleT = 0
    for _, l in ipairs(latches) do state[l.key] = false end
    return
  end
  state.idleT = (state.idleT or 0) + dt
  for _, l in ipairs(latches) do
    if state.idleT > l.limit then state[l.key] = true end
  end
end

return M
