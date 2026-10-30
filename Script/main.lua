local modDirectory = g_currentModDirectory
local modName = g_currentModName

print(string.format("[CowBreedsRLRM] main.lua sourced (modName=%s, modDir=%s)", tostring(modName), tostring(modDirectory)))

source(modDirectory .. "Script/BaseBreedAccessories.lua")
source(modDirectory .. "Script/Migration.lua")
source(modDirectory .. "Script/CoatMigrationData.lua")
source(modDirectory .. "Script/CoatMigration.lua")
source(modDirectory .. "Script/VisualMonitor.lua")
source(modDirectory .. "Script/HornSelector.lua")
source(modDirectory .. "Script/EarTagGlyphs.lua")
source(modDirectory .. "Script/EarTagLayout.lua")
source(modDirectory .. "Script/EarTags.lua")
source(modDirectory .. "Script/CollarFits.lua")
source(modDirectory .. "Script/RumpFits.lua")
source(modDirectory .. "Script/CowVariants.lua")
