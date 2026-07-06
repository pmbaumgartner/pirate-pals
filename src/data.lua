-- Static design tables. Balance tweaks and new content start here:
-- add a role/outfit/treasure entry and the rest of the game picks it up.
local M = {}

M.ROLES = {
  captain = { label = 'CAPTAIN', hp = 14, atk = 5, move = 3, range = 1,
    spec = { name = 'YO-HO!', desc = 'ALL PALS +2 ATK' },
    ship = { name = 'FIRE ALL!', desc = 'TWO CANNONBALLS' } },
  deckhand = { label = 'DECKHAND', hp = 12, atk = 4, move = 4, range = 1,
    spec = { name = 'HEAVE-HO!', desc = 'SHOVE AN ENEMY' },
    ship = { name = 'FULL SAILS', desc = 'DODGE NEXT HIT' } },
  strongman = { label = 'STRONGMAN', hp = 18, atk = 6, move = 2, range = 1,
    spec = { name = 'SMASH!', desc = 'HIT ALL NEIGHBORS' },
    ship = { name = 'HEAVY BALL', desc = 'BIG DAMAGE' } },
  sharpshooter = { label = 'SHARPSHOOTER', hp = 10, atk = 4, move = 3, range = 3,
    spec = { name = 'LONG SHOT', desc = 'HIT ANY ENEMY' },
    ship = { name = 'TRUE SHOT', desc = 'NEVER MISSES' } },
  medic = { label = 'MEDIC', hp = 11, atk = 3, move = 3, range = 1,
    spec = { name = 'PATCH UP', desc = 'HEAL A PAL +8' },
    ship = { name = 'PATCH SHIP', desc = 'REPAIR +12' } },
}

M.EROLES = {
  grunt  = { label = 'SEA DOG', hp = 7, hpLv = 3, atk = 2, atkLv = 1, move = 3, range = 1, join = 'deckhand' },
  gunner = { label = 'GUNNER', hp = 5, hpLv = 2, atk = 2, atkLv = 1, move = 3, range = 3, join = 'sharpshooter' },
  brute  = { label = 'BRUTE', hp = 10, hpLv = 4, atk = 3, atkLv = 1, move = 2, range = 1, join = 'strongman' },
  -- Gimmick enemies, one visible rule each. CRAB: shell halves
  -- frontal damage, hit it from behind (see damage() in person_battle.lua).
  -- THIEF PARROT: grabs gold and flees; join=nil keeps escapo-birds out of
  -- the recruit pool.
  crab   = { label = 'CRAB', hp = 9, hpLv = 3, atk = 2, atkLv = 1, move = 1, range = 1, join = 'strongman' },
  thief  = { label = 'THIEF PARROT', hp = 5, hpLv = 2, atk = 1, atkLv = 0, move = 4, range = 1, join = nil },
  king   = { label = 'PIRATE KING', hp = 26, hpLv = 0, atk = 5, atkLv = 0, move = 1, range = 1, join = nil },
}

-- Biomes: palette swap + exactly one visible twist rule each, applied
-- flag-driven in sail.lua. `twist` is the banner/hint wording a pre-reader
-- hears read aloud once and then recognizes by the palette + icon.
M.BIOMES = {
  calm    = { name = 'CALM SEA', twist = 'SMOOTH SAILING!', icon = 'bio_calm' },
  icy     = { name = 'ICY SEA', twist = 'SLIPPY ICE! WHEE!', icon = 'bio_icy' },
  foggy   = { name = 'FOGGY SEA', twist = 'WHO GOES THERE?', icon = 'bio_foggy' },
  volcano = { name = 'VOLCANO SEA', twist = 'DODGE THE ROCKS!', icon = 'bio_volcano' },
}

-- Draw pool for seas 2+ (sea 1 and the boss sea are always calm). Calm stays
-- in the pool so plain seas keep appearing between twists.
M.BIOME_POOL = { 'calm', 'icy', 'foggy', 'volcano' }

