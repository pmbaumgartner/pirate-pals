-- Pure round-resolution logic for the TWO CAPTAINS fleet ship battle (C3),
-- kept free of LÖVE/engine state so tests/fleet_round_test.lua can exercise
-- the queue rules headlessly.
local M = {}

-- Actions resolve one at a time, in the order the captains confirmed them.
function M.resolveOrder(ships)
  local order = {}
  for i in ipairs(ships) do order[#order + 1] = i end
  table.sort(order, function(a, b)
    return (ships[a].confirmOrder or 0) < (ships[b].confirmOrder or 0)
  end)
  return order
end

-- BROADSIDE: both captains picked FIRE while both ships are NEAR, once per
-- battle. Purely a bonus — never a requirement.
function M.broadsideReady(ships, used)
  return not used and #ships == 2
    and ships[1].chosen == 'fire' and ships[2].chosen == 'fire'
    and ships[1].range == 'NEAR' and ships[2].range == 'NEAR'
end

-- Kind auto-choice for an idle-collapsed captain: keep patching if downed,
-- otherwise fire.
function M.autoChoice(ship)
  return ship.patched and 'patch' or 'fire'
end

function M.allChosen(ships)
  for _, sh in ipairs(ships) do
    if not sh.chosen then return false end
  end
  return true
end

return M
