-- Detect FS25_AnimalPackage_vanillaEdition at load time and surface its cow
-- breeds as additional RLRM bridge entries. We synthesize a small "virtual
-- bridge pack" under <packModDir>/_synth/ at regenerate time (animals.xml +
-- fillTypes.xml + translations + a combined husbandry config that joins this
-- pack's 21 animal entries with vanilla AnimalPackage's first 8). At runtime
-- we hook RLMapBridge.scanAnimalPacks via a chain through FillTypeManager.
-- loadMapData and manually push our bridge entry into RLMapBridge.activeBridges
-- — RLRM then processes it through its normal flow, which applies our config
-- override and registers our _vanilla subtypes alongside its own.

print("[CowBreedsRLRM/VanillaBridge] module sourced (v0.5.6.0)")

-- Kill switch: if this file exists, the bridge does nothing.
-- Path: <userProfile>/modSettings/CowBreedsRLRM_VanillaBridge.disabled
do
    local disabledPath = getUserProfileAppPath() .. "modSettings/CowBreedsRLRM_VanillaBridge.disabled"
    if fileExists(disabledPath) then
        print("[CowBreedsRLRM/VanillaBridge] disabled by " .. disabledPath .. ", skipping")
        return
    end
end

local TAG          = "[CowBreedsRLRM/VanillaBridge]"
local VANILLA_MOD  = "FS25_AnimalPackage_vanillaEdition"
local SYNTH_NAME   = "FS25_CowBreedsRLRM_VanillaBridge"
local SYNTH_TITLE  = "Cow Breeds - Vanilla Bridge"
local SYNTH_VERSION = "0.5.6.0"
local SUFFIX       = "_vanilla"

-- Whitelisted breeds. Engine has a confirmed hard 32-entry-per-husbandry-XML
-- limit. With pack now at 18 entries (after buffalo removal) and the bridge
-- emitting 12 vanilla entries (dairy + beef, GS03 skipped), total = 30 → fits.
-- Dairy 3 breeds share vanilla visualAnimalIndex 1..8; Limousin + Angus share
-- 9..16. Highland and Water Buffalo still excluded (would need 17+).
local BREED_GROUPS = {
    { breed = "HOLSTEIN",    female = "COW_HOLSTEIN",    male = "BULL_HOLSTEIN",    display = "Holstein (Vanilla)",     dairy = true,  milkFillType = "MILK" },
    { breed = "REDHOLSTEIN", female = "COW_REDHOLSTEIN", male = "BULL_REDHOLSTEIN", display = "Red Holstein (Vanilla)", dairy = true,  milkFillType = "MILK" },
    { breed = "BROWNSWISS",  female = "COW_BROWNSWISS",  male = "BULL_BROWNSWISS",  display = "Brown Swiss (Vanilla)",  dairy = true,  milkFillType = "MILK" },
    { breed = "LIMOUSIN",    female = "COW_LIMOUSIN",    male = "BULL_LIMOUSIN",    display = "Limousin (Vanilla)",     dairy = false },
    { breed = "ANGUS",       female = "COW_ANGUS",       male = "BULL_ANGUS",       display = "Angus (Vanilla)",        dairy = false },
}

local function logf(fmt, ...) print(string.format("%s " .. fmt, TAG, ...)) end

local function ensureSlash(p)
    if p == nil or p == "" then return p end
    local last = p:sub(-1)
    if last == "/" or last == "\\" then return p end
    return p .. "/"
end

-- Collapse `..` segments and normalize separators in a path.
local function normalizePath(path)
    if path == nil then return path end
    path = path:gsub("\\", "/")
    local isAbs = path:sub(1, 1) == "/" or path:match("^[A-Za-z]:/") ~= nil
    local prefix = ""
    if path:match("^[A-Za-z]:/") then
        prefix = path:sub(1, 3) -- "C:/"
        path = path:sub(4)
    elseif isAbs then
        prefix = "/"
        path = path:sub(2)
    end
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." and #parts > 0 and parts[#parts] ~= ".." then
            table.remove(parts)
        elseif part ~= "." then
            table.insert(parts, part)
        end
    end
    return prefix .. table.concat(parts, "/")
end

-- Resolve an asset path that lives inside an XML at <baseDir>/something.xml.
-- $dataS/-prefixed and already-absolute paths are returned untouched. Relative
-- paths are joined against baseDir and normalized so any leading '..' segments
-- collapse correctly.
local function resolveAsset(rawPath, baseDir)
    if rawPath == nil or rawPath == "" then return rawPath end
    if rawPath:sub(1, 1) == "$" then return rawPath end
    if rawPath:match("^[A-Za-z]:[/\\]") or rawPath:sub(1, 1) == "/" or rawPath:sub(1, 1) == "\\" then
        return rawPath
    end
    return normalizePath(ensureSlash(baseDir) .. rawPath)
end

-- Split a path into segments. Drive letter (F:) becomes its own first segment.
local function splitPath(p)
    if p == nil then return {} end
    p = p:gsub("\\", "/")
    local parts = {}
    for part in p:gmatch("[^/]+") do table.insert(parts, part) end
    return parts
end

-- Compute the relative path from `fromDirAbs` (an absolute directory) to
-- `targetAbs` (an absolute file or directory). Returns nil if they're on
-- different drives — caller should fall back to an absolute path.
local function relativeFromTo(fromDirAbs, targetAbs)
    local fromParts = splitPath(fromDirAbs)
    local targetParts = splitPath(targetAbs)
    if fromParts[1] == nil or targetParts[1] == nil then return nil end
    if fromParts[1]:lower() ~= targetParts[1]:lower() then return nil end
    local common = 0
    while common < #fromParts and common < #targetParts
          and fromParts[common + 1]:lower() == targetParts[common + 1]:lower() do
        common = common + 1
    end
    local rel = {}
    for _ = common + 1, #fromParts do table.insert(rel, "..") end
    for i = common + 1, #targetParts do table.insert(rel, targetParts[i]) end
    return table.concat(rel, "/")
end

-- Resolve a path from a source XML to a relative path that works when the
-- combined husbandry XML lives at synthHusbDir. xmlBaseDir is the directory of
-- the source XML the rawPath came from (so the rawPath's relative semantics
-- are preserved). Returns the path string to emit.
local function resolveAssetRelative(rawPath, xmlBaseDir, synthHusbDir)
    if rawPath == nil or rawPath == "" then return rawPath end
    if rawPath:sub(1, 1) == "$" then return rawPath end
    local abs = resolveAsset(rawPath, xmlBaseDir)
    -- abs is now an absolute path (or unchanged if already absolute)
    if abs:sub(1, 1) == "$" then return abs end
    local rel = relativeFromTo(synthHusbDir, abs)
    if rel == nil then return abs end -- different drive: fall back, will likely fail
    return rel
end

-- Vanilla AnimalPackage's `filenamePosed` paths are relative to the MOD ROOT
-- (e.g. "animals/domesticated/cattle/dairy/static/FM01.i3d"), unlike its
-- `filename` paths which are relative to the husbandry XML's directory
-- (e.g. "dairy/Cattle_F_GS01_Dairy.i3d"). To resolve filenamePosed correctly
-- we need to use the mod-root dir as the baseDir.
local function resolveModRootRelative(rawPath, modRootDir, synthHusbDir)
    if rawPath == nil or rawPath == "" then return rawPath end
    if rawPath:sub(1, 1) == "$" then return rawPath end
    if rawPath:match("^[A-Za-z]:[/\\]") or rawPath:sub(1, 1) == "/" or rawPath:sub(1, 1) == "\\" then
        local rel = relativeFromTo(synthHusbDir, normalizePath(rawPath))
        return rel or rawPath
    end
    local abs = normalizePath(ensureSlash(modRootDir) .. rawPath)
    local rel = relativeFromTo(synthHusbDir, abs)
    return rel or abs
end

local function xmlEscape(s)
    if s == nil then return "" end
    s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\"", "&quot;")
    return s
end

local function writeFile(path, content)
    local f, err = io.open(path, "w")
    if f == nil then error("cannot write " .. path .. ": " .. tostring(err), 0) end
    f:write(content)
    f:close()
end