-- Crew colors (color selector): each captain picks one; it paints their
-- ship's sail + flag and a checkered sash on their pals. `sail` is the
-- bright shade, `flag` the dark shade -- WHITE keeps its red flag so the
-- classic look stays classic. Player purple is a step lighter than the
-- sharpshooter/King coat purple (#9a63e0); enemy ships read by shape
-- (tattered sails + skull flag), not color, so no swatch is banned.
M.PLAYER_COLORS = {
  { id = 'white',  name = 'WHITE',  sail = '#ffffff', flag = '#e84b4b', accent = '#ffffff' },
  { id = 'red',    name = 'RED',    sail = '#e84b4b', flag = '#94263a', accent = '#e84b4b' },
  { id = 'orange', name = 'ORANGE', sail = '#ff9838', flag = '#c05f1d', accent = '#ff9838' },
  { id = 'yellow', name = 'YELLOW', sail = '#ffcf40', flag = '#c9891b', accent = '#ffcf40' },
  { id = 'green',  name = 'GREEN',  sail = '#54cf62', flag = '#20803a', accent = '#54cf62' },
  { id = 'blue',   name = 'BLUE',   sail = '#4a90d9', flag = '#2b5fa8', accent = '#4a90d9' },
  { id = 'purple', name = 'PURPLE', sail = '#b07ef0', flag = '#6a3fae', accent = '#b07ef0' },
  { id = 'pink',   name = 'PINK',   sail = '#f291c7', flag = '#b3477f', accent = '#f291c7' },
}

function M.playerColorById(id)
  for _, c in ipairs(M.PLAYER_COLORS) do
    if c.id == id then return c end
  end
  return M.PLAYER_COLORS[1]
end

-- Boarding deck shapes: hand-authored ASCII masks, parsed by
-- person_battle/model.lua's buildDeck. Legend: 'P' party spawn band, 'E'
-- enemy spawn band, 'c' crate-eligible open deck, '#' plain open deck,
-- '.' hole (drawn as sea, never walkable). Rows must all share one width.
-- `weight` only matters once a sea is old enough to draw from the full pool
-- (see model.pickDeckId) — classic is forced alone on seas 1-2 and stays the
-- heaviest weight after that, so variety stays seasoning, not chaos.
M.DECKS = {
  { id = 'classic', weight = 10, rows = {
    'PccccccEE',
    'PccccccEE',
    'PccccccEE',
    'PccccccEE',
    'PccccccEE',
  } },
  -- `logText`: the Voyage Log line the first-ever battle on
  -- this shape appends; classic gets none since it's never a "first".
  { id = 'gangplank', weight = 2, choke = true, logText = 'BATTLE ON THE PLANK!', rows = {
    'PPccc....EE',
    'PPcccccccEE',
    'PPccc....EE',
  } },
  { id = 'lshape', weight = 2, logText = 'BATTLE IN THE L-SHAPED HOLD!', rows = {
    'PPcccc...',
    'PPcccc...',
    'PPcccc...',
    'PPccccEEE',
    'PPccccEEE',
  } },
  { id = 'twinDecks', weight = 1, choke = true, logText = 'BATTLE ACROSS THE TWIN DECKS!', rows = {
    'PPcc..ccEE',
    'PPcc##ccEE',
    'PPcc##ccEE',
    'PPcc..ccEE',
    'PPcc..ccEE',
  } },
  { id = 'crowsnest', weight = 1, logText = "BATTLE ON THE CROW'S NEST!", rows = {
    '.EEEEE.',
    'EEEEEEE',
    'ccccccc',
    'ccc^ccc',
    'ccccccc',
    'PPPPPPP',
    '.PPPPP.',
  } },
  { id = 'bigDeck', weight = 2, logText = 'BATTLE ON THE BIG DECK!', rows = {
    'PPccccccEEE',
    'PPccccccEEE',
    'PPccccccEEE',
    'PPccccccEEE',
    'PPccccccEEE',
  } },
  { id = 'barricade', weight = 1, choke = true, logText = 'BATTLE AT THE BARRICADE!', rows = {
    'PPcccbccEE',
    'PPcccbccEE',
    'PPccc#c^EE',
    'PPcccbccEE',
    'PPcccbccEE',
  } },
  { id = 'tidepool', weight = 1, logText = 'BATTLE AT THE TIDEPOOL!', rows = {
    'PccccccEE',
    'Pccc.ccEE',
    'Pccc^ccEE',
    'Pccc.ccEE',
    'PccccccEE',
  } },
}

-- Outfits are bought with gold (price) or unlocked at treasure-log
-- milestones (mile). Order matters: index 1 is the default.
M.OUTFITS = {
  { id = 'none',  name = 'NO HAT' },
  { id = 'bandR', name = 'RED BANDANA', price = 15 },
  { id = 'patch', name = 'EYEPATCH', price = 25 },
  { id = 'straw', name = 'STRAW HAT', price = 40 },
  { id = 'tri',   name = 'TRICORN', price = 60 },
  { id = 'parrot', name = 'PARROT PAL', price = 120 },
  { id = 'bandB', name = 'BLUE BANDANA', mile = 3 },
  { id = 'cap',   name = "CAPTAIN'S HAT", mile = 6 },
  { id = 'crown', name = 'ROYAL CROWN', mile = 9 },
}

M.TREASURES = {
  { id = 'coin',  name = 'GOLD COIN', tier = 0 },
  { id = 'ring',  name = 'SILVER RING', tier = 0 },
  { id = 'glass', name = 'SEA GLASS', tier = 0 },
  { id = 'map',   name = 'OLD MAP', tier = 0 },
  { id = 'pearl', name = 'PEARL', tier = 1 },
  { id = 'ruby',  name = 'RUBY', tier = 1 },
  { id = 'spy',   name = 'SPYGLASS', tier = 1 },
  { id = 'anchor', name = 'ANCHOR CHARM', tier = 1 },
  { id = 'ban',   name = 'GOLD BANANA', tier = 2 },
  { id = 'tooth', name = 'KRAKEN TOOTH', tier = 2 },
  { id = 'bottle', name = 'SHIP BOTTLE', tier = 2 },
  { id = 'star',  name = 'STAR SHELL', tier = 2 },
}

M.MILESTONES = { { n = 3, id = 'bandB' }, { n = 6, id = 'cap' }, { n = 9, id = 'crown' } }

-- Hidden delights: small undocumented purely-positive finds,
-- never rules -- `name` is shown once found, `hint` is the vague ALL-CAPS
-- nudge shown as the unfound slot's caption. `src/game.lua`'s foundSecret is
-- the only writer of meta.data.secrets; new entries here pair with a
-- foundSecret(id) call at whatever hook triggers them.
M.SECRETS = {
  { id = 'hatbark', name = 'ALL HAIL!', hint = 'A CROWNED PAL SPEAKS UP' },
  { id = 'napbuddies', name = 'NAP BUDDIES', hint = 'TWO SLEEPY PALS TOGETHER' },
  { id = 'kingsniff', name = 'NICE HATS. STILL NO.', hint = 'MATCHING HATS, FINAL SEA' },
  { id = 'cannonball', name = 'CANNONBALL RUN!', hint = 'THREE PERFECT SHOTS' },
  { id = 'seashell', name = 'SEASHELL!', hint = 'DIG NEAR THE SAND' },
  { id = 'echobark', name = 'ECHO SQUAWK!', hint = 'BOTH BARK AS ONE' },
  { id = 'bootsong', name = 'BOOT SONG', hint = 'SIT STILL A WHILE' },
  { id = 'fishfriend', name = 'FISH FRIEND!', hint = 'HOLD STILL ON ICY WATER' },
  { id = 'luckycoin', name = 'LUCKY STREAK!', hint = 'CLEAR EVERY CHEST UNBROKEN' },
  { id = 'tightrope', name = 'NOBODY WOBBLED!', hint = 'CROSS THE PLANK CAREFULLY' },
}

-- Perk picks: two options per role at milestone levels 2/4/6, both
-- good, effects limited to flat stat deltas so game.statsOf stays a single
-- choke point. `icon` keys a small sprite drawn on the loot pick card.
M.PERKS = {
  captain = {
    [2] = { { id = 'capBoots', name = 'BIG BOOTS', desc = '+1 MOVE', icon = 'boots', effects = { move = 1 } },
      { id = 'capBelly', name = 'TOUGH BELLY', desc = '+4 HP', icon = 'belly', effects = { hp = 4 } } },
    [4] = { { id = 'capArms', name = 'LONG ARMS', desc = '+1 RANGE', icon = 'arms', effects = { range = 1 } },
      { id = 'capMuscle', name = 'STRONG ARMS', desc = '+2 ATK', icon = 'muscle', effects = { atk = 2 } } },
    [6] = { { id = 'capLegs', name = 'SEA LEGS', desc = '+1 MOVE +2 HP', icon = 'boots', effects = { move = 1, hp = 2 } },
      { id = 'capHide', name = 'IRON HIDE', desc = '+6 HP', icon = 'belly', effects = { hp = 6 } } },
  },
  deckhand = {
    [2] = { { id = 'dhBoots', name = 'BIG BOOTS', desc = '+1 MOVE', icon = 'boots', effects = { move = 1 } },
      { id = 'dhBelly', name = 'TOUGH BELLY', desc = '+4 HP', icon = 'belly', effects = { hp = 4 } } },
    [4] = { { id = 'dhArms', name = 'LONG ARMS', desc = '+1 RANGE', icon = 'arms', effects = { range = 1 } },
      { id = 'dhMuscle', name = 'STRONG ARMS', desc = '+2 ATK', icon = 'muscle', effects = { atk = 2 } } },
    [6] = { { id = 'dhLegs', name = 'SEA LEGS', desc = '+1 MOVE +2 HP', icon = 'boots', effects = { move = 1, hp = 2 } },
      { id = 'dhHide', name = 'IRON HIDE', desc = '+6 HP', icon = 'belly', effects = { hp = 6 } } },
  },
  strongman = {
    [2] = { { id = 'smBoots', name = 'BIG BOOTS', desc = '+1 MOVE', icon = 'boots', effects = { move = 1 } },
      { id = 'smBelly', name = 'TOUGH BELLY', desc = '+4 HP', icon = 'belly', effects = { hp = 4 } } },
    [4] = { { id = 'smArms', name = 'LONG ARMS', desc = '+1 RANGE', icon = 'arms', effects = { range = 1 } },
      { id = 'smMuscle', name = 'STRONG ARMS', desc = '+2 ATK', icon = 'muscle', effects = { atk = 2 } } },
    [6] = { { id = 'smLegs', name = 'SEA LEGS', desc = '+1 MOVE +2 HP', icon = 'boots', effects = { move = 1, hp = 2 } },
      { id = 'smHide', name = 'IRON HIDE', desc = '+6 HP', icon = 'belly', effects = { hp = 6 } } },
  },
  sharpshooter = {
    [2] = { { id = 'ssBoots', name = 'BIG BOOTS', desc = '+1 MOVE', icon = 'boots', effects = { move = 1 } },
      { id = 'ssBelly', name = 'TOUGH BELLY', desc = '+4 HP', icon = 'belly', effects = { hp = 4 } } },
    [4] = { { id = 'ssArms', name = 'LONG ARMS', desc = '+1 RANGE', icon = 'arms', effects = { range = 1 } },
      { id = 'ssMuscle', name = 'STRONG ARMS', desc = '+2 ATK', icon = 'muscle', effects = { atk = 2 } } },
    [6] = { { id = 'ssLegs', name = 'SEA LEGS', desc = '+1 MOVE +2 HP', icon = 'boots', effects = { move = 1, hp = 2 } },
      { id = 'ssHide', name = 'IRON HIDE', desc = '+6 HP', icon = 'belly', effects = { hp = 6 } } },
  },
  medic = {
    [2] = { { id = 'mdBoots', name = 'BIG BOOTS', desc = '+1 MOVE', icon = 'boots', effects = { move = 1 } },
      { id = 'mdBelly', name = 'TOUGH BELLY', desc = '+4 HP', icon = 'belly', effects = { hp = 4 } } },
    [4] = { { id = 'mdArms', name = 'LONG ARMS', desc = '+1 RANGE', icon = 'arms', effects = { range = 1 } },
      { id = 'mdMuscle', name = 'STRONG ARMS', desc = '+2 ATK', icon = 'muscle', effects = { atk = 2 } } },
    [6] = { { id = 'mdLegs', name = 'SEA LEGS', desc = '+1 MOVE +2 HP', icon = 'boots', effects = { move = 1, hp = 2 } },
      { id = 'mdHide', name = 'IRON HIDE', desc = '+6 HP', icon = 'belly', effects = { hp = 6 } } },
  },
}

M.FOE_CAPTAINS = {
  'RUSTY ROGER', 'SQUID SID', 'GALE GRETA', 'IRON IVAN', 'SALTY SUE',
  'BILGE BOB', 'MOLLY MIST', 'SHARKTOOTH SAM', 'FOGGY FRAN', 'CRABBY CRAIG',
}

M.PAL_NAMES = {
  'PEG-LEG PETE', 'BOSUN BETTY', 'CORAL KATE', 'FISHBONE FINN', 'BARNACLE BILL',
  'MARINA', 'GULLY', 'ANCHOVY ANDY', 'SUNNY', 'SHELLS', 'PIPPA', 'DRIFT',
  'MANGO', 'WAVE WILL', 'LUCKY LU', 'TIDE', 'OTTER OZ', 'KELPY',
}

-- Barks: 2-4 ALL-CAPS lines per role per trigger, all short enough
-- for a scale-1 floater near a 16px unit. `src/barks.lua` is the only
-- reader; every player role + `king` must carry every trigger (see
-- data_shape_test.lua) even where a trigger never actually fires for that
-- role (e.g. king's bestMates), so the table stays a simple, testable grid.
M.BARK_TRIGGERS = { 'battleStart', 'perfect', 'levelUp', 'bestMates', 'ko', 'victory', 'special' }

M.BARKS = {
  captain = {
    battleStart = { 'ALL HANDS!', 'YO HO HO!', 'TO ARMS, CREW!' },
    perfect = { 'PERFECT HIT!', 'BULLSEYE!' },
    levelUp = { 'STRONGER NOW!', 'LEVEL UP!' },
    bestMates = { 'TRUE MATES!', 'CREW FOR LIFE!' },
    ko = { 'ZZZ NAP TIME!', 'NIGHT NIGHT!' },
    victory = { 'WE DID IT!', 'HUZZAH!', 'FINE CREW!' },
    special = { 'YO-HO!', 'RALLY ROUND!' },
  },
  deckhand = {
    battleStart = { "LET'S GO!", 'HEAVE HO!' },
    perfect = { 'NICE ONE!', 'BOOM!' },
    levelUp = { 'GETTING GOOD!', 'LEVEL UP!' },
    bestMates = { 'BEST MATES!', "YOU'RE ALRIGHT" },
    ko = { 'ZZZ NAP TIME!', 'NIGHT NIGHT!' },
    victory = { 'WOOHOO!', 'WE WON!' },
    special = { 'HEAVE-HO!', 'OUTTA HERE!' },
  },
  strongman = {
    battleStart = { 'SMASH TIME!', 'RRRAAH!' },
    perfect = { 'CRUSHED IT!', 'SMASH!' },
    levelUp = { 'SO STRONG!', 'LEVEL UP!' },
    bestMates = { 'MY PAL!', 'BEST MATES!' },
    ko = { 'ZZZ NAP TIME!', 'NIGHT NIGHT!' },
    victory = { 'EASY!', 'WE WON!' },
    special = { 'SMASH!!', 'TAKE THIS!' },
  },
  sharpshooter = {
    battleStart = { 'LOCKED ON!', 'EYES UP!' },
    perfect = { 'CALLED IT!', 'BULLSEYE!' },
    levelUp = { 'SHARPER NOW!', 'LEVEL UP!' },
    bestMates = { 'GOT YOUR BACK!', 'BEST MATES!' },
    ko = { 'ZZZ NAP TIME!', 'NIGHT NIGHT!' },
    victory = { 'NAILED IT!', 'WE WON!' },
    special = { 'LONG SHOT!', 'SNIPED!' },
  },
  medic = {
    battleStart = { 'STAY SAFE!', 'HANG TIGHT!' },
    perfect = { 'PERFECT!', 'GOT IT!' },
    levelUp = { 'FEELS GOOD!', 'LEVEL UP!' },
    bestMates = { 'BEST MATES!', 'HERE FOR YOU!' },
    ko = { 'ZZZ NAP TIME!', 'NIGHT NIGHT!' },
    victory = { 'ALL PATCHED UP', 'WE WON!' },
    special = { 'PATCH UP!', 'GOOD AS NEW!' },
  },
  king = {
    battleStart = { 'BOW TO ME!', 'YE FOOLS!' },
    perfect = { 'TOO EASY!', 'IMPRESSIVE...' },
    levelUp = { 'MORE POWER!', 'STRONGER YET!' },
    bestMates = { 'SO WEAK!', 'PATHETIC!' },
    ko = { 'NOOOO!', 'MY SHIP...' },
    victory = { 'NEVER!', 'IMPOSSIBLE!' },
    special = { "YE'LL PAY!", 'RRRAAGH!' },
  },
}

-- Name overrides (optional, standout pals only): checked before the role
-- table, per trigger, so a pal can have a quirk on just one or two beats.
M.BARKS_BY_NAME = {
  GULLY = {
    battleStart = { 'SMASH SMASH!' },
    special = { 'SMAAASH!' },
  },
  PIPPA = {
    battleStart = { 'YIPPEE!' },
    perfect = { 'YIPPEE!' },
  },
  MANGO = {
    ko = { 'ZZZ MANGO NAP!' },
    victory = { 'MANGO WINS!' },
  },
}

-- Outfit-keyed bark overrides (for the 'hatbark' secret): checked before the
-- name/role tables in barks.say, so a hat can make a pal talk differently.
-- Partial like BARKS_BY_NAME -- a missing trigger falls through to the name
-- or role table instead of going silent.
M.BARKS_BY_OUTFIT = {
  crown = {
    battleStart = { 'I DARE SAY, TALLY-HO!' },
    perfect = { 'MOST SPLENDID!' },
    victory = { 'HUZZAH, GOOD SHOW!' },
    special = { 'I DARE SAY, BONK!' },
  },
}

-- Pirate King one-off barks (item 5): standalone, not part of the generic
-- M.BARKS grid, since they fire at King-only beats (boss intro, bar break,
-- SLAM telegraph) rather than the shared triggers above.
M.BARKS_KING = {
  taunt = { 'FEAR ME!', 'NONE SHALL PASS!' },
  rage = { "YE'LL NEVER— HEY!", 'ME BEAUTIFUL SHIP!' },
  slam = { 'HERE IT COMES!' },
}

function M.outfitById(id)
  for _, o in ipairs(M.OUTFITS) do
    if o.id == id then return o end
  end
  return M.OUTFITS[1]
end

function M.treasureById(id)
  for _, t in ipairs(M.TREASURES) do
    if t.id == id then return t end
  end
  return M.TREASURES[1]
end

function M.secretById(id)
  for _, s in ipairs(M.SECRETS) do
    if s.id == id then return s end
  end
  return nil
end

-- Milestone levels only; callers should check before asking (3,5 aren't
-- milestones and have no perk pair).
function M.perksFor(role, level)
  return M.PERKS[role] and M.PERKS[role][level]
end

local PERK_BY_ID = {}
for _, roleTbl in pairs(M.PERKS) do
  for _, pair in pairs(roleTbl) do
    for _, perk in ipairs(pair) do PERK_BY_ID[perk.id] = perk end
  end
end

function M.perkById(id)
  return PERK_BY_ID[id]
end

-- Ship combat shot tables.
M.SHOTS = {
  round = { id = 'round', label = 'ROUND SHOT', power = 7, powder = 999999, effect = 'plain' },
  chain = { id = 'chain', label = 'CHAIN SHOT', power = 4, powder = 3, effect = 'sails_down' },
  grape = { id = 'grape', label = 'GRAPE SHOT', power = 3, powder = 3, effect = 'guns_down' },
  fire  = { id = 'fire',  label = 'FIRE SHOT',  power = 5, powder = 2, effect = 'ablaze' },
}

M.SHIPCLASSES = {
  sloop = {
    id = 'sloop',
    name = 'SLOOP',
    hullBase = 24,
    hullScale = 8,
    guns = 2,
    sails = 3,
    weak = 'chain',
    ai = 'sloop',
    armor = 0,
  },
  brig = {
    id = 'brig',
    name = 'BRIG',
    hullBase = 28,
    hullScale = 8,
    guns = 2,
    sails = 2,
    weak = 'grape',
    ai = 'brig',
    armor = 0,
  },
  fireship = {
    id = 'fireship',
    name = 'FIRESHIP',
    hullBase = 44,
    hullScale = 8,
    guns = 0,
    sails = 2,
    weak = 'round',
    ai = 'fireship',
    armor = 0,
  },
  manowar = {
    id = 'manowar',
    name = 'MAN-O-WAR',
    hullBase = 18,
    hullScale = 4,
    guns = 2,
    sails = 1,
    weak = 'fire',
    ai = 'manowar',
    armor = 1,
  }
}

M.KING = {
  name = "KING'S GALLEON",
  hull = 120,
  repairs = 1,
  armor = 2,
  weak = 'fire',
  bigshotKegs = 3,
  volleyKegs = 2,
  ramDmg = 18,
  ramRecoil = 6,
  fleetHull = 180,
  fleetBigshotKegs = 4,
  kraken = {
    hull = 120,
    weak = 'chain',
    immuneAblaze = true,
  }
}

return M
