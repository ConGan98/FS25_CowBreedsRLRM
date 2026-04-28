-- CHECKPOINT: File is being read
--print(">>> HOOK_DEBUG 1: File started")

MyLivestockHook = {}
MyLivestockHook.isHooked = false
VisualsHook = {
    isHooked = false,
    checked = false
}


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
                
                -- Run custom shader code
                if instance.nodes and instance.nodes.monitor then
                    if instance.animal == nil then return end
					local uniqueId = instance.animal.uniqueId
					local numChildren = getNumOfChildren(instance.nodes.monitor)
					
					if numChildren ==  nil then return end 
                    for i = 0, 5 do
						if i < numChildren then
							local child = getChildAt(instance.nodes.monitor, i)
							--print("The value is: " .. tostring(i))
							if child ~= nil then
								-- Success! Perform actions
								local digit = tonumber(string.sub(uniqueId, i+1, i+1)) or 0
								--print(string.format("Node Index: %d | ID Position: %d | Digit: %d", i, i + 1, digit))
								setShaderParameter(child, "playScale", digit, 0, 64, 1, false)
							end
						end
					end
                    --print(">>> Hook active: Shader applied to Monitor for ID: " .. uniqueId)
                end
            end
            
            VisualsHook.isHooked = true
        end
	end
end

-- CHECKPOINT: Registering the Listener
addModEventListener(MyLivestockHook)
--print(">>> HOOK_DEBUG 3: Registration finished")