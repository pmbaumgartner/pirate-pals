# CLAUDE.md

`AGENTS.md` is a symlink to this file; keep this as the single agent-context source of truth.

## Commands

Run commands from the repo root.

- `make check` runs luacheck with `.luacheckrc`; keep it clean because CI treats warnings as failures.
- `make test` runs every `tests/*_test.lua`; prefer this over maintaining per-file test lists.
- `make smoke` runs `love . --smoke`; CI runs the same smoke path under xvfb.
- `love . --smoke --shots` also dumps per-state PNGs to the LÖVE save directory.
- `makelove` builds distributables from `makelove.toml` into `build/`.

## Dev Tooling

- `src/dev/*` is loaded only when a dev flag is present; do not add dev-only dependencies to the default require graph.
- Use `love . --seed=N --warp=<scenario>` to reproduce stateful bugs; scenario names live in `src/dev/scenarios.lua`.
- Use `love . --script=path.lua` for scripted repros; helpers are defined in `src/dev/script.lua`.
- Keep dev-flag and script failures on the `FAIL: <msg>` plus nonzero-exit path, not uncaught LÖVE errors, because the interactive error screen can hang headless runs.
- If sea hex layout constants in `src/states/sail.lua` change, update `src/dev/script.lua`'s `tapCell` math so scripted sea taps still hit cells.
- Under `--live`, `love.filesystem` merges the save dir into the root; keep lurker reloads limited to `main.lua` and first-party `src/` files.

## Code Conventions

- Do not edit vendored third-party code in `src/lib/`; `.luacheckrc` excludes it.
- Preserve the state require DAG: `main.lua` requires states for registration, and parameterized states are entered via exported `start(...)` functions.
- Keep `game.run` plain serializable data; `run.party` entries are references into `run.crew`, and save/load must preserve that identity.
- Add new content by updating `src/data.lua` plus the matching ASCII sprite block and `makeSprite` call in `src/sprites.lua`.
- Keep sea biome behavior as small flag-driven branches in `src/states/sail.lua` until there are at least five biomes.
- Timed visual juice is hand-rolled: advance a `.t = .t + dt` field per-effect in `update`, shaping it with `util.ease`/`util.lerp`; this fast-forwards naturally under `--speed` since it rides game `dt`.
- Never hardcode key names ('Z', 'N', ...) in UI strings; build prompts with `input.promptKey(ctx, action)` so they track the real per-player bindings (and pad button names).
- Scripted runs enforce a visual invariant: no text may draw outside the 320x180 canvas (`src/dev/bounds.lua` wraps `font.drawText`). Clamp intentional transients in game code; there is no allowlist.


## General
- Put plans in `.plans/`, move to `.plans/.archive` when they're completed.
- Bias towards visual tests via screenshots and integration/smoke tests, as they're the ground truth of how the game plays.
