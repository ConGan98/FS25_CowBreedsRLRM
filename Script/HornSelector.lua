-- Per-animal horn selection.
--
-- The shared "Horns" accessory (models/cow/Horns/Horns.i3d) holds three shapes:
--   Horns_ORI_Beef, Horns_ORI_Dairy, Horns_ORI_Highland
-- referenced into ADULT animal i3ds. All three are visible by default, so this
-- script shows at most ONE per animal (or none) based on the animal's breed, and
-- hides the rest.
--
-- Horn choice is PER BREED (not per model): breeds share visualAnimalIndex models,
-- so a shared model (e.g. the beef bull) can carry the reference and this script
-- decides per animal whether Hereford shows horns while Angus stays polled.
--
-- We hook RLRM's VisualAnimal:load (once per spawned visual) and locate the horn
-- shapes BY NAME under the animal root, so it's independent of where/how deep the
-- reference sits. Only ADULT models carry the reference, so calves are hornless
-- automatically (no shapes found -> no-op).
--
-- "Some horned, some not" is a deterministic per-animal roll seeded off the
-- animal's uniqueId, so an individual's horn state stays stable across reloads
-- (it never flickers) while the herd shows a natural mix.

HornSelector = { installed = false }

local TAG = "[CowBreedsRLRM/HornSelector]"

-- ===========================================================================
-- BREED -> HORN CONFIG   (tweak freely)
--   type      = which horn shape to show ("beef" | "dairy" | "highland")
--   cow, bull = % chance an ADULT of that gender is horned (0..100)
-- Any breed NOT listed here is polled (all horns hidden).
-- Runtime breed strings confirmed from RLRM/pack config.
-- ===========================================================================
local BREED_HORNS = {
    -- Highland: always horned
    HIGHLAND         = { type = "highland", cow = 100, bull = 100 },
    -- Mostly horned dairy
    SWISS_BROWN      = { type = "dairy",    cow = 85,  bull = 95  },
    KERRY_PACK       = { type = "dairy",    cow = 85,  bull = 95  },
    -- Low chance beef (bulls hornier)
    HEREFORD         = { type = "beef",     cow = 10,  bull = 25  },
    LIMOUSIN         = { type = "beef",     cow = 10,  bull = 25  },
    CHAROLAIS_PACK   = { type = "beef",     cow = 10,  bull = 25  },
    SHORTHORN_PACK   = { type = "beef",     cow = 10,  bull = 25  },
    BRITISHBLUE_PACK = { type = "beef",     cow = 10,  bull = 25  },
    SIMMENTAL_PACK   = { type = "beef",     cow = 10,  bull = 25  },
    -- Everything else (Holstein, Red Holstein, Ayrshire, Jersey, Guernsey,
    -- Shorthorn Milkers, Angus, Red Angus, Irish Moiled, Belted Galloway,
    -- Water Buffalo, ...) = polled -> not listed.
}

-- Deterministic 0..99 from a string. Stable across reloads (no math.random),
-- so each animal's horned/polled state is fixed for its lifetime.
local function stableRoll(str)
    local h = 5381
    for i = 1, #str do
        h = (h * 33 + string.byte(str, i)) % 2147483647
    end
    return h % 100
end

-- Recursively collect the three horn shapes beneath `node`.
local function findHorns(node, found)
    if node == nil or node == 0 then return end
    local n = getNumOfChildren(node)
    for i = 0, n - 1 do
        local child = getChildAt(node, i)
        if child ~= nil and child ~= 0 then
            local name = getName(child)
            if name == "Horns_ORI_Beef" then found.beef = child
            elseif name == "Horns_ORI_Dairy" then found.dairy = child
            elseif name == "Horns_ORI_Highland" then found.highland = child end
            findHorns(child, found)
        end
    end
end

-- Log each distinct breed once (to catch any breed-string mismatch without spam).
local loggedBreeds = {}

local function applyHorns(instance)
    if instance == nil or instance.nodes == nil or instance.animal == nil then return end
    local root = instance.nodes.root
    if root == nil or root == 0 then return end

    local found = {}
    findHorns(root, found)
    if found.beef == nil and found.dairy == nil and found.highland == nil then
        return -- this model has no horns reference
    end

    local animal = instance.animal
    local breed = animal.breed
    local cfg = BREED_HORNS[breed]

    local showType = nil
    if cfg ~= nil then
        local chance = (animal.gender == "male") and cfg.bull or cfg.cow
        if chance >= 100 or stableRoll(tostring(animal.uniqueId) .. "|horn") < chance then
            showType = cfg.type
        end
    end

    if found.beef ~= nil then setVisibility(found.beef, showType == "beef") end
    if found.dairy ~= nil then setVisibility(found.dairy, showType == "dairy") end
    if found.highland ~= nil then setVisibility(found.highland, showType == "highland") end

    if not loggedBreeds[tostring(breed)] then
        loggedBreeds[tostring(breed)] = true
        print(string.format("%s breed=%s gender=%s -> %s (cfg=%s)",
            TAG, tostring(breed), tostring(animal.gender),
            showType or "polled", cfg ~= nil and "mapped" or "unmapped"))
    end
end

function HornSelector:loadMap(name)
    self:update()
end

function HornSelector:update(dt)
    if self.installed then return end

    local modTable = FS25_RealisticLivestockRM
    if modTable == nil or modTable.VisualAnimal == nil or modTable.VisualAnimal.load == nil then
        return
    end

    local originalLoad = modTable.VisualAnimal.load
    modTable.VisualAnimal.load = function(instance)
        originalLoad(instance)
        local ok, err = pcall(applyHorns, instance)
        if not ok then print(string.format("%s applyHorns error: %s", TAG, tostring(err))) end
    end

    self.installed = true
    print(string.format("%s installed VisualAnimal.load hook", TAG))
end

addModEventListener(HornSelector)
