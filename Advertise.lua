-- Crafting and Farming Forever :: Advertise
-- Advertising in Trade chat: the Ad box beside the chat, its destination picker and secure send buttons, quotes in
-- whispers.

local _, ns = ...
local UI = ns.UI
local FlatButton = UI.FlatButton
local Color = UI.Color
local COLOR_WARN = "ffff9933"

local Advertise = {}
ns.Advertise = Advertise

local AD = {
	COOLDOWN_SECONDS = 60,
	BOX_WIDTH = 26, BOX_HEIGHT = 20,
	BUTTON_WIDTH = 130, BUTTON_HEIGHT = 20,
}
local lastAdvertised = {} -- by destination

-- Where an ad can go. The slash command is for the chat box fallback; Trade's depends on its channel number.
local DESTINATIONS = {
	{ key = "TRADE", label = "Trade", chatType = "CHANNEL" },
	{ key = "GUILD", label = "Guild", chatType = "GUILD", slash = "/g" },
	{ key = "SAY", label = "Say", chatType = "SAY", slash = "/s" },
	{ key = "YELL", label = "Yell", chatType = "YELL", slash = "/y" },
}

-- {profession} becomes the profession's link. The player can write their own on the Options tab.
Advertise.DEFAULT_TEXT = "{profession} available for hire! Your materials, or I'll give you a price based on material cost."
Advertise.TEXT_MAX = 180 -- bytes: a chat line holds 255, and the link takes about 70

-- Off hides the Ad box beside the chat and the Profit tab's Advertise button.
function Advertise.Enabled()
	return ns.Option("adEnabled")
end

function Advertise.Text()
	return ns.db.ui.adText or Advertise.DEFAULT_TEXT
end

-- Empty, or the default itself, goes back to the default.
function Advertise.SetText(text)
	text = ns.CleanChatText(text, Advertise.TEXT_MAX)
	ns.db.ui.adText = (text ~= "" and text ~= Advertise.DEFAULT_TEXT) and text or nil
end

function Advertise.Destinations()
	return DESTINATIONS
end

function Advertise.SetDestination(key)
	ns.db.ui.adDestination = key
end

local function CurrentDestination()
	local selected = ns.db.ui.adDestination
	for _, destination in ipairs(DESTINATIONS) do
		if destination.key == selected then return destination end
	end
	return DESTINATIONS[1]
end

-- The tab's profession, or on the All tab the one that's open.
function Advertise.DestinationLabel()
	return CurrentDestination().label
end

-- The same profession the Profit tab's Skill up mode looks at.
function UI.AdvertisedProfession()
	return (UI.SkillProfession())
end

-- Why this profession can't be advertised on this character; nil when it can.
function Advertise.Reason(professionID)
	if not Advertise.Enabled() then return "Advertising is turned off. Turn it on in the Options tab." end
	if not professionID then return "Pick a profession tab first." end
	if not ns.Recipes.IsCraftingProfession(professionID) then return "Gathering professions aren't advertised." end
	if not ns.Recipes.CharHasProfession(ns.CharKey(), professionID) then
		return "This character doesn't have that profession."
	end
	return nil
end

-- The channel number of Trade chat, preferring plain Trade over a separate services channel. Nil when not in it.
local function TradeChannel()
	local tradeName = (TRADE or "Trade"):lower()
	local channels = { GetChannelList() }
	local fallback
	for i = 1, #channels, 3 do
		local id, name = channels[i], channels[i + 1]
		if type(name) == "string" and name:lower():find(tradeName, 1, true) then
			if not name:lower():find("services", 1, true) then return id end
			fallback = fallback or id
		end
	end
	return fallback
end

local function OpenChatWith(text)
	if ChatFrameUtil and ChatFrameUtil.OpenChat then
		ChatFrameUtil.OpenChat(text)
	else
		ChatFrame_OpenChat(text)
	end
end

-- A reply to whoever whispered last. Never sent automatically: the user checks it and presses Enter.
function Advertise.QuoteInWhisper(recipeID, crafts)
	local text = ns.Queue.QuoteText(recipeID, crafts)
	if not text then
		ns.Say("chatWarnings", "A material has no price yet, so there's nothing to quote. Scan the auction house first.")
		return
	end
	-- A customer gets this price, so say so every time, not once a session.
	if ns.Prices.IsStale() then
		ns.Say("chatWarnings", Color(COLOR_WARN, UI.ScanAgeText() .. " This quote may be off: scan the auction house before you send it."))
	end
	local getTarget = (ChatFrameUtil and ChatFrameUtil.GetLastTellTarget) or ChatEdit_GetLastTellTarget
	local target = getTarget and getTarget()
	-- /w takes one word as the name: a two-part Forever name ("Felo Bank") would whisper "Felo" with "Bank ..." as the
	-- text. /r goes to the same person.
	if target and target ~= "" and not target:find(" ", 1, true) then
		OpenChatWith("/w " .. target .. " " .. text)
	else
		OpenChatWith("/r " .. text)
	end
