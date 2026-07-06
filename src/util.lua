-- Tiny pure utilities. irand/pick accept float-tolerant bounds so tuned
-- values like shake magnitudes keep working.
local M = {}

function M.clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

function M.lerp(a, b, t) return a + (b - a) * t end

function M.irand(a, b) return math.floor(a + love.math.random() * (b - a + 1)) end

function M.chance(p) return love.math.random() < p end

function M.pick(arr) return arr[math.floor(love.math.random() * #arr) + 1] end

-- ease-in-out quad
function M.ease(t)
  if t < 0.5 then return 2 * t * t end
  return 1 - ((-2 * t + 2) ^ 2) / 2
end

function M.round(v) return math.floor(v + 0.5) end

return M
