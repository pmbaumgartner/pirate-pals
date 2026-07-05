-- Turns a plain Lua table (numbers/strings/booleans/nil, nested tables of
-- the same) into a loadable Lua literal and back. Built for save files:
-- decode() runs the literal through load() with an empty sandbox env, so a
-- hand-edited or corrupted file can't execute code, only fail to parse.
local M = {}

local function encodeValue(v)
  local t = type(v)
  if t == 'string' then return string.format('%q', v) end
  if t == 'number' or t == 'boolean' then return tostring(v) end
  if t == 'table' then return M.encode(v) end
  error('cannot serialize value of type ' .. t)
end

-- Every key is written explicitly (`[k]=v`) rather than relying on Lua's
-- positional array syntax, so 0-based or sparse tables (e.g. the hex sea
-- grid) round-trip without renumbering.
function M.encode(t)
  local parts = {}
  for k, v in pairs(t) do
    local key = type(k) == 'number' and ('[' .. k .. ']') or ('[' .. string.format('%q', k) .. ']')
    parts[#parts + 1] = key .. '=' .. encodeValue(v)
  end
  return '{' .. table.concat(parts, ',') .. '}'
end

-- Returns nil on any parse/runtime failure instead of raising, so a save
-- file corrupted outside the game degrades to "no save" rather than a crash.
function M.decode(text)
  local chunk = load('return ' .. text, 'save', 't', {})
  if not chunk then return nil end
  local ok, result = pcall(chunk)
  if not ok then return nil end
  return result
end

return M
