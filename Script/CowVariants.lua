-- =============================================================================
-- CowVariants.lua  -  Cow Breeds Pack for RLRM
-- Body, udder and male parts of every adult dairy and beef animal, shown through
-- RLRM's VisualAnimal.
--
-- BEEF (every beef breed, models/cow/angus/cattleAngus*.i3d): the same idea, with a
-- weight level and the breed's build in every body name:
--   F_<stage>[_preg|_preg_late]_<lean|normal|heavy>_<native|continental|double>
--   M_<young|adult|old|pedigree>[_steer]_<weight>_<build>, each male body with its
--   own <body>_sack (scrotum, or a steer's pouch) and <body>_sheath
--   F_udder_<stage>_<state> as for the dairy cows
-- The weight level is the animal's RLRM weight against what its breed weighs at its
-- age; the build is the breed's (CONFIG.beef.breeds). The size is a ladder of 5%
-- steps (young one down, pedigree two up, compact breeds one down, tall breeds one
-- up), kept to steps -1 .. +2 - the engine loads at most 32 model entries per
-- species. Every step but the stock one is its own model + 1.05^step animation copy
-- on its own slot (CONFIG.beef.slots), and a beef animal on slot 7 (cows and bulls)
-- is sent to its step's slot like a pedigree dairy bull. Both sexes of a size share
-- its model. (Built in blender/: inject_beef.py, make_beef_anims.py; the size table
-- there is blender/beef_sizes.py - keep the two the same.)
--
-- DAIRY SIZES (models/cow/holstein/cattleHolsteinStepM<1..5>.i3d): as the beef, a ladder of 5%
-- steps - young one down, pedigree two up, and the breed's height class: large (Holstein, Red
-- Holstein, Brown Swiss) at the stock size, medium (Shorthorn Milkers, Ayrshire, Guernsey) two down,
-- small (Jersey, Kerry) four down (CONFIG.dairy; blender/dairy_sizes.py - keep the two the same).
-- Each size is the dairy model scaled whole with the variants of its stages, its own scaled clips and
-- slot; a dairy animal on slot 2 is sent to its size's slot - a large pedigree bull to the pedigree
-- slot 22, a medium one stays on 2, a small one goes to the medium adults' size.
--
-- HIGHLAND BULLS: the Highland calf and adult models (slots 20 / 21, both sexes) carry the bull's
-- body as M_highland next to the stock body - shown on males (blender/merge_highland_bulls.py).
--
-- BEEF CALVES 6-12 months (models/cow/angus/cattleCalfStep<0..3>.i3d): in the calf model's
-- cattleCalf group, next to the stock "calf" body,
--   C_F_<early|late>_<weight>_<build>              heifer calves (the stock udder)
--   C_M_<early|late>[_steer]_<weight>_<build>      bull / steer calves, each with its
--   <body>_groin, <body>_sack and <body>_sheath    bare groin skin, scrotum (a steer's pouch), sheath
-- early 6-9 months, late 9-12. Four sizes: the age half plus the breed's height class
-- (compact / standard / tall), 9% a step (CONFIG.calf; blender/calf_sizes.py - keep the two the
-- same), each its own model + scaled clips on its own slot. RLRM's age table gives every 6-12 month
-- beef calf the calf slot 8; this script sends it to its size's slot like the adults. The 3-6 month
-- baby is a bigger copy of the stock baby on slot 26 - this script sends a baby there from slot 9 (not a
-- visual stage: RLRM's map bridge inserts a stage that RLRM's own subtypes - Holstein, Brown Swiss, Angus,
-- Hereford, Limousin - don't have WITHOUT its textureIndexes, so those babies drew any coat tile). Only
-- the first two months wobble on the baby clips: from 2 months the stock baby's own entry 4 and the
-- bigger baby play the calf clips fitted to them (the baby skeleton is the calf's x 2/3). Both baby
-- files carry bull and steer babies, C_M_baby[_steer]_<native|dairy> + _groin / _sack / _sheath (the
-- calves' male parts at baby size, blender/build_baby_variants.py); a heifer keeps the stock body.
--
-- DAIRY CALVES share the beef calf and baby models (the same mesh, UVs and skeleton), sized by their
-- age half plus the dairy height class (small one below the beef ladder's first step - its own file,
-- slot 6 - medium on it, large one up). A file a dairy size uses carries the native-build bodies again
-- on the dairy materials as the "dairy" build (C_F_<age>_<weight>_dairy ...), and every calf and baby
-- file a dairyCoat group of D_<name> copies of its stock shapes (body, eyes, teeth, tongue, hair) on
-- them: a dairy calf or baby shows those instead of the beef ones (blender/calf_sizes.py,
-- inject_calf.py). Nothing swaps a material at runtime - that rendered the animal black in game.
--
-- The model: models/cow/holstein/cattleHolstein.i3d, slot 2, used by the adult dairy
-- cows AND bulls (the bull subtypes point at slot 2 too; their old slot 13 now holds
-- a beef size). Next to the stock "body" it carries, all hidden and
-- all on the one skeleton (so every one plays the stock adult animations):
--   F_<young|adult|old>[_preg|_preg_late]   cow bodies (no udder at LOD0/LOD1)
--   F_udder_<stage>_<heifer|heifer_springing|lactating|dry|springing>
--   M_<young|adult|old|pedigree>, M_<young|adult|old>_steer   bull / steer bodies
--   M_scrotum_<stage>, M_cod_<stage> (steer pouch), M_sheath
-- in each LOD group it was built for (LOD2 has only the plain stage bodies, which
-- keep their udder there). This script shows the right ones per animal and hides
-- the stock body. If it doesn't run, the stock cow body shows, as before.
--
-- The pedigree bull is bigger, so he has his own slot (22, models/cow/animals.xml):
-- holstein/cattleHolsteinPedigree.i3d, the pedigree body and parts 1.1x on a 1.1x
-- skeleton, played by a 1.1x copy of the adult animation (a scale on the animal in
-- game breaks the clips, which store bone positions at cow size). RLRM picks a slot
-- by subtype and age only, so this script sends pedigree bulls from the dairy adult
-- slot 2 to 22 - and back when they stop being one (castrated) - by wrapping
-- AnimalSystem:getVisualAnimalIndexByAge, which RLRM calls right after asking the
-- animal its subtype.
--
-- The state: none of our own. Everything comes from RLRM's animal fields, which RLRM
-- saves and streams, so every machine works it out the same way:
--   gender, age (months), isCastrated, isParent (has calved), isLactating,
--   isPregnant + reproduction (pregnancy progress 0-100), genetics.
-- Re-checked:
--   * when RLRM builds the animal's visual  - wraps VisualAnimal.load
--   * right after a castration              - wraps AnimalCastrateEvent.sendEvent / .run
--   * every new day and month               - pregnancy, calving, lactation and age
-- An animal on the wrong slot after one of those (a bull just turned pedigree, a
-- castrated pedigree) gets its pen's visuals rebuilt, which moves it.
-- Hooks go in at source time (a husbandry ready on the first frame builds its visuals
-- before any mod listener runs); if RLRM isn't there yet, loadMap retries and sweeps.
--
-- COLLAR (models/collar.i3d, blender/build_collar.py): the activity-monitor collar RLRM shows for a
-- monitored animal, one for every adult body - a strap per group of necks scaled to the body's own,
-- four yellow number tags down each side with the animal's last four ID digits, a sensor and a buckle,
-- each placed per body from Script/CollarFits.lua. Calves and Highlands keep their ear monitor.
--
-- EAR TAGS: Script/EarTags.lua prints the real Irish / UK number tag and the name tag (installed from here).
--
-- PRICES: the animals these models show as top quality sell as such - RLRM's sale value
-- (Animal:getSellPrice, which its dealer marks up too) times CowVariants.priceFactor:
-- a pedigree bull as breeding stock, a beef animal on the heavy model per kg of its
-- extra weight plus a top-grade premium (CONFIG.prices).
--
-- Console:  cowVariants          re-check every adult cattle animal now and report the counts
--           cowVariantsWeights   every beef animal's weight against its breed's, the level and value factor
-- =============================================================================

CowVariants = {
    hooksInstalled = false,
}

local TAG = "[CowBreedsRLRM/CowVariants]"
local STOCK_BODY = "body"
local LOD_GROUPS = { LOD0 = true, LOD1 = true, LOD2 = true }
local CALF_GROUP, CALF_BODY = "cattleCalf", "calf"         -- the calf models' mesh group and stock body
-- the Highland models' mesh groups and stock bodies (adult, calf); the bull body in both is M_highland
local HIGHLAND_GROUPS = { ["01_LOD0"] = "01_body", cattleCalfHighland = "body" }
local HIGHLAND_BULL = "M_highland"
-- the water buffalo's and Brahman's mesh groups and stock bodies - the adult's, the calf's and baby's; a male
-- shows the bull body (build_male_variants.py) with its groin, its sheath and, entire, its scrotum, a bull calf
-- his scrotum and the buffalo calf his sheath (build_male_calves.py) on the stock calf body
local PLAIN_GROUPS = { water_buffalo = "water_buffalo_body", Brahman = "body",
                       geo = "WaterBuffaloCalf", Hair = "WaterBuffaloCalf", BrahmanCalf = "brahmanBody" }
local PLAIN_BULLS = { WATER_BUFFALO = "M_buffalo", BRAHMAN = "M_brahman" }
local TILE_PARAM = "atlasInvSizeAndOffsetUV"
local COAT_GROUP, COAT_PREFIX = "dairyCoat", "D_"  -- the calf / baby files' dairy copies of their stock shapes

-- ---------------------------------------------------------------------------
-- Tuning (months / RLRM pregnancy progress 0-100 / RLRM overall genetics 0-1)
-- ---------------------------------------------------------------------------
CowVariants.CONFIG = {
    cowStages = { { minAge = 72, stage = "old" }, { minAge = 24, stage = "adult" }, { minAge = 0, stage = "young" } },
    bullStages = { { minAge = 60, stage = "old" }, { minAge = 24, stage = "adult" }, { minAge = 0, stage = "young" } },
    pregnantFrom = 40,          -- belly starts to show
    pregnantLateFrom = 75,      -- full belly
    heiferSpringingFrom = 70,   -- a heifer's udder fills in the last part of her first pregnancy
    cowSpringingFrom = 85,      -- a dry cow bags up again close to calving
    pedigree = {
        minAge = 24,
        minGenetics = 0.8,      -- RLRM "Very Good" overall genetics or better
        -- of the bulls with the genetics, the share that also have the type (conformation) for it - fixed per
        -- bull by his herd and ID number, so selective breeding can't make every bull one (user, 2026-10-30)
        typeChance = 0.25,
        -- His size comes from his own slot, not a scale at runtime. Tested in game (2026-10-22/23), a
        -- scale on the animal's root node holds but breaks his animation; on cattleSkeleton the engine
        -- resets it, on cow_root_skin_jnt the animation does.
        slot = { from = 2, to = 22 },       -- dairy adult slot (bulls too) -> pedigree slot (models/cow/animals.xml)
    },
    -- Bulls wear the bum ID where the bull model had it (fuller rump) - and the old collar where it was, if
    -- models/collar.i3d is the old one (the new one fits itself, fitCollar).
    -- translation (m), rotation (degrees), scale - from the stock cattleHolsteinBull.i3d.
    bullAccessories = {
        monitor = { t = { 0.173, 0.289, 0 }, r = { 24.185, 90, 0 }, s = { 1.5, 1.1, 1 } },
        bumId = { t = { -0.228, 0.149, 0.06 }, r = { -179.055, -3.776, 172.98 }, s = { 1, 1, 1 } },
    },

    beef = {
        -- RLRM breed -> height class (size) and build (muscling)
        breeds = {
            ANGUS = { height = "standard", build = "native" },
            REDANGUS_PACK = { height = "standard", build = "native" },
            HEREFORD = { height = "standard", build = "native" },
            SHORTHORN_PACK = { height = "standard", build = "native" },
            BELTEDGALLOWAY_PACK = { height = "compact", build = "native" },
            IRISHMOILED_PACK = { height = "compact", build = "native" },
            CHAROLAIS_PACK = { height = "tall", build = "continental" },
            LIMOUSIN = { height = "tall", build = "continental" },
            SIMMENTAL_PACK = { height = "tall", build = "continental" },
            BRITISHBLUE_PACK = { height = "standard", build = "double" },
        },
        step = 1.05,                                         -- size per step
        stageStep = { young = -1, adult = 0, old = 0, pedigree = 2 },
        heightStep = { compact = -1, standard = 0, tall = 1 },
        -- the engine loads at most 32 model entries per species, so only four sizes: steps -1 .. +2
        minStep = -1,
        maxStep = 2,
        -- size step -> slot (models/cow/animals.xml); step 0 is the stock size on the beef slot 7. -1 and
        -- +1 reuse the entries of the old separate bull slots 13 and 15 (bulls now share their cows' 2 / 7)
        slots = { [-1] = 13, [1] = 15, [2] = 23 },
        baseSlots = { [7] = true },
        -- RLRM weight against what the breed weighs at that age (CowVariants.expectedWeight's band):
        -- lean below leanBelow x its low end, heavy from heavyFrom x its high end (steers finish sooner)
        weight = { leanBelow = 0.92, heavyFrom = 1.08, steerHeavyFrom = 1.04 },
        -- where cattleAngusBull.i3d had the collar and bum ID, at the stock size (x the size of the slot)
        bullAccessories = {
            monitor = { t = { 0.195, 0.291, 0 }, r = { 22.774, 90, 0 }, s = { 1.5, 1.1, 1 } },
            bumId = { t = { -0.235, 0.142, 0.055 }, r = { -178.65, -7.34, 166.768 }, s = { 1, 1, 1 } },
        },
    },

    dairy = {
        -- RLRM breed -> height class; a breed not listed on the dairy slot counts as large
        breeds = {
            HOLSTEIN = "large", REDHOLSTEIN_PACK = "large", SWISS_BROWN = "large",
            SHORTHORNMILKERS_PACK = "medium", AYRSHIRE_PACK = "medium", GUERNSEY_PACK = "medium",
            JERSEY_PACK = "small", KERRY_PACK = "small",
        },
        step = 1.05,
        stageStep = { young = -1, adult = 0, old = 0, pedigree = 2 },
        heightStep = { large = 0, medium = -2, small = -4 },
        -- size step -> slot (models/cow/animals.xml); 0 is the dairy slot 2 itself, +2 the pedigree slot
        slots = { [-5] = 31, [-4] = 30, [-3] = 29, [-2] = 28, [-1] = 27, [2] = 22 },
        baseSlot = 2,
    },

    -- Beef and dairy calves 6-12 months (months; RLRM's age table moves them to the adult slots at 12)
    calf = {
        minAge = 6,
        adultAge = 12,
        lateFrom = 9,                                        -- early 6-9, late 9-12
        ageStep = { early = 0, late = 1 },
        heightStep = { compact = 0, standard = 1, tall = 2 },
        dairyHeightStep = { small = -1, medium = 0, large = 1 },   -- by CONFIG.dairy.breeds
        dairyBuild = "dairy",                                -- a dairy calf's bodies: the native ones in the dairy coat
        -- size step -> slot (models/cow/animals.xml); 8 and 16 are the old heifer / bull calf entries,
        -- 6 the old dairy calf entry (step -1 is the small dairy breeds' alone)
        slots = { [-1] = 6, [0] = 24, [1] = 8, [2] = 16, [3] = 25 },
        baseSlots = { [8] = true, [16] = true },             -- what RLRM's age table gives a calf (16: old saves)
        -- babies: RLRM's age table gives 0-6 months the baby slot (the wobbly baby clips); from walkBabyFrom
        -- months the same baby on the calf clips, from bigBabyFrom the bigger baby (on the calf clips too)
        babySlot = 9, walkBabySlot = 4, walkBabyFrom = 2, bigBabySlot = 26, bigBabyFrom = 3,
    },

    -- Sale value x this on top of RLRM's (the per-kg ladder in animals.xml prices a standard animal)
    prices = {
        -- a pedigree bull sells as breeding stock: x atMin at Very Good overall genetics (0.8), up to
        -- x atMax at the best (1.0), on top of RLRM's own meat-quality term (about +35% / +70% there);
        -- the full premium until fullUntil months, none by endAge (RLRM's last breeding month for a bull)
        pedigree = { atMin = 1.5, atMax = 3.0, fullUntil = 84, endAge = 132 },
        -- a beef animal on the heavy model is paid for every kg over its breed's band (RLRM's weight
        -- term only pays ~40% of a kg, so weightExponent tops it up) and grade more per kg
        heavy = { grade = 0.15, weightExponent = 0.6 },
        skipBreeds = { WATER_BUFFALO = true },
    },
}

local function stageFor(stages, age)
    for _, s in ipairs(stages) do
        if age >= s.minAge then return s.stage end
    end
    return stages[#stages].stage
end


--- RLRM's overall genetics factor (RLGenetics.aggregate: sum / (MAX * count), 0.8 = Very Good).
local function geneticsFactor(animal)
    local genetics = animal.genetics
    if genetics == nil then return 0 end

    local rlrm = FS25_RealisticLivestockRM
    local rlg = rlrm ~= nil and rlrm.RLGenetics or nil
    if rlg ~= nil and rlg.aggregate ~= nil then
        local ok, factor = pcall(rlg.aggregate, genetics)
        if ok and type(factor) == "number" then return factor end
    end

    local sum, count = 0, 0
    for _, key in ipairs({ "metabolism", "quality", "health", "fertility", "productivity" }) do
        if type(genetics[key]) == "number" then
            sum, count = sum + genetics[key], count + 1
        end
    end
    return count > 0 and sum / (1.75 * count) or 0
end


--- The bull's type roll, 0..1 and fixed for life: a hash of his herd number and ID (RLRM keeps both as
--- strings, saved and synced, so every player gets the same). Consecutive IDs land far apart.
function CowVariants.typeRoll(animal)
    local key = tostring(animal.farmId or "") .. ":" .. tostring(animal.uniqueId or "")
    local h = 5381
    for i = 1, #key do h = (h * 33 + string.byte(key, i)) % 2147483647 end
    for _ = 1, 3 do h = (h * 48271) % 2147483647 end      -- products stay under 2^47: exact in doubles
    return h / 2147483647
end


--- An entire bull old enough with Very Good genetics (or better) and the type for it (CONFIG typeChance).
function CowVariants.isPedigree(animal)
    local cfg = CowVariants.CONFIG.pedigree
    return animal.gender == "male" and not animal.isCastrated and (animal.age or 0) >= cfg.minAge
        and geneticsFactor(animal) >= cfg.minGenetics and CowVariants.typeRoll(animal) < cfg.typeChance
end


--- A text from RLRM's text table, where MapBridge.loadPackTranslations puts this pack's translations (the
--- pack's own table has none) next to RLRM's; the fallback when it isn't there.
local RLRM_TEXTS = "FS25_RealisticLivestockRM"
local function rlrmText(key, fallback)
    if g_i18n ~= nil and g_i18n:hasText(key, RLRM_TEXTS) then return g_i18n:getText(key, RLRM_TEXTS) end
    return fallback
end


--- A pedigree bull's "Pedigree: Yes" row in RLRM's info lists (Animal:addInfos: the RL menu's detail pane,
--- the Animals page - which draws each row a bar, his a full green one).
function CowVariants.addPedigreeInfo(animal, infos)
    if animal.animalTypeIndex ~= AnimalType.COW or not CowVariants.isPedigree(animal) then return end
    if animal.cvInfoPedigree == nil then
        animal.cvInfoPedigree = { title = rlrmText("cvb_ui_pedigree", "Pedigree"), valueText = rlrmText("rl_ui_yes", "Yes"),
                                  value = 1, ratio = 1, invertedBar = true }
    end
    table.insert(infos, animal.cvInfoPedigree)
end


--- The same line in the look-at box.
function CowVariants.showPedigreeInfo(animal, box)
    if animal.animalTypeIndex ~= AnimalType.COW or not CowVariants.isPedigree(animal) then return end
    box:addLine(rlrmText("cvb_ui_pedigree", "Pedigree"), rlrmText("rl_ui_yes", "Yes"))
end


--- The beef breed config of an animal, nil for the dairy (and other) breeds.
function CowVariants.beefBreed(animal)
    return CowVariants.CONFIG.beef.breeds[animal.breed or ""]
end


--- What a well-kept animal of its breed weighs at its age, as a band (low, high). RLRM grows animals
--- on one curve (Animal:updateWeight: cows at 0.6 of the rate, steers 1.15x, faster the younger) and
--- gives bought ones a straight line (Animal.new), so for young stock the two differ a lot - anything
--- between them is normal. Both stop at the breed's target weight, which RLRM holds adults near.
function CowVariants.expectedWeight(animal, subType)
    local target, minWeight = subType.targetWeight, subType.minWeight or 0
    local adultMonth = (subType.reproductionMinAgeMonth or 12) * 1.5
    local age = math.max(animal.age or 0, 0)
    local rate = (animal.gender == "female" and 0.6 or 1.0) * (animal.isCastrated and 1.15 or 1.0)
    local grown = minWeight + (target - minWeight) * rate * (age + (adultMonth * age - age * age / 2) / 75) / adultMonth
    local bought = minWeight + (target - minWeight) * math.min(age, 20) / adultMonth
    grown, bought = math.min(grown, target), math.min(bought, target)
    return math.min(grown, bought), math.max(grown, bought)
end


--- lean / normal / heavy: RLRM weight against what the breed weighs at the animal's age.
function CowVariants.weightLevel(animal)
    local cfg = CowVariants.CONFIG.beef.weight
    local ok, subType = pcall(animal.getSubType, animal)
    if not ok or subType == nil or subType.targetWeight == nil or animal.weight == nil then return "normal" end

    local low, high = CowVariants.expectedWeight(animal, subType)
    if low <= 0 then return "normal" end
    animal.cvWeightBand = { low, high }
    if animal.weight < low * cfg.leanBelow then return "lean" end
    if animal.weight >= high * (animal.isCastrated and cfg.steerHeavyFrom or cfg.heavyFrom) then return "heavy" end
    return "normal"
end


--- What RLRM's sale value is multiplied by: a pedigree bull's breeding value, a heavy beef animal's
--- weight and grade premium, 1 for everything else.
function CowVariants.priceFactor(animal)
    local cfg = CowVariants.CONFIG.prices
    if animal.animalTypeIndex ~= AnimalType.COW or cfg.skipBreeds[animal.breed or ""] then return 1 end

    if CowVariants.isPedigree(animal) then
        local p, minGenetics = cfg.pedigree, CowVariants.CONFIG.pedigree.minGenetics
        local g = math.min((geneticsFactor(animal) - minGenetics) / (1 - minGenetics), 1)
        local fade = math.min(math.max((p.endAge - (animal.age or 0)) / (p.endAge - p.fullUntil), 0), 1)
        return 1 + (p.atMin + (p.atMax - p.atMin) * g - 1) * fade
    end

    if CowVariants.beefBreed(animal) ~= nil and CowVariants.weightLevel(animal) == "heavy" then
        local h = cfg.heavy
        return (1 + h.grade) * (animal.weight / animal.cvWeightBand[2]) ^ h.weightExponent
    end
    return 1
end


--- The dairy height class of an animal (CONFIG.dairy.breeds), nil for the beef (and other) breeds.
function CowVariants.dairyBreed(animal)
    return CowVariants.CONFIG.dairy.breeds[animal.breed or ""]
end


--- A beef or dairy calf's age half - "early" (6-9 months) or "late" (9-12) - nil outside the calf months
--- or for another breed.
function CowVariants.calfAge(animal)
    local cfg = CowVariants.CONFIG.calf
    local age = animal.age or 0
    if CowVariants.beefBreed(animal) == nil and CowVariants.dairyBreed(animal) == nil then return nil end
    if age < cfg.minAge or age >= cfg.adultAge then return nil end
    return age >= cfg.lateFrom and "late" or "early"
end


--- What an animal shows: { body = node name, parts = { node names }, stage, male, steer, beef, dairy, calf, highland }.
function CowVariants.choose(animal)
    local cfg = CowVariants.CONFIG
    local age = animal.age or 0

    -- Highland: the calf and adult models carry the bull's body (steers keep it, as on the old bull
    -- models); a cow shows the stock body ("F_highland" names no node)
    if animal.breed == "HIGHLAND" then
        local male = animal.gender == "male"
        return { body = male and HIGHLAND_BULL or "F_highland", parts = {}, male = male,
                 steer = male and animal.isCastrated == true, highland = true }
    end

    -- water buffalo, Brahman: the cow's adult model carries the bull body and parts, the calf and baby models
    -- the bull calf's on their stock body; a cow shows the stock body ("F_plain" names no node). Each model
    -- shows the parts it has (a calf model hasn't the bull body: its stock body stays)
    local bull = PLAIN_BULLS[animal.breed]
    if bull ~= nil then
        local male = animal.gender == "male"
        local steer = male and animal.isCastrated == true
        local parts = not male and {} or steer and { bull .. "_groin", bull .. "_sheath", bull .. "Calf_sheath" }
            or { bull .. "_groin", bull .. "_sack", bull .. "_sheath", bull .. "Calf_sack", bull .. "Calf_sheath" }
        return { body = male and bull or "F_plain", parts = parts, male = male, steer = steer, plain = true }
    end

    local beef = CowVariants.beefBreed(animal)
    local dairy = CowVariants.dairyBreed(animal) ~= nil

    -- a baby (to 6 months) on the calf baby models: a heifer the stock body, a bull or steer the male baby
    -- (C_M_baby[_steer]_<native|dairy> with its groin, sack and sheath) - a dairy one in the dairy coat
    if age < cfg.calf.minAge and (beef ~= nil or dairy) then
        if animal.gender == "male" then
            local steer = animal.isCastrated == true
            local body = "C_M_baby" .. (steer and "_steer" or "") .. "_" .. (beef ~= nil and "native" or cfg.calf.dairyBuild)
            return { body = body, parts = { body .. "_groin", body .. "_sack", body .. "_sheath" }, stage = "baby",
                     male = true, steer = steer, beef = beef ~= nil, dairy = beef == nil, calf = true, baby = true }
        end
        return { body = "C_baby", parts = {}, stage = "baby", male = false, beef = beef ~= nil,
                 dairy = beef == nil, calf = true, baby = true }
    end

    local tail = beef ~= nil and ("_" .. CowVariants.weightLevel(animal) .. "_" .. beef.build) or ""

    local calf = CowVariants.calfAge(animal)
    if calf ~= nil then
        -- a dairy calf wears the dairy build's bodies (the native ones in the dairy coat) at its weight
        local calfTail = beef ~= nil and tail or ("_" .. CowVariants.weightLevel(animal) .. "_" .. cfg.calf.dairyBuild)
        if animal.gender == "male" then
            local steer = animal.isCastrated == true
            local body = "C_M_" .. calf .. (steer and "_steer" or "") .. calfTail
            return { body = body, parts = { body .. "_groin", body .. "_sack", body .. "_sheath" }, stage = calf,
                     male = true, steer = steer, beef = beef ~= nil, dairy = beef == nil, calf = true }
        end
        return { body = "C_F_" .. calf .. calfTail, parts = {}, stage = calf, beef = beef ~= nil, dairy = beef == nil,
                 calf = true }
    end

    if animal.gender == "male" then
        local stage = stageFor(cfg.bullStages, age)
        local steer = animal.isCastrated == true
        if not steer and CowVariants.isPedigree(animal) then stage = "pedigree" end
        local body = "M_" .. stage .. (steer and "_steer" or "") .. tail
        local parts
        if beef ~= nil then
            parts = { body .. "_sack", body .. "_sheath" }
        else
            parts = { "M_sheath", (steer and "M_cod_" or "M_scrotum_") .. stage }
        end
        return { body = body, parts = parts, stage = stage, male = true, steer = steer, beef = beef ~= nil }
    end

    local stage = stageFor(cfg.cowStages, age)
    local progress = animal.isPregnant and (animal.reproduction or 0) or -1
    local body = "F_" .. stage
    if progress >= cfg.pregnantLateFrom then
        body = body .. "_preg_late"
    elseif progress >= cfg.pregnantFrom then
        body = body .. "_preg"
    end
    body = body .. tail

    local udder
    if not animal.isParent then
        udder = progress >= cfg.heiferSpringingFrom and "heifer_springing" or "heifer"
    elseif animal.isLactating then
        udder = "lactating"
    elseif progress >= cfg.cowSpringingFrom then
        udder = "springing"
    else
        udder = "dry"
    end

    return { body = body, parts = { "F_udder_" .. stage .. "_" .. udder }, stage = stage, beef = beef ~= nil }
end


local function choiceKey(choice)
    return choice.body .. "|" .. table.concat(choice.parts, "|")
end


-- ---------------------------------------------------------------------------
-- Nodes
-- ---------------------------------------------------------------------------

-- name -> node of every node under a node whose name is a key of want (not under skip)
local function findNamed(node, want, found, skip)
    for i = 0, getNumOfChildren(node) - 1 do
        local child = getChildAt(node, i)
        if child ~= skip then
            if want[getName(child)] ~= nil then found[getName(child)] = child end
            findNamed(child, want, found, skip)
        end
    end
    return found
end


-- Every variant group under the visual root - an adult model's LOD group (LOD0/1/2), a calf or baby
-- model's cattleCalf group - with its stock body's name and its children by name; a calf / baby group
-- also its dairy coat (coat: stock shape name -> its D_ copy, originals: name -> the stock shape). Empty
-- for models without variants (the old calf models, Highland babies, buffalo).
local function collectGroups(node, groups)
    for i = 0, getNumOfChildren(node) - 1 do
        local child = getChildAt(node, i)
        local name = getName(child)
        local stock = LOD_GROUPS[name] and STOCK_BODY
            or (name == CALF_GROUP and CALF_BODY or HIGHLAND_GROUPS[name] or PLAIN_GROUPS[name])

        if stock ~= nil then
            local group = { node = child, nodes = {}, variants = 0, stock = stock }
            for j = 0, getNumOfChildren(child) - 1 do
                local shape = getChildAt(child, j)
                local shapeName = getName(shape)
                local prefix = string.sub(shapeName, 1, 2)
                if shapeName == stock or prefix == "F_" or prefix == "M_" or prefix == "C_" then
                    group.nodes[shapeName] = shape
                    if shapeName ~= stock then group.variants = group.variants + 1 end
                elseif shapeName == COAT_GROUP then
                    group.coat = {}
                    for k = 0, getNumOfChildren(shape) - 1 do
                        local copy = getChildAt(shape, k)
                        local copyName = getName(copy)
                        if string.sub(copyName, 1, #COAT_PREFIX) == COAT_PREFIX then
                            group.coat[string.sub(copyName, #COAT_PREFIX + 1)] = copy
                        end
                    end
                    group.originals = findNamed(child, group.coat, {}, shape)
                    group.variants = group.variants + 1
                end
            end
            -- a group of that name carrying nothing of ours: look inside (the buffalo baby's body is a group
            -- further down, in "Hair" under "geo")
            if group.variants > 0 then table.insert(groups, group) else collectGroups(child, groups) end
        else
            collectGroups(child, groups)
        end
    end
end


function CowVariants.findGroups(root)
    local groups = {}
    if root ~= nil and root ~= 0 then collectGroups(root, groups) end
    return groups
end


-- The body to show in one LOD group: the exact variant, else its plain stage body (LOD2 only has
-- the open / entire ones, beef at normal weight), else - a beef build this size's model doesn't carry
-- (a map decoration animal stays on the stock size) - the native build's, else nil (keep the stock body).
local function pickBody(group, body)
    if group.nodes[body] ~= nil then return body end
    -- (a calf keeps "_steer": every calf size carries both, and a steer must keep his pouch)
    local stageBody = string.sub(body, 1, 2) == "C_" and body
        or string.gsub(string.gsub(string.gsub(body, "_preg_late", ""), "_preg", ""), "_steer", "")
    if group.nodes[stageBody] ~= nil then return stageBody end
    local normal = string.gsub(stageBody, "_%a+_(%a+)$", "_normal_%1")      -- beef: <weight>_<build>
    if normal ~= stageBody and group.nodes[normal] ~= nil then return normal end
    local build = string.match(body, "_(%a+)$")
    if build == "continental" or build == "double" then
        for _, name in ipairs({ (string.gsub(body, "_%a+$", "_native")), (string.gsub(normal, "_%a+$", "_native")) }) do
            if group.nodes[name] ~= nil then return name end
        end
    end
    return nil
end


local function applyToGroup(group, choice)
    local shown = {}
    local body = pickBody(group, choice.body)
    -- a model with no stock body and not this one (the pedigree model, for a bull castrated a moment
    -- ago): keep what it shows until RLRM has moved the animal to its slot
    if body == nil and group.nodes[group.stock] == nil then return nil end
    if body ~= nil then shown[body] = true end
    for _, part in ipairs(choice.parts) do
        -- a beef body's own sack / sheath follow it when another body stood in for the chosen one
        if group.nodes[part] == nil and body ~= nil and body ~= choice.body
                and string.sub(part, 1, #choice.body) == choice.body then
            part = body .. string.sub(part, #choice.body + 1)
        end
        if group.nodes[part] ~= nil then shown[part] = true end
    end

    -- a dairy animal on a calf / baby model wears its dairy coat: the D_ copies of the stock shapes
    -- instead of them (the stock body's copy only where the stock body would show)
    local dairy = group.coat ~= nil and choice.dairy == true
    for name, node in pairs(group.nodes) do
        if name == group.stock then
            setVisibility(node, body == nil and not (dairy and group.coat[name] ~= nil))
        else
            setVisibility(node, shown[name] == true)
        end
    end
    if group.coat ~= nil then
        for name, copy in pairs(group.coat) do
            if name == group.stock then
                setVisibility(copy, dairy and body == nil)
            else
                setVisibility(copy, dairy)
                if group.originals[name] ~= nil then setVisibility(group.originals[name], not dairy) end
            end
        end
    end

    -- the breed tile the engine set on the stock body, onto what we show
    local stock = group.nodes[group.stock]
    if stock ~= nil and getHasShaderParameter(stock, TILE_PARAM) then
        local x, y, z, w = getShaderParameter(stock, TILE_PARAM)
        for name in pairs(shown) do
            local node = group.nodes[name]
            if getHasShaderParameter(node, TILE_PARAM) then
                setShaderParameter(node, TILE_PARAM, x, y, z, w, false)
            end
        end
    end

    return body
end


local function setTransform(node, cfg, k)
    k = k or 1
    setTranslation(node, cfg.t[1] * k, cfg.t[2] * k, cfg.t[3] * k)
    setRotation(node, math.rad(cfg.r[1]), math.rad(cfg.r[2]), math.rad(cfg.r[3]))
    setScale(node, cfg.s[1] * k, cfg.s[2] * k, cfg.s[3] * k)
end


--- The beef size step of a slot (0 for the beef slot 7 and any other), and its scale.
function CowVariants.beefSlotStep(slot)
    for step, s in pairs(CowVariants.CONFIG.beef.slots) do
        if s == slot then return step end
    end
    return 0
end


function CowVariants.beefSlotScale(slot)
    return CowVariants.CONFIG.beef.step ^ CowVariants.beefSlotStep(slot)
end


-- ---------------------------------------------------------------------------
-- The monitor collar (models/collar.i3d)
-- ---------------------------------------------------------------------------
-- One collar for every adult (blender/build_collar.py): a strap per group of necks, the body's own strap
-- scaled and moved to its neck, and the eight number tags, sensor and buckle placed on it - all from
-- CowCollarFits (Script/CollarFits.lua) by body. The collar node itself goes to its one place under the
-- neck joint x the model's size: the size steps scale the skeleton, so the joint's offset gives it.

local NECK_JOINT = "cow_neck_skin_jnt_02"
local NECK_JOINT_OFFSET = 0.256434          -- its translation in the stock models (dairy and beef alike)

--- The collar's nodes by name, or nil when the model hasn't this collar (the old one, a calf's ear
--- monitor). Cached on the visual.
local function collarParts(visualAnimal)
    if visualAnimal.cvCollar == nil then
        local fits, monitor = CowCollarFits, visualAnimal.nodes.monitor
        local parts = false
        if fits ~= nil and monitor ~= nil and monitor ~= 0 then
            -- the referenced collar's children sit on the monitor node (or one node down)
            local holders = { monitor }
            for i = 0, getNumOfChildren(monitor) - 1 do table.insert(holders, getChildAt(monitor, i)) end
            for _, holder in ipairs(holders) do
                local found = {}
                for i = 0, getNumOfChildren(holder) - 1 do
                    local child = getChildAt(holder, i)
                    found[getName(child)] = child
                end
                if found[fits.parts[1]] ~= nil then
                    parts = found
                    break
                end
            end
        end
        visualAnimal.cvCollar = parts
        if parts then
            local parent = getParent(monitor)
            local k = 1
            if parent ~= nil and parent ~= 0 and getName(parent) == NECK_JOINT then
                local x, y, z = getTranslation(parent)
                k = MathUtil.vector3Length(x, y, z) / NECK_JOINT_OFFSET
            end
            visualAnimal.cvCollarScale = (k > 0.6 and k < 1.6) and k or 1
        end
    end
    return visualAnimal.cvCollar or nil
end


--- The animal's last four ID digits on the collar's tags, top to bottom on both sides. False when the
--- model hasn't this collar.
function CowVariants.setCollarNumber(visualAnimal)
    local fits = CowCollarFits
    if fits == nil or visualAnimal == nil or visualAnimal.nodes == nil then return false end
    local parts = collarParts(visualAnimal)
    if parts == nil then return false end
    local id = visualAnimal.animal ~= nil and tostring(visualAnimal.animal.uniqueId or "") or ""
    local digits = string.sub("    " .. id, -4)
    for i = 1, 4 do
        local digit = tonumber(string.sub(digits, i, i)) or fits.blank
        for _, side in ipairs({ "tagL", "tagR" }) do
            local tag = parts[side .. i]
            if tag ~= nil then setShaderParameter(tag, "playScale", digit, 0, 16, 1, false) end
        end
    end
    return true
end


--- The collar onto the body the animal shows (an adult's; a calf and a Highland wear an ear monitor). False
--- when the model hasn't this collar.
function CowVariants.fitCollar(visualAnimal, choice)
    local fits = CowCollarFits
    if fits == nil or choice.calf or choice.highland or choice.plain then return false end
    local parts = collarParts(visualAnimal)
    if parts == nil then return false end
    local key = string.gsub(choice.body, "_preg_late", "")
    key = string.gsub(key, "_preg", "")
    local fit = fits.bodies[key] or fits.bodies[choice.beef and fits.default.beef or fits.default.dairy]
    if fit == nil then return false end

    local monitor, k = visualAnimal.nodes.monitor, visualAnimal.cvCollarScale
    local t, r = fits.node.t, fits.node.r
    setTranslation(monitor, t[1] * k, t[2] * k, t[3] * k)
    setRotation(monitor, math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
    setScale(monitor, k, k, k)

    for i, name in ipairs(fits.straps) do
        if parts[name] ~= nil then setVisibility(parts[name], i == fit[1]) end
    end
    local strap, s = parts[fits.straps[fit[1]]], fit[2]
    if strap ~= nil then
        setTranslation(strap, s[1], s[2], s[3])
        setRotation(strap, math.rad(s[4]), math.rad(s[5]), math.rad(s[6]))
        setScale(strap, s[7], s[8], 1)
    end
    for i, name in ipairs(fits.parts) do
        local node, p = parts[name], fit[3][i]
        if node ~= nil and p ~= nil then
            setTranslation(node, p[1], p[2], p[3])
            setRotation(node, math.rad(p[4]), math.rad(p[5]), math.rad(p[6]))
        end
    end
    CowVariants.setCollarNumber(visualAnimal)
    return true
end


--- The bulls the collar doesn't look right on (user, 2026-10-30): a pedigree bull, and an entire adult (or
--- old) bull on the heavy body. Young bulls, steers and cows keep theirs.
local function wearsNoCollar(choice)
    if not choice.male or choice.steer or choice.calf then return false end
    if choice.stage == "pedigree" then return true end
    return (choice.stage == "adult" or choice.stage == "old") and string.find(choice.body, "_heavy_", 1, true) ~= nil
end


--- RLRM's rule for the monitor (VisualAnimal:setMonitor: shown while it is active), except on the bulls
--- that wear no collar (wearsNoCollar). Only the look: their monitor keeps working.
function CowVariants.showMonitor(visualAnimal)
    local nodes, animal = visualAnimal.nodes, visualAnimal.animal
    local monitor = nodes ~= nil and nodes.monitor or nil
    if monitor == nil or monitor == 0 or animal == nil or animal.monitor == nil then return end
    setVisibility(monitor, animal.monitor.active == true and not visualAnimal.cvNoCollar)
end


-- ---------------------------------------------------------------------------
-- The spray marker and bum ID (models/sprayedMarker_cattle.i3d, models/bumId.i3d)
-- ---------------------------------------------------------------------------
-- The stock decal and number tiles sit on the stock back and float or sink on the other bodies.
-- blender/build_rump_marks.py measured every body: CowRumpFits (Script/RumpFits.lua) gives each its own
-- marker decal - a child m<g> of the marker's root (m00 the stock decal, for any other model) - fitted to
-- its back, and its bum ID's four tiles laid on its rump. Both in their nodes' own frames, which the size
-- steps only scale, so one table serves every size.

-- The table's name for a body: a pregnant one's open body, a dairy calf's the native one, every baby the one.
local function rumpKey(choice, body)
    if choice.baby then return "C_baby" end
    local key = string.gsub(string.gsub(body, "_preg_late", ""), "_preg", "")
    if choice.calf then key = string.gsub(key, "_dairy$", "_native") end
    return key
end


--- The marker's decals by number, or nil when the model has the old marker. Cached on the visual.
local function markerDecals(visualAnimal)
    if visualAnimal.cvMarker == nil then
        local marker, decals = visualAnimal.nodes.marker, false
        if marker ~= nil and marker ~= 0 and getNumOfChildren(marker) > 0 and getName(getChildAt(marker, 0)) == "m00" then
            decals = {}
            for i = 0, getNumOfChildren(marker) - 1 do
                local child = getChildAt(marker, i)
                local g = tonumber(string.match(getName(child), "^m(%d+)$"))
                if g ~= nil then decals[g] = child end
            end
        end
        visualAnimal.cvMarker = decals
    end
    return visualAnimal.cvMarker or nil
end


--- The marker and bum ID onto the body shown (nil: the stock body - the stock decal, the tiles as modelled;
--- a baby's stock body is the measured one).
function CowVariants.fitRumpMarks(visualAnimal, choice, body)
    local fits = CowRumpFits
    if fits == nil then return end
    local fit = (body ~= nil or choice.baby) and fits.bodies[rumpKey(choice, body)] or nil

    local decals = markerDecals(visualAnimal)
    if decals ~= nil then
        local m = fit ~= nil and fit.marker or nil
        local shown = m ~= nil and decals[m[1]] ~= nil and m[1] or 0
        for g, node in pairs(decals) do setVisibility(node, g == shown) end
        if shown ~= 0 then
            local node = decals[shown]
            setTranslation(node, m[2], m[3], m[4])
            setRotation(node, math.rad(m[5]), math.rad(m[6]), math.rad(m[7]))
            setScale(node, 1, m[8], 1)
        end
    end

    local bumId = visualAnimal.nodes.bumId
    if bumId ~= nil and bumId ~= 0 and getNumOfChildren(bumId) >= 4 then
        local tiles = fit ~= nil and fit.bum or nil
        for i = 1, 4 do
            local tile, p = getChildAt(bumId, i - 1), tiles ~= nil and tiles[i] or false
            if p then
                setTranslation(tile, p[1], p[2], p[3])
                setRotation(tile, math.rad(p[4]), math.rad(p[5]), math.rad(p[6]))
            else
                setTranslation(tile, 0, 0, 0)
                setRotation(tile, 0, 0, 0)
            end
        end
    end
end


--- RLRM colours the marker's root (VisualAnimal:setMarker); the decals are its children.
function CowVariants.colourMarker(visualAnimal)
    local marker = visualAnimal ~= nil and visualAnimal.nodes ~= nil and visualAnimal.nodes.marker or nil
    if marker == nil or marker == 0 or not getHasShaderParameter(marker, "colorScale") then return end
    local x, y, z, w = getShaderParameter(marker, "colorScale")
    for i = 0, getNumOfChildren(marker) - 1 do
        local child = getChildAt(marker, i)
        if getHasShaderParameter(child, "colorScale") then setShaderParameter(child, "colorScale", x, y, z, w, false) end
    end
end


-- ---------------------------------------------------------------------------
-- Apply to an RLRM VisualAnimal
-- ---------------------------------------------------------------------------

function CowVariants.applyVisual(visualAnimal, force)
    if visualAnimal == nil or visualAnimal.nodes == nil or visualAnimal.animal == nil then return end

    local root = visualAnimal.nodes.root
    if root == nil or root == 0 then return end

    if visualAnimal.cvGroups == nil then
        visualAnimal.cvGroups = CowVariants.findGroups(root)
        -- the pedigree model has no stock body; its bull accessories are already placed (and scaled)
        visualAnimal.cvOwnModel = true
        for _, group in ipairs(visualAnimal.cvGroups) do
            if group.nodes[group.stock] ~= nil then visualAnimal.cvOwnModel = false end
        end
    end
    if #visualAnimal.cvGroups == 0 then return end      -- not a variant model

    local animal = visualAnimal.animal
    local choice = CowVariants.choose(animal)
    local key = choiceKey(choice)
    if not force and visualAnimal.cvKey == key then return end
    visualAnimal.cvKey = key
    animal.cvShown = key

    local body
    for i, group in ipairs(visualAnimal.cvGroups) do
        local shown = applyToGroup(group, choice)
        if i == 1 then body = shown end             -- the first group: LOD0, or the calf / baby model's
    end
    local collared = CowVariants.fitCollar(visualAnimal, choice)
    visualAnimal.cvNoCollar = wearsNoCollar(choice)
    CowVariants.showMonitor(visualAnimal)       -- a bull turning pedigree or heavy (or castrated out of it)
    CowVariants.fitRumpMarks(visualAnimal, choice, body)

    if choice.male and not choice.calf then      -- a calf keeps its calf model's collar and ear tags
        local nodes, cfg, k = visualAnimal.nodes, CowVariants.CONFIG.bullAccessories, 1
        if choice.beef then
            -- the model of a beef size has its accessories scaled with it; the bull placement is too
            cfg, k = CowVariants.CONFIG.beef.bullAccessories, CowVariants.beefSlotScale(animal.visualAnimalIndex)
        else
            k = CowVariants.dairySlotScale(animal.visualAnimalIndex)      -- likewise a dairy size
        end
        -- the pedigree model has its bull placement baked in; a Highland bull wore the cow's (his old
        -- model's accessories were the cow model's), as the buffalo and Brahman bulls do
        if visualAnimal.cvOwnModel or choice.highland or choice.plain then visualAnimal.cvBullAccessories = true end
        if nodes.monitor ~= nil and not visualAnimal.cvBullAccessories and not collared then   -- the old collar
            setTransform(nodes.monitor, cfg.monitor, k)
        end
        if nodes.bumId ~= nil and not visualAnimal.cvBullAccessories then
            setTransform(nodes.bumId, cfg.bumId, k)
        end
        visualAnimal.cvBullAccessories = true
        if nodes.noseRing ~= nil then setVisibility(nodes.noseRing, not choice.steer) end   -- steers aren't ringed
    end
end


function CowVariants.refresh(animal, force)
    if animal ~= nil and animal.visualAnimal ~= nil then CowVariants.applyVisual(animal.visualAnimal, force) end
end


--- The cattle models ship their collar, nose ring, spray mark, bum ID and horns hidden (so a map's
--- decoration animals look plain). RLRM sets the collar, ring and mark per animal and HornSelector the
--- horns, but nothing ever sets the bum ID's visibility - an owned animal wears it.
function CowVariants.showOwnedAccessories(visualAnimal)
    local animal = visualAnimal ~= nil and visualAnimal.animal or nil
    if animal == nil or visualAnimal.nodes == nil or animal.animalTypeIndex ~= AnimalType.COW then return end
    if visualAnimal.nodes.bumId ~= nil then setVisibility(visualAnimal.nodes.bumId, true) end
end


-- ---------------------------------------------------------------------------
-- Map decoration animals
-- ---------------------------------------------------------------------------
-- Pens a map fills with animals you don't own (the base game's SimpleHusbandry) spawn straight from
-- models/cow/animals.xml and never get an RLRM VisualAnimal, so nothing picks their body, parts or
-- horns: a bull would show the stock cow body. SimpleHusbandry.addAnimals doesn't keep which subtype
-- each animal is, so it is replaced by the same code plus one step per animal: an adult of its subtype
-- (breed, gender; a nursing cow or an entire bull, normal weight) gets its body and parts, its breed's
-- horn chance and, bulls, the nose ring. Decoration animals stay on their subtype's own slot (stock size).

local DECOR_AGE = 48            -- months: a grown animal of every stage table

local function nodeAtPath(root, path)
    if root == nil or root == 0 or path == nil then return nil end
    local node = root
    for part in string.gmatch(path, "[^|]+") do
        local index = tonumber(part)
        if index == nil or index >= getNumOfChildren(node) then return nil end
        node = getChildAt(node, index)
    end
    return node
end


function CowVariants.decorate(root, subType, visual, seed)
    if root == nil or root == 0 or subType == nil then return end
    local male = subType.gender == "male"
    local animal = { gender = male and "male" or "female", breed = subType.breed, age = DECOR_AGE,
                     isParent = not male, isLactating = not male }

    local groups = CowVariants.findGroups(root)
    if #groups > 0 then
        local choice = CowVariants.choose(animal)
        for _, group in ipairs(groups) do applyToGroup(group, choice) end
    end
    if male and visual ~= nil and visual.noseRing ~= nil then
        local ring = nodeAtPath(root, visual.noseRing)
        if ring ~= nil then setVisibility(ring, true) end
    end
    if HornSelector ~= nil and HornSelector.applyToRoot ~= nil then
        HornSelector.applyToRoot(root, animal.breed, animal.gender, seed)
    end
end


-- SimpleHusbandry.addAnimals as the base game has it (animals/husbandry/SimpleHusbandry.lua), plus decorate
local function addDecorationAnimals(self)
    local system = g_currentMission.animalSystem
    local isCow = self.animalType ~= nil and (self.animalType.typeIndex == AnimalType.COW or self.animalType.name == "COW")
    for _ = 1, math.random(math.min(self.maxNumberOfAnimals, 2), self.maxNumberOfAnimals) do
        local subType = self.subTypeIndex ~= nil and system:getSubTypeByIndex(self.subTypeIndex) or nil
        if subType == nil then
            local subTypes = self.animalType.subTypes
            subType = system:getSubTypeByIndex(subTypes[math.random(1, #subTypes)])
        end
        local visual = subType.visuals[#subType.visuals]
        local animalId = addHusbandryAnimal(self.husbandryId, visual.visualAnimalIndex - 1)
        table.insert(self.animalIds, animalId)
        local root = getAnimalRootNode(self.husbandryId, animalId)
        I3DUtil.setShaderParameterRec(root, "dirt", math.random(0, 0.7), nil, nil, nil)
        local x, y, z, w = getAnimalShaderParameter(self.husbandryId, animalId, "atlasInvSizeAndOffsetUV")
        I3DUtil.setShaderParameterRec(root, "atlasInvSizeAndOffsetUV", x, y, z, w)
        if isCow then
            local ok, err = pcall(CowVariants.decorate, root, subType, visual, tostring(root))
            if not ok then print(string.format("%s decoration animal error: %s", TAG, tostring(err))) end
        end
    end
end


if SimpleHusbandry ~= nil and SimpleHusbandry.addAnimals ~= nil then
    SimpleHusbandry.addAnimals = addDecorationAnimals
else
    print(TAG .. " SimpleHusbandry not found - map decoration cattle keep the model defaults")
end


-- fn(placeable, animals) for every cow pen with a cluster system
local function forEachCowPen(fn)
    local husbandrySystem = g_currentMission ~= nil and g_currentMission.husbandrySystem or nil
    if husbandrySystem == nil then return end

    for _, placeable in ipairs(husbandrySystem.placeables) do
        local clusterSystem = placeable.getClusterSystem ~= nil and placeable:getClusterSystem() or nil
        local isCowPen = placeable.getAnimalTypeIndex ~= nil and placeable:getAnimalTypeIndex() == AnimalType.COW

        if clusterSystem ~= nil and isCowPen and clusterSystem.animals ~= nil then fn(placeable, clusterSystem.animals) end
    end
end


-- fn(animal) for every animal of every cow pen
local function forEachCow(fn)
    forEachCowPen(function(_, animals)
        for _, animal in ipairs(animals) do fn(animal) end
    end)
end
CowVariants.forEachCow = forEachCow


-- ---------------------------------------------------------------------------
-- Pedigree slot
-- ---------------------------------------------------------------------------

local baseVisualIndex = nil     -- AnimalSystem.getVisualAnimalIndexByAge as it was before the wrap
local askingAnimal = nil        -- the animal that was last asked its subtype
local routedVisuals = {}        -- age stage visual -> slot -> that visual on the slot (routedVisual)


--- An age stage's visual on another slot: the same coat list, accessory paths and shop data (the routed
--- models keep the base slot's node paths and atlas), only visualAnimalIndex moved. One copy per stage
--- and slot, kept.
local function routedVisual(visual, slot)
    local bySlot = routedVisuals[visual]
    if bySlot == nil then
        bySlot = {}
        routedVisuals[visual] = bySlot
    end
    local copy = bySlot[slot]
    if copy == nil then
        copy = {}
        for key, value in pairs(visual) do copy[key] = value end
        copy.visualAnimalIndex = slot
        bySlot[slot] = copy
    end
    return copy
end


--- Is this slot loaded (the COW type's models/cow/animals.xml has it)?
local function slotLoaded(system, slot)
    local cowType = system ~= nil and system.getTypeByIndex ~= nil and system:getTypeByIndex(AnimalType.COW) or nil
    return cowType ~= nil and cowType.animals ~= nil and cowType.animals[slot] ~= nil
end


local function pedigreeSlotLoaded(system)
    return slotLoaded(system, CowVariants.CONFIG.pedigree.slot.to)
end


--- The beef size step of an animal: its stage's plus its breed's height class's.
function CowVariants.beefStep(animal)
    local cfg, beef = CowVariants.CONFIG, CowVariants.beefBreed(animal)
    if beef == nil then return 0 end
    local stage
    if animal.gender == "male" then
        stage = stageFor(cfg.bullStages, animal.age or 0)
        if CowVariants.isPedigree(animal) then stage = "pedigree" end
    else
        stage = stageFor(cfg.cowStages, animal.age or 0)
    end
    local step = (cfg.beef.stageStep[stage] or 0) + (cfg.beef.heightStep[beef.height] or 0)
    return math.min(math.max(step, cfg.beef.minStep), cfg.beef.maxStep)
end


--- A calf's size step: its age half's plus its breed's height class's - beef or dairy (nil: not a
--- 6-12 month beef or dairy calf).
function CowVariants.calfStep(animal)
    local cfg, half = CowVariants.CONFIG.calf, CowVariants.calfAge(animal)
    if half == nil then return nil end
    local beef = CowVariants.beefBreed(animal)
    local height = beef ~= nil and cfg.heightStep[beef.height] or cfg.dairyHeightStep[CowVariants.dairyBreed(animal)]
    return (cfg.ageStep[half] or 0) + (height or 0)
end


--- A dairy adult's size step: its stage's (pedigree for a pedigree bull) plus its breed's height class's.
function CowVariants.dairyStep(animal)
    local cfg = CowVariants.CONFIG
    local stage
    if animal.gender == "male" then
        stage = CowVariants.isPedigree(animal) and "pedigree" or stageFor(cfg.bullStages, animal.age or 0)
    else
        stage = stageFor(cfg.cowStages, animal.age or 0)
    end
    local height = cfg.dairy.breeds[animal.breed or ""] or "large"
    return (cfg.dairy.stageStep[stage] or 0) + (cfg.dairy.heightStep[height] or 0)
end


--- The scale of a dairy size's slot (1 for the dairy slot 2 and any other).
function CowVariants.dairySlotScale(slot)
    for step, s in pairs(CowVariants.CONFIG.dairy.slots) do
        if s == slot then return CowVariants.CONFIG.dairy.step ^ step end
    end
    return 1
end


--- The slot an animal belongs on, given the slot RLRM's age table has for its subtype and age.
function CowVariants.slotFor(animal, index, system)
    -- cattle only: the slot numbers are the COW type's - RLRM's Landrace pigs and sheep, Pinto horses and
    -- roosters sit on index 2 of their own types, and routing them gave them a cattle slot they haven't
    if animal == nil or animal.animalTypeIndex ~= AnimalType.COW then return index end
    local dairy = CowVariants.CONFIG.dairy
    if index == dairy.baseSlot and CowVariants.beefBreed(animal) == nil then
        local sized = dairy.slots[CowVariants.dairyStep(animal)]
        if sized ~= nil and slotLoaded(system, sized) then return sized end
        return index
    end

    local calf = CowVariants.CONFIG.calf
    if index == calf.babySlot and (CowVariants.beefBreed(animal) ~= nil or CowVariants.dairyBreed(animal) ~= nil) then
        local age = animal.age or 0
        if age >= calf.bigBabyFrom and slotLoaded(system, calf.bigBabySlot) then return calf.bigBabySlot end
        if age >= calf.walkBabyFrom and slotLoaded(system, calf.walkBabySlot) then return calf.walkBabySlot end
        return index
    end
    if calf.baseSlots[index] then
        local step = CowVariants.calfStep(animal)
        local sized = step ~= nil and calf.slots[step] or nil
        if sized ~= nil and slotLoaded(system, sized) then return sized end
    end

    local beef = CowVariants.CONFIG.beef
    if beef.baseSlots[index] and CowVariants.beefBreed(animal) ~= nil then
        local sized = beef.slots[CowVariants.beefStep(animal)]
        if sized ~= nil and slotLoaded(system, sized) then return sized end
    end
    return index
end


--- Rebuild a pen's visuals when one of its animals is on the wrong slot - RLRM's updateVisuals moves
--- every animal whose slot changed. True when it did.
function CowVariants.checkSlots(placeable)
    if baseVisualIndex == nil or placeable == nil or placeable.updateVisualAnimals == nil then return false end
    local clusterSystem = placeable.getClusterSystem ~= nil and placeable:getClusterSystem() or nil
    if clusterSystem == nil or clusterSystem.animals == nil then return false end

    local system = g_currentMission.animalSystem
    for _, animal in ipairs(clusterSystem.animals) do
        local current = animal.visualAnimalIndex
        if current ~= nil then
            local age = animal.age or 0
            local index = baseVisualIndex(system, animal.subTypeIndex, age == -1 and 0 or age)
            if CowVariants.slotFor(animal, index, system) ~= current then
                placeable:updateVisualAnimals()
                return true
            end
        end
    end
    return false
end


local function sweep()
    forEachCowPen(function(placeable, animals)
        local ok, err = pcall(CowVariants.checkSlots, placeable)
        if not ok then print(string.format("%s slot check error: %s", TAG, tostring(err))) end
        for _, animal in ipairs(animals) do
            ok, err = pcall(CowVariants.refresh, animal, false)
            if not ok then print(string.format("%s refresh error: %s", TAG, tostring(err))) end
        end
    end)
end


-- ---------------------------------------------------------------------------
-- RLRM hooks
-- ---------------------------------------------------------------------------

function CowVariants:installHooks()
    if self.hooksInstalled then return true end

    local rlrm = FS25_RealisticLivestockRM
    if rlrm == nil or rlrm.VisualAnimal == nil or rlrm.VisualAnimal.load == nil then return false end

    if CowEarTags ~= nil and not CowEarTags.install(rlrm) then     -- the real ear tags (Script/EarTags.lua)
        print(TAG .. " RLRM's ear tag functions not found - the tags keep RLRM's text")
    end

    -- the marker's colour onto its decals (RLRM colours the root)
    local setMarker = rlrm.VisualAnimal.setMarker
    if setMarker ~= nil then
        rlrm.VisualAnimal.setMarker = function(visualAnimal, ...)
            local result = setMarker(visualAnimal, ...)
            pcall(CowVariants.colourMarker, visualAnimal)
            return result
        end
    end

    local loadVisual = rlrm.VisualAnimal.load
    rlrm.VisualAnimal.load = function(visualAnimal, ...)
        local result = loadVisual(visualAnimal, ...)
        visualAnimal.cvGroups, visualAnimal.cvKey, visualAnimal.cvBullAccessories = nil, nil, nil
        visualAnimal.cvMarker, visualAnimal.cvNoCollar = nil, nil
        pcall(CowVariants.showOwnedAccessories, visualAnimal)
        local ok, err = pcall(CowVariants.applyVisual, visualAnimal, true)
        if not ok then print(string.format("%s applyVisual error: %s", TAG, tostring(err))) end
        return result
    end

    -- Slot routing (pedigree, dairy / beef / calf / baby sizes). RLRM up to 1.4.2.0-dev.2: updateVisuals asks
    -- animal:getSubTypeIndex() and then getVisualAnimalIndexByAge(subTypeIndex, age) for each animal, so the
    -- animal last asked its subtype is the one the slot is for (checked by subtype; used once).
    -- From dev.4 it takes the slot from getVisualByAge(subTypeIndex, age, animal) - the animal passed in (the
    -- base game ignores it) - so that one returns the stage's visual on the routed slot (routedVisual).
    local animalClass = rlrm.Animal
    if animalClass ~= nil and animalClass.getSubTypeIndex ~= nil and AnimalSystem ~= nil
            and AnimalSystem.getVisualAnimalIndexByAge ~= nil then
        local getSubTypeIndex = animalClass.getSubTypeIndex
        animalClass.getSubTypeIndex = function(animal, ...)
            askingAnimal = animal
            return getSubTypeIndex(animal, ...)
        end

        baseVisualIndex = AnimalSystem.getVisualAnimalIndexByAge
        AnimalSystem.getVisualAnimalIndexByAge = function(system, subTypeIndex, age, ...)
            local index = baseVisualIndex(system, subTypeIndex, age, ...)
            local animal = askingAnimal
            askingAnimal = nil
            if animal ~= nil and animal.subTypeIndex == subTypeIndex then
                local ok, slot = pcall(CowVariants.slotFor, animal, index, system)
                if ok and slot ~= nil then return slot end
            end
            return index
        end

        local baseVisualByAge = AnimalSystem.getVisualByAge
        if baseVisualByAge ~= nil then
            AnimalSystem.getVisualByAge = function(system, subTypeIndex, age, animal, ...)
                local visual = baseVisualByAge(system, subTypeIndex, age, animal, ...)
                if visual == nil or type(animal) ~= "table" or animal.subTypeIndex ~= subTypeIndex then return visual end
                askingAnimal = nil                   -- answered here (getVisualAnimalIndexByAge isn't coming)
                local ok, slot = pcall(CowVariants.slotFor, animal, visual.visualAnimalIndex, system)
                if not ok or slot == nil or slot == visual.visualAnimalIndex then return visual end
                return routedVisual(visual, slot)
            end
        end
    else
        print(TAG .. " RLRM's Animal class not found - pedigree bulls and beef sizes stay on the stock slots")
    end

    -- Prices: every sale, the dealer (its markup is on this) and the value RLRM shows go through
    -- Animal:getSellPrice.
    if animalClass ~= nil and animalClass.getSellPrice ~= nil then
        local getSellPrice = animalClass.getSellPrice
        animalClass.getSellPrice = function(animal, ...)
            local price = getSellPrice(animal, ...)
            local ok, factor = pcall(CowVariants.priceFactor, animal)
            if ok and type(price) == "number" and type(factor) == "number" and factor == factor and factor > 0 then
                return price * factor
            end
            return price
        end
    end

    -- A pedigree bull's line in RLRM's info lists (Animal:addInfos) and its look-at box (Animal:showInfo).
    if animalClass ~= nil and animalClass.addInfos ~= nil then
        local addInfos = animalClass.addInfos
        animalClass.addInfos = function(animal, infos, ...)
            local result = addInfos(animal, infos, ...)
            if type(infos) == "table" then pcall(CowVariants.addPedigreeInfo, animal, infos) end
            return result
        end
    end
    if animalClass ~= nil and animalClass.showInfo ~= nil then
        local showInfo = animalClass.showInfo
        animalClass.showInfo = function(animal, box, ...)
            local result = showInfo(animal, box, ...)
            if box ~= nil then pcall(CowVariants.showPedigreeInfo, animal, box) end
            return result
        end
    end

    -- Castration: the player who did it mutates the animal, then calls sendEvent; every other
    -- machine (and the server, for a client's request) gets it through run(). A castrated pedigree
    -- goes back to the dairy adult slot (a beef one to its size's).
    local castrate = rlrm.AnimalCastrateEvent
    if castrate ~= nil then
        local sendEvent = castrate.sendEvent
        castrate.sendEvent = function(object, animal, ...)
            local result = sendEvent(object, animal, ...)
            pcall(CowVariants.refresh, animal, false)
            pcall(CowVariants.checkSlots, object)
            return result
        end

        local function redrawPen(placeable)
            local clusterSystem = placeable ~= nil and placeable.getClusterSystem ~= nil and placeable:getClusterSystem() or nil
            if clusterSystem ~= nil and clusterSystem.animals ~= nil then
                for _, animal in ipairs(clusterSystem.animals) do pcall(CowVariants.refresh, animal, false) end
                pcall(CowVariants.checkSlots, placeable)
            end
        end

        local run = castrate.run
        castrate.run = function(event, ...)
            local result = run(event, ...)
            redrawPen(event.object)
            return result
        end

        -- the herdsman castrates on the server without sendEvent (RLHerdsmanExecutor._doCastrate sets the flag
        -- and broadcasts the event, whose run() is the clients'): its pen is redrawn here when it castrated any
        local executor = rlrm.RLHerdsmanExecutor
        if executor ~= nil and executor._doCastrate ~= nil then
            local doCastrate = executor._doCastrate
            executor._doCastrate = function(action, ctx, placeable, ...)
                local results = { doCastrate(action, ctx, placeable, ...) }
                if results[2] == true then pcall(redrawPen, placeable) end
                return unpack(results, 1, table.maxn(results))
            end
        end
    end

    self.hooksInstalled = true
    return true
end


-- ---------------------------------------------------------------------------
-- Mod event listener
-- ---------------------------------------------------------------------------

function CowVariants:loadMap(_)
    if not self.hooksInstalled then
        if self:installHooks() then
            print(TAG .. " hooks installed")
            sweep()
        else
            print(TAG .. " FS25_RealisticLivestockRM not found - variants disabled")
            return
        end
    end

    g_messageCenter:subscribe(MessageType.DAY_CHANGED, sweep, self)
    g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, sweep, self)

    addConsoleCommand("cowVariants", "Re-check the body/udder/male parts of every adult cattle animal and report the counts",
        "consoleCommandVariants", self)
    addConsoleCommand("cowVariantsWeights", "List every beef animal's weight against its breed's and the body weight it shows",
        "consoleCommandWeights", self)
    addConsoleCommand("cowVariantsYoung", "List every cattle animal under 12 months: the slot it shows, the slot it belongs on, the model",
        "consoleCommandYoung", self)
    self.consoleCommandAdded = true
end


function CowVariants:deleteMap()
    g_messageCenter:unsubscribeAll(self)
    if self.consoleCommandAdded then
        removeConsoleCommand("cowVariants")
        removeConsoleCommand("cowVariantsWeights")
        removeConsoleCommand("cowVariantsYoung")
        self.consoleCommandAdded = false
    end
end


function CowVariants:consoleCommandVariants()
    local counts, total, noVisual, rebuilt = {}, 0, 0, 0
    local pedigreeSlot = CowVariants.CONFIG.pedigree.slot.to

    forEachCowPen(function(placeable)
        if CowVariants.checkSlots(placeable) then rebuilt = rebuilt + 1 end
    end)

    forEachCow(function(animal)
        if animal.visualAnimal == nil then
            noVisual = noVisual + 1
            return
        end
        CowVariants.refresh(animal, true)
        if animal.cvShown ~= nil then
            local key = animal.cvShown .. string.format("  (slot %s)", tostring(animal.visualAnimalIndex))
            counts[key] = (counts[key] or 0) + 1
            total = total + 1
        end
    end)

    local lines = {}
    for key, n in pairs(counts) do table.insert(lines, string.format("  %3d  %s", n, key)) end
    table.sort(lines)
    local system = g_currentMission.animalSystem
    local missing = {}
    if not pedigreeSlotLoaded(system) then table.insert(missing, tostring(pedigreeSlot)) end
    for _, sizes in ipairs({ CowVariants.CONFIG.beef.slots, CowVariants.CONFIG.calf.slots, CowVariants.CONFIG.dairy.slots,
                             { CowVariants.CONFIG.calf.walkBabySlot, CowVariants.CONFIG.calf.bigBabySlot } }) do
        for _, slot in pairs(sizes) do
            if not slotLoaded(system, slot) and slot ~= pedigreeSlot then table.insert(missing, tostring(slot)) end
        end
    end
    table.sort(missing)
    local slots = #missing == 0 and "pedigree, dairy, beef and calf size slots loaded"
        or ("slots NOT loaded: " .. table.concat(missing, ", ") .. " - check models/cow/animals.xml")
    return string.format("CowVariants: %d adult cattle re-checked (%d cattle without a visual); %s, "
        .. "%d pens rebuilt for it%s\n%s", total, noVisual, slots, rebuilt,
        baseVisualIndex == nil and " (slot routing NOT installed)" or "", table.concat(lines, "\n"))
end


--- Console: every beef animal's weight against its breed's weight for its age, and the level shown.
function CowVariants:consoleCommandWeights()
    local lines = {}
    forEachCow(function(animal)
        local beef = CowVariants.beefBreed(animal)
        if beef == nil or animal.visualAnimal == nil then return end
        animal.cvWeightBand = nil
        local level = CowVariants.weightLevel(animal)
        local band = animal.cvWeightBand or { 0, 0 }
        local calfStep = CowVariants.calfStep(animal)
        local step = calfStep ~= nil and string.format("calf %d", calfStep) or string.format("step %+d", CowVariants.beefStep(animal))
        table.insert(lines, string.format("  %-20s %-6s %3dm %7.1f kg  normal %4.0f-%4.0f kg  %-6s %-7s slot %s  value x%.2f",
            tostring(animal.breed), tostring(animal.gender), animal.age or 0, animal.weight or 0, band[1], band[2],
            level, step, tostring(animal.visualAnimalIndex), CowVariants.priceFactor(animal)))
    end)
    table.sort(lines)
    local w = CowVariants.CONFIG.beef.weight
    return string.format("CowVariants beef weights (lean below x%.2f of the band, heavy from x%.2f, steers x%.2f):\n%s",
        w.leanBelow, w.heavyFrom, w.steerHeavyFrom, table.concat(lines, "\n"))
end


--- Every calf and baby: the slot its visual is on (RLRM's animal.visualAnimalIndex, nil when it has none), the
--- slot it belongs on for its age (RLRM's age stage, routed), and the model file - to see the growth stages
--- in game. A "<<" marks one on the wrong slot (a pen rebuild moves it: the day's sweep does).
function CowVariants:consoleCommandYoung()
    local system = g_currentMission.animalSystem
    local cowType = system:getTypeByIndex(AnimalType.COW)
    local lines, wrong = {}, 0
    forEachCowPen(function(placeable, animals)
        local pen = placeable.getName ~= nil and tostring(placeable:getName()) or "?"
        for _, animal in ipairs(animals) do
            local age = animal.age or 0
            if age < 12 then
                local base = baseVisualIndex ~= nil and baseVisualIndex(system, animal.subTypeIndex, age == -1 and 0 or age) or nil
                local ok, want = pcall(CowVariants.slotFor, animal, base, system)
                if not ok then want = "error: " .. tostring(want) end
                local slot = animal.visualAnimalIndex
                local model = slot ~= nil and cowType ~= nil and cowType.animals[slot] ~= nil and cowType.animals[slot].filename or "-"
                if slot ~= want then wrong = wrong + 1 end
                table.insert(lines, string.format("  %-16s %-22s %-6s %2dm  uid %-8s slot %-3s belongs %-3s %s %s",
                    pen, tostring(animal.breed), tostring(animal.gender), age, tostring(animal.uniqueId), tostring(slot),
                    tostring(want), slot ~= want and "<<" or "  ", string.match(tostring(model), "[^/]*$")))
            end
        end
    end)
    table.sort(lines)
    return string.format("CowVariants young cattle: %d under 12 months, %d not on their slot%s\n%s", #lines, wrong,
        baseVisualIndex == nil and " (slot routing NOT installed)" or "", table.concat(lines, "\n"))
end


-- RLRM loads after this pack (mods load in name order), so this usually waits for loadMap
CowVariants:installHooks()

addModEventListener(CowVariants)
