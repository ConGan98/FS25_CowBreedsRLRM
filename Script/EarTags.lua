-- =============================================================================
-- EarTags.lua  -  Cow Breeds Pack for RLRM
-- Real ear tags (models/earTags.i3d, models/earTagsRight.i3d; blender/build_eartags.py): the left ear's
-- official number tag printed as an Irish one (372 / <birth year>-<herd> / <check digit><animal number>)
-- or a UK one (UK / <herd mark> / <check digit><animal number>), the right ear's with the animal's name
-- in marker (an animal without a name wears the number tag there too). Each tag carries a row of glyph
-- quads (one letter tile of models/earTagGlyphs_diffuse.dds each, Script/EarTagGlyphs.lua); this lays them out (Script/EarTagLayout.lua) from RLRM's animal - its
-- farmId, uniqueId, birthday and name - instead of RLRM's own 3D text, in RLRM's text colours. RLRM's tag
-- colour stays on the tag (and goes on the stud's button behind the ear). Each tag is put on its ear once:
-- turned so its print faces the cow's front (some models hang it the other way), moved onto the ear and its
-- button set behind the ear, as measured per model family (Script/EarTagLayout.lua).
--
-- The style is the player's (both are Irish by default): cowEarTags IE|UK, kept in the mod's settings
-- folder. A tag file without the quads (another pack's animals) keeps RLRM's own text.
-- =============================================================================

CowEarTags = {
    style = "IE",
    installed = false,
}

local TAG = "[CowBreedsRLRM/EarTags]"
-- this mod's settings folder: the game points g_currentModSettingsDirectory at each mod only while sourcing it
-- (mods.lua) - read later, it is the last mod's
local SETTINGS_DIR = g_currentModSettingsDirectory
local SETTINGS = SETTINGS_DIR ~= nil and (SETTINGS_DIR .. "earTags.xml") or nil
local STYLES = { IE = true, UK = true }
local DEFAULT_YEAR = 24             -- RLRM's first year (RLConstants.START_YEAR.PARTIAL) when it can't be read
-- names: accented letters written plain (the marker tiles are A-Z a-z)
local PLAIN = { ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["Á"] = "A", ["É"] = "E", ["Í"] = "I",
    ["Ó"] = "O", ["Ú"] = "U", ["à"] = "a", ["è"] = "e", ["ä"] = "a", ["ö"] = "o", ["ü"] = "u", ["Ä"] = "A", ["Ö"] = "O",
    ["Ü"] = "U", ["ß"] = "ss", ["ñ"] = "n", ["ç"] = "c", ["ø"] = "o", ["å"] = "a", ["æ"] = "ae" }
local rlrm


-- ---------------------------------------------------------------------------
-- Numbers
-- ---------------------------------------------------------------------------

local function digitsOf(value)
    return (string.gsub(tostring(value or ""), "%D", ""))
end


local function lastDigits(value, n)
    local s = digitsOf(value)
    if #s >= n then return string.sub(s, -n) end
    return string.rep("0", n - #s) .. s
end


--- The official tag's herd line and big number for an animal: Irish <yy>-<5-digit herd> and the check digit
--- with the last 4 of its number; UK the 6-digit herd mark and its 6-figure number (RLRM's uniqueId is the
--- check digit and the padded animal number already).
function CowEarTags.numbers(animal, style)
    local uid = digitsOf(animal.uniqueId)
    if style == "UK" then
        return lastDigits(animal.farmId, 6), lastDigits(uid, 6)
    end

    local year = DEFAULT_YEAR
    local birthday = animal.getBirthday ~= nil and animal:getBirthday() or animal.birthday
    local start = rlrm ~= nil and rlrm.RLConstants ~= nil and rlrm.RLConstants.START_YEAR ~= nil
        and rlrm.RLConstants.START_YEAR.PARTIAL or DEFAULT_YEAR
    if type(birthday) == "table" and type(birthday.year) == "number" then year = birthday.year + start end
    local check = #uid > 0 and string.sub(uid, 1, 1) or "0"
    return string.format("%02d-%s", math.floor(year) % 100, lastDigits(animal.farmId, 5)), check .. lastDigits(uid, 4)
end


-- ---------------------------------------------------------------------------
-- Laying out the quads
-- ---------------------------------------------------------------------------

--- The tag's glyph quads g01, g02, ... (nil when the tag file has none). Cached on the visual by node.
local function tagQuads(visual, side)
    local node = side == "left" and visual.nodes.earTagLeft or visual.nodes.earTagRight
    if node == nil or node == 0 then return nil end
    visual.cetQuads = visual.cetQuads or {}
    local cached = visual.cetQuads[side]
    if cached == nil or cached.node ~= node then
        local list = {}
        for i = 1, 99 do
            local child = getChild(node, string.format("g%02d", i))
            if child == nil or child == 0 then break end
            list[i] = child
        end
        cached = { node = node, list = #list > 0 and list or false }
        visual.cetQuads[side] = cached
    end
    return cached.list or nil
end


--- A line's width in glyph cells.
local function measure(text, set)
    local width = 0
    for i = 1, #text do
        local info = set.chars[string.sub(text, i, i)]
        width = width + (info ~= nil and info[2] or set.space)
    end
    if #text > 1 then width = width + set.track * (#text - 1) end
    return width
end


--- One line onto the quads from used + 1 on, centred on line.z (reading runs along -z), on line.y's
--- baseline, squeezed / stretched to line.width within the set's fit (smaller still if it won't squeeze
--- in). Returns the quads used so far.
local function layLine(quads, used, text, line, ink)
    local set = CowEarTagGlyphs[line.set]
    local cell = line.cap / set.cap
    local width = measure(text, set) * cell
    if width <= 0 then return used end
    local fit = CowEarTagLayout.fit[line.set]
    local k = math.min(line.width / width, fit[2])
    if k < fit[1] then                      -- too long to squeeze into its width: smaller as well
        cell = cell * k / fit[1]
        width = width * k / fit[1]
        k = fit[1]
    end
    local pen = line.z + width * k / 2
    local y = line.y + (set.base - 0.5) * cell
    for i = 1, #text do
        local info = set.chars[string.sub(text, i, i)]
        local advance = (info ~= nil and info[2] or set.space) * cell * k
        if info ~= nil and used < #quads then
            used = used + 1
            local quad = quads[used]
            setTranslation(quad, CowEarTagLayout.face, y, pen - advance / 2)
            setScale(quad, 1, cell, cell * k)
            setShaderParameter(quad, "playScale", info[1], 0, CowEarTagGlyphs.cols, CowEarTagGlyphs.rows, false)
            setShaderParameter(quad, "colorScale", ink[1], ink[2], ink[3], nil, false)
            setVisibility(quad, true)
        end
        pen = pen - advance - set.track * cell * k
    end
    return used
end


local function hideFrom(quads, used)
    for i = used + 1, #quads do setVisibility(quads[i], false) end
end


--- The stud's button behind the ear in the tag's colour.
local function colourButton(tagNode)
    local button = getChild(tagNode, "button")
    if button == nil or button == 0 or not getHasShaderParameter(tagNode, "colorScale") then return end
    local r, g, b = getShaderParameter(tagNode, "colorScale")
    setShaderParameter(button, "colorScale", r, g, b, nil, false)
end


-- ---------------------------------------------------------------------------
-- The tag on the ear
-- ---------------------------------------------------------------------------

--- The model family the tag's placement was measured on (build_eartags.FAMILIES), nil for any other model
--- (Highland, buffalo, Brahman): by age as RLRM's age table gives the models - baby to 6 months, calf to 12 -
--- then the beef or dairy adult.
local OWN_PLACEMENT = { HIGHLAND = true, WATER_BUFFALO = true, BRAHMAN = true }
local function familyOf(animal)
    if animal == nil or OWN_PLACEMENT[animal.breed] then return nil end
    local age = animal.age or 0
    if age < 6 then return "baby" end
    if age < 12 then return "calf" end
    if CowVariants ~= nil and CowVariants.beefBreed ~= nil and CowVariants.beefBreed(animal) ~= nil then return "beef" end
    return "dairy"
end


--- Once per tag node: its print to the cow's front (some models hang the tag the other way round - turned
--- about its own upright, which keeps the stud's hole where it was), moved onto the ear and its stud's button
--- flat on the back of the ear, as measured for the model family.
local function placeTag(visual, side)
    local node = side == "left" and visual.nodes.earTagLeft or visual.nodes.earTagRight
    visual.cetPlaced = visual.cetPlaced or {}
    if node == nil or node == 0 or visual.cetPlaced[side] == node then return end
    visual.cetPlaced[side] = node
    local parent, root = getParent(node), visual.nodes.root

    if root ~= nil and root ~= 0 and parent ~= nil and parent ~= 0 then
        local ax, ay, az = localDirectionToWorld(node, 1, 0, 0)
        local fx, fy, fz = localDirectionToWorld(root, 0, 0, 1)             -- the animal's forward
        if ax * fx + ay * fy + az * fz < 0 then
            local ux, uy, uz = localDirectionToLocal(node, parent, 0, 1, 0)
            local zx, zy, zz = localDirectionToLocal(node, parent, 0, 0, 1)
            setDirection(node, -zx, -zy, -zz, ux, uy, uz)
        end
    end

    local layout = CowEarTagLayout
    local family = layout.families[familyOf(visual.animal) or ""]
    local fit = family ~= nil and family[side]
        or { 0, -layout.depth, layout.holeY, 0, -1, 0, 0, layout.depth - layout.back }
    if fit[1] ~= 0 and parent ~= nil and parent ~= 0 then
        setTranslation(node, localToLocal(node, parent, fit[1], 0, 0))
    end
    local button, pin = getChild(node, "button"), getChild(node, "pin")
    if button ~= nil and button ~= 0 then
        setTranslation(button, fit[2], fit[3], fit[4])
        setDirection(button, fit[5], fit[6], fit[7], 0, 1, 0)                -- flat on the back of the ear
    end
    if pin ~= nil and pin ~= 0 then
        setTranslation(pin, -layout.back, layout.holeY, 0)
        setScale(pin, math.max(fit[8], 0.001), 1, 1)
    end
end


--- The official tag's lines onto a tag's quads (the left tag, and the right one for an animal without a
--- name); hides the quads it doesn't use.
local function layOfficial(quads, animal, ink)
    local style = STYLES[CowEarTags.style] and CowEarTags.style or "IE"
    local herd, number = CowEarTags.numbers(animal, style)
    local used = 0
    for _, line in ipairs(CowEarTagLayout.official[style]) do
        local text = string.gsub(line.text, "{herd}", herd)
        text = string.gsub(text, "{number}", number)
        used = layLine(quads, used, text, line, ink)
    end
    hideFrom(quads, used)
end


--- The official number tag (left ear). False when the tag has no quads.
function CowEarTags.fillLeft(visual)
    local quads = tagQuads(visual, "left")
    if quads == nil or visual.animal == nil then return false end
    placeTag(visual, "left")
    layOfficial(quads, visual.animal, visual.leftTextColour or { 0, 0, 0 })
    colourButton(visual.nodes.earTagLeft)
    return true
end


--- The name tag (right ear): the name on one line, or two (split at the space nearest its middle) when one
--- would squeeze it too far; a single word stays on one line, smaller. An animal without a name wears the
--- official tag in this ear too. False when the tag has no quads.
function CowEarTags.fillRight(visual)
    local quads = tagQuads(visual, "right")
    if quads == nil or visual.animal == nil then return false end
    placeTag(visual, "right")
    local set = CowEarTagGlyphs.hand
    local name = tostring(visual.animal.getName ~= nil and visual.animal:getName() or "")
    for accented, plain in pairs(PLAIN) do name = string.gsub(name, accented, plain) end
    local kept = {}
    for i = 1, #name do
        local ch = string.sub(name, i, i)
        if set.chars[ch] ~= nil or ch == " " then table.insert(kept, ch) end
    end
    name = string.gsub(table.concat(kept), "%s+", " ")
    name = string.gsub(string.gsub(name, "^ ", ""), " $", "")

    local ink = visual.rightTextColour or { 0, 0, 0 }
    if name == "" then
        layOfficial(quads, visual.animal, ink)
        colourButton(visual.nodes.earTagRight)
        return true
    end
    local layout = CowEarTagLayout.name
    local used = 0
    do
        local one = layout.one
        local width = measure(name, set) * one.cap / set.cap
        if one.width / width >= 0.7 or not string.find(name, " ") then     -- one word stays whole
            used = layLine(quads, used, name, one, ink)
        else
            local cut, best = nil, nil
            for i = 2, #name - 1 do
                if string.sub(name, i, i) == " " and (best == nil or math.abs(i - #name / 2) < best) then
                    cut, best = i, math.abs(i - #name / 2)
                end
            end
            used = layLine(quads, used, string.sub(name, 1, cut - 1), layout.two[1], ink)
            used = layLine(quads, used, string.sub(name, cut + 1), layout.two[2], ink)
        end
    end
    hideFrom(quads, used)
    colourButton(visual.nodes.earTagRight)
    return true
end


-- ---------------------------------------------------------------------------
-- Hooks (CowVariants:installHooks calls this once RLRM is there)
-- ---------------------------------------------------------------------------

function CowEarTags.install(rlrmEnv)
    if CowEarTags.installed then return true end
    rlrm = rlrmEnv
    local visualClass = rlrm ~= nil and rlrm.VisualAnimal or nil
    if visualClass == nil or visualClass.setLeftEarTag == nil or visualClass.setRightEarTag == nil then return false end

    local setLeft, setRight, setColours = visualClass.setLeftEarTag, visualClass.setRightEarTag, visualClass.setEarTagColours
    visualClass.setLeftEarTag = function(visual, ...)
        local ok, done = pcall(CowEarTags.fillLeft, visual)
        if not ok then print(string.format("%s left tag error: %s", TAG, tostring(done))) end
        if ok and done then return end
        return setLeft(visual, ...)
    end
    visualClass.setRightEarTag = function(visual, ...)
        local ok, done = pcall(CowEarTags.fillRight, visual)
        if not ok then print(string.format("%s right tag error: %s", TAG, tostring(done))) end
        if ok and done then return end
        return setRight(visual, ...)
    end
    if setColours ~= nil then
        -- the text colours to the quads, the tag colour to the button
        visualClass.setEarTagColours = function(visual, ...)
            local result = setColours(visual, ...)
            pcall(CowEarTags.fillLeft, visual)
            pcall(CowEarTags.fillRight, visual)
            return result
        end
    end

    CowEarTags.installed = true
    return true
end


-- ---------------------------------------------------------------------------
-- The style: setting and console
-- ---------------------------------------------------------------------------

function CowEarTags.loadSettings()
    if SETTINGS == nil or not fileExists(SETTINGS) then return end
    local xml = loadXMLFile("cowEarTags", SETTINGS)
    if xml == nil or xml == 0 then return end
    local style = getXMLString(xml, "earTags#style")
    if style ~= nil and STYLES[string.upper(style)] then CowEarTags.style = string.upper(style) end
    delete(xml)
end


function CowEarTags.saveSettings()
    if SETTINGS == nil then return end
    createFolder(SETTINGS_DIR)
    local xml = createXMLFile("cowEarTags", SETTINGS, "earTags")
    if xml == nil or xml == 0 then return end
    setXMLString(xml, "earTags#style", CowEarTags.style)
    saveXMLFile(xml)
    delete(xml)
end


--- Every cattle visual's tags again (after a style change): the number tag, and the right ear's - the name, or
--- the number tag again on an animal without a name.
function CowEarTags.refreshAll()
    local count = 0
    if CowVariants ~= nil and CowVariants.forEachCow ~= nil then
        CowVariants.forEachCow(function(animal)
            if animal.visualAnimal ~= nil then
                local left = pcall(CowEarTags.fillLeft, animal.visualAnimal)
                local right = pcall(CowEarTags.fillRight, animal.visualAnimal)
                if left or right then count = count + 1 end
            end
        end)
    end
    return count
end


function CowEarTags:consoleCommandEarTags(style)
    style = style ~= nil and string.upper(style) or nil
    if style == nil or not STYLES[style] then
        return string.format("Ear tags: %s (cowEarTags IE | UK)", CowEarTags.style)
    end
    CowEarTags.style = style
    CowEarTags.saveSettings()
    return string.format("Ear tags now %s - %d animals retagged", style, CowEarTags.refreshAll())
end


function CowEarTags:loadMap(_)
    CowEarTags.loadSettings()
    addConsoleCommand("cowEarTags", "Ear tag style: IE (Irish) or UK", "consoleCommandEarTags", self)
    self.consoleCommandAdded = true
end


function CowEarTags:deleteMap()
    if self.consoleCommandAdded then
        removeConsoleCommand("cowEarTags")
        self.consoleCommandAdded = false
    end
end


CowEarTags.loadSettings()
addModEventListener(CowEarTags)