end

-- Whether the current destination can take an ad right now, its Trade channel number if any, and why not if not.
local function DestinationState(destination)
	if destination.key == "TRADE" then
		local channel = TradeChannel()
		if not channel then return false, nil, "You're not in Trade chat. Go to a city and try again." end
		return true, channel
	end
	if destination.key == "GUILD" and not IsInGuild() then return false, nil, "This character isn't in a guild." end
	return true
end

local function CooldownLeft(destination)
	return math.max(0, AD.COOLDOWN_SECONDS - (time() - (lastAdvertised[destination.key] or 0)))
end

-- The chat command for an ad, or nil and the reason there can't be one right now.
local function AdCommand(professionID, destination)
	local reason = Advertise.Reason(professionID)
	if reason then return nil, reason end
	local available, channel, why = DestinationState(destination)
	if not available then return nil, why end
	local char = ns.db.chars[ns.CharKey()]
	local link = char.links and char.links[professionID]
	local message = ns.Fill(Advertise.Text(), { profession = link or ns.Recipes.ProfessionName(professionID) or "Crafting" })
	return (destination.slash or ("/" .. tostring(channel))) .. " " .. message, nil, link ~= nil
end

local NO_LINK_NOTE = "No profession link saved yet, so this uses its name. Open the profession once to get the link."

-- For the Profit window button and the slash command. The game blocks add-ons from sending chat, and only the secure
-- buttons beside the chat window can post on one click, so this fills in the chat box for Enter to send.
function Advertise.Send(professionID)
	local destination = CurrentDestination()
	local command, why, hasLink = AdCommand(professionID, destination)
	if not command then
		ns.Say("chatWarnings", why)
		return
	end
	local wait = CooldownLeft(destination)
	if wait > 0 then
		ns.Say("chatWarnings", ("Please wait %d more seconds, so %s doesn't get spammed."):format(wait, destination.label))
		return
	end
	if not hasLink then ns.Say("chatWarnings", NO_LINK_NOTE) end
	lastAdvertised[destination.key] = time()
	Advertise.UpdateButtons()
	OpenChatWith(command)
end

-- Beside the chat frame: one small box that opens a destination picker and a button per crafting profession of this
-- character. They work with no profession window open, using the link saved when the profession was last opened, and
-- show whenever the chosen destination can take a post. Posting closes them again.
local adButtons = {}
Advertise.buttons = adButtons
local cooldownTimerRunning = false
local adBox, destinationButton, destinationMenu
local adOpen = false

