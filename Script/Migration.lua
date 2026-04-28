-- Save-game migration for the _pack breed rename.
--
-- Saves written before all 12 breeds were given a "_pack" suffix contain the
-- old subType strings (e.g. "COW_REDHOLSTEIN"). The registered subTypes are now
-- "COW_REDHOLSTEIN_pack", so a stock lookup returns nil and RLRM drops the
-- animal on load (see AnimalPersistence.loadFromXMLFile).
--
-- This hook intercepts AnimalSystem:getSubTypeIndexByName: if the requested
-- name is a known legacy ID, it retries with the renamed equivalent. The next
-- time the save is written, animal.subType already holds the resolved (new)
-- name, so the on-disk IDs are upgraded automatically and the alias path is
-- only walked once per legacy animal.

local SUBTYPE_ALIASES = {
    COW_REDHOLSTEIN     = "COW_REDHOLSTEIN_pack",
    BULL_REDHOLSTEIN    = "BULL_REDHOLSTEIN_pack",
    COW_AYRSHIRE        = "COW_AYRSHIRE_pack",
    BULL_AYRSHIRE       = "BULL_AYRSHIRE_pack",
    COW_JERSEY          = "COW_JERSEY_pack",
    BULL_JERSEY         = "BULL_JERSEY_pack",
    COW_GUERNSEY        = "COW_GUERNSEY_pack",
    BULL_GUERNSEY       = "BULL_GUERNSEY_pack",
    COW_CHAROLAIS       = "COW_CHAROLAIS_pack",
    BULL_CHAROLAIS      = "BULL_CHAROLAIS_pack",
    COW_REDANGUS        = "COW_REDANGUS_pack",
    BULL_REDANGUS       = "BULL_REDANGUS_pack",
    COW_SHORTHORN       = "COW_SHORTHORN_pack",
    BULL_SHORTHORN      = "BULL_SHORTHORN_pack",
    COW_IRISHMOILED     = "COW_IRISHMOILED_pack",
    BULL_IRISHMOILED    = "BULL_IRISHMOILED_pack",
    COW_BRITISHBLUE     = "COW_BRITISHBLUE_pack",
    BULL_BRITISHBLUE    = "BULL_BRITISHBLUE_pack",
    COW_BELTEDGALLOWAY  = "COW_BELTEDGALLOWAY_pack",
    BULL_BELTEDGALLOWAY = "BULL_BELTEDGALLOWAY_pack",
    COW_SIMMENTAL       = "COW_SIMMENTAL_pack",
    BULL_SIMMENTAL      = "BULL_SIMMENTAL_pack",
}

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
