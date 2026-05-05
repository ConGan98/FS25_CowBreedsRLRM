-- Detect FS25_AnimalPackage_vanillaEdition at load time and surface its cow
-- breeds as additional RLRM bridge entries. We synthesize a small "virtual
-- bridge pack" under <packModDir>/_synth/ at regenerate time (animals.xml +
-- fillTypes.xml + translations + a combined husbandry config that joins this
-- pack's 21 animal entries with vanilla AnimalPackage's first 8). At runtime
-- we hook RLMapBridge.scanAnimalPacks via a chain through FillTypeManager.
-- loadMapData and manually push our bridge entry into RLMapBridge.activeBridges
-- — RLRM then processes it through its normal flow, which applies our config
-- override and registers our _vanilla subtypes alongside its own.

print("[CowBreedsRLRM/VanillaBridge] module sourced (v0.2.1.0)")

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
local SYNTH_VERSION = "0.2.1.0"
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
local function allocateVanillaSlots(packXml, vanillaToWalk)
    local packUsed = {}
    local packCount = countHusbandryEntries(packXml)
    for i = 0, packCount - 1 do
        local vai = getXMLInt(packXml, string.format("animalHusbandry.animals.animal(%d)#visualAnimalIndex", i)) or (i + 1)
        packUsed[vai] = true
    end

    local freeSlots = {}
    for vai = 1, 32 do
        if not packUsed[vai] then table.insert(freeSlots, vai) end
    end

    local origToOutput = {}
    local freeIdx = 1
    for vai = 1, vanillaToWalk do
        if freeIdx > #freeSlots then
            logf("free-slot pool exhausted at vanilla vai=%d (free=%d)", vai, #freeSlots)
            break
        end
        origToOutput[vai] = freeSlots[freeIdx]
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
local function buildCombinedHusbandryXml(packXml, vanillaXml, packModDir, vanillaModDir, synthHusbDir, origToOutput)
    origToOutput = origToOutput or {}
    local packBaseDir    = ensureSlash(packModDir)    .. "models/cow/"
    local vanillaBaseDir = ensureSlash(vanillaModDir) .. "animals/domesticated/cattle/"

    local lines = {}
    table.insert(lines, '<?xml version="1.0" encoding="utf-8" standalone="no" ?>')
    table.insert(lines, '<animalHusbandry>')
    local mrsg  = getXMLString(packXml, "animalHusbandry.animals#milkRobotSoundGroup")
              or  getXMLString(vanillaXml, "animalHusbandry.animals#milkRobotSoundGroup")
              or "milkRobot"
    local mrdsg = getXMLString(packXml, "animalHusbandry.animals#milkRobotDoorSoundGroup")
              or  getXMLString(vanillaXml, "animalHusbandry.animals#milkRobotDoorSoundGroup")
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

    for sourceVai, outputVai in pairs(origToOutput) do
        if slots[outputVai] ~= nil then
            logf("ERROR: vanilla slot %d collides with %s — bridge inactive", outputVai, slots[outputVai].kind)
            slots = {} ; maxSlot = 0
            break
        end
        slots[outputVai] = { xml = vanillaXml, sourceIdx = sourceVai - 1, baseDir = vanillaBaseDir, modRoot = vanillaModDir, kind = "vanilla" }
        if outputVai > maxSlot then maxSlot = outputVai end
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
    if getXMLString(packXml, "animalHusbandry.sound.soundGroup(0)#name") ~= nil
       or getXMLString(vanillaXml, "animalHusbandry.sound.soundGroup(0)#name") ~= nil then
        table.insert(lines, '\t<sound>')
        local seen = {}
        emitSoundGroups(lines, packXml, seen, packBaseDir, synthHusbDir)
        emitSoundGroups(lines, vanillaXml, seen, vanillaBaseDir, synthHusbDir)
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

-- Hook FillTypeManager.loadMapData. RLRM appends its own loadBridgeFillTypes
-- (which calls scanAnimalPacks) to this same function. By appending our hook
-- first, our fn runs in the chain BEFORE RLRM's appended fn, letting us install
-- a scanAnimalPacks hook just in time. By that point RLMapBridge is defined.
-- We also install the applyPropertyOverrides accessory hook here for the same
-- timing reason.
local function installFillTypeManagerHook(modDir)
    if FillTypeManager == nil or FillTypeManager.loadMapData == nil then
        logf("FillTypeManager.loadMapData missing, hook skipped")
        return
    end
    if FillTypeManager.__cowBreedsVanillaBridgeHooked then return end

    FillTypeManager.loadMapData = Utils.appendedFunction(
        FillTypeManager.loadMapData,
        function(self)
            local RLMapBridge = getRLMapBridge()
            if RLMapBridge == nil or RLMapBridge.scanAnimalPacks == nil then
                logf("RLMapBridge not available at FillTypeManager.loadMapData; bridge inactive")
                return
            end
            if not RLMapBridge.__cowBreedsVanillaBridgeHooked then
                RLMapBridge.scanAnimalPacks = Utils.appendedFunction(
                    RLMapBridge.scanAnimalPacks,
                    function() manualLoadSynthPack(modDir) end
                )
                RLMapBridge.__cowBreedsVanillaBridgeHooked = true
                logf("installed scanAnimalPacks appended hook")
            end
            installVisualAccessoryHook(RLMapBridge)
        end
    )
    FillTypeManager.__cowBreedsVanillaBridgeHooked = true
end

local function regenerate(vanillaDir, tempDir, packModDir)
    -- Read vanilla source XMLs
    local cowXml = loadXMLFile("vanillaCow", ensureSlash(vanillaDir) .. "xmls/animals/cow.xml")
    if cowXml == nil then error("cannot load vanilla xmls/animals/cow.xml", 0) end
    local fillXml = loadXMLFile("vanillaFill", ensureSlash(vanillaDir) .. "xmls/fillTypes.xml")
    if fillXml == nil then delete(cowXml); error("cannot load vanilla xmls/fillTypes.xml", 0) end
    local vanillaHusbXml = loadXMLFile("vanillaHusb",
        ensureSlash(vanillaDir) .. "animals/domesticated/cattle/husbandryAnimalsCattle.xml")
    if vanillaHusbXml == nil then delete(cowXml); delete(fillXml); error("cannot load vanilla husbandryAnimalsCattle.xml", 0) end

    -- Read this mod's existing models/cow/animals.xml so we can put its 21 entries
    -- first in the combined husbandry config (preserving _pack subtype indices).
    local packHusbXml = loadXMLFile("packHusb",
        ensureSlash(packModDir) .. "models/cow/animals.xml")
    if packHusbXml == nil then
        delete(cowXml); delete(fillXml); delete(vanillaHusbXml)
        error("cannot load pack models/cow/animals.xml", 0)
    end
    local packCount = countHusbandryEntries(packHusbXml)
    logf("pack husbandry has %d animal entries", packCount)

    -- Pre-compute vanilla source-vai → output-vai map. Used by both
    -- buildAnimalsXml (so subType visuals reference correct output slots) AND
    -- buildCombinedHusbandryXml (so the husbandry XML emits matching entries).
    local origToOutput = allocateVanillaSlots(packHusbXml, VANILLA_HUSBANDRY_LIMIT)
    do
        local emitted = 0
        for vai = 1, 32 do if origToOutput[vai] then emitted = emitted + 1 end end
        logf("vanilla slot map: walked 1..%d, emitted %d entries", VANILLA_HUSBANDRY_LIMIT, emitted)
    end

    createFolder(tempDir)
    createFolder(tempDir .. "models")
    createFolder(tempDir .. "models/cow")
    createFolder(tempDir .. "translations")

    writeFile(tempDir .. "rlrm_pack.xml",  buildPackXml())
    writeFile(tempDir .. "animals.xml",    buildAnimalsXml(cowXml, vanillaDir, origToOutput))
    writeFile(tempDir .. "fillTypes.xml",  buildFillTypesXml(fillXml))
    -- Combined husbandry XML — referenced by configOverride in synth animals.xml.
    -- Asset paths inside this file are emitted relative to synthHusbDir using `..`
    -- traversal so the engine routes through both the pack and vanilla mod zips.
    local synthHusbDir = tempDir .. "models/cow/"
    writeFile(tempDir .. "models/cow/animals.xml",
        buildCombinedHusbandryXml(packHusbXml, vanillaHusbXml, packModDir, vanillaDir, synthHusbDir, origToOutput))
    local trans = buildTranslationsXml()
    writeFile(tempDir .. "translations/translation_en.xml", trans)
    writeFile(tempDir .. "translations/translation_de.xml", trans)

    delete(cowXml)
    delete(fillXml)
    delete(vanillaHusbXml)
    delete(packHusbXml)
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

local function setup()
    if g_modIsLoaded == nil then
        logf("g_modIsLoaded nil; bridge skipped")
        return
    end

    local actualVanillaName = findVanillaModName()
    if actualVanillaName == nil then
        logf("AnimalPackage not found; bridge skipped. Loaded mods follow:")
        local names = {}
        for name, _ in pairs(g_modIsLoaded) do table.insert(names, name) end
        table.sort(names)
        for _, name in ipairs(names) do logf("  loaded: %s", name) end
        return
    end
    if actualVanillaName ~= VANILLA_MOD then
        logf("matched AnimalPackage under alternate name: '%s'", actualVanillaName)
    end

    local vanillaDir = g_modNameToDirectory[actualVanillaName]
    if vanillaDir == nil or vanillaDir == "" then
        logf("vanilla mod directory unknown; bridge skipped")
        return
    end
    vanillaDir = ensureSlash(vanillaDir)

    local packModDir = g_currentModDirectory or g_modNameToDirectory[g_currentModName or ""]
    if packModDir == nil or packModDir == "" then
        logf("cannot resolve pack mod directory; bridge skipped")
        return
    end

    -- Synth dir lives INSIDE the pack mod's directory so relative `..` paths
    -- in the combined husbandry XML can navigate to the AnimalPackage mod
    -- (same drive guaranteed). Cross-drive `..` traversal doesn't work, and
    -- the engine doesn't recognize Windows drive letters (`F:/`) as absolute,
    -- so any path resolution must produce a relative path from synth/models/cow/
    -- back to the target asset.
    local tempDir = ensureSlash(packModDir) .. "_synth/"
    local vanillaVersion = readVanillaModVersion(vanillaDir)

    -- Shipping path: dev populates _synth/ once unzipped, commits it, players
    -- load the .zip read-only. If the bundle is already complete, skip regen
    -- entirely (writes would throw against a zipped mod dir).
    if synthIsComplete(tempDir) then
        logf("synth bundle present at %s; skipping regenerate (vanilla v%s)",
             tempDir, vanillaVersion)
    else
        logf("regenerating bridge (vanilla v%s, pack=%s)", vanillaVersion, packModDir)
        local rok, rerr = pcall(regenerate, vanillaDir, tempDir, packModDir)
        if not rok then
            logf("regenerate failed: %s; bridge inactive", tostring(rerr))
            return
        end
        logf("regenerated bridge files at %s", tempDir)
    end

    -- Hook RLRM's bridge directly. We do NOT add a fake mod to g_modIsLoaded:
    -- doing so caused other game code paths (g_onCreateUtil init, onCreate
    -- script registration) to crash when iterating loaded mods because our
    -- synthetic mod has no real modDesc.xml on disk. Instead, we wait until
    -- RLMapBridge is loaded (by hooking FillTypeManager.loadMapData), then
    -- append a manual pack-load to RLMapBridge.scanAnimalPacks so our pack
    -- ends up in RLMapBridge.activeBridges through RLRM's own code path.
    installFillTypeManagerHook(tempDir)
end

local ok, err = pcall(setup)
if not ok then
    logf("setup failed: %s", tostring(err))
end
