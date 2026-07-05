-- LÖVE runs LuaJIT (5.1 + extensions); tests also run under plain Lua 5.1+.
std = 'luajit'
read_globals = { 'love' }

exclude_files = { 'src/lib' } -- vendored third-party code

max_line_length = false
unused_args = false -- LÖVE callbacks and state update(dt) have fixed signatures
ignore = { '213/_.*' } -- underscore-prefixed loop vars are intentionally unused

-- main.lua/conf.lua define the love.* callbacks.
files['main.lua'] = { globals = { love = { other_fields = true } } }
files['conf.lua'] = { globals = { love = { other_fields = true } } }

-- Unit tests run under any Lua from 5.1 up, and stub the love global.
files['tests'] = { std = 'max', globals = { 'love' } }

-- script.lua wraps love.keyboard.isDown so scripted taps reach baton's polling.
files['src/dev/script.lua'] = { globals = { love = { other_fields = true } } }

-- Dev scripts run inside script.lua's env, which injects these helpers.
files['src/dev/smoke_script.lua'] = {
  read_globals = { 'tap', 'tap2', 'tapCell', 'wait', 'waitUntil', 'shot', 'expect', 'dump' },
}
