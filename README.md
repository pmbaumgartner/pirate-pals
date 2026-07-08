# Pirate Pals

A pirate-themed adventure game built with LÖVE 11.x. Renders to a fixed
320x180 virtual canvas scaled to the window with integer snapping, so the
pixel art stays crisp at any window size.

## Running

Install [LÖVE](https://love2d.org) 11.4+ and run from the project root:

    love .

Or zip the contents (with `main.lua` at the archive root) as
`pirate-pals.love` and double-click it.

**Controls:** Arrows/WASD move, Z/Space/Enter confirm, X/Esc back,
C crew menu, T treasure log, M mute. Gamepads and touch (on-screen buttons
appear on first touch) are also supported.

The sea is a hex grid: left/right sail along the row, and up/down take the
diagonal on the side the ship is facing (the highlighted hexes with little
chevrons preview exactly where up/down will land). You can also tap or
click any water hex and the ship sails there by itself, stopping if an
enemy ship gets too close. Boarding battles stay on a square grid.

## Smoke test

    love . --smoke

Drives the game through every state for ~15 seconds — injecting d-pad
taps, a sea tap, and Z presses so hex sailing and the timing bar actually
run — then quits with `SMOKE OK` on success; any Lua error aborts the run.
Works headless under `xvfb-run` for CI. Add `--shots` to also dump
per-state PNGs into the LÖVE save directory for screenshot checks.

## Unit tests

The pure modules have plain-Lua tests (no LÖVE needed; any Lua 5.1+ or
`texlua` works). Run from the project root:

    lua tests/grid_test.lua
    lua tests/timing_test.lua

## Releases

CI uploads package artifacts for every run. To publish durable downloads
that do not expire with workflow artifacts, push a `v*` tag:

    git tag v0.1.0
    git push origin v0.1.0

The tagged CI run creates or updates the matching GitHub Release and
uploads the Windows, macOS, and Linux / Steam Deck builds as release assets.

## Structure

    main.lua                 LÖVE callbacks, virtual-canvas scaling, main loop
    conf.lua                 window config
    src/
      util.lua               clamp/lerp/irand/pick/ease
      grid.lua               square (4-dir) + odd-r hex grid helpers;
                             BFS flood/path over either neighborhood
      palette.lua            named colors
      font.lua               3x5 bitmap font ('@' = heart)
      sprites.lua            ASCII pixel art baked to Images at load
      audio.lua              chiptune SFX synthesized to SoundData
      input.lua              keyboard/gamepad/touch -> logical buttons
      data.lua               roles, outfits, treasures, names (design tables)
      game.lua               run state, sea generation, pirate/treasure logic
      engine.lua             state registry + FX (floaters, particles,
                             shake, banner, iris transition)
      timing.lua             the oscillating timing-bar minigame (attack + parry)
      ui.lua                 bars, outlines, cursor
      smoke.lua              smoke-test driver (only loaded with --smoke)
      states/                one module per game state; each registers
        title.lua            itself into engine.states on require
        sail.lua             hex-sea exploration (d-pad + tap-to-sail)
        ship_battle.lua      turn-based cannon duel (exports start(foe))
        person_battle.lua    boarding tactics grid (exports start(foe))
        loot.lua             reward reveal (exports start(parts, title))
        crew.lua             party management + dress-up
        tailor.lua           hat shop
        log.lua              treasure collection checklist

Flow between states goes through `engine.setState(name)` for simple screens
and through the exported `start(...)` constructors for parameterized ones
(sail -> ship_battle -> person_battle -> loot). Dependencies form a DAG:
states never require "backwards", so there are no require cycles.

## Extending

- **New content** (role, hat, treasure, enemy type): add a row to the
  matching table in `src/data.lua`; sprites go in `src/sprites.lua` as an
  ASCII block plus a `makeSprite` call in `build()`.
- **New game state**: create `src/states/foo.lua`, register a table with
  `update`/`draw` (and optional `enter`) into `engine.states`, require it
  from `main.lua`, and reach it with `engine.setState('foo')`.
- **New sound**: add an entry to `audio.sfx` composed from `audio.tone` /
  `audio.noiseBurst`.
- **Battle internals** are reachable for tooling/tests via
  `ship_battle.sb` and `person_battle.pb` (the live battle tables).