-- (No readFile helper: FS25's sandboxed io.open only permits write mode.)

-- Deterministic hash → HSL(hue, 0.7, 0.55) → RGB. Stable per breed name across saves.
local function markerColourFor(name)
    local h = 0
    for i = 1, #name do h = (h * 31 + name:byte(i)) % 65536 end
    local hue = (h % 360) / 360
    local s, l = 0.7, 0.55
    local function f(p, q, t)
        if t < 0 then t = t + 1 end
        if t > 1 then t = t - 1 end
        if t < 1/6 then return p + (q - p) * 6 * t end
        if t < 1/2 then return q end
        if t < 2/3 then return p + (q - p) * (2/3 - t) * 6 end
        return p
    end
    local q = (l < 0.5) and l * (1 + s) or l + s - l * s
    local p = 2 * l - q
    return f(p, q, hue + 1/3), f(p, q, hue), f(p, q, hue - 1/3)
end

-- Emit a list of <key ageMonth="..." value="..."/> children. Returns concatenated lines.
local function emitKeyedList(xml, basePath, indent)
    local lines = {}
    local i = 0
    while true do
        local kpath = string.format("%s.key(%d)", basePath, i)
        local age = getXMLInt(xml, kpath .. "#ageMonth")
        if age == nil then break end
        local val = getXMLString(xml, kpath .. "#value") or "0"
        table.insert(lines, string.format('%s<key ageMonth="%d" value="%s"/>', indent, age, val))
        i = i + 1
    end
    return table.concat(lines, "\n")
end

-- Emit a parent element wrapping a keyed list (e.g. <buyPrice>...</buyPrice>).
local function emitKeyedBlock(xml, basePath, tagName, indent, extraAttrs)
    local i = 0
    local hasAny = (getXMLInt(xml, string.format("%s.key(0)#ageMonth", basePath)) ~= nil)
    if not hasAny then return "" end
    local keys = emitKeyedList(xml, basePath, indent .. "\t")
    return string.format("%s<%s%s>\n%s\n%s</%s>",
        indent, tagName, extraAttrs or "", keys, indent, tagName)
end

-- Find the index N of the subType element in animals.animal(0).subType(N) matching subTypeName.
local function findSubTypeIndex(xml, subTypeName)
    local i = 0
    while true do
        local key = string.format("animals.animal(0).subType(%d)#subType", i)
        local v = getXMLString(xml, key)
        if v == nil then return nil end
        if v == subTypeName then return i end
        i = i + 1
    end
end

-- Build one synthesized <subType> block from the vanilla XML.
-- origToOutput maps vanilla-source visualAnimalIndex → output visualAnimalIndex
-- in the synth husbandry XML. Includes GS03→GS04 redirects (vai 3→GS04slot,
-- 7→bullGS04slot, etc.) so animals at the GS03 age range render the GS04 model.
local function synthSubType(xml, vanillaModDir, group, isMale, origToOutput)
    origToOutput = origToOutput or {}
    local sourceName = isMale and group.male or group.female
    local idx = findSubTypeIndex(xml, sourceName)
    if idx == nil then
        logf("vanilla subType '%s' not found, skipping", sourceName)
        return nil
    end
    local base = string.format("animals.animal(0).subType(%d)", idx)

    local newName     = sourceName .. SUFFIX
    local newFillType = newName
    local newBreed    = group.breed .. SUFFIX
    local gender      = isMale and "male" or "female"

    -- Auto-default weights: dairy ~700kg target; beef ~850kg; bulls run heavier.
    local target = group.dairy and 700.0 or 850.0
    if isMale then target = target * 1.15 end
    local minW = math.floor(target * 0.06)
    local maxW = math.floor(target * 1.55)

    local lines = {}
    local push = function(s) table.insert(lines, s) end

    push(string.format(
        '\t\t<subType subType="%s" fillTypeName="%s" gender="%s" minWeight="%.1f" targetWeight="%.1f" maxWeight="%.1f" breed="%s">',
        newName, newFillType, gender, minW, target, maxW, newBreed
    ))

    -- Visuals
    push('\t\t\t<visuals>')
    local v = 0
    while true do
        local vbase = string.format("%s.visuals.visual(%d)", base, v)
        local minAge = getXMLInt(xml, vbase .. "#minAge")
        if minAge == nil then break end
        local rawVai = getXMLInt(xml, vbase .. "#visualAnimalIndex") or 1
        local vai = origToOutput[rawVai]
        if vai == nil then
            -- vanilla source idx not in our emitted set (e.g. above
            -- VANILLA_HUSBANDRY_LIMIT). Skip this visual rather than emit a
            -- dangling visualAnimalIndex. Luau `continue` is used throughout
            -- RLRM so this is safe in this engine.
            v = v + 1
            continue
        end
        local img = getXMLString(xml, vbase .. "#image") or ""
        local canBuy = getXMLBool(xml, vbase .. "#canBeBought")
        if canBuy == nil then canBuy = true end
        -- Emit image as a relative-with-`..` path from synth animals.xml's
        -- directory to the vanilla mod's icon — same resolution mechanism that
        -- works for i3d files in the husbandry XML. Synth animals.xml lives at
        -- <packMod>/_synth/animals.xml, so 2 ups reach <modsDir>/, then into
        -- the vanilla mod. $dataS/... paths stay as-is.
        local imgFinal = img:sub(1, 1) == "$"
            and img
            or ("../../" .. VANILLA_MOD .. "/" .. img)
        local nameAttr = getXMLString(xml, vbase .. "#name")
        local nameStr = (nameAttr ~= nil) and string.format(' name="%s"', xmlEscape(nameAttr)) or ""
        push(string.format(
            '\t\t\t\t<visual minAge="%d" visualAnimalIndex="%d"%s image="%s" canBeBought="%s">',
            minAge, vai, nameStr, xmlEscape(imgFinal), canBuy and "true" or "false"
        ))
        local d = 0
        while true do
            local descPath = vbase .. string.format(".description(%d)", d)
            local descTxt = getXMLString(xml, descPath)
            if descTxt == nil then break end
            push(string.format('\t\t\t\t\t<description>%s</description>', xmlEscape(descTxt)))
            d = d + 1
        end
        push('\t\t\t\t\t<textureIndexes>')
        local t = 0
        while true do
            local tval = getXMLInt(xml, vbase .. string.format(".textureIndexes.value(%d)", t))
            if tval == nil then break end
            push(string.format('\t\t\t\t\t\t<value>%d</value>', tval))
            t = t + 1
        end
        push('\t\t\t\t\t</textureIndexes>')
        push('\t\t\t\t</visual>')
        v = v + 1
    end
    push('\t\t\t</visuals>')

    -- Reproduction
    local repMinAge = getXMLInt(xml, base .. ".reproduction#minAgeMonth")
    if repMinAge ~= nil then
        local repDur = getXMLInt(xml, base .. ".reproduction#durationMonth")
        local repHF  = getXMLString(xml, base .. ".reproduction#minHealthFactor")
        local repSup = getXMLBool(xml, base .. ".reproduction#supported")
        local attrs = string.format(' minAgeMonth="%d"', repMinAge)
        if repDur ~= nil then attrs = attrs .. string.format(' durationMonth="%d"', repDur) end
        if repHF  ~= nil then attrs = attrs .. string.format(' minHealthFactor="%s"', repHF) end
        if repSup == false then attrs = attrs .. ' supported="false"' end
        push(string.format('\t\t\t<reproduction%s/>', attrs))
    end

    -- Buy / sell / transport prices
    local b = emitKeyedBlock(xml, base .. ".buyPrice",       "buyPrice",       "\t\t\t")
    if b ~= "" then push(b) end
    local s = emitKeyedBlock(xml, base .. ".sellPrice",      "sellPrice",      "\t\t\t")
    if s ~= "" then push(s) end
    local tr = emitKeyedBlock(xml, base .. ".transportPrice","transportPrice", "\t\t\t")
    if tr ~= "" then push(tr) end

    -- Input (straw / water / food)
    local hasInput = (getXMLInt(xml, base .. ".input.straw.key(0)#ageMonth") ~= nil)
                  or (getXMLInt(xml, base .. ".input.water.key(0)#ageMonth") ~= nil)
                  or (getXMLInt(xml, base .. ".input.food.key(0)#ageMonth") ~= nil)
    if hasInput then
        push('\t\t\t<input>')
        for _, child in ipairs({ "straw", "water", "food" }) do
            local block = emitKeyedBlock(xml, base .. ".input." .. child, child, "\t\t\t\t")
            if block ~= "" then push(block) end
        end
        push('\t\t\t</input>')
    end

    -- Output (milk / manure / liquidManure)
    local hasMilk     = (getXMLInt(xml, base .. ".output.milk.key(0)#ageMonth") ~= nil)
    local hasManure   = (getXMLInt(xml, base .. ".output.manure.key(0)#ageMonth") ~= nil)
    local hasLiq      = (getXMLInt(xml, base .. ".output.liquidManure.key(0)#ageMonth") ~= nil)
    if hasMilk or hasManure or hasLiq then
        push('\t\t\t<output>')
        if hasMilk then
            local milkType = getXMLString(xml, base .. ".output.milk#fillType") or group.milkFillType or "MILK"
            local block = emitKeyedBlock(xml, base .. ".output.milk", "milk", "\t\t\t\t",
                string.format(' fillType="%s"', milkType))
            if block ~= "" then push(block) end
        end
        if hasManure then
            local block = emitKeyedBlock(xml, base .. ".output.manure", "manure", "\t\t\t\t")
            if block ~= "" then push(block) end
        end
        if hasLiq then
            local block = emitKeyedBlock(xml, base .. ".output.liquidManure", "liquidManure", "\t\t\t\t")
            if block ~= "" then push(block) end
        end
        push('\t\t\t</output>')
    end

    push('\t\t</subType>')
    return table.concat(lines, "\n")
end

local function buildAnimalsXml(xml, vanillaModDir, origToOutput)
    origToOutput = origToOutput or {}
    local lines = {}
    table.insert(lines, '<?xml version="1.0" encoding="utf-8" standalone="no" ?>')
    table.insert(lines, '<animals>')
    -- Override the cow husbandry config with our combined file (pack's original
    -- visualAnimalIndex values preserved; vanilla entries placed in free slots
    -- inside {1..32}, computed by allocateVanillaSlots). RLMapBridge applies
    -- overrides in pack alphabetical order; the synth pack ('Cow Breeds - Vanilla
    -- Bridge') runs AFTER the main _pack ('Cow Breeds') so our override wins.
    -- This is the ONLY way the engine's C++ side learns about the new model
    -- entries — Lua-level animals[] insertion doesn't propagate.
    table.insert(lines, '\t<configOverrides>')
    table.insert(lines, '\t\t<override type="COW" configFilename="models/cow/animals.xml"/>')
    table.insert(lines, '\t</configOverrides>')

    table.insert(lines, '\t<breeds>')
    for _, g in ipairs(BREED_GROUPS) do
        local r, gn, b = markerColourFor(g.breed)
        local bn = g.breed .. SUFFIX
        local key = "$l10n_breed_" .. g.breed:lower() .. "_vanilla"
        table.insert(lines, string.format(
            '\t\t<breed name="%s" displayName="%s" markerColour="%.3f %.3f %.3f"/>',
            bn, key, r, gn, b
        ))
    end
    table.insert(lines, '\t</breeds>')

    table.insert(lines, '\t<animal type="COW">')
    for _, g in ipairs(BREED_GROUPS) do
        for _, isMale in ipairs({ false, true }) do
            local block = synthSubType(xml, vanillaModDir, g, isMale, origToOutput)
            if block ~= nil then table.insert(lines, block) end
        end
    end
    table.insert(lines, '\t</animal>')
    table.insert(lines, '</animals>')
    table.insert(lines, '')
    return table.concat(lines, "\n")
end

-- Synthesize fillTypes.xml from vanilla BRC_COW_*/BRC_BULL_* entries.
local function buildFillTypesXml(xml)
    local lines = {}
    table.insert(lines, '<?xml version="1.0" encoding="utf-8" standalone="no" ?>')
    table.insert(lines, '<map xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="$data/shared/xml/schema/fillTypes.xsd">')
    table.insert(lines, '\t<fillTypes>')

    -- Build a quick lookup of vanilla fillType entries by name.
    local idx = 0
    local byName = {}
    while true do
        local nm = getXMLString(xml, string.format("map.fillTypes.fillType(%d)#name", idx))
        if nm == nil then break end
        byName[nm] = idx
        idx = idx + 1
    end

    for _, g in ipairs(BREED_GROUPS) do
        for _, isMale in ipairs({ false, true }) do
            local subTypeName = isMale and g.male or g.female
            local newFt = subTypeName .. SUFFIX
            local vanillaFt = "BRC_" .. subTypeName -- BRC_COW_HOLSTEIN, BRC_BULL_HOLSTEIN
            local i = byName[vanillaFt]
            if i ~= nil then
                local p = string.format("map.fillTypes.fillType(%d)", i)
                local mass  = getXMLString(xml, p .. ".physics#massPerLiter")     or (isMale and "750.0" or "600.0")
                local angle = getXMLString(xml, p .. ".physics#maxPhysicalSurfaceAngle") or "0"
                local price = getXMLString(xml, p .. ".economy#pricePerLiter")   or "4000"
                local img   = getXMLString(xml, p .. ".image#hud")               or "$dataS/menu/hud/fillTypes/hud_fill_cow.png"
                local titleKey = string.format("$l10n_fillType_%s_vanilla", subTypeName:lower())
                table.insert(lines, string.format(
                    '\t\t<fillType name="%s" title="%s" showOnPriceTable="false">',
                    newFt, titleKey
                ))
                table.insert(lines, string.format(
                    '\t\t\t<physics massPerLiter="%s" maxPhysicalSurfaceAngle="%s"/>', mass, angle
                ))
                table.insert(lines, string.format('\t\t\t<economy pricePerLiter="%s"/>', price))
                table.insert(lines, string.format('\t\t\t<image hud="%s"/>', xmlEscape(img)))
                table.insert(lines, '\t\t</fillType>')
            else
                logf("vanilla fillType '%s' missing, skipping", vanillaFt)
            end
        end
    end

    table.insert(lines, '\t</fillTypes>')
    table.insert(lines, '</map>')
    table.insert(lines, '')
    return table.concat(lines, "\n")
end

-- Count <animal> entries in a husbandry XML.
local function countHusbandryEntries(xml)
    local n = 0
    while getXMLString(xml, string.format("animalHusbandry.animals.animal(%d)#radius", n)) ~= nil do
        n = n + 1
    end
    return n
end

-- Emit one <animal> block at the given source index `srcIdx` (0-based) from
-- husbandry `xml`, into `lines`, with `outputVai` as its visualAnimalIndex.
-- Asset paths are emitted as relative paths from synthHusbDir so the engine's
-- path resolver can navigate via `..` segments to the source mod (which works
-- across mod boundaries on the same drive). assetBaseDir is the source XML's
-- directory (used for resolving filename/animation/locomotion); modRootDir is
-- the source mod's root (used for filenamePosed which uses a different relative
-- convention in some mods).
local function emitAnimalEntry(lines, xml, srcIdx, outputVai, assetBaseDir, modRootDir, synthHusbDir)
    local base = string.format("animalHusbandry.animals.animal(%d)", srcIdx)
    local radius = getXMLString(xml, base .. "#radius")
    if radius == nil then return false end

    local function attr(name)
        local v = getXMLString(xml, base .. "#" .. name)
        if v == nil then return "" end
        return string.format(' %s="%s"', name, xmlEscape(v))
    end
    local extra = ""
    for _, a in ipairs({
        "name","handleThreats","threatAwarenessRadius","slowingDistance",
        "allowMilkingPlace","headOffset",
        "canEat","canDrink","canSleep","canEatDuringNight","canBeCleaned",
        "interessDistance"
    }) do extra = extra .. attr(a) end
    table.insert(lines, string.format(
        '\t\t<animal visualAnimalIndex="%d" radius="%s"%s>', outputVai, radius, extra
    ))

    do
        local attrs = ""
        for _, k in ipairs({
            "idleMin","idleMax","sleepMin","sleepMax","restMin","restMax",
            "grazeMin","grazeMax","chewMin","chewMax","eatMin","eatMax",
            "wanderMin","wanderMax"
        }) do
            local v = getXMLString(xml, base .. ".statesTimers#" .. k)
            if v ~= nil then attrs = attrs .. string.format(' %s="%s"', k, v) end
        end
        if attrs ~= "" then
            table.insert(lines, string.format('\t\t\t<statesTimers%s/>', attrs))
        end
    end

    local filename       = resolveAssetRelative(getXMLString(xml, base .. ".assets#filename"),      assetBaseDir, synthHusbDir)
    local filenamePosed  = resolveModRootRelative(getXMLString(xml, base .. ".assets#filenamePosed"), modRootDir, synthHusbDir)
    local animation      = resolveAssetRelative(getXMLString(xml, base .. ".assets#animation"),     assetBaseDir, synthHusbDir)
    local skeletonIndex  = getXMLString(xml, base .. ".assets#skeletonIndex")
    local meshIndex      = getXMLString(xml, base .. ".assets#meshIndex")
    local proxyIndex     = getXMLString(xml, base .. ".assets#proxyIndex")
    local shaderIndex    = getXMLString(xml, base .. ".assets#shaderIndex")
    local headIndex      = getXMLString(xml, base .. ".assets#headIndex")
    local assetAttrs = ""
    if filename      ~= nil then assetAttrs = assetAttrs .. string.format(' filename="%s"',      xmlEscape(filename)) end
    if filenamePosed ~= nil then assetAttrs = assetAttrs .. string.format(' filenamePosed="%s"', xmlEscape(filenamePosed)) end
    if animation     ~= nil then assetAttrs = assetAttrs .. string.format(' animation="%s"',     xmlEscape(animation)) end
    if skeletonIndex ~= nil then assetAttrs = assetAttrs .. string.format(' skeletonIndex="%s"', skeletonIndex) end
    if meshIndex     ~= nil then assetAttrs = assetAttrs .. string.format(' meshIndex="%s"',     meshIndex) end
    if proxyIndex    ~= nil then assetAttrs = assetAttrs .. string.format(' proxyIndex="%s"',    proxyIndex) end
    if shaderIndex   ~= nil then assetAttrs = assetAttrs .. string.format(' shaderIndex="%s"',   shaderIndex) end
    if headIndex     ~= nil then assetAttrs = assetAttrs .. string.format(' headIndex="%s"',     xmlEscape(headIndex)) end
    table.insert(lines, string.format('\t\t\t<assets%s>', assetAttrs))

    local t = 0
    while true do
        local tbase = base .. string.format(".assets.texture(%d)", t)
        local multi = getXMLString(xml, tbase .. "#multi")
        if multi == nil then break end
        local tu = getXMLString(xml, tbase .. "#tileUIndex") or "0"
        local tv = getXMLString(xml, tbase .. "#tileVIndex") or "0"
        local nu = getXMLString(xml, tbase .. "#numTilesU") or "1"
        local nv = getXMLString(xml, tbase .. "#numTilesV") or "1"
        local mv = getXMLString(xml, tbase .. "#mirrorV")   or "false"
        table.insert(lines, string.format(
            '\t\t\t\t<texture multi="%s" tileUIndex="%s" tileVIndex="%s" numTilesU="%s" numTilesV="%s" mirrorV="%s"/>',
            multi, tu, tv, nu, nv, mv
        ))
        t = t + 1
    end
    -- Pass through any <node ... visibility="..."/> children inside <assets>
    local nIdx = 0
    while true do
        local nbase = base .. string.format(".assets.node(%d)", nIdx)
        local nIndex = getXMLString(xml, nbase .. "#index")
        if nIndex == nil then break end
        local nVis = getXMLString(xml, nbase .. "#visibility")
        if nVis ~= nil then
            table.insert(lines, string.format('\t\t\t\t<node index="%s" visibility="%s"/>',
                xmlEscape(nIndex), nVis))
        end
        nIdx = nIdx + 1
    end
    table.insert(lines, '\t\t\t</assets>')

    local locFile = resolveAssetRelative(getXMLString(xml, base .. ".locomotion#filename"), assetBaseDir, synthHusbDir)
    if locFile ~= nil then
        table.insert(lines, string.format('\t\t\t<locomotion filename="%s"/>', xmlEscape(locFile)))
    end

    do
        local attrs = ""
        for _, k in ipairs({
            "eatSoundGroup","yellSoundGroup","walkSoundGroup",
            "yellMinInterval","yellMaxInterval","yellTimerCrowdScale"
        }) do
            local v = getXMLString(xml, base .. ".audio#" .. k)
            if v ~= nil then attrs = attrs .. string.format(' %s="%s"', k, v) end
        end
        if attrs ~= "" then
            table.insert(lines, string.format('\t\t\t<audio%s/>', attrs))
        end
    end

    table.insert(lines, '\t\t</animal>')
    return true
end

-- Append the <soundGroup> children of one source XML's <sound> section into
-- `lines`, skipping any soundGroup whose name already appeared (kept in `seen`).
local function emitSoundGroups(lines, xml, seen, sampleBaseDir, synthHusbDir)
    local sg = 0
    while true do
        local gbase = string.format("animalHusbandry.sound.soundGroup(%d)", sg)
        local gname = getXMLString(xml, gbase .. "#name")
        if gname == nil then break end
        if seen[gname] == nil then
            seen[gname] = true
            local gattrs = string.format(' name="%s"', xmlEscape(gname))
            for _, k in ipairs({
                "volume","indoorVolume","volumeRandMin","volumeRandMax",
                "range","innerRange","pitch","pitchRandMin","pitchRandMax"
            }) do
                local v = getXMLString(xml, gbase .. "#" .. k)
                if v ~= nil then gattrs = gattrs .. string.format(' %s="%s"', k, v) end
            end
            table.insert(lines, string.format('\t\t<soundGroup%s>', gattrs))
            local sm = 0
            while true do
                local fn = getXMLString(xml, gbase .. string.format(".sample(%d)#filename", sm))
                if fn == nil then break end
                fn = resolveAssetRelative(fn, sampleBaseDir, synthHusbDir)
                table.insert(lines, string.format('\t\t\t<sample filename="%s"/>', xmlEscape(fn)))
                sm = sm + 1
            end
            table.insert(lines, '\t\t</soundGroup>')
        end
        sg = sg + 1
    end
end

-- Vanilla source range we WALK (1-based vai). Engine has a hard 32-entry cap
-- per husbandry XML; with pack at ~13 entries (after trimming the redundant
-- beef-rig duplicates and consolidating dairy onto the 4×4 atlas) we have 19
-- free slots inside {1..32}. We walk vanilla 1..16 (dairy 1-8 + beef 9-16) —
-- all 4 growth stages emit cleanly. Total: 13 + 16 = 29, comfy 3-slot margin.
local VANILLA_HUSBANDRY_LIMIT = 16

-- ---------- Map-mod (Mechet) support ----------
-- FS25_The_Mechet defines its own COW meshes at vai 22-30 inside
-- maps/animals/cow/animals.xml (Charolaise/Simmental/Montbeliarde/Vosgienne).
-- Our pack's <configOverride> normally replaces that husbandry XML with our 12-
-- slot version, so Mechet's mesh definitions never load and its breeds resolve
-- to vai=1 (= WATER_BUFFALO in our V1.0.2 layout). When Mechet is loaded we
-- regenerate the synth husbandry with vai 22-30 entries pointing at Mechet's
-- i3d files (cross-mod relative paths). Vanilla bridge slot allocator avoids
-- 22-30 so Mechet's slots stay reserved.
local MECHET_MOD       = "FS25_The_Mechet"
local MECHET_HUSB_PATH = "maps/animals/cow/animals.xml"
-- Mechet's NEW subTypes claim vai 19-30:
--   19-21: CharolaiseEtSimmental rig (used by COW_CHAROLAISE)
--   22-24: MontbeliardeEtVosgienne rig (used by COW_MONTBELIARDE)
--   25-27: CharolaiseEtSimmental rig duplicate (used by COW_SIMMENTAL)
--   28-30: MontbeliardeEtVosgienne rig duplicate (used by COW_VOSGIENNE)
-- Phase-1 had Highland at 19-21, but our pack overrides COW_HIGHLAND_CATTLE
-- with V1.0.2 vai's so Highland still renders correctly via the remap hook.
local MECHET_VAI_START = 19
local MECHET_VAI_END   = 30

local function findMechetMod()
    if g_modIsLoaded == nil then return nil end
    if g_modIsLoaded[MECHET_MOD] then return MECHET_MOD end
    local target = MECHET_MOD:lower()
    for name, _ in pairs(g_modIsLoaded) do
        if name:lower() == target then return name end
    end
    return nil
end

-- ---------- One-time Mechet+vanilla compatibility warning ----------
-- When AnimalPackage and Mechet are both loaded the vanilla bridge is capped
-- at 6 slots (instead of 16) so Mechet's CharolaiseEtSimmental rig at 19-21
-- and unique meshes at 22-30 stay reserved. Players see a one-time dialog
-- explaining this; once they click OK we persist a flag file in userProfile
-- so the dialog never shows again on this profile.
-- Per-savegame ack: each new save shows the warning once. The ack file lives
-- under <userProfile>/modSettings/ with the savegame index baked into the
-- filename so saves are independent. Returns nil if no save context is
-- available yet (during early bootstrap, before g_currentMission settles).
local WARNING_ACK_FILE_PREFIX = "modSettings/CowBreedsRLRM_MechetVanillaWarning_save"

local function getMechetVanillaWarningAckPath()
    local saveIdx = nil
    if g_currentMission ~= nil and g_currentMission.missionInfo ~= nil then
        saveIdx = g_currentMission.missionInfo.savegameIndex
    end
    if saveIdx == nil then return nil end
    return ensureSlash(getUserProfileAppPath()) .. WARNING_ACK_FILE_PREFIX .. tostring(saveIdx) .. ".acknowledged"
end

local function isMechetVanillaWarningAcknowledged()
    local path = getMechetVanillaWarningAckPath()
    if path == nil then return false end -- can't confirm; assume not acknowledged
    return fileExists(path)
end

local function writeMechetVanillaWarningAck()
    local path = getMechetVanillaWarningAckPath()
    if path == nil then
        logf("save context missing at ack write time; skipping (warning will repeat)")
        return
    end
    local f, err = io.open(path, "w")
    if f ~= nil then
        f:write("acknowledged")
        f:close()
        logf("Mechet+vanilla warning acknowledged; flag written to %s", path)
    else
        logf("could not write warning ack file: %s", tostring(err))
    end
end

local WARNING_TEXT =
    "FS25 Cow Breeds RLRM\n\n" ..
    "FS25_AnimalPackage_vanillaEdition and FS25_The_Mechet are both loaded.\n\n" ..
    "Mechet's four custom breeds (Charolaise, Simmental, Montbeliarde, Vosgienne) " ..
    "keep their meshes. To stay within the engine's 32-slot husbandry cap, the " ..
    "vanilla animal pack is limited to bulls only (M_GS01 through M_GS04 across " ..
    "all 5 vanilla breeds). Vanilla cow subtypes are not purchasable in this " ..
    "configuration.\n\n" ..
    "This warning will not show again on this save."

local function showMechetVanillaWarningNow()
    if isMechetVanillaWarningAcknowledged() then return end
    -- FS25's actual API is InfoDialog.show(text, callback) — not g_gui:showInfoDialog.
    if InfoDialog == nil or InfoDialog.show == nil then
        logf("InfoDialog not ready when warning fired; skipped")
        return
    end
    InfoDialog.show(WARNING_TEXT, writeMechetVanillaWarningAck)
    logf("displayed Mechet+vanilla warning dialog")
end

-- The bridge bootstrap fires inside FillTypeManager.loadMapData — way too
-- early for g_gui (we're still on the loading screen). Subscribe via the
-- message center so the dialog fires once the player is actually in the
-- game. The ack file is per-savegame, so a fresh save with the same mod
-- combo will see the warning again until acknowledged.
local function maybeScheduleMechetVanillaWarning()
    -- Don't pre-check ack here: g_currentMission isn't ready, so we can't
    -- resolve the per-save ack path yet. The actual show callback re-checks.
    if g_messageCenter ~= nil and MessageType ~= nil then
        local mt = MessageType.LOADED_MISSION_FINISHED
                or MessageType.SAVEGAME_LOADED
                or MessageType.LOAD_GAME_FINISHED
        if mt ~= nil then
            g_messageCenter:subscribe(mt, showMechetVanillaWarningNow)
            logf("Mechet+vanilla warning scheduled for message type %s", tostring(mt))
            return
        end
    end
    logf("no message center hook available; attempting immediate dialog")
    showMechetVanillaWarningNow()
end

-- Compute a mapping from vanilla source visualAnimalIndex (1-based) → output
-- visualAnimalIndex in the synth husbandry XML. Output indices are drawn from
-- {1..32} minus the indices the pack already uses, so vanilla entries land in
-- any gaps left by removed pack entries (e.g. buffalo, redundant beef-rig
-- duplicates).
--
-- All vanilla source entries are emitted (no GS03 skip / redirect). Earlier
-- versions skipped GS03 to fit under the engine's 32-entry cap when the pack
-- contributed 18+ entries; once the pack was trimmed to ~13 entries, all four
-- growth stages fit cleanly.
--
-- Returns: { [vanillaVai] = outputVai, ... }
-- vanillaToWalk: either a count N (walks source vai 1..N) or a list of
-- source vai's to allocate explicitly. The list form lets callers pick a
-- non-contiguous subset (e.g. {5, 7, 8} for bull GS01/GS03/GS04 only).
local function allocateVanillaSlots(packXml, vanillaToWalk, reservedSlots)
    local packUsed = {}
    local packCount = countHusbandryEntries(packXml)
    for i = 0, packCount - 1 do
        local vai = getXMLInt(packXml, string.format("animalHusbandry.animals.animal(%d)#visualAnimalIndex", i)) or (i + 1)
        packUsed[vai] = true
    end
    -- Reserved slots (e.g. Mechet's 19-30) get treated as "used" so the
    -- vanilla allocator skips them.
    if reservedSlots ~= nil then
        for vai, _ in pairs(reservedSlots) do packUsed[vai] = true end
    end

    local freeSlots = {}
    for vai = 1, 32 do
        if not packUsed[vai] then table.insert(freeSlots, vai) end
    end

    local sources
    if type(vanillaToWalk) == "table" then
        sources = vanillaToWalk
    else
        sources = {}
        for v = 1, vanillaToWalk or 0 do table.insert(sources, v) end
    end

    local origToOutput = {}
    local freeIdx = 1
    for _, sourceVai in ipairs(sources) do
        if freeIdx > #freeSlots then
            logf("free-slot pool exhausted at vanilla source vai=%d (free=%d)", sourceVai, #freeSlots)
            break
        end
        origToOutput[sourceVai] = freeSlots[freeIdx]
        freeIdx = freeIdx + 1
    end

    return origToOutput
end

-- Synthesize a combined husbandry visual config. The engine uses POSITIONAL
-- indexing of <animal> blocks (it ignores the `visualAnimalIndex` attribute and
-- treats each element's position as its rig index, position 0 = visualAnimalIndex
-- 1 etc.). So we must emit entries in slot-order with NO GAPS — otherwise pack
-- subType references like `visualAnimalIndex="16"` would resolve to whatever
-- entry happens to land at position 15, producing scrambled visuals.
--
-- We assemble a "slot table" mapping output-vai → (source XML, source index),
-- then emit slots 1..maxSlot in order. Pack entries claim their original vai
-- attribute as their slot; vanilla entries claim slots assigned by
-- allocateVanillaSlots (which picks free slots in {1..32} \ pack_used).
-- GS03 vanilla sources don't claim slots — they share the GS04 sibling's slot
-- via redirect inside synthSubType.
local function buildCombinedHusbandryXml(packXml, vanillaXml, packModDir, vanillaModDir, synthHusbDir, origToOutput, mechetXml, mechetModDir)
    origToOutput = origToOutput or {}
    local packBaseDir    = ensureSlash(packModDir) .. "models/cow/"
    local vanillaBaseDir = vanillaModDir and (ensureSlash(vanillaModDir) .. "animals/domesticated/cattle/") or nil
    local mechetBaseDir  = mechetModDir  and (ensureSlash(mechetModDir)  .. "maps/animals/cow/")            or nil

    local lines = {}
    table.insert(lines, '<?xml version="1.0" encoding="utf-8" standalone="no" ?>')
    table.insert(lines, '<animalHusbandry>')
    local mrsg  = getXMLString(packXml, "animalHusbandry.animals#milkRobotSoundGroup")
              or (vanillaXml and getXMLString(vanillaXml, "animalHusbandry.animals#milkRobotSoundGroup"))
              or "milkRobot"
    local mrdsg = getXMLString(packXml, "animalHusbandry.animals#milkRobotDoorSoundGroup")
              or (vanillaXml and getXMLString(vanillaXml, "animalHusbandry.animals#milkRobotDoorSoundGroup"))
              or "milkRobotDoor"
    table.insert(lines, string.format('\t<animals milkRobotSoundGroup="%s" milkRobotDoorSoundGroup="%s">', mrsg, mrdsg))

    -- Build slot table: outputVai -> { xml, sourceIdx, baseDir, modRoot }
    local slots = {}
    local maxSlot = 0

    local packCount = countHusbandryEntries(packXml)
    for i = 0, packCount - 1 do
        local vai = getXMLInt(packXml, string.format("animalHusbandry.animals.animal(%d)#visualAnimalIndex", i)) or (i + 1)
        if slots[vai] ~= nil then
            logf("WARNING: duplicate pack slot %d (sourceIdx %d collides with prior)", vai, i)
        end
        slots[vai] = { xml = packXml, sourceIdx = i, baseDir = packBaseDir, modRoot = packModDir, kind = "pack" }
        if vai > maxSlot then maxSlot = vai end
    end

    -- Vanilla bridge slots claim first (allocator already avoided 22-30 via
    -- reservedSlots, so vanilla typically lands in 13-21).
    for sourceVai, outputVai in pairs(origToOutput) do
        if slots[outputVai] ~= nil then
            logf("ERROR: vanilla slot %d collides with %s — bridge inactive", outputVai, slots[outputVai].kind)
            slots = {} ; maxSlot = 0
            break
        end
        slots[outputVai] = { xml = vanillaXml, sourceIdx = sourceVai - 1, baseDir = vanillaBaseDir, modRoot = vanillaModDir, kind = "vanilla" }
        if outputVai > maxSlot then maxSlot = outputVai end
    end

    -- Mechet: claim vai positions 13-30 that aren't already occupied. The
    -- unique Mechet content lives at vai 22-30 (Charolaise/Simmental/
    -- Montbeliarde/Vosgienne meshes). The 13-21 range holds Phase-1 standard
    -- entries (buffalo/beef/highland) that Mechet's base subTypes reference;
    -- we need them in the synth to keep slots contiguous from 1..maxSlot
    -- when no vanilla bridge is active.
    --
    -- Mechet's <animal> elements do NOT carry a visualAnimalIndex attribute;
    -- vai is positional (1st <animal> = vai 1). Fall back to (i+1) when the
    -- attribute is absent, matching how the engine resolves it.
    if mechetXml ~= nil and mechetBaseDir ~= nil then
        local mechetCount = countHusbandryEntries(mechetXml)
        local mechetClaimed = 0
        for i = 0, mechetCount - 1 do
            local vai = getXMLInt(mechetXml, string.format("animalHusbandry.animals.animal(%d)#visualAnimalIndex", i)) or (i + 1)
            if vai >= 13 and vai <= MECHET_VAI_END then
                if slots[vai] == nil then
                    slots[vai] = { xml = mechetXml, sourceIdx = i, baseDir = mechetBaseDir, modRoot = mechetModDir, kind = "mechet" }
                    mechetClaimed = mechetClaimed + 1
                    if vai > maxSlot then maxSlot = vai end
                end
            end
        end
        logf("Mechet contributed %d husbandry slot(s) (vai 13-%d, source had %d animals)",
             mechetClaimed, MECHET_VAI_END, mechetCount)
    end

    -- Emit in slot order. Engine uses positional indexing so we MUST be contiguous
    -- from slot 1 to maxSlot. A gap means subType visualAnimalIndex references
    -- past the gap would resolve to the wrong entry.
    for slot = 1, maxSlot do
        local entry = slots[slot]
        if entry == nil then
            logf("ERROR: slot %d has no entry — positional indexing would break, bridge inactive", slot)
            return ""
        end
        emitAnimalEntry(lines, entry.xml, entry.sourceIdx, slot, entry.baseDir, entry.modRoot, synthHusbDir)
    end

    table.insert(lines, '\t</animals>')

    -- Combined sound section: pack first, then vanilla (skipping duplicate names).
    local hasPackSounds    = getXMLString(packXml,    "animalHusbandry.sound.soundGroup(0)#name") ~= nil
    local hasVanillaSounds = vanillaXml and getXMLString(vanillaXml, "animalHusbandry.sound.soundGroup(0)#name") ~= nil
    if hasPackSounds or hasVanillaSounds then
        table.insert(lines, '\t<sound>')
        local seen = {}
        emitSoundGroups(lines, packXml, seen, packBaseDir, synthHusbDir)
        if vanillaXml ~= nil then
            emitSoundGroups(lines, vanillaXml, seen, vanillaBaseDir, synthHusbDir)
        end
        table.insert(lines, '\t</sound>')
    end

    table.insert(lines, '</animalHusbandry>')
    table.insert(lines, '')
    return table.concat(lines, "\n")
end

-- Translation file (en/de). Only emits text entries we know we generate $l10n_ keys for.
local function buildTranslationsXml()
    local lines = {}
    table.insert(lines, '<?xml version="1.0" encoding="utf-8" standalone="no" ?>')
    table.insert(lines, '<l10n>')
    table.insert(lines, '\t<texts>')
    for _, g in ipairs(BREED_GROUPS) do
        table.insert(lines, string.format('\t\t<text name="breed_%s_vanilla" text="%s"/>',
            g.breed:lower(), xmlEscape(g.display)))
        local cowDisplay  = g.display:gsub(" %(Vanilla%)", "") .. " Cow (Vanilla)"
        local bullDisplay = g.display:gsub(" %(Vanilla%)", "") .. " Bull (Vanilla)"
        table.insert(lines, string.format('\t\t<text name="fillType_%s_vanilla" text="%s"/>',
            g.female:lower(), xmlEscape(cowDisplay)))
        table.insert(lines, string.format('\t\t<text name="fillType_%s_vanilla" text="%s"/>',
            g.male:lower(), xmlEscape(bullDisplay)))
    end
    table.insert(lines, '\t</texts>')
    table.insert(lines, '</l10n>')
    table.insert(lines, '')
    return table.concat(lines, "\n")
end

local function buildPackXml()
    return table.concat({
        '<?xml version="1.0" encoding="utf-8" standalone="no" ?>',
        string.format('<rlrmPack name="%s" author="Con_Gan" version="%s">',
            xmlEscape(SYNTH_TITLE), SYNTH_VERSION),
        '\t<animals path="animals.xml"/>',
        '\t<fillTypes path="fillTypes.xml"/>',
        '\t<translations prefix="translations/translation"/>',
        '</rlrmPack>',
        ''
    }, "\n")
end

local function readVanillaModVersion(vanillaDir)
    local xml = loadXMLFile("vanillaModDesc", ensureSlash(vanillaDir) .. "modDesc.xml")
    if xml == nil then return "unknown" end
    local v = getXMLString(xml, "modDesc.version") or "unknown"
    delete(xml)
    return v
end

-- We deliberately do NOT add a fake mod entry to g_modIsLoaded /
-- g_modNameToDirectory / g_modNameToTitle. Doing so caused other game code paths
-- (notably onCreate/g_onCreateUtil initialization) to choke when iterating the
-- mod list, since our synthetic "mod" has no real modDesc.xml or onCreate scripts
-- on disk to back it up. Instead, we hook RLRM's bridge directly and push the
-- pack into its activeBridges list — RLRM never has to consult g_modIsLoaded
-- to know about us.

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

-- Manually load our synth pack into RLMapBridge's bridge list. Mirrors the body of
-- RLMapBridge.scanAnimalPacks for a single pack so we end up in activeBridges
-- without needing a fake entry in g_modIsLoaded.
local function manualLoadSynthPack(modDir)
    local RLMapBridge = getRLMapBridge()
    if RLMapBridge == nil or RLMapBridge.activeBridges == nil then
        logf("RLMapBridge unavailable, cannot register synth pack manually")
        return
    end
    -- Don't double-add if scanAnimalPacks already picked us up
    for _, b in ipairs(RLMapBridge.activeBridges) do
        if b.modName == SYNTH_NAME then
            logf("synth pack already in activeBridges, skipping manual load")
            return
        end
    end

    local packXmlPath = modDir .. "rlrm_pack.xml"
    if not fileExists(packXmlPath) then
        logf("rlrm_pack.xml missing at %s", packXmlPath)
        return
    end
    local xml = loadXMLFile("synthRlrmPack", packXmlPath)
    if xml == nil then
        logf("failed to load %s", packXmlPath)
        return
    end
    local packName = getXMLString(xml, "rlrmPack#name") or SYNTH_NAME
    local animalsPath = getXMLString(xml, "rlrmPack.animals#path")
    local fillTypesPath = getXMLString(xml, "rlrmPack.fillTypes#path")
    local translationsPrefix = getXMLString(xml, "rlrmPack.translations#prefix")
    delete(xml)

    local bridge = {
        modName = SYNTH_NAME, name = packName, isPack = true,
        packModDir = modDir, packAnimalsPath = animalsPath,
        packFillTypesPath = fillTypesPath, packTranslationsPrefix = translationsPrefix,
        resolvedConfigPath = ""
    }

    if translationsPrefix ~= nil and RLMapBridge.loadPackTranslations ~= nil then
        local tok, terr = pcall(RLMapBridge.loadPackTranslations, bridge)
        if not tok then logf("translation load failed: %s", tostring(terr)) end
    end

    if fillTypesPath ~= nil and g_fillTypeManager ~= nil then
        local fullFillTypesPath = modDir .. fillTypesPath
        local ftXml = loadXMLFile("synthPackFillTypes", fullFillTypesPath)
        if ftXml ~= nil then
            local fok, ferr = pcall(function()
                g_fillTypeManager:loadFillTypes(ftXml, modDir, false, "FS25_RealisticLivestockRM")
            end)
            delete(ftXml)
            if not fok then
                logf("fillType load failed: %s", tostring(ferr))
                return
            end
        else
            logf("fillTypes XML missing at %s", fullFillTypesPath)
        end
    end

    table.insert(RLMapBridge.activeBridges, bridge)
    logf("synth pack '%s' registered manually into RLMapBridge.activeBridges", packName)
end

-- Hook RLMapBridge.applyPropertyOverrides to copy accessory attributes
-- (monitor, earTagLeft, earTagRight, marker, bumId, noseRing) from bridge XML
-- onto existing subType visuals. RLRM's base implementation only copies
-- image/description/canBeBought/textureIndexes/visualAnimalIndex on the
-- override path (RLMapBridge.lua:~1300). Pack subTypes that already exist in
-- RLRM's bundled xml/animals.xml (COW_HOLSTEIN, COW_SWISS_BROWN, COW_HEREFORD,
-- COW_ANGUS, COW_LIMOUSIN + their BULL_ counterparts) go through the override
-- path, so their accessory attributes are silently dropped — leaving them with
-- RLRM's bundle paths which don't resolve in the pack's customized i3d files.
-- This hook reads the same XML structure and patches the missing attributes
-- onto the registered visuals AFTER RLRM finishes its normal override pass.
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

-- Map RLRM Phase-1 husbandry vai (1..21) to the equivalent slot in this pack's
-- V1.0.2 husbandry XML (12 entries). External map mods (e.g. FS25_Witcombe) hard-
-- code visualAnimalIndex values against the Phase-1 layout when defining their
-- own subTypes (Witcombe's BULL_JERSEY uses vai=5 expecting Holstein baby). Our
-- configOverride replaces the husbandry XML, so vai=5 now resolves to
-- WATER_BUFFALO_KID and the cow renders as a buffalo. This table redirects each
-- Phase-1 vai to the V1.0.2 slot that holds the same logical model.
local PHASE1_TO_V102_VAI = {
    [1]  = 2,    -- Holstein adult       -> V1.0.2 vai 2 (Holstein 4x4)
    [2]  = 2,    -- Holstein adult dup   -> V1.0.2 vai 2
    [3]  = 7,    -- Angus adult          -> V1.0.2 vai 7 (beef-v3)
    [4]  = 7,    -- Angus/Limousin adult -> V1.0.2 vai 7
    [5]  = 4,    -- BABY_SWISS_BROWN     -> V1.0.2 vai 4 (Holstein 4x4 baby)
    [6]  = 4,    -- Holstein baby dup    -> V1.0.2 vai 4
    [7]  = 9,    -- Angus baby           -> V1.0.2 vai 9 (beef-v3 baby)
    [8]  = 9,    -- Angus baby dup       -> V1.0.2 vai 9
    [9]  = 6,    -- Holstein calf        -> V1.0.2 vai 6 (Holstein 4x4 calf)
    [10] = 6,    -- Holstein calf dup    -> V1.0.2 vai 6
    [11] = 8,    -- Angus calf           -> V1.0.2 vai 8 (beef-v3 calf)
    [12] = 8,    -- Angus calf dup       -> V1.0.2 vai 8
    [13] = 3,    -- WATER_BUFFALO_BABY   -> V1.0.2 vai 3
    [14] = 5,    -- WATER_BUFFALO_KID    -> V1.0.2 vai 5
    [15] = 1,    -- WATER_BUFFALO        -> V1.0.2 vai 1
    [16] = 7,    -- beef-v3 adult        -> V1.0.2 vai 7
    [17] = 8,    -- beef-v3 calf         -> V1.0.2 vai 8
    [18] = 9,    -- beef-v3 baby         -> V1.0.2 vai 9
    [19] = 10,   -- HIGHLAND_CATTLE_BABY -> V1.0.2 vai 10
    [20] = 11,   -- HIGHLAND_CATTLE_KID  -> V1.0.2 vai 11
    [21] = 12,   -- HIGHLAND_CATTLE      -> V1.0.2 vai 12
}

-- For foreign subTypes (not in PACK_SUBTYPES) that share a breed name with our
-- pack atlases, this maps the breed-prefix portion of the name to the
-- textureIndexes that select that breed's tile within the V1.0.2 atlas.
-- Without this, foreign Jersey/etc. cows render with random dairy textures
-- because their bridge XML omits textureIndexes and the atlas exposes all 12.
local BREED_TEXTURE_INDEXES = {
    -- Holstein 4x4 dairy atlas (vai 2 adult / 4 baby / 6 calf)
    JERSEY      = {7, 8},
    GUERNSEY    = {1, 2},
    REDHOLSTEIN = {3, 4},
    AYRSHIRE    = {5, 6},
    BROWNSWISS  = {9, 10},
    SWISSBROWN  = {9, 10},
    HOLSTEIN    = {11, 12},
}

-- SubTypes whose visualAnimalIndex values are authored against the V1.0.2 layout
-- (our pack subTypes + base-game subTypes we override + vanilla bridge subTypes).
-- These must NOT be remapped — they're already correct.
-- Foreign subTypes whose visualAnimalIndex values are AUTHORED against the
-- combined synth husbandry XML (with Mechet's slots 13-30 included). These
-- must NOT be remapped — Charolaise's vai 19/20/21 already correctly point at
-- Mechet's CharolaiseEtSimmental mesh that we baked into synth slots 19/20/21.
-- Without this skip, the Phase-1 remap table sends vai 19→10 (Highland) and
-- the cow renders as a Highland.
local MECHET_SUBTYPES = {
    COW_CHAROLAISE   = true, BULL_CHAROLAISE   = true,
    COW_MONTBELIARDE = true, BULL_MONTBELIARDE = true,
    COW_SIMMENTAL    = true, BULL_SIMMENTAL    = true,
    COW_VOSGIENNE    = true, BULL_VOSGIENNE    = true,
}

local PACK_SUBTYPES = {
    -- Pack _PACK breeds
    COW_REDHOLSTEIN_PACK = true, BULL_REDHOLSTEIN_PACK = true,
    COW_AYRSHIRE_PACK    = true, BULL_AYRSHIRE_PACK    = true,
    COW_JERSEY_PACK      = true, BULL_JERSEY_PACK      = true,
    COW_GUERNSEY_PACK    = true, BULL_GUERNSEY_PACK    = true,
    COW_CHAROLAIS_PACK   = true, BULL_CHAROLAIS_PACK   = true,
    COW_REDANGUS_PACK    = true, BULL_REDANGUS_PACK    = true,
    COW_HEREFORD_PACK    = true, BULL_HEREFORD_PACK    = true,
    COW_SHORTHORN_PACK   = true, BULL_SHORTHORN_PACK   = true,
    COW_IRISHMOILED_PACK = true, BULL_IRISHMOILED_PACK = true,
    COW_BRITISHBLUE_PACK = true, BULL_BRITISHBLUE_PACK = true,
    COW_BELTEDGALLOWAY_PACK = true, BULL_BELTEDGALLOWAY_PACK = true,
    COW_SIMMENTAL_PACK   = true, BULL_SIMMENTAL_PACK   = true,
    -- Base-game subTypes our pack overrides with V1.0.2 vai's
    COW_HOLSTEIN         = true, BULL_HOLSTEIN         = true,
    COW_SWISS_BROWN      = true, BULL_SWISS_BROWN      = true,
    COW_LIMOUSIN         = true, BULL_LIMOUSIN         = true,
    COW_ANGUS            = true, BULL_ANGUS            = true,
    COW_HEREFORD         = true, BULL_HEREFORD         = true,
    COW_HIGHLAND_CATTLE  = true, BULL_HIGHLAND_CATTLE  = true,
    COW_WATERBUFFALO     = true, BULL_WATERBUFFALO     = true,
    -- Vanilla edition bridge subTypes
    COW_HOLSTEIN_VANILLA    = true, BULL_HOLSTEIN_VANILLA    = true,
    COW_REDHOLSTEIN_VANILLA = true, BULL_REDHOLSTEIN_VANILLA = true,
    COW_BROWNSWISS_VANILLA  = true, BULL_BROWNSWISS_VANILLA  = true,
    COW_LIMOUSIN_VANILLA    = true, BULL_LIMOUSIN_VANILLA    = true,
    COW_ANGUS_VANILLA       = true, BULL_ANGUS_VANILLA       = true,
}

-- Hook RLMapBridge.applyPropertyOverrides to remap stale Phase-1 visualAnimalIndex
-- values on foreign COW subTypes. Many are loaded in Phase 2 from a map's
-- map/config/animals.xml (e.g. FS25_Witcombe defines COW_JERSEY there with
-- vai=5/9/1) — visuals never appear in any Phase-3 bridge XML, so a per-bridge
-- XML walk would miss them. Instead we walk every COW subType in animalSystem
-- after each bridge applies (idempotent because each visual is flagged once
-- remapped) and rewrite Phase-1 vai's to V1.0.2 equivalents. PACK_SUBTYPES are
-- skipped because their visuals are authored against V1.0.2 directly.
local function installVisualIndexRemapHook(RLMapBridge)
    if RLMapBridge.__cowBreedsVaiRemapHooked then return end
    if RLMapBridge.applyPropertyOverrides == nil then
        logf("RLMapBridge.applyPropertyOverrides missing, vai remap hook skipped")
        return
    end

    -- Find the "_PACK" pack equivalent for a foreign subType (e.g. for
    -- "COW_JERSEY" return the COW_JERSEY_PACK subType if registered) so we
    -- can copy textureIndexes + accessory attrs (monitor, earTagLeft, etc.)
    -- onto the foreign visual. Returns nil if no pack equivalent exists yet
    -- — common during Witcombe's bridge call (our pack hasn't loaded). The
    -- caller defers the copy until a later hook call when the source exists.
    local function findPackEquivalent(animalSystem, cowType, foreignName)
        local upper = foreignName:upper()
        if upper:find("_PACK$") or upper:find("_VANILLA$") then return nil end
        local target = upper .. "_PACK"
        for _, idx in ipairs(cowType.subTypes) do
            local s = animalSystem.subTypes and animalSystem.subTypes[idx]
            if s ~= nil and s.name ~= nil and s.name:upper() == target then return s end
        end
        return nil
    end

    -- Static fallback for textureIndexes only — used when no _PACK equivalent
    -- exists (e.g. a foreign breed we haven't packed). Derive breed key from
    -- subType name.
    local function deriveBreed(subTypeName)
        local rest = subTypeName:upper():match("^COW_(.+)$")
                  or subTypeName:upper():match("^BULL_(.+)$")
        if rest == nil then return nil end
        return rest:gsub("_", "")
    end

    local ACCESSORY_ATTRS = {"monitor","earTagLeft","earTagRight","marker","bumId","noseRing"}

    -- Beef breed names (used to pick beef-v3 rig for unknown high vai's).
    local BEEF_BREEDS = {
        CHAROLAIS=true, CHAROLAISE=true,
        SIMMENTAL=true,
        HEREFORD=true,
        ANGUS=true, REDANGUS=true,
        LIMOUSIN=true,
        SHORTHORN=true,
        BRITISHBLUE=true,
        IRISHMOILED=true,
        BELTEDGALLOWAY=true,
    }

    -- Resolve a foreign vai to a V1.0.2 husbandry slot. Tries the explicit
    -- Phase-1 table first; if the vai is out of Phase-1 range (e.g. a map mod
    -- like FS25_The_Mechet defines its own meshes at vai 22+), falls back to
    -- age + breed heuristics so the cow at least renders as cattle instead
    -- of falling through to the default vai 1 (= WATER_BUFFALO in V1.0.2).
    local function resolveVai(currentVai, minAge, breed)
        local explicit = PHASE1_TO_V102_VAI[currentVai]
        if explicit ~= nil then return explicit end
        if minAge == nil then return nil end
        local isBeef = breed and BEEF_BREEDS[breed] or false
        if isBeef then
            if minAge >= 12 then return 7    -- beef-v3 adult
            elseif minAge >= 6 then return 8 -- beef-v3 calf
            else return 9                    -- beef-v3 baby
            end
        else
            if minAge >= 12 then return 2    -- Holstein 4x4 adult
            elseif minAge >= 6 then return 6 -- Holstein 4x4 calf
            else return 4                    -- Holstein 4x4 baby
            end
        end
    end

    local function walkAndRemap(animalSystem, bridgeName)
        if animalSystem == nil or animalSystem.nameToType == nil then return 0 end
        local cowType = animalSystem.nameToType["COW"]
        if cowType == nil or cowType.subTypes == nil then return 0 end
        local remapped = 0
        local retextured = 0
        local accessoriesCopied = 0
        for _, idx in ipairs(cowType.subTypes) do
            local subType = animalSystem.subTypes and animalSystem.subTypes[idx]
            if subType ~= nil and subType.name ~= nil and subType.visuals ~= nil then
                local upper = subType.name:upper()
                if not PACK_SUBTYPES[upper] and not MECHET_SUBTYPES[upper] then
                    local source = findPackEquivalent(animalSystem, cowType, subType.name)
                    local breed = deriveBreed(subType.name)
                    local breedTex = breed and BREED_TEXTURE_INDEXES[breed]
                    for _, v in ipairs(subType.visuals) do
                        -- (1) vai remap — one-shot, doesn't need source.
                        if v.__cowBreedsVaiRemapped ~= true then
                            local current = v.visualAnimalIndex
                            local target = current and resolveVai(current, v.minAge, breed)
                            if target ~= nil and target ~= current then
                                v.visualAnimalIndex = target
                                remapped = remapped + 1
                            end
                            if breedTex ~= nil and (v.textureIndexes == nil or #v.textureIndexes == 0) then
                                v.textureIndexes = { breedTex[1], breedTex[2] }
                                retextured = retextured + 1
                            end
                            v.__cowBreedsVaiRemapped = true
                        end
                        -- (2) Accessory + textureIndexes copy from _PACK source.
                        -- Deferred until source exists; on the bridge call where
                        -- our pack subTypes get registered, this finally fires.
                        -- We OVERWRITE rather than only-fill-if-nil because
                        -- RLRM initializes unspecified accessory attrs to default
                        -- strings (not nil), and we want the pack's breed-correct
                        -- pattern (e.g. monitor only on the Jersey tile) to win.
                        if v.__cowBreedsAccessoryCopied ~= true and source ~= nil and source.visuals ~= nil then
                            local match = nil
                            for _, sv in ipairs(source.visuals) do
                                if sv.minAge == v.minAge then match = sv; break end
                            end
                            if match ~= nil then
                                if match.textureIndexes ~= nil then
                                    v.textureIndexes = match.textureIndexes
                                end
                                for _, attr in ipairs(ACCESSORY_ATTRS) do
                                    if match[attr] ~= nil then
                                        v[attr] = match[attr]
                                        accessoriesCopied = accessoriesCopied + 1
                                    end
                                end
                                v.__cowBreedsAccessoryCopied = true
                            end
                        end
                    end
                end
            end
        end
        if remapped > 0 or retextured > 0 or accessoriesCopied > 0 then
            logf("vai remap [%s]: rewrote %d vai, %d textureIndexes, copied %d accessory attr(s)",
                 tostring(bridgeName), remapped, retextured, accessoriesCopied)
        end
        return remapped
    end

    RLMapBridge.applyPropertyOverrides = Utils.appendedFunction(
        RLMapBridge.applyPropertyOverrides,
        function(animalSystem, xmlFile, bridgeName, mapModDir)
            local ok, err = pcall(walkAndRemap, animalSystem, bridgeName)
            if not ok then
                logf("vai remap hook failed for bridge '%s': %s", tostring(bridgeName), tostring(err))
            end
        end
    )

    -- Also hook loadBridgeAnimals so we get a final walk AFTER ALL bridges
    -- finish — this is when our pack's _PACK subTypes are finally registered
    -- and the deferred accessory copy from foreign visuals can succeed.
    -- applyPropertyOverrides only fires for bridges that override existing
    -- subTypes (Witcombe), so without this our hook never runs again once
    -- Cow Breeds has loaded.
    if RLMapBridge.loadBridgeAnimals ~= nil then
        RLMapBridge.loadBridgeAnimals = Utils.appendedFunction(
            RLMapBridge.loadBridgeAnimals,
            function(animalSystem)
                local ok, err = pcall(walkAndRemap, animalSystem, "<post-loadBridgeAnimals>")
                if not ok then
                    logf("vai remap post-bridge hook failed: %s", tostring(err))
                end
            end
        )
        logf("installed loadBridgeAnimals post-bridge vai remap hook")
    end

    RLMapBridge.__cowBreedsVaiRemapHooked = true
    logf("installed applyPropertyOverrides vai remap hook")
end

-- Hook FillTypeManager.loadMapData. RLRM appends its own loadBridgeFillTypes
-- (which calls scanAnimalPacks) to this same function. By appending our hook
-- first, our fn runs in the chain BEFORE RLRM's appended fn, letting us install
-- a scanAnimalPacks hook just in time. By that point RLMapBridge is defined.
-- We also install the applyPropertyOverrides accessory hook here for the same
-- timing reason.
--
-- Importantly, we ALSO defer companion-mod detection (AnimalPackage / Mechet)
-- and synth regeneration to this hook. Map mods like Mechet aren't yet present
-- in g_modIsLoaded at module-source time — they only get registered once the
-- save's map starts loading, which happens before loadMapData runs but after
-- our module is sourced. So bridgeLateBootstrap() runs the detection/regen
-- once per launch when this hook fires.
local function installFillTypeManagerHook(packModDir, bridgeLateBootstrap)
    if FillTypeManager == nil or FillTypeManager.loadMapData == nil then
        logf("FillTypeManager.loadMapData missing, hook skipped")
        return
    end
    if FillTypeManager.__cowBreedsVanillaBridgeHooked then return end

    FillTypeManager.loadMapData = Utils.appendedFunction(
        FillTypeManager.loadMapData,
        function(self)
            -- Late detection + regeneration: g_modIsLoaded is fully populated by
            -- now (including map mods). bridgeLateBootstrap returns the synth
            -- dir to register, or nil if no companion mod was found.
            local tempDir = bridgeLateBootstrap(packModDir)
            if tempDir == nil then return end

            local RLMapBridge = getRLMapBridge()
            if RLMapBridge == nil or RLMapBridge.scanAnimalPacks == nil then
                logf("RLMapBridge not available at FillTypeManager.loadMapData; bridge inactive")
                return
            end
            if not RLMapBridge.__cowBreedsVanillaBridgeHooked then
                RLMapBridge.scanAnimalPacks = Utils.appendedFunction(
                    RLMapBridge.scanAnimalPacks,
                    function() manualLoadSynthPack(tempDir) end
                )
                RLMapBridge.__cowBreedsVanillaBridgeHooked = true
                logf("installed scanAnimalPacks appended hook (synth=%s)", tempDir)
            end
            installVisualAccessoryHook(RLMapBridge)
            installVisualIndexRemapHook(RLMapBridge)
        end
    )
    FillTypeManager.__cowBreedsVanillaBridgeHooked = true
end

-- Minimal animals.xml + fillTypes.xml stubs for the Mechet-only synth bundle.
-- The synth pack still needs an animals.xml (for the configOverride) but no
-- vanilla bridge subTypes get registered.
local function buildMinimalAnimalsXml()
    return table.concat({
        '<?xml version="1.0" encoding="utf-8" standalone="no" ?>',
        '<animals>',
        '\t<configOverrides>',
        '\t\t<override type="COW" configFilename="models/cow/animals.xml"/>',
        '\t</configOverrides>',
        '\t<breeds>',
        '\t</breeds>',
        '</animals>',
        ''
    }, "\n")
end

local function buildMinimalFillTypesXml()
    return table.concat({
        '<?xml version="1.0" encoding="utf-8" standalone="no" ?>',
        '<map xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="$data/shared/xml/schema/fillTypes.xsd">',
        '\t<fillTypes>',
        '\t</fillTypes>',
        '</map>',
        ''
    }, "\n")
end

local function regenerate(vanillaDir, tempDir, packModDir, mechetDir)
    -- Vanilla source XMLs are optional — only load when AnimalPackage is present.
    local cowXml, fillXml, vanillaHusbXml = nil, nil, nil
    if vanillaDir ~= nil then
        cowXml = loadXMLFile("vanillaCow", ensureSlash(vanillaDir) .. "xmls/animals/cow.xml")
        if cowXml == nil then error("cannot load vanilla xmls/animals/cow.xml", 0) end
        fillXml = loadXMLFile("vanillaFill", ensureSlash(vanillaDir) .. "xmls/fillTypes.xml")
        if fillXml == nil then delete(cowXml); error("cannot load vanilla xmls/fillTypes.xml", 0) end
        vanillaHusbXml = loadXMLFile("vanillaHusb",
            ensureSlash(vanillaDir) .. "animals/domesticated/cattle/husbandryAnimalsCattle.xml")
        if vanillaHusbXml == nil then delete(cowXml); delete(fillXml); error("cannot load vanilla husbandryAnimalsCattle.xml", 0) end
    end

    -- Read this mod's existing models/cow/animals.xml so we can put its 12 entries
    -- first in the combined husbandry config (preserving _pack subtype indices).
    local packHusbXml = loadXMLFile("packHusb",
        ensureSlash(packModDir) .. "models/cow/animals.xml")
    if packHusbXml == nil then
        if cowXml then delete(cowXml) end
        if fillXml then delete(fillXml) end
        if vanillaHusbXml then delete(vanillaHusbXml) end
        error("cannot load pack models/cow/animals.xml", 0)
    end
    local packCount = countHusbandryEntries(packHusbXml)
    logf("pack husbandry has %d animal entries", packCount)

    -- Optionally read Mechet's husbandry XML (for the _synth_mechet*/ builds).
    local mechetHusbXml = nil
    local effectiveVanillaLimit = vanillaDir and VANILLA_HUSBANDRY_LIMIT or 0
    local reservedSlots = nil
    if mechetDir ~= nil then
        mechetHusbXml = loadXMLFile("mechetHusb", ensureSlash(mechetDir) .. MECHET_HUSB_PATH)
        if mechetHusbXml ~= nil then
            -- 32 cap: 12 pack + 12 Mechet (19-30) = 24. With Mechet loaded the
            -- vanilla bridge collapses to bulls-only across all 4 growth stages
            -- for both dairy and beef rigs:
            --   source vai 5-8  = dairy bulls (Holstein/RedHolstein/BrownSwiss)
            --   source vai 13-16 = beef bulls (Limousin/Angus)
            -- 8 husbandry slots used. Cow _VANILLA subTypes get 0 visuals
            -- (Mechet's dairy and our pack already cover that side).
            -- Total: 12 pack + 8 vanilla + 12 Mechet = 32 / 32 (exactly at cap).
            if vanillaDir ~= nil then
                effectiveVanillaLimit = { 5, 6, 7, 8, 13, 14, 15, 16 }
            end
            reservedSlots = {}
            for vai = MECHET_VAI_START, MECHET_VAI_END do reservedSlots[vai] = true end
            local vanillaDesc = (type(effectiveVanillaLimit) == "table")
                and ("source vai's {" .. table.concat(effectiveVanillaLimit, ",") .. "}")
                or  ("limit " .. tostring(effectiveVanillaLimit))
            logf("Mechet husbandry loaded; vanilla %s, reserved vai %d-%d",
                 vanillaDesc, MECHET_VAI_START, MECHET_VAI_END)
        else
            logf("Mechet husbandry XML missing at %s%s; ignoring Mechet support", mechetDir, MECHET_HUSB_PATH)
        end
    end

    -- Pre-compute vanilla source-vai → output-vai map. Empty when AnimalPackage
    -- is absent, but allocateVanillaSlots is still called so reservedSlots is
    -- consistently honoured.
    local origToOutput = allocateVanillaSlots(packHusbXml, effectiveVanillaLimit, reservedSlots)
    do
        local emitted = 0
        for vai = 1, 32 do if origToOutput[vai] then emitted = emitted + 1 end end
        local walkedDesc = (type(effectiveVanillaLimit) == "table")
            and ("vai {" .. table.concat(effectiveVanillaLimit, ",") .. "}")
            or  ("1.." .. tostring(effectiveVanillaLimit))
        logf("vanilla slot map: walked %s, emitted %d entries", walkedDesc, emitted)
    end

    createFolder(tempDir)
    createFolder(tempDir .. "models")
    createFolder(tempDir .. "models/cow")
    createFolder(tempDir .. "translations")

    writeFile(tempDir .. "rlrm_pack.xml", buildPackXml())
    if vanillaDir ~= nil then
        writeFile(tempDir .. "animals.xml",   buildAnimalsXml(cowXml, vanillaDir, origToOutput))
        writeFile(tempDir .. "fillTypes.xml", buildFillTypesXml(fillXml))
    else
        -- Mechet-only mode: no vanilla bridge subTypes, just the configOverride stub.
        writeFile(tempDir .. "animals.xml",   buildMinimalAnimalsXml())
        writeFile(tempDir .. "fillTypes.xml", buildMinimalFillTypesXml())
    end
    -- Combined husbandry XML — referenced by configOverride in synth animals.xml.
    -- Asset paths inside this file are emitted relative to synthHusbDir using `..`
    -- traversal so the engine routes through both the pack and companion mod dirs.
    local synthHusbDir = tempDir .. "models/cow/"
    writeFile(tempDir .. "models/cow/animals.xml",
        buildCombinedHusbandryXml(packHusbXml, vanillaHusbXml, packModDir, vanillaDir, synthHusbDir, origToOutput, mechetHusbXml, mechetDir))
    local trans = buildTranslationsXml()
    writeFile(tempDir .. "translations/translation_en.xml", trans)
    writeFile(tempDir .. "translations/translation_de.xml", trans)

    if cowXml         then delete(cowXml) end
    if fillXml        then delete(fillXml) end
    if vanillaHusbXml then delete(vanillaHusbXml) end
    delete(packHusbXml)
    if mechetHusbXml ~= nil then delete(mechetHusbXml) end
end

-- Find the AnimalPackage mod even if its zip filename uses different casing
-- (g_modIsLoaded keys = zip filename minus .zip). Returns the actual key name or nil.
local function findVanillaModName()
    if g_modIsLoaded == nil then return nil end
    if g_modIsLoaded[VANILLA_MOD] then return VANILLA_MOD end
    local target = VANILLA_MOD:lower()
    for name, _ in pairs(g_modIsLoaded) do
        if name:lower() == target then return name end
    end
    -- Looser match: any mod whose name contains "animalpackage" and "vanilla"
    for name, _ in pairs(g_modIsLoaded) do
        local lower = name:lower()
        if lower:find("animalpackage", 1, true) and lower:find("vanilla", 1, true) then
            return name
        end
    end
    return nil
end

-- All six artefacts produced by regenerate(). When all are present we skip
-- regenerate entirely — required for zipped mods, where the pack directory is
-- read-only and createFolder/writeFile throw. fileExists works in the sandbox.
local function synthIsComplete(tempDir)
    return fileExists(tempDir .. "rlrm_pack.xml")
       and fileExists(tempDir .. "animals.xml")
       and fileExists(tempDir .. "fillTypes.xml")
       and fileExists(tempDir .. "models/cow/animals.xml")
       and fileExists(tempDir .. "translations/translation_en.xml")
       and fileExists(tempDir .. "translations/translation_de.xml")
end

-- Late bootstrap: runs once on first FillTypeManager.loadMapData call.
-- Returns the synth dir to register with RLRM, or nil if no companion mod
-- is loaded. By this point map mods (Mechet) ARE in g_modIsLoaded.
local bridgeLateBootstrapDone = false
local function bridgeLateBootstrap(packModDir)
    if bridgeLateBootstrapDone then return nil end
    bridgeLateBootstrapDone = true

    if g_modIsLoaded == nil then
        logf("g_modIsLoaded nil at late bootstrap; bridge skipped")
        return nil
    end

    -- Detect both companion mods. Bridge activates if EITHER is present;
    -- only skips if neither AnimalPackage nor Mechet is loaded.
    local actualVanillaName = findVanillaModName()
    local mechetName        = findMechetMod()

    if actualVanillaName == nil and mechetName == nil then
        logf("Neither AnimalPackage nor Mechet found; bridge skipped. Loaded mods follow:")
        local names = {}
        for name, _ in pairs(g_modIsLoaded) do table.insert(names, name) end
        table.sort(names)
        for _, name in ipairs(names) do logf("  loaded: %s", name) end
        return nil
    end

    local vanillaDir = nil
    if actualVanillaName ~= nil then
        if actualVanillaName ~= VANILLA_MOD then
            logf("matched AnimalPackage under alternate name: '%s'", actualVanillaName)
        end
        vanillaDir = g_modNameToDirectory[actualVanillaName]
        if vanillaDir == nil or vanillaDir == "" then
            logf("AnimalPackage directory unknown; vanilla bridge inactive")
            vanillaDir = nil
        else
            vanillaDir = ensureSlash(vanillaDir)
        end
    end

    local mechetDir = nil
    if mechetName ~= nil then
        mechetDir = g_modNameToDirectory[mechetName]
        if mechetDir == nil or mechetDir == "" then
            logf("Mechet detected (%s) but mod directory unknown; Mechet support inactive", mechetName)
            mechetDir = nil
        else
            mechetDir = ensureSlash(mechetDir)
            logf("Mechet detected at %s", mechetDir)
        end
    end

    if vanillaDir == nil and mechetDir == nil then
        logf("Both companion mods detected but directories unknown; bridge skipped")
        return nil
    end

    if packModDir == nil or packModDir == "" then
        logf("cannot resolve pack mod directory; bridge skipped")
        return nil
    end

    -- Synth dir lives INSIDE the pack mod's directory so relative `..` paths
    -- in the combined husbandry XML can navigate to companion mods (same drive
    -- guaranteed). Cross-drive `..` traversal doesn't work and the engine
    -- doesn't recognize Windows drive letters (`F:/`) as absolute, so any path
    -- resolution must produce a relative path from synth/models/cow/ back to
    -- the target asset.
    --
    -- Three synth bundles exist:
    --   _synth/             — only AnimalPackage loaded
    --   _synth_mechet/      — both AnimalPackage AND Mechet loaded
    --   _synth_mechet_only/ — only Mechet loaded (no vanilla bridge subTypes)
    -- Each is pre-built unzipped and shipped in the zip; runtime regeneration
    -- to userProfile doesn't work because the synth's relative paths can't
    -- traverse drive boundaries.
    local synthSubdir
    if vanillaDir ~= nil and mechetDir ~= nil then
        synthSubdir = "_synth_mechet/"
    elseif mechetDir ~= nil then
        synthSubdir = "_synth_mechet_only/"
    else
        synthSubdir = "_synth/"
    end
    local tempDir = ensureSlash(packModDir) .. synthSubdir
    local vanillaVersion = vanillaDir and readVanillaModVersion(vanillaDir) or "n/a"

    -- Shipping path: dev populates _synth*/ once unzipped, commits it, players
    -- load the .zip read-only. If the bundle is already complete, skip regen
    -- entirely (writes would throw against a zipped mod dir).
    if synthIsComplete(tempDir) then
        logf("synth bundle present at %s; skipping regenerate (vanilla=%s, mechet=%s)",
             tempDir, tostring(vanillaDir), tostring(mechetDir))
    else
        logf("regenerating bridge at %s (vanilla=%s, mechet=%s)",
             tempDir, tostring(vanillaDir), tostring(mechetDir))
        local rok, rerr = pcall(regenerate, vanillaDir, tempDir, packModDir, mechetDir)
        if not rok then
            logf("regenerate failed: %s; bridge inactive", tostring(rerr))
            return nil
        end
        logf("regenerated bridge files at %s", tempDir)
    end

    -- One-time warning when both AnimalPackage and Mechet are loaded.
    -- Scheduled for after-load so g_gui is ready by the time the dialog fires.
    if vanillaDir ~= nil and mechetDir ~= nil then
        pcall(maybeScheduleMechetVanillaWarning)
    end

    return tempDir
end

-- Module-source bootstrap: just install the FillTypeManager hook with the pack
-- directory and a deferred bootstrap callback. Real detection + regeneration
-- happens later inside the hook (after maps load and g_modIsLoaded is fully
-- populated). We do NOT add a fake mod to g_modIsLoaded: doing so caused other
-- game code paths (g_onCreateUtil init, onCreate script registration) to crash
-- when iterating loaded mods because our synthetic mod has no real modDesc.xml
-- on disk. Instead, we wait until RLMapBridge is loaded, then append a manual
-- pack-load to RLMapBridge.scanAnimalPacks so our pack ends up in
-- RLMapBridge.activeBridges through RLRM's own code path.
local function setup()
    local packModDir = g_currentModDirectory or g_modNameToDirectory[g_currentModName or ""]
    if packModDir == nil or packModDir == "" then
        logf("cannot resolve pack mod directory; bridge skipped")
        return
    end
    installFillTypeManagerHook(packModDir, bridgeLateBootstrap)
end

local ok, err = pcall(setup)
if not ok then
    logf("setup failed: %s", tostring(err))
end
