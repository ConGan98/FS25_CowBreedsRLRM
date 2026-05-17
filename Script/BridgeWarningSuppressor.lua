-- Suppresses RLRM's player-facing "configOverride conflict" dialog.
--
-- Timing (verified from log):
--   T+0       BridgeWarningSuppressor sourced, listener registered.
--   T+20s     RLRM bridge load completes; _summariseConfigOverrideConflicts
--             sets RLMapBridge.pendingConfigOverrideConflictWarning.
--   T+44s     loadMap fires on our listener.
--   T+84s     RealisticLivestock_FSBaseMission._showStartupDialogs reads
--             and clears the pending slot; the dialog is queued for display.
--   T+84.3s   update() begins firing - already 300ms too late.
--
-- So polling in update() is unwinnable: the dialog reader runs before the
-- first update tick. loadMap is the earliest mod-event-listener callback,
-- and it fires comfortably before the reader. We clear the slot there.
-- update() is kept as a defensive backstop in case timing ever shifts.

BridgeWarningSuppressor = {
    suppressed = false,
}

local function clearPendingWarning(self, callerLabel)
    if self.suppressed then return end

    local rlrm = FS25_RealisticLivestockRM
    if rlrm == nil or rlrm.RLMapBridge == nil then return end

    local bridge = rlrm.RLMapBridge
    if bridge.pendingConfigOverrideConflictWarning ~= nil then
        print(string.format("[CowBreedsRLRM/BridgeSuppressor] suppressed RLMapBridge configOverride conflict dialog (via %s)", callerLabel))
        bridge.pendingConfigOverrideConflictWarning = nil
        self.suppressed = true
    end
end

function BridgeWarningSuppressor:loadMap(name)
    clearPendingWarning(self, "loadMap")
end

function BridgeWarningSuppressor:update(dt)
    clearPendingWarning(self, "update")
end

addModEventListener(BridgeWarningSuppressor)
