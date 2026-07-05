-- State dump (0.5): `--dump` prints this at quit; scripts can also call the
-- `dump()` helper (src/dev/script.lua) on demand. `game.run` is plain data so
-- it round-trips through serialize.encode() as-is; battle state lives outside
-- run (module-level sb/pb), so it gets its own shallow, reference-free
-- summary — skipping foeRef/ref back-pointers into game.run.
local serialize = require 'src.serialize'
local game = require 'src.game'
local shipBattle = require 'src.states.ship_battle'
local personBattle = require 'src.states.person_battle'

local M = {}

function M.dump()
  local lines = { 'RUN ' .. serialize.encode(game.run) }

  local sb = shipBattle.sb
  if sb then
    local shipsStr = {}
    for i, sh in ipairs(sb.ships) do
      shipsStr[#shipsStr + 1] = string.format('ship%d=%d/%d(%s)', i, sh.hp, sh.max, sh.range)
    end
    lines[#lines + 1] = string.format(
      'SHIP turn=%s %s foe=%d/%d over=%s',
      sb.turn, table.concat(shipsStr, ' '), sb.foe.hp, sb.foe.max, tostring(sb.over))
  end

  local pb = personBattle.pb
  if pb then
    lines[#lines + 1] = string.format('BOARD phase=%s over=%s', pb.phase, tostring(pb.over))
    for _, u in ipairs(pb.units) do
      lines[#lines + 1] = string.format(
        '  UNIT %s side=%s hp=%d/%d pos=%d,%d alive=%s',
        u.name, u.side, u.hp, u.max, u.x, u.y, tostring(u.alive))
    end
  end

  local out = table.concat(lines, '\n')
  print(out)
  return out
end

return M
