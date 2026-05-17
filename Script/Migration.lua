-- Save-game migration for the breed-ID renames.
--
-- Two historical forms of the subType IDs exist in the wild:
--   1. Pre-pack:      "COW_REDHOLSTEIN"       (original v0.1 release)
--   2. Intermediate:  "COW_REDHOLSTEIN_pack"  (lowercase suffix, brief window)
-- The current registered form is "COW_REDHOLSTEIN_PACK" (uppercase suffix).
-- Uppercase was chosen so the breed string matches RLRM's MapBridge, which
-- uppercases breed names when populating BREED_TO_NAME / BREED_TO_MARKER_COLOUR.
--
-- This hook intercepts AnimalSystem:getSubTypeIndexByName: if the requested
-- name is a known legacy ID, it retries with the renamed equivalent. The next
-- time the save is written, animal.subType already holds the resolved (new)
-- name, so the on-disk IDs are upgraded automatically and the alias path is
-- only walked once per legacy animal.

local PACK_BREEDS = {
    "REDHOLSTEIN", "AYRSHIRE", "JERSEY", "GUERNSEY", "CHAROLAIS", "REDANGUS",
    "SHORTHORN", "IRISHMOILED", "BRITISHBLUE", "BELTEDGALLOWAY", "SIMMENTAL",
    "HEREFORD",
}

local SUBTYPE_ALIASES = {}
for _, b in ipairs(PACK_BREEDS) do
    local target_cow  = "COW_"  .. b .. "_PACK"
    local target_bull = "BULL_" .. b .. "_PACK"
    -- Pre-pack form (no suffix)
    SUBTYPE_ALIASES["COW_"  .. b] = target_cow
    SUBTYPE_ALIASES["BULL_" .. b] = target_bull
    -- Intermediate form (lowercase _pack)
    SUBTYPE_ALIASES["COW_"  .. b .. "_pack"] = target_cow
    SUBTYPE_ALIASES["BULL_" .. b .. "_pack"] = target_bull
end

local function migrateGetSubTypeIndexByName(self, superFunc, name)
    local idx = superFunc(self, name)
    if idx ~= nil then return idx end

    local mapped = SUBTYPE_ALIASES[name]
    if mapped ~= nil then
        local mappedIdx = superFunc(self, mapped)
        if mappedIdx ~= nil then
            print(string.format("[CowBreedsRLRM] migrated legacy subType '%s' -> '%s'", name, mapped))
            return mappedIdx
        end
    end

    return nil
end

if AnimalSystem ~= nil and AnimalSystem.getSubTypeIndexByName ~= nil then
    AnimalSystem.getSubTypeIndexByName = Utils.overwrittenFunction(
        AnimalSystem.getSubTypeIndexByName,
        migrateGetSubTypeIndexByName
    )
end
