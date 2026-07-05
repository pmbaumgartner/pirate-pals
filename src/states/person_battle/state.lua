-- Shared battle-state box for the person_battle module family (model, ai,
-- rewards, draw, and the main input FSM): a plain reference cell rather
-- than a module-local upvalue, since each concern now lives in its own
-- file but they all read/write the one active battle.
return { pb = nil }
