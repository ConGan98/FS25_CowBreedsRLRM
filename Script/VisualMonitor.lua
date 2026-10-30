-- CHECKPOINT: File is being read
--print(">>> HOOK_DEBUG 1: File started")

MyLivestockHook = {}
MyLivestockHook.isHooked = false
VisualsHook = {
    isHooked = false,
    checked = false
}



-- RLRM's "apply / remove all monitors" (the in-game menu's livestock page, RealisticLivestockFrame) sets
-- every animal's monitor but doesn't redraw them - its RLRM-menu button for one animal does
-- (animal:updateVisualMonitor) - and AnimalMonitorEvent:run doesn't either, so the collars only showed
-- after a reload. Both redraw here (the event: for the other players in multiplayer).
local function refreshMonitors(animals)
    for _, animal in pairs(animals or {}) do
        if animal.updateVisualMonitor ~= nil then animal:updateVisualMonitor() end
    end
end

local function hookMonitorRefresh(modTable)
    local frame = modTable.RealisticLivestockFrame
    if frame ~= nil and frame.onClickChangeMonitors ~= nil then
        frame.onClickChangeMonitors = Utils.appendedFunction(frame.onClickChangeMonitors, function(self)
            local ok, err = pcall(function()
                local row = self.selectedRow
                if row ~= nil and row.placeable ~= nil and row.placeable.getClusters ~= nil then
                    refreshMonitors(row.placeable:getClusters())
                end
            end)
            if not ok then print("[CowBreedsRLRM/VisualMonitor] apply-all refresh error: " .. tostring(err)) end
        end)
    end
    local event, util = modTable.AnimalMonitorEvent, modTable.RLAnimalUtil
    if event ~= nil and event.run ~= nil and util ~= nil and util.find ~= nil then
        event.run = Utils.appendedFunction(event.run, function(self)
            local ok, err = pcall(function()
                local ids = self.animal
                if self.object == nil or ids == nil or self.object.getClusterSystem == nil then return end
                local clusterSystem = self.object:getClusterSystem()
                if clusterSystem == nil then return end
                local country = ids.country or (ids.birthday ~= nil and ids.birthday.country or nil)
                refreshMonitors({ util.find(clusterSystem.animals, ids.farmId, ids.uniqueId, country) })
            end)
            if not ok then print("[CowBreedsRLRM/VisualMonitor] monitor event refresh error: " .. tostring(err)) end
        end)
    end
end

-- CHECKPOINT : Event Listeners
function MyLivestockHook:loadMap(name)
    --print(">>> HOOK_DEBUG 2: loadMap reached")
    self:update()
end

function MyLivestockHook:update(dt)
	-- EXTRA SAFETY: Check if the table itself exists
    if not VisualsHook then 
        return 
    end

    -- Use the direct table name to avoid 'self' being nil
    if VisualsHook.isHooked then 
        return 
    end

    -- 3. Use Data Dump Mod Table name here
    local modTable = FS25_RealisticLivestockRM 
    
    if modTable ~= nil and modTable.VisualAnimal ~= nil then
        local targetClass = modTable.VisualAnimal
        
        if targetClass.setMonitor ~= nil then
            --print(">>> SUCCESS: Found nested setMonitor! Injecting now...")
            
            -- 3. THE INJECTION
            local originalSetMonitor = targetClass.setMonitor
            
            targetClass.setMonitor = function(instance)
                -- Run the original mod code (handles visibility)
                originalSetMonitor(instance)

                -- Run custom shader code, fully guarded so a bad node/id can never
                -- throw out of setMonitor (which renders per-visual).
                local ok, err = pcall(function()
                    if instance.nodes == nil or instance.nodes.monitor == nil then return end
                    -- a pedigree bull's collar stays hidden (CowVariants.showMonitor)
                    if CowVariants ~= nil and CowVariants.showMonitor ~= nil then CowVariants.showMonitor(instance) end
                    -- the new collar's number tags (CowVariants); the rest is the old collar's digits
                    if CowVariants ~= nil and CowVariants.setCollarNumber ~= nil and CowVariants.setCollarNumber(instance) then
                        return
                    end
                    if instance.animal == nil or instance.animal.uniqueId == nil then return end
                    local uniqueId = tostring(instance.animal.uniqueId)
                    local numChildren = getNumOfChildren(instance.nodes.monitor)
                    if numChildren == nil then return end
                    for i = 0, 5 do
                        if i < numChildren then
                            local child = getChildAt(instance.nodes.monitor, i)
                            if child ~= nil then
                                local digit = tonumber(string.sub(uniqueId, i + 1, i + 1)) or 0
                                setShaderParameter(child, "playScale", digit, 0, 64, 1, false)
                            end
                        end
                    end
                end)
                if not ok then
                    print("[CowBreedsRLRM/VisualMonitor] setMonitor shader error: " .. tostring(err))
                end
            end
            
            hookMonitorRefresh(modTable)
            VisualsHook.isHooked = true
        end
	end
end

-- CHECKPOINT: Registering the Listener
addModEventListener(MyLivestockHook)
--print(">>> HOOK_DEBUG 3: Registration finished")