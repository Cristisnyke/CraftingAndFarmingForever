-- Crafting and Farming Forever :: What's new
-- The Changelog tab: every version's notes from CHANGELOG.md (through Changelog.lua), the new ones marked, what the
-- add-on needs and what's coming. The tab is lit until the notes of the installed version have been opened.
-- Also the chat warning when Syndicator is missing.

local ADDON, ns = ...

local WhatsNew = {}
ns.WhatsNew = WhatsNew

local GOLD = "|cffffd100"

WhatsNew.NEEDS = GOLD .. "Auctionator|r and " .. GOLD .. "Syndicator|r are both needed for Crafting and Farming "
	.. "Forever to work properly: Auctionator for prices and the shopping list, Syndicator for your alts' stock, "
	.. "your auctions and the Restock tab."
WhatsNew.COMING = GOLD .. "Coming soon:|r TradeSkillMaster (TSM) support."
WhatsNew.NO_SYNDICATOR = "Syndicator isn't installed or is turned off. Crafting and Farming Forever needs it to "
	.. "work properly: without it your alts' stock isn't counted (so it may tell you to buy what an alt already has) "
	.. "and the Restock tab is off. Install Syndicator from CurseForge, then restart the game."

---------------------------------------------------------------------------
-- Versions
---------------------------------------------------------------------------

function WhatsNew.CurrentVersion()
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
	return get and get(ADDON, "Version") or nil
end

local function Parts(version)
	local a, b, c = tostring(version or ""):match("^(%d+)%.(%d+)%.(%d+)")
	if not a then return nil end
	return { tonumber(a), tonumber(b), tonumber(c) }
end

-- -1, 0 or 1 as a is older than, the same as or newer than b. nil if either isn't x.y.z.
function WhatsNew.Compare(a, b)
	local pa, pb = Parts(a), Parts(b)
	if not (pa and pb) then return nil end
	for i = 1, 3 do
		if pa[i] ~= pb[i] then return pa[i] < pb[i] and -1 or 1 end
	end
	return 0
end

-- The changelog sections that are new after updating from `seen` to `current`, newest first: every version newer than
-- `seen`, up to `current`. With no `seen` (updated from a version before this window existed) only the newest one.
function WhatsNew.Sections(seen, current)
	local result = {}
	for _, section in ipairs(ns.CHANGELOG or {}) do
		local notNewer = WhatsNew.Compare(section.version, current)
		if notNewer and notNewer <= 0 then
			if seen == nil then
				table.insert(result, section)
				break
			end
			local newer = WhatsNew.Compare(section.version, seen)
			if newer and newer > 0 then table.insert(result, section) end
		end
	end
	return result
end

---------------------------------------------------------------------------
-- Seen or not
---------------------------------------------------------------------------
-- db.lastSeenVersion is the version whose notes the player has opened. Until the saved data is known it can't be
-- told whether this is an update, so nothing counts as unseen.

function WhatsNew.HasUnseen()
	if not ns.dataReady then return false end
	local current = WhatsNew.CurrentVersion()
	if not WhatsNew.Compare(current, current) then return false end
	local seen = ns.db.lastSeenVersion
	return seen == nil or (WhatsNew.Compare(seen, current) or 0) < 0
end

-- Returns the version seen before, for marking what's new.
function WhatsNew.MarkSeen()
	local before = ns.db.lastSeenVersion
	local current = WhatsNew.CurrentVersion()
	if ns.dataReady and WhatsNew.Compare(current, current) then ns.db.lastSeenVersion = current end
	return before
end

-- A first install has nothing new to point at: its notes would only repeat the add-on's description.
ns.WhenDataReady(function()
	if not ns.savedDataFound then WhatsNew.MarkSeen() end
	if ns.UI and ns.UI.RefreshTabs then ns.UI.RefreshTabs() end
end)

---------------------------------------------------------------------------
-- Changelog tab
---------------------------------------------------------------------------

-- Every version's notes, newest first, with the ones new since `seenBefore` marked.
function WhatsNew.Text(seenBefore, wasUnseen)
	local new = {}
	if wasUnseen then
		for _, section in ipairs(WhatsNew.Sections(seenBefore, WhatsNew.CurrentVersion())) do new[section] = true end
	end
	local parts = {}
	for _, section in ipairs(ns.CHANGELOG or {}) do
		local heading = GOLD .. "Version " .. section.version .. "|r"
		if new[section] then heading = heading .. "  |cff55dd55new|r" end
		table.insert(parts, heading .. "\n" .. table.concat(section.lines, "\n"))
	end
	if #parts == 0 then table.insert(parts, "No notes yet.") end
	return table.concat(parts, "\n\n")
