-- Base-breed accessory hook.
--
-- RLRM's RLMapBridge.applyPropertyOverrides only copies image / description /
-- canBeBought / textureIndexes / visualAnimalIndex when overriding subTypes that
-- already exist in RLRM's bundled xml/animals.xml (COW_HOLSTEIN, COW_SWISS_BROWN,
-- COW_HEREFORD, COW_ANGUS, COW_LIMOUSIN + their BULL_ counterparts). It silently
-- drops the accessory attributes (monitor, earTagLeft, earTagRight, marker,
-- bumId, noseRing), leaving those breeds pointing at RLRM's bundle paths which
-- don't resolve against this pack's customized i3d files. This hook re-reads the
-- same bridge XML and patches the missing accessory attributes back onto the
-- registered visuals AFTER RLRM finishes its normal override pass.
--
-- Extracted from the former VanillaEditionBridge.lua. The synth / Mechet /
-- Witcombe / vanilla-AnimalPackage bridging was removed; this is the only piece
-- of that system the base pack needs. It runs whether or not any companion mod
-- is present.

print("[CowBreedsRLRM/BaseBreedAccessories] module sourced")

local TAG = "[CowBreedsRLRM/BaseBreedAccessories]"
local function logf(fmt, ...) print(string.format("%s " .. fmt, TAG, ...)) end

-- Resolve RLRM's RLMapBridge object. FS25 mods have isolated globals: a bare
-- 'RLMapBridge = {}' in RLRM's main.lua is reachable from our mod only via
-- FS25_RealisticLivestockRM.RLMapBridge, not as a top-level global.
local function getRLMapBridge()
    if FS25_RealisticLivestockRM ~= nil and FS25_RealisticLivestockRM.RLMapBridge ~= nil then
        return FS25_RealisticLivestockRM.RLMapBridge
    end
    if rawget(_G, "RLMapBridge") ~= nil then
        return _G.RLMapBridge
    end
    return nil
end

local function installVisualAccessoryHook(RLMapBridge)
    if RLMapBridge.__cowBreedsAccessoryHooked then return end
    if RLMapBridge.applyPropertyOverrides == nil then
        logf("RLMapBridge.applyPropertyOverrides missing, accessory hook skipped")
        return
    end

    RLMapBridge.applyPropertyOverrides = Utils.appendedFunction(
        RLMapBridge.applyPropertyOverrides,
        function(animalSystem, xmlFile, bridgeName, mapModDir)
            local ok, err = pcall(function()
                local patched = 0
                for _, key in xmlFile:iterator("animals.animal") do
                    local rawTypeName = xmlFile:getString(key .. "#type")
                    if rawTypeName == nil then continue end
                    local typeName = rawTypeName:upper()
                    local animalType = animalSystem.nameToType and animalSystem.nameToType[typeName]
                    if animalType == nil or animalType.subTypes == nil then continue end

                    for _, subTypeKey in xmlFile:iterator(key .. ".subType") do
                        local rawSubTypeName = xmlFile:getString(subTypeKey .. "#subType")
                        if rawSubTypeName == nil then continue end
                        -- RLRM uppercases subType names on registration; match accordingly.
                        local needles = { rawSubTypeName, rawSubTypeName:upper() }
                        local subType = nil
                        for _, idx in ipairs(animalType.subTypes) do
                            local s = animalSystem.subTypes and animalSystem.subTypes[idx]
                            if s and s.name then
                                for _, n in ipairs(needles) do
                                    if s.name == n then subType = s; break end
                                end
                                if subType ~= nil then break end
                            end
                        end
                        if subType == nil or subType.visuals == nil then continue end

                        for _, visualKey in xmlFile:iterator(subTypeKey .. ".visuals.visual") do
                            local minAge = xmlFile:getInt(visualKey .. "#minAge")
                            if minAge == nil then continue end
                            local matched = nil
                            for _, v in ipairs(subType.visuals) do
                                if v.minAge == minAge then matched = v; break end
                            end
                            if matched == nil then continue end

                            for _, attr in ipairs({"monitor","earTagLeft","earTagRight","marker","bumId","noseRing"}) do
                                local val = xmlFile:getString(visualKey .. "#" .. attr, nil)
                                if val ~= nil then
                                    matched[attr] = val
                                    patched = patched + 1
                                end
                            end
                        end
                    end
                end
                if patched > 0 then
                    logf("accessory hook: patched %d accessory attribute(s) for bridge '%s'",
                         patched, tostring(bridgeName))
                end
            end)
            if not ok then
                logf("accessory hook failed for bridge '%s': %s", tostring(bridgeName), tostring(err))
            end
        end
    )
    RLMapBridge.__cowBreedsAccessoryHooked = true
    logf("installed applyPropertyOverrides accessory hook")
end

-- Install the accessory hook via FillTypeManager.loadMapData. RLRM appends its
-- own loadBridgeFillTypes (which calls scanAnimalPacks) to this same function;
-- by appending ours we run in the chain once RLMapBridge is defined. RLMapBridge
-- is resolved lazily inside the callback because it isn't available at
-- module-source time.
local function installHook()
    if FillTypeManager == nil or FillTypeManager.loadMapData == nil then
        logf("FillTypeManager.loadMapData missing, accessory installer skipped")
        return
    end
    if FillTypeManager.__cowBreedsAccessoryInstaller then return end

    FillTypeManager.loadMapData = Utils.appendedFunction(
        FillTypeManager.loadMapData,
        function(self)
            local RLMapBridge = getRLMapBridge()
            if RLMapBridge ~= nil then
                installVisualAccessoryHook(RLMapBridge)
            else
                logf("RLMapBridge unavailable at FillTypeManager.loadMapData; accessory hook not installed this run")
            end
        end
    )
    FillTypeManager.__cowBreedsAccessoryInstaller = true
    logf("installed FillTypeManager.loadMapData accessory installer")
end

local ok, err = pcall(installHook)
if not ok then
    logf("setup failed: %s", tostring(err))
end