local function CreateDestinationPicker()
	adBox = FlatButton(UIParent, "Ad", AD.BOX_WIDTH, AD.BOX_HEIGHT, false, "CFFAdBox")
	-- Past the chat frame's own scroll bar.
	adBox:SetPoint("BOTTOMLEFT", ChatFrame1, "BOTTOMRIGHT", 28, 0)
	adBox:SetText("Ad")
	adBox:SetScript("OnClick", function()
		-- The profession buttons are secure, so they can't appear or hide during combat.
		if InCombatLockdown() then
			ns.Say("chatWarnings", "Advertising buttons can't open during combat.")
			return
		end
		adOpen = not adOpen
		Advertise.UpdateButtons()
	end)
	Advertise.box = adBox

	destinationButton = FlatButton(UIParent, "", AD.BUTTON_WIDTH, AD.BUTTON_HEIGHT, false, "CFFAdDestination")
	destinationButton:SetPoint("BOTTOMLEFT", adBox, "TOPLEFT", 0, 2)
	destinationButton:Hide()
	Advertise.destinationButton = destinationButton

	destinationMenu = CreateFrame("Frame", nil, destinationButton)
	destinationMenu:SetSize(60, #DESTINATIONS * AD.BUTTON_HEIGHT)
	destinationMenu:SetPoint("BOTTOMLEFT", destinationButton, "BOTTOMRIGHT", 2, 0)
	destinationMenu:Hide()
	Advertise.destinationMenu = destinationMenu
	destinationMenu.options = {}
	for index, destination in ipairs(DESTINATIONS) do
		local option = FlatButton(destinationMenu, "", 60, AD.BUTTON_HEIGHT)
		option:SetPoint("BOTTOMLEFT", 0, (index - 1) * AD.BUTTON_HEIGHT)
		option:SetText(destination.label)
		option:SetScript("OnClick", function()
			ns.db.ui.adDestination = destination.key
			destinationMenu:Hide()
			Advertise.UpdateButtons()
			ns.UI.Refresh("profit")
			ns.Options.Sync()
		end)
		destinationMenu.options[destination.key] = option
	end

	destinationButton:SetScript("OnClick", function()
		destinationMenu:SetShown(not destinationMenu:IsShown())
	end)

	-- The ad buttons aren't anchored to this one, so move them when the chat window moves.
	local lastLeft, lastTop, elapsedSinceCheck = nil, nil, 0
	adBox:SetScript("OnUpdate", function(self, elapsed)
		elapsedSinceCheck = elapsedSinceCheck + elapsed
		if elapsedSinceCheck < 0.5 then return end
		elapsedSinceCheck = 0
		local left, top = self:GetLeft(), self:GetTop()
		if left ~= lastLeft or top ~= lastTop then
			lastLeft, lastTop = left, top
			Advertise.UpdateButtons()
		end
	end)
end

-- A secure macro button: the game itself runs the chat command from the click, which add-on code isn't allowed to do.
-- These can't be changed during combat, so UpdateButtons waits until it ends, and they're placed on the screen rather
-- than anchored to the chat frame, which would restrict the chat frame in combat too.
local function AdButton(index)
	local button = adButtons[index]
	if not button then
		button = FlatButton(UIParent, "", AD.BUTTON_WIDTH, AD.BUTTON_HEIGHT, false, "CFFAdvertiseButton" .. index,
			"SecureActionButtonTemplate")
		button:RegisterForClicks("AnyUp", "AnyDown")
		button:SetAttribute("type", "macro")
		button:SetScript("PostClick", function(self, _, down)
			-- With both directions registered, the macro only runs on the one matching this setting.
			if (down and true or false) ~= (GetCVarBool("ActionButtonUseKeyDown") and true or false) then return end
			if not self.hasLink then ns.Say("chatWarnings", NO_LINK_NOTE) end
			lastAdvertised[self.destinationKey] = time()
			adOpen = false
			Advertise.UpdateButtons()
		end)
		adButtons[index] = button
	end
	return button
end

function Advertise.UpdateButtons()
	if not ns.CharKey() or InCombatLockdown() then return end
	local crafting = {}
	for _, profession in ipairs(ns.Recipes.KnownProfessions()) do
		if Advertise.Reason(profession.id) == nil then table.insert(crafting, profession) end
	end

	if not Advertise.Enabled() then adOpen = false end
	if #crafting > 0 and not destinationButton then CreateDestinationPicker() end
	local destination = CurrentDestination()
	if adBox then
		adBox:SetShown(#crafting > 0)
		destinationButton:SetText("To: " .. destination.label)
		destinationButton:SetShown(adOpen and #crafting > 0)
		if not adOpen then destinationMenu:Hide() end
	end

	-- The profession buttons stack above the picker, which sits above the box.
	local left = adBox and adBox:GetLeft()
	local top = adBox and adBox:GetTop() and (adBox:GetTop() + AD.BUTTON_HEIGHT + 2)
	local available = DestinationState(destination)
	local wait = CooldownLeft(destination)
	local shown = 0
	if adOpen and available and left and top then
		for _, profession in ipairs(crafting) do
			local command, _, hasLink = AdCommand(profession.id, destination)
			if command then
				shown = shown + 1
				local button = AdButton(shown)
				button.hasLink = hasLink
				button.destinationKey = destination.key
				button:SetAttribute("macrotext", command)
				button:ClearAllPoints()
				button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, top + 2 + (shown - 1) * (AD.BUTTON_HEIGHT + 2))
				button:SetText(wait > 0 and ("%s (%d)"):format(profession.name, wait) or profession.name)
				button:SetEnabled(wait <= 0)
				button:Show()
			end
		end
	end
	for index = shown + 1, #adButtons do adButtons[index]:Hide() end

	if wait > 0 and shown > 0 and not cooldownTimerRunning then
		cooldownTimerRunning = true
		C_Timer.After(1, function()
			cooldownTimerRunning = false
			Advertise.UpdateButtons()
		end)
	end
end

local function RequestAdButtonUpdate()
	-- Channel changes can land just after these events.
	ns.Debounce("adbuttons", 1, Advertise.UpdateButtons)
end

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "CHANNEL_UI_UPDATE", "CHAT_MSG_CHANNEL_NOTICE", "PLAYER_GUILD_UPDATE", "PLAYER_REGEN_ENABLED" }) do
	ns.On(event, RequestAdButtonUpdate)
end
