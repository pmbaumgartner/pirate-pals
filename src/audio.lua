-- Chiptune SFX synthesized at runtime (LÖVE has no WebAudio, so tones are
-- rendered to SoundData once and cached by parameters; noise bursts are
-- regenerated per play so each one crackles differently, like the original).
-- Delayed notes ("when") sit in a pending queue drained by update(dt).
local M = { muted = false }

local RATE = 22050
local toneCache = {}
local pending = {}
local warming = false

local function play(sd)
  love.audio.newSource(sd, 'static'):play()
end

local function queue(sd, when)
  if warming then return end
  if when and when > 0 then
    pending[#pending + 1] = { t = when, sd = sd }
  else
    play(sd)
  end
end

function M.update(dt)
  for i = #pending, 1, -1 do
    local p = pending[i]
    p.t = p.t - dt
    if p.t <= 0 then
      play(p.sd)
      table.remove(pending, i)
    end
  end
end

local TWO_PI = 2 * math.pi

local function synthTone(freq, dur, wave, vol, slideTo)
  local len = math.floor(RATE * (dur + 0.05))
  local sd = love.sound.newSoundData(len, RATE, 16, 1)
  local phase = 0
  local f0 = freq
  local f1 = slideTo and math.max(20, slideTo) or freq
  local attack = 0.012
  for i = 0, len - 1 do
    local t = i / RATE
    local k = math.min(1, t / dur)
    local f = f0 * ((f1 / f0) ^ k) -- exponential frequency ramp
    phase = (phase + f / RATE) % 1
    local s
    if wave == 'sine' then s = math.sin(TWO_PI * phase)
    elseif wave == 'triangle' then s = 1 - 4 * math.abs(phase - 0.5)
    elseif wave == 'sawtooth' then s = 2 * phase - 1
    else s = phase < 0.5 and 1 or -1 end
    local env
    if t < attack then
      env = 0.0001 * ((vol / 0.0001) ^ (t / attack))
    elseif t < dur then
      local q = (t - attack) / math.max(0.0001, dur - attack)
      env = vol * ((0.0001 / vol) ^ q)
    else
      env = 0
    end
    sd:setSample(i, s * env)
  end
  return sd
end

function M.tone(freq, dur, wave, vol, slideTo, when)
  if M.muted then return end
  wave = wave or 'square'
  vol = vol or 0.08
  local key = table.concat({ freq, dur, wave, vol, slideTo or 0 }, '|')
  local sd = toneCache[key]
  if not sd then
    sd = synthTone(freq, dur, wave, vol, slideTo)
    toneCache[key] = sd
  end
  queue(sd, when)
end

function M.noiseBurst(dur, vol, when)
  if M.muted then return end
  vol = vol or 0.1
  local len = math.floor(RATE * dur)
  local sd = love.sound.newSoundData(len, RATE, 16, 1)
  for i = 0, len - 1 do
    local t = i / RATE
    local fade = 1 - i / len
    local gain = vol * ((0.0001 / vol) ^ (t / dur))
    sd:setSample(i, (love.math.random() * 2 - 1) * fade * gain)
  end
  queue(sd, when)
end

local tone, noiseBurst = M.tone, M.noiseBurst

-- Role sound motifs (Gap 1): a 2-3 note signature per role, played by
-- src/barks.lua alongside a bark line. Distinct register per role; each
-- totals well under 0.25s. Tones are cache-keyed like sfx, so repeats are free.
local MOTIFS = {
  captain = function()
    tone(660, 0.05, 'square', 0.05)
    tone(880, 0.07, 'square', 0.05, nil, 0.05)
  end,
  deckhand = function()
    tone(440, 0.04, 'square', 0.05)
    tone(554, 0.04, 'square', 0.05, nil, 0.045)
    tone(659, 0.06, 'square', 0.05, nil, 0.09)
  end,
  strongman = function()
    tone(120, 0.09, 'triangle', 0.08)
    tone(90, 0.1, 'triangle', 0.08, nil, 0.08)
  end,
  sharpshooter = function()
    tone(1000, 0.03, 'square', 0.05)
    tone(1000, 0.03, 'square', 0.05, nil, 0.05)
  end,
  medic = function()
    tone(700, 0.08, 'sine', 0.05)
    tone(900, 0.09, 'sine', 0.05, nil, 0.08)
  end,
  king = function() tone(90, 0.16, 'sawtooth', 0.09, 45) end,
}

function M.motif(roleKey)
  local fn = MOTIFS[roleKey]
  if fn then fn() end
end

M.sfx = {
  move = function() tone(200, 0.045, 'square', 0.03) end,
  sel = function() tone(540, 0.06, 'square', 0.05) end,
  back = function() tone(300, 0.06, 'square', 0.04, 180) end,
  bump = function() tone(90, 0.08, 'triangle', 0.08, 60) end,
  boom = function() noiseBurst(0.22, 0.16); tone(75, 0.2, 'triangle', 0.16, 38) end,
  shot = function() noiseBurst(0.07, 0.1); tone(340, 0.07, 'square', 0.06, 120) end,
  splash = function() noiseBurst(0.16, 0.07); tone(500, 0.14, 'sine', 0.05, 160) end,
  hit = function() tone(170, 0.08, 'square', 0.1, 80) end,
  perfect = function()
    tone(660, 0.07, 'square', 0.07)
    tone(880, 0.07, 'square', 0.07, nil, 0.07)
    tone(1320, 0.12, 'square', 0.07, nil, 0.14)
  end,
  good = function() tone(560, 0.08, 'square', 0.06) end,
  miss = function() tone(160, 0.16, 'sawtooth', 0.05, 90) end,
  block = function() tone(240, 0.05, 'square', 0.08); tone(240, 0.05, 'square', 0.08, nil, 0.06) end,
  coin = function() tone(920, 0.05, 'square', 0.06); tone(1380, 0.09, 'square', 0.06, nil, 0.05) end,
  heal = function() tone(520, 0.09, 'sine', 0.08, 780); tone(780, 0.12, 'sine', 0.07, 1040, 0.09) end,
  fanfare = function()
    tone(523, 0.1, 'square', 0.07)
    tone(659, 0.1, 'square', 0.07, nil, 0.1)
    tone(784, 0.22, 'square', 0.08, nil, 0.2)
  end,
  bigwin = function()
    tone(523, 0.09, 'square', 0.07)
    tone(659, 0.09, 'square', 0.07, nil, 0.09)
    tone(784, 0.09, 'square', 0.07, nil, 0.18)
    tone(1047, 0.3, 'square', 0.08, nil, 0.27)
  end,
  lose = function() tone(320, 0.15, 'triangle', 0.08, 160); tone(160, 0.3, 'triangle', 0.08, 80, 0.15) end,
  level = function()
    tone(440, 0.07, 'square', 0.07)
    tone(554, 0.07, 'square', 0.07, nil, 0.07)
    tone(659, 0.16, 'square', 0.08, nil, 0.14)
  end,
  buy = function() tone(700, 0.06, 'square', 0.06); tone(1050, 0.1, 'square', 0.06, nil, 0.06) end,
  poof = function() noiseBurst(0.12, 0.06); tone(300, 0.12, 'sine', 0.05, 120) end,
  push = function() tone(220, 0.1, 'square', 0.09, 110) end,
}

-- Synthesize every tone into the cache without playing anything, so the
-- first real play of each SFX doesn't hiccup a frame. Call once at load.
-- Noise bursts are regenerated per play by design and are cheap.
function M.warm()
  warming = true
  for _, fn in pairs(M.sfx) do fn() end
  for _, fn in pairs(MOTIFS) do fn() end
  warming = false
end

return M
