-- Plain-Lua unit tests for hidden delights: data-shape,
-- game.foundSecret idempotency, and the meta round-trip of the secrets set.
-- game.lua's foundSecret pulls in engine/audio, which only touch love.*
-- inside function bodies, so a stub table is enough (same approach as
-- person_battle_test.lua). Run: `lua tests/secrets_test.lua`.
package.path = './?.lua;' .. package.path
love = {
  graphics = {},
  math = { random = function() return 0.5 end },
  audio = { newSource = function() return { play = function() end } end },
  sound = { newSoundData = function(len, rate, bits, ch)
    return { setSample = function() end }
  end },
  filesystem = {
    getInfo = function() return nil end,
    write = function() end,
    read = function() return nil end,
  },
}
local data = require 'src.data'
local meta = require 'src.meta'
local game = require 'src.game'
local audio = require 'src.audio'
local serialize = require 'src.serialize'
audio.muted = true

local fails = 0
local function ok(cond, msg)
  if not cond then
    fails = fails + 1
    print('FAIL: ' .. msg)
  end
end

-- Data shape: every SECRETS entry has an id and a name, ids are unique.
local seen = {}
for _, s in ipairs(data.SECRETS) do
  ok(s.id ~= nil and s.id ~= '', 'secret has a non-empty id')
  ok(s.name ~= nil and s.name ~= '', s.id .. ' has a non-empty name')
  ok(not seen[s.id], s.id .. ' is not a duplicate id')
  seen[s.id] = true
end

-- game.foundSecret idempotency: repeat calls don't re-fire the banner (the
-- caller-visible signal is meta.data.secrets staying a plain true, not a
-- counter), and an unknown id is a no-op-safe write.
meta.newMeta()
local someId = data.SECRETS[1].id
ok(meta.data.secrets[someId] == nil, 'fresh meta has no secrets found yet')
game.foundSecret(someId)
ok(meta.data.secrets[someId] == true, 'foundSecret marks the id found')
game.foundSecret(someId) -- second call must not error or change shape
ok(meta.data.secrets[someId] == true, 'a repeat foundSecret call is a no-op')
ok(game.distinctSecrets() == 1, 'distinctSecrets counts found secrets')

game.foundSecret(data.SECRETS[2].id)
ok(game.distinctSecrets() == 2, 'distinctSecrets tracks multiple finds')

-- Meta round-trip: the secrets set survives serialize like every other
-- meta.data field (hats/upgrades/etc, see meta_test.lua).
local encoded = serialize.encode(meta.data)
local decoded = serialize.decode(encoded)
ok(decoded.secrets[someId] == true, 'meta round-trips a found secret through serialize')
ok(decoded.secrets[data.SECRETS[2].id] == true, 'meta round-trips a second found secret')

-- meta.load() defaults secrets to {} for saves written before this field
-- existed, mirroring how hats/voyagesWon/etc default on load.
local savedNoSecrets = { version = 1 }
local origRead = love.filesystem.read
love.filesystem.read = function() return serialize.encode(savedNoSecrets) end
meta.load()
ok(type(meta.data.secrets) == 'table', 'meta.load() defaults a missing secrets field to a table')
love.filesystem.read = origRead

if fails > 0 then
  print(fails .. ' FAILURES')
  os.exit(1)
end
print('secrets_test OK')
