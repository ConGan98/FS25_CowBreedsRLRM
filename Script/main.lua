local modDirectory = g_currentModDirectory
local modName = g_currentModName

print(string.format("[CowBreedsRLRM] main.lua sourced (modName=%s, modDir=%s)", tostring(modName), tostring(modDirectory)))

source(modDirectory .. "Script/VanillaEditionBridge.lua")
source(modDirectory .. "Script/Migration.lua")
source(modDirectory .. "Script/VisualMonitor.lua")
source(modDirectory .. "Script/BridgeWarningSuppressor.lua")
