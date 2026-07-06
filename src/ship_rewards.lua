local data = require 'src.data'
local util = require 'src.util'

local M = {}

local function ensureProgressTables(run)
  run.salvage = run.salvage or { timber = 0, cloth = 0, iron = 0 }
  run.salvage.timber = run.salvage.timber or 0
  run.salvage.cloth = run.salvage.cloth or 0
  run.salvage.iron = run.salvage.iron or 0
  run.blueprints = run.blueprints or {}
  run.blueprintDrops = run.blueprintDrops or { sea2 = false, sea5 = false }
  run.bossFlotsam = run.bossFlotsam or {}
end

function M.awardFlotsam(run, foeRef, isBoss)
  ensureProgressTables(run)
  if isBoss then
    local seaLv = run.sea and run.sea.lv or (foeRef and foeRef.lv) or 1
    run.bossFlotsam[seaLv] = run.bossFlotsam[seaLv] or 0
    if run.bossFlotsam[seaLv] >= 3 then return false end
    run.bossFlotsam[seaLv] = run.bossFlotsam[seaLv] + 1
    run.salvage.timber = run.salvage.timber + 1
    return true
  end

  if foeRef and not foeRef.flotsamPaid then
    foeRef.flotsamPaid = true
    run.salvage.timber = run.salvage.timber + 1
    return true
  end
  return false
end

local function materialPool(class)
  if class == 'sloop' then
    return { 'cloth', 'cloth', 'timber', 'iron' }
  elseif class == 'manowar' then
    return { 'iron', 'iron', 'timber', 'cloth' }
  elseif class == 'brig' then
    return { 'timber', 'cloth', 'iron' }
  elseif class == 'fireship' then
    return { 'timber', 'timber', 'cloth', 'iron' }
  end
  return { 'timber', 'cloth', 'iron' }
end

local function blueprintDesc(shotId)
  if shotId == 'chain' then return 'SAILS -1 STAGE' end
  if shotId == 'grape' then return 'GUNS -1 STAGE' end
  if shotId == 'fire' then return 'ABLAZE STATUS' end
  return ''
end

local function addBlueprintOption(options, run, shotId)
  if run.blueprints[shotId] then return end
  options[#options + 1] = {
    id = shotId,
    name = data.SHOTS[shotId].label,
    desc = blueprintDesc(shotId),
  }
end

function M.victoryParts(run, foeRef, lv)
  if not (foeRef and foeRef.class) then return {} end
  ensureProgressTables(run)

  local parts = {}
  local numPieces = util.irand(1, 3)
  local material = util.pick(materialPool(foeRef.class))
  run.salvage[material] = run.salvage[material] + numPieces
  parts[#parts + 1] = { type = 'salvage', material = material, n = numPieces }

  if lv == 2 and not run.blueprintDrops.sea2 then
    run.blueprintDrops.sea2 = true
    local options = {}
    addBlueprintOption(options, run, 'chain')
    addBlueprintOption(options, run, 'grape')
    if #options > 0 then
      parts[#parts + 1] = { type = 'blueprint_choice', options = options, choice = 1 }
    end
  elseif lv == 5 and not run.blueprintDrops.sea5 then
    run.blueprintDrops.sea5 = true
    local options = {}
    for _, shotId in ipairs({ 'chain', 'grape', 'fire' }) do
      addBlueprintOption(options, run, shotId)
    end
    if #options > 1 then
      parts[#parts + 1] = { type = 'blueprint_choice', options = options, choice = 1 }
    elseif #options == 1 then
      local opt = options[1]
      run.blueprints[opt.id] = true
      parts[#parts + 1] = { type = 'blueprint_single', id = opt.id }
    end
  end

  return parts
end

return M
