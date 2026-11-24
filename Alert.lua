-- Crafting and Farming Forever :: Alert
-- The craft alert: a sound a few seconds before a batch of crafts runs out while this character still has crafts in
-- the queue, so you can be alt-tabbed and come back in time to press Craft Next. Set up in the Craft alert menu on the
-- Options tab. db.ui.craftAlert (on only when true), alertSound, alertChannel, alertLead (seconds).

local _, ns = ...

local Alert = {}
ns.Alert = Alert

-- The game's own sounds, so nothing has to be shipped. kit = the SOUNDKIT name, id = its number when a client
-- lacks the name.
Alert.SOUNDS = {
	{ key = "raidWarning", label = "Raid warning", kit = "RAID_WARNING", id = 8959 },
	{ key = "readyCheck", label = "Ready check", kit = "READY_CHECK", id = 8960 },
	{ key = "alarm", label = "Alarm clock", kit = "ALARM_CLOCK_WARNING_3", id = 12889 },
	{ key = "queuePop", label = "Queue ready", kit = "PVP_THROUGH_QUEUE", id = 8458 },
	{ key = "whisper", label = "Whisper", kit = "TELL_MESSAGE", id = 3081 },
	{ key = "levelUp", label = "Level up", kit = "LEVELUPSOUND", id = 888 },
}
-- The game's sound channels, each with its own volume slider (System > Sound) and on/off switch.
Alert.CHANNELS = {
	{ key = "Master", label = "Master", enable = "Sound_EnableAllSound", volume = "Sound_MasterVolume" },
	{ key = "SFX", label = "Effects", enable = "Sound_EnableSFX", volume = "Sound_SFXVolume" },
	{ key = "Music", label = "Music", enable = "Sound_EnableMusic", volume = "Sound_MusicVolume" },
	{ key = "Ambience", label = "Ambience", enable = "Sound_EnableAmbience", volume = "Sound_AmbienceVolume" },
	{ key = "Dialog", label = "Dialog", enable = "Sound_EnableDialog", volume = "Sound_DialogVolume" },
}
Alert.LEAD_DEFAULT, Alert.LEAD_MAX = 3, 30
local BACKGROUND_CVAR = "Sound_EnableSoundWhenGameIsInBG"

local function Find(list, key)
	for _, entry in ipairs(list) do
		if entry.key == key then return entry end
	end
	return list[1]
end

function Alert.Enabled() return ns.db.ui.craftAlert == true end
function Alert.SetEnabled(on) ns.db.ui.craftAlert = on and true or false end
function Alert.Sound() return Find(Alert.SOUNDS, ns.db.ui.alertSound) end
function Alert.SetSound(key) ns.db.ui.alertSound = key end
function Alert.Channel() return Find(Alert.CHANNELS, ns.db.ui.alertChannel) end
function Alert.SetChannel(key) ns.db.ui.alertChannel = key end
function Alert.Lead() return ns.db.ui.alertLead or Alert.LEAD_DEFAULT end

function Alert.SetLead(seconds)
	ns.db.ui.alertLead = math.min(math.max(math.floor(seconds), 1), Alert.LEAD_MAX)
end

function Alert.Play()
	local sound = Alert.Sound()
	PlaySound((SOUNDKIT and SOUNDKIT[sound.kit]) or sound.id, Alert.Channel().key)
end

-- The game's "Sound in Background" setting; nil when this client doesn't have it.
function Alert.BackgroundSound()
	if GetCVar(BACKGROUND_CVAR) == nil then return nil end
	return GetCVarBool(BACKGROUND_CVAR)
end

function Alert.SetBackgroundSound(on) SetCVar(BACKGROUND_CVAR, on and "1" or "0") end

-- Why the alert can't be heard, or nil: the channel or all sound switched off or at volume 0.
function Alert.MutedReason()
	local channel = Alert.Channel()
	if GetCVar("Sound_EnableAllSound") == "0" then return "All sound is off in the game's Sound options." end
	if GetCVar(channel.enable) == "0" then return ("%s is turned off in the game's Sound options."):format(channel.label) end
	if tonumber(GetCVar("Sound_MasterVolume") or "1") == 0 then return "The master volume is at 0." end
	if tonumber(GetCVar(channel.volume) or "1") == 0 then return ("The %s volume is at 0."):format(channel.label) end
end

---------------------------------------------------------------------------
-- Following the batch the game is crafting
---------------------------------------------------------------------------

local batch -- { recipeID, left = crafts the game still does without a click (nil = unknown), castEnd, alerted }
local ticker = CreateFrame("Frame")
ticker:Hide()

-- Craft Next asked the game for count crafts of the recipe.
function Alert.BatchStarted(recipeID, count)
	batch = { recipeID = recipeID, left = count }
	if Alert.Enabled() then ticker:Show() end
end

local function SecondsLeft(progress)
	if not batch.left then return progress.runSeconds end
	local each = ns.Queue.CraftSeconds(batch.recipeID)
	if batch.castEnd then return math.max(batch.castEnd - GetTime(), 0) + (batch.left - 1) * each end
	return batch.left * each
end

local function Check()
	if not batch or not Alert.Enabled() then
		ticker:Hide()
		return
	end
	if batch.alerted then return end
	local progress = ns.Queue.CraftProgress()
	local batchLeft = batch.left
		or (progress.recipeID == batch.recipeID and progress.total and progress.total - progress.done) or 1
	-- Nothing queued after this batch: no click is needed, so no sound.
	if (progress.allCount or 0) <= batchLeft then return end
	local seconds = SecondsLeft(progress)
	if seconds and seconds <= Alert.Lead() then
		batch.alerted = true
		Alert.Play()
	end
end

local since = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
	since = since + elapsed
	if since < 0.1 then return end
	since = 0
	local ok, err = pcall(Check)
	if not ok then
		ticker:Hide()
		geterrorhandler()(err)
	end
end)

local function IsCraft(unit, spellID)
	if unit ~= "player" then return false end
	if issecretvalue and issecretvalue(spellID) then return false end
	return ns.db and ns.db.recipes[spellID] ~= nil
end

ns.On("UNIT_SPELLCAST_START", function(unit, _, spellID)
	if not IsCraft(unit, spellID) then return end
	-- Started with the game's own Create button: how many it will make isn't known, the queue's count stands in.
	if not batch or batch.recipeID ~= spellID then batch = { recipeID = spellID } end
	local _, _, _, _, endMS = UnitCastingInfo("player")
	batch.castEnd = type(endMS) == "number" and endMS / 1000 or nil
	if Alert.Enabled() then ticker:Show() end
end)

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
	if not IsCraft(unit, spellID) or not batch or batch.recipeID ~= spellID then return end
	batch.castEnd = nil
	if batch.left then
		batch.left = batch.left - 1
		if batch.left <= 0 then batch = nil end
	end
end)

-- Moving or pressing Escape ends the whole batch.
local function Ended(unit, _, spellID)
	if unit ~= "player" or not batch then return end
	if spellID and not (issecretvalue and issecretvalue(spellID)) and spellID ~= batch.recipeID then return end
	batch = nil
	ticker:Hide()
end
ns.On("UNIT_SPELLCAST_INTERRUPTED", Ended)
ns.On("UNIT_SPELLCAST_FAILED", Ended)

-- After a batch made with the game's own button ends, nothing is cast for a while: forget it.
ns.On("UNIT_SPELLCAST_STOP", function(unit)
	if unit ~= "player" or not batch or batch.left then return end
	C_Timer.After(1.5, function()
		if batch and not batch.left and not UnitCastingInfo("player") then
			batch = nil
			ticker:Hide()
		end
	end)
end)
