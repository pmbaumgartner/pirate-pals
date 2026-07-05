-- Game palette. hex() is exported for sprite color maps.
local M = {}

function M.hex(s)
  return {
    tonumber(s:sub(2, 3), 16) / 255,
    tonumber(s:sub(4, 5), 16) / 255,
    tonumber(s:sub(6, 7), 16) / 255,
  }
end

local hex = M.hex

M.CO = {
  ink = hex '#221433', night = hex '#0d1b33',
  sea = hex '#2a63ae', seaD = hex '#1d4d92', seaL = hex '#4b86cc', foam = hex '#bfe6f5',
  sky = hex '#a9def0', skyD = hex '#7cc2e0', sun = hex '#ffe08a',
  wood = hex '#96662f', woodD = hex '#6b4420', woodL = hex '#b98546',
  sand = hex '#ecd693', sandD = hex '#c4a95f',
  white = hex '#ffffff', paper = hex '#ffedc2', gray = hex '#9aa3b6', grayD = hex '#5c6473',
  gold = hex '#ffcf40', goldD = hex '#c9891b',
  red = hex '#e84b4b', redD = hex '#94263a',
  green = hex '#54cf62', greenD = hex '#20803a',
  blue = hex '#4a90d9', purple = hex '#9a63e0', orange = hex '#ff9838',
  hp = hex '#54cf62', hpBad = hex '#e84b4b', uiBg = hex '#221433', uiBg2 = hex '#38235c',
}

return M
