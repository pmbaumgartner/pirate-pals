-- Plain-Lua unit tests for perk data + game.statsOf's perk math (3.3).
-- game.lua now pulls in engine/audio (design-gaps/06 foundSecret) which only
-- touch love.* inside function bodies, so a stub table is enough to load
-- them (same approach as person_battle_test.lua).
package.path = './?.lua;' .. package.path
love = {
  graphics = {},
  audio = {},
  sound = {},
  math = { random = math.random },
  filesystem = {
    getInfo = function() return nil end,
    write = function() end,
    read = function() return nil end,
  },
}
local data = require 'src.data'
local game = require 'src.game'

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

-- Every role has exactly two, both-good options at each milestone level.
for role in pairs(data.ROLES) do
  for _, lv in ipairs({ 2, 4, 6 }) do
    local opts = data.perksFor(role, lv)
    ok(opts ~= nil, role .. ' has a perk pair at level ' .. lv)
    ok(opts and #opts == 2, role .. ' level ' .. lv .. ' offers exactly two options')
  end
  ok(data.perksFor(role, 3) == nil, role .. ' level 3 is not a milestone')
end

-- perkById flattens the per-role tables so statsOf can look up by id alone.
local anyPerk = data.perksFor('captain', 2)[1]
ok(data.perkById(anyPerk.id) == anyPerk, 'perkById finds a known perk')
ok(data.perkById('nope') == nil, 'perkById returns nil for an unknown id')

-- statsOf applies every perk's effects on top of the role/level baseline.
local p = game.makePirate('deckhand', 'FIN', 3)
local base = game.statsOf(p)
p.perks = { 'dhBoots' } -- +1 move
local withBoots = game.statsOf(p)
ok(withBoots.move == base.move + 1, 'a single perk applies its stat delta')
ok(withBoots.hp == base.hp and withBoots.atk == base.atk and withBoots.range == base.range,
  'unrelated stats are untouched by an unrelated perk')

p.perks = { 'dhBoots', 'dhMuscle' } -- +1 move, +2 atk
local stacked = game.statsOf(p)
ok(stacked.move == base.move + 1, 'stacked perks keep the move delta')
ok(stacked.atk == base.atk + 2, 'stacked perks add the atk delta too')

-- A pirate with no perks at all round-trips through statsOf unaffected.
local plain = game.makePirate('medic', 'PIPPA', 2)
local plainStats = game.statsOf(plain)
ok(plainStats.hp == data.ROLES.medic.hp + 2, 'statsOf works with no p.perks field at all')

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('perks_test OK')