end

function WhatsNew.NotesText()
	local lines = { WhatsNew.NEEDS }
	if not WhatsNew.SyndicatorLoaded() then
		table.insert(lines, "|cffff6655Syndicator isn't active on this character.|r")
	end
	table.insert(lines, WhatsNew.COMING)
	return table.concat(lines, "\n")
end

local function UpdateScroll(pane)
	local height = pane.text:GetStringHeight() or 0
	pane.child:SetHeight(math.max(height, 1))
	local range = math.max(0, height - (pane.scroll:GetHeight() or 0))
	pane.range = range
	pane.slider:SetMinMaxValues(0, range)
	pane.slider:SetShown(range > 0)
	pane.slider:SetValue(math.min(pane.scroll:GetVerticalScroll() or 0, range))
end

local function ScrollTo(pane, value)
	value = math.max(0, math.min(value, pane.range or 0))
	pane.scroll:SetVerticalScroll(value)
	pane.slider:SetValue(value)
end

-- Fills the main window's Changelog pane. top: where the text starts; the pane's top row stays free for the
-- stale-price banner. Returns the pane's update function.
function WhatsNew.BuildPane(frame, top)
	local pane = {}
	local footer = 70

	local scroll = CreateFrame("ScrollFrame", nil, frame)
	scroll:SetPoint("TOPLEFT", 14, -top)
	scroll:SetPoint("BOTTOMRIGHT", -26, footer)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta) ScrollTo(pane, (self:GetVerticalScroll() or 0) - delta * 40) end)
	pane.scroll = scroll

	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)
	pane.child = child

	local text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT")
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	text:SetSpacing(2)
	pane.text = text

	local function FitWidth(width)
		width = math.max(100, (type(width) == "number" and width or 0) - 4)
		child:SetWidth(width)
		text:SetWidth(width)
	end
	scroll:SetScript("OnSizeChanged", function(_, width)
		FitWidth(width)
		UpdateScroll(pane)
	end)

	local slider = CreateFrame("Slider", nil, frame)
	slider:SetPoint("TOPRIGHT", -10, -top)
	slider:SetPoint("BOTTOMRIGHT", -10, footer)
	slider:SetWidth(10)
	slider:SetOrientation("VERTICAL")
	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(0.6, 0.6, 0.6, 0.8)
	thumb:SetSize(10, 36)
	slider:SetThumbTexture(thumb)
	slider:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)
	pane.slider = slider

	local rule = frame:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(0.5, 0.5, 0.5, 0.5)
	rule:SetHeight(1)
	rule:SetPoint("BOTTOMLEFT", 10, footer - 6)
	rule:SetPoint("BOTTOMRIGHT", -10, footer - 6)

	local notes = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	notes:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 4, -6)
	notes:SetPoint("TOPRIGHT", rule, "BOTTOMRIGHT", -4, -6)
	notes:SetJustifyH("LEFT")
	notes:SetTextColor(1, 1, 1)
	pane.notes = notes

	-- Opening the tab marks the notes seen. The "new" marks stay for the rest of the session.
	local seenBefore, wasUnseen = nil, false

	return function()
		if WhatsNew.HasUnseen() then
			wasUnseen = true
			seenBefore = WhatsNew.MarkSeen()
			if ns.UI.RefreshTabs then ns.UI.RefreshTabs() end
		end
		FitWidth(scroll:GetWidth())
		text:SetText(WhatsNew.Text(seenBefore, wasUnseen))
		notes:SetText(WhatsNew.NotesText())
		-- The text's height is only known once the client has laid it out.
		C_Timer.After(0, function() UpdateScroll(pane) end)
	end
end

---------------------------------------------------------------------------
-- Syndicator warning
---------------------------------------------------------------------------

function WhatsNew.SyndicatorLoaded()
	local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
	return loaded ~= nil and loaded("Syndicator") and true or false
end

-- Once per session. Syndicator loads before this add-on, so if it isn't loaded by now it's missing or turned off.
ns.On("PLAYER_LOGIN", function()
	C_Timer.After(8, function()
		if not WhatsNew.SyndicatorLoaded() then ns.Print("|cffff6655" .. WhatsNew.NO_SYNDICATOR .. "|r") end
	end)
end)
