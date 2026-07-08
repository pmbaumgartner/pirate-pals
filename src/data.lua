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
  -- Secret rescue pal (Grandma and the Pirates questline): only joins via the
  -- sea-5 shaky box, never the random recruit pool or newGamePlus carryover.
  grandma = { label = 'GRANDMA', hp = 13, atk = 4, move = 3, range = 1,
    spec = { name = 'NOODLE WHIP', desc = 'LASH FOES IN A ROW' },
    ship = { name = 'NOODLE PUDDING CATAPULT', desc = 'SPLAT A FOE, FEED THE CREW' } },
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

-- Outfits are bought with gold (price), unlocked at treasure-log milestones
-- (mile), or awarded by a secret/deed (neither field set -- see SECRETS'/
-- DEEDS' `reward` and the all-deeds check in game.earnDeed). Order matters:
-- index 1 is the default. tailor.lua's shopItems() only lists price/mile
-- entries, so reward-only hats never show up for sale.
M.OUTFITS = {
  { id = 'none',  name = 'NO HAT' },
  { id = 'bandR', name = 'RED BANDANA', price = 15 },
  { id = 'patch', name = 'EYEPATCH', price = 25 },
  { id = 'souwester', name = "SOU'WESTER", price = 35 },
  { id = 'straw', name = 'STRAW HAT', price = 40 },
  { id = 'tri',   name = 'TRICORN', price = 60 },
  { id = 'parrot', name = 'PARROT PAL', price = 120 },
  { id = 'bandB', name = 'BLUE BANDANA', mile = 3 },
  { id = 'cap',   name = "CAPTAIN'S HAT", mile = 6 },
  { id = 'crown', name = 'ROYAL CROWN', mile = 9 },
  { id = 'fish',  name = 'FISH HAT' },
  { id = 'shell', name = 'SHELL CAP' },
  { id = 'kraken', name = 'KRAKEN CAP' },
  { id = 'goldband', name = 'GOLD BANDANA' },
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
-- foundSecret(id) call at whatever hook triggers them. `reward` (an
-- OUTFITS id) is optional -- foundSecret unlocks it via game.unlockHat.
-- `slot` (a sprite name) is optional -- log.lua's curios shelf draws it in
-- the found slot instead of the generic checkmark.
M.SECRETS = {
  { id = 'hatbark', name = 'ALL HAIL!', hint = 'WEAR THE CROWN INTO BATTLE AND LISTEN' },
  { id = 'napbuddies', name = 'NAP BUDDIES', hint = 'PEEK AT THE CREW WHEN TWO PALS NAP' },
  { id = 'kingsniff', name = 'NICE HATS. STILL NO.', hint = "MATCHING BANDANAS ON THE KING'S SEA" },
  { id = 'cannonball', name = 'CANNONBALL RUN!', hint = 'THREE PERFECT SHOTS IN ONE SEA FIGHT' },
  { id = 'seashell', name = 'SEASHELL!', hint = 'TRY DIGGING RIGHT BESIDE AN ISLAND',
    reward = 'shell', slot = 'hat_shell' },
  { id = 'echobark', name = 'ECHO SQUAWK!', hint = 'TWO CAPTAINS SHOUT AT THE SAME MOMENT' },
  { id = 'bootsong', name = 'BOOT SONG', hint = 'STOP SAILING AND JUST LISTEN A WHILE' },
  { id = 'fishfriend', name = 'FISH FRIEND!', hint = "PARK ON AN ICY SEA AND DON'T MOVE",
    reward = 'fish', slot = 'hat_fish' },
  { id = 'luckycoin', name = 'LUCKY STREAK!', hint = 'OPEN EVERY CHEST BEFORE ANY BATTLE' },
  { id = 'tightrope', name = 'NOBODY WOBBLED!', hint = 'WIN THE PLANK FIGHT, NEVER STEP ON IT' },
  { id = 'sogybird', name = 'POLLY PLOPPED!', hint = 'GIVE THAT SNEAKY BIRD A GOOD SHOVE' },
  { id = 'wheee', name = 'DOUBLE SLIDE!', hint = 'SKID A LONG, LONG WAY ON THE ICE' },
  { id = 'birdsquad', name = 'BIRDS OF A FEATHER', hint = 'BRING A BIRD TO MEET A BIRD' },
  { id = 'hotfoot', name = 'HOT FOOT HARBOR!', hint = 'DANCE THROUGH THE FIRE SEA UNTOUCHED' },
  { id = 'kindtrader', name = 'KINDNESS OF STRANGERS', hint = 'VISIT A TRADER WITH EMPTY POCKETS' },
  { id = 'nestking', name = 'KING OF THE NEST', hint = 'HOLD THE HIGH SPOT ALL BATTLE' },
  { id = 'sorryisland', name = 'SORRY, ISLAND!', hint = 'SOME SHIPS JUST KEEP ON BUMPING' },
  { id = 'raftup', name = 'RAFT-UP!', hint = 'TWO SHIPS, ONE COZY SPOT' },
  { id = 'grandma', name = 'GRANDMA ABOARD!', hint = 'A SAD PARROT KNOWS WHERE THE BOX RATTLES',
    slot = 'slot_grandma' },
}

-- DEEDS: a visible achievements checklist (unlike SECRETS, the goal is shown
-- before it's earned). Counter deeds carry `key`/`goal` (progress reads from
-- meta.data.counts[key]); collection deeds carry `flagKeys`/`goal` (progress
-- is how many of those per-item flags are set). `hatrack` and `shipshape`
-- read other meta state directly (see game.deedProgress) and carry neither.
-- `src/game.lua`'s earnDeed/deedTick/deedFlag are the only writers of
-- meta.data.deeds/meta.data.counts. `reward` (an OUTFITS id) is optional --
-- earnDeed unlocks it via game.unlockHat.
M.DEEDS = {
  { id = 'firstpal', name = 'WELCOME ABOARD', goalText = 'RECRUIT YOUR FIRST PAL' },
  { id = 'firstbond', name = 'BEST MATES', goalText = 'FORGE YOUR FIRST BOND' },
  { id = 'xmarks', name = 'X MARKS THE SPOT', goalText = 'DIG UP THE BURIED MAP PRIZE' },
  { id = 'newvoyage', name = 'NEW VOYAGE, WHO DIS', goalText = 'START A NEW VOYAGE+' },
  { id = 'cannoncareer', name = 'CANNON CAREER', goalText = 'LAND 25 PERFECT HITS', key = 'perfectHits', goal = 25 },
  { id = 'shipwrecker', name = 'SHIPWRECKER', goalText = 'WIN 15 SHIP BATTLES', key = 'shipsSunk', goal = 15 },
  { id = 'boardingparty', name = 'BOARDING PARTY', goalText = 'WIN 15 DECK BATTLES', key = 'deckWins', goal = 15 },
  { id = 'goldhoarder', name = 'GOLD HOARDER', goalText = 'BANK 500 GOLD', key = 'goldBanked', goal = 500 },
  { id = 'chestchaser', name = 'CHEST CHASER', goalText = 'OPEN 30 CHESTS', key = 'chestsOpened', goal = 30 },
  { id = 'digdog', name = 'DIG DOG', goalText = 'DIG 20 TIMES', key = 'digs', goal = 20 },
  { id = 'seenseas', name = 'SEEN THE SEAS', goalText = 'SAIL ALL 4 SEA TYPES',
    flagKeys = { 'biome_calm', 'biome_icy', 'biome_foggy', 'biome_volcano' }, goal = 4 },
  { id = 'deckexplorer', name = 'DECK EXPLORER', goalText = 'FIGHT ON ALL 8 DECKS',
    flagKeys = { 'deck_classic', 'deck_gangplank', 'deck_lshape', 'deck_twinDecks',
      'deck_crowsnest', 'deck_bigDeck', 'deck_barricade', 'deck_tidepool' }, goal = 8 },
  { id = 'fleetspotter', name = 'FLEET SPOTTER', goalText = 'DEFEAT EVERY SHIP CLASS',
    flagKeys = { 'fleet_sloop', 'fleet_brig', 'fleet_fireship', 'fleet_manowar' }, goal = 4 },
  { id = 'hatrack', name = 'HAT RACK', goalText = 'OWN ALL 9 BASE HATS' },
  { id = 'fullpowder', name = 'FULL POWDER', goalText = 'FIRE EVERY SHOT TYPE',
    flagKeys = { 'shot_round', 'shot_chain', 'shot_grape', 'shot_fire' }, goal = 4 },
  { id = 'kingtoppler', name = 'KING TOPPLER', goalText = 'WIN A VOYAGE' },
  { id = 'krakentamer', name = 'KRAKEN TAMER', goalText = 'DEFEAT THE KRAKEN', reward = 'kraken' },
  { id = 'shipshape', name = 'SHIPSHAPE', goalText = 'MAX EVERY HOME PORT UPGRADE' },
}

-- All-deeds prize: GOLD BANDANA (an OUTFITS id), the 100% completion unlock.
-- Not a per-deed `reward` since it depends on every deed, not one -- checked
-- in game.earnDeed after each earn via M.checkAllDeeds().
M.ALL_DEEDS_REWARD = 'goldband'

-- Perk picks: two options per role at milestone levels 2/4/6, both
-- good, effects limited to flat stat deltas so game.statsOf stays a single
-- choke point. `icon` keys a small sprite drawn on the loot pick card.
local PERK_TEMPLATE = {
  [2] = { { suffix = 'Boots', name = 'BIG BOOTS', desc = '+1 MOVE', icon = 'boots', effects = { move = 1 } },
    { suffix = 'Belly', name = 'TOUGH BELLY', desc = '+4 HP', icon = 'belly', effects = { hp = 4 } } },
  [4] = { { suffix = 'Arms', name = 'LONG ARMS', desc = '+1 RANGE', icon = 'arms', effects = { range = 1 } },
    { suffix = 'Muscle', name = 'STRONG ARMS', desc = '+2 ATK', icon = 'muscle', effects = { atk = 2 } } },
  [6] = { { suffix = 'Legs', name = 'SEA LEGS', desc = '+1 MOVE +2 HP', icon = 'boots', effects = { move = 1, hp = 2 } },
    { suffix = 'Hide', name = 'IRON HIDE', desc = '+6 HP', icon = 'belly', effects = { hp = 6 } } },
}

local PERK_ROLE_PREFIXES = {
  { role = 'captain', prefix = 'cap' },
  { role = 'deckhand', prefix = 'dh' },
  { role = 'strongman', prefix = 'sm' },
  { role = 'sharpshooter', prefix = 'ss' },
  { role = 'medic', prefix = 'md' },
  { role = 'grandma', prefix = 'gm' },
}

M.PERKS = {}
for _, entry in ipairs(PERK_ROLE_PREFIXES) do
  local roleTbl = {}
  for level, pair in pairs(PERK_TEMPLATE) do
    local perks = {}
    for i, perk in ipairs(pair) do
      perks[i] = { id = entry.prefix .. perk.suffix, name = perk.name, desc = perk.desc,
        icon = perk.icon, effects = perk.effects }
    end
    roleTbl[level] = perks
  end
  M.PERKS[entry.role] = roleTbl
end

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
  grandma = {
    battleStart = { "SOUP'S ON!", 'BEHAVE NOW!' },
    perfect = { 'THAT WAS NICE!', 'GOOD FORM!' },
    levelUp = { 'STILL GOT IT!', 'LEVEL UP!' },
    bestMates = { 'SWEET CHILD!', 'BEST MATES!' },
    ko = { 'ZZZ NAP TIME!', 'NIGHT NIGHT!' },
    victory = { "WHO'S HUNGRY?", 'WE WON!' },
    special = { 'NOODLE WHIP!', 'WHAP WHAP!' },
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

function M.deedById(id)
  for _, d in ipairs(M.DEEDS) do
    if d.id == id then return d end
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
  round = { id = 'round', label = 'ROUND SHOT', power = 7, powder = 999999, effect = 'plain', icon = 'icon_fire' },
  chain = { id = 'chain', label = 'CHAIN SHOT', power = 4, powder = 3, effect = 'sails_down', icon = 'icon_chain' },
  grape = { id = 'grape', label = 'GRAPE SHOT', power = 3, powder = 3, effect = 'guns_down', icon = 'icon_grape' },
  fire  = { id = 'fire',  label = 'FIRE SHOT',  power = 5, powder = 2, effect = 'ablaze', icon = 'icon_flame' },
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
