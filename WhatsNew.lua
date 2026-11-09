-- Crafting and Farming Forever :: What's new
-- The window that opens once after an update with that version's notes from CHANGELOG.md (through Changelog.lua),
-- what the add-on needs and what's coming. Also the chat warning when Syndicator is missing.

local ADDON, ns = ...

local WhatsNew = {}
ns.WhatsNew = WhatsNew

local WIDTH, HEIGHT = 460, 420
local TEXT_WIDTH = WIDTH - 50
local FOOTER = 104
local LOGO_TEXTURE = "Interface\\AddOns\\CraftingAndFarmingForever\\Media\\Logo"
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

-- The changelog sections to show after updating from `seen` to `current`, newest first: every version newer than
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
-- Window
---------------------------------------------------------------------------

local window

local function UpdateScroll()
	local child, scroll = window.child, window.scroll
	local height = window.text:GetStringHeight() or 0
	child:SetHeight(math.max(height, 1))
	local range = math.max(0, height - (scroll:GetHeight() or 0))
	window.range = range
	window.slider:SetMinMaxValues(0, range)
	window.slider:SetShown(range > 0)
	window.slider:SetValue(math.min(scroll:GetVerticalScroll() or 0, range))
end

local function ScrollTo(value)
	value = math.max(0, math.min(value, window.range or 0))
	window.scroll:SetVerticalScroll(value)
	window.slider:SetValue(value)
end

local function CreateWindow()
	local frame = CreateFrame("Frame", "CFFWhatsNew", UIParent, "BackdropTemplate")
	window = { frame = frame }
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER", 0, 60)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	table.insert(UISpecialFrames, "CFFWhatsNew") -- Escape closes it

	local logo = frame:CreateTexture(nil, "ARTWORK")
	logo:SetSize(28, 28)
	logo:SetPoint("TOPLEFT", 10, -8)
	logo:SetTexture(LOGO_TEXTURE)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("LEFT", logo, "RIGHT", 6, 0)
	title:SetJustifyH("LEFT")
	window.title = title

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 0, 0)
	close:SetScript("OnClick", function() frame:Hide() end)

	local scroll = CreateFrame("ScrollFrame", nil, frame)
	scroll:SetPoint("TOPLEFT", 14, -44)
	scroll:SetPoint("BOTTOMRIGHT", -26, FOOTER)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta) ScrollTo((self:GetVerticalScroll() or 0) - delta * 40) end)
	window.scroll = scroll

	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(TEXT_WIDTH, 1)
	scroll:SetScrollChild(child)
	window.child = child

	local text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT")
	text:SetWidth(TEXT_WIDTH)
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	text:SetSpacing(2)
	window.text = text

	local slider = CreateFrame("Slider", nil, frame)
	slider:SetPoint("TOPRIGHT", -10, -44)
	slider:SetPoint("BOTTOMRIGHT", -10, FOOTER)
	slider:SetWidth(10)
	slider:SetOrientation("VERTICAL")
	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(0.6, 0.6, 0.6, 0.8)
	thumb:SetSize(10, 36)
	slider:SetThumbTexture(thumb)
	slider:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)
	window.slider = slider

	local rule = frame:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(0.5, 0.5, 0.5, 0.5)
	rule:SetHeight(1)
	rule:SetPoint("BOTTOMLEFT", 10, FOOTER - 6)
	rule:SetPoint("BOTTOMRIGHT", -10, FOOTER - 6)

	local notes = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	notes:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 4, -6)
	notes:SetPoint("TOPRIGHT", rule, "BOTTOMRIGHT", -4, -6)
	notes:SetJustifyH("LEFT")
	notes:SetTextColor(1, 1, 1)
	window.notes = notes

	local ok = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	ok:SetSize(90, 22)
	ok:SetPoint("BOTTOMRIGHT", -12, 10)
	ok:SetText("Got it")
	ok:SetScript("OnClick", function() frame:Hide() end)

	local again = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	again:SetPoint("BOTTOMLEFT", 14, 16)
	again:SetText("/cff changelog shows this again.")

	-- The text's height is only known once the client has laid it out.
	frame:SetScript("OnShow", function() C_Timer.After(0, UpdateScroll) end)
end

local function NotesText()
	local lines = { WhatsNew.NEEDS }
	if not WhatsNew.SyndicatorLoaded() then
		table.insert(lines, "|cffff6655Syndicator isn't active on this character.|r")
	end
	table.insert(lines, WhatsNew.COMING)
	return table.concat(lines, "\n")
end

-- sections: changelog sections, newest first.
function WhatsNew.Show(sections, titleText)
	if not window then CreateWindow() end
	window.title:SetText(titleText or "What's new in Crafting and Farming Forever")
	local parts = {}
	for _, section in ipairs(sections) do
		table.insert(parts, GOLD .. "Version " .. section.version .. "|r\n" .. table.concat(section.lines, "\n"))
	end
	if #parts == 0 then table.insert(parts, "No notes for this version.") end
	window.text:SetText(table.concat(parts, "\n\n"))
	window.notes:SetText(NotesText())
	window.scroll:SetVerticalScroll(0)
	window.frame:Hide()
	window.frame:Show()
end

function WhatsNew.ShowAll()
	WhatsNew.Show(ns.CHANGELOG or {}, "Crafting and Farming Forever changelog")
end

function WhatsNew.IsShown()
	return window ~= nil and window.frame:IsShown()
end

function WhatsNew.Hide()
	if window then window.frame:Hide() end
end

---------------------------------------------------------------------------
-- Once after an update
---------------------------------------------------------------------------

local loggedIn = false

-- Runs when both the player is in the world and the saved data is known. If the saved data only arrives after the
-- add-on gave up waiting for it, the version seen is lost with the stand-in data, and the notes show next session.
function WhatsNew.CheckUpdate()
	if not (loggedIn and ns.dataReady) then return end
	local current = WhatsNew.CurrentVersion()
	if not WhatsNew.Compare(current, current) then return end
	local seen = ns.db.lastSeenVersion
	ns.db.lastSeenVersion = current
	-- A first install has nothing to compare with; the notes would only repeat the add-on's description.
	if not ns.savedDataFound then return end
	if seen and (WhatsNew.Compare(seen, current) or 0) >= 0 then return end
	local sections = WhatsNew.Sections(seen, current)
	if #sections == 0 then return end
	C_Timer.After(3, function() WhatsNew.Show(sections) end)
end

ns.On("PLAYER_LOGIN", function()
	loggedIn = true
	WhatsNew.CheckUpdate()
end)
ns.WhenDataReady(function() WhatsNew.CheckUpdate() end)

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
