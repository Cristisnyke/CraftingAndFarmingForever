-- Crafting and Farming Forever :: Minimap
-- The minimap button. When another add-on has loaded LibDataBroker and LibDBIcon, the button is registered with them,
-- so broker bars and minimap button collectors treat it like any other. Without them it's the add-on's own button,
-- named the way LibDBIcon names its buttons, which is what collectors look for. Neither library is bundled.

local addonName, ns = ...

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local ICON = "Interface\\AddOns\\CraftingAndFarmingForever\\Media\\Logo"
local DEFAULT_ANGLE = 200 -- degrees round the minimap, counter-clockwise from the right
local BUTTON_NAME = "LibDBIcon10_" .. addonName

local libIcon -- LibDBIcon, when the button is registered with it
local button -- the add-on's own button otherwise

local function Settings()
	local ui = ns.db.ui
	if type(ui.minimap) ~= "table" then ui.minimap = {} end
	return ui.minimap
end

local function OnClick(_, mouseButton)
	if mouseButton == "RightButton" then
		ns.UI.ToggleNextStep()
	else
		ns.UI.ToggleMain()
	end
end

local function AddTooltipLines(tooltip)
	tooltip:AddLine("Crafting and Farming Forever")
	local queued = #ns.db.queue
	if queued > 0 then
		tooltip:AddLine(("%s in the queue"):format(ns.Plural(queued, "recipe", "recipes")), 0.6, 0.8, 1)
	end
	tooltip:AddLine("Left-click: open or close the window", 1, 1, 1)
	tooltip:AddLine("Right-click: fold or unfold the Next step bar", 1, 1, 1)
	tooltip:AddLine("Drag: move the button. /cff minimap hides it.", 0.6, 0.6, 0.6)
end

-- Where a button at this angle sits, from the minimap's centre.
function MinimapButton.Offset(angle, radius)
	local radians = math.rad(angle)
	return math.cos(radians) * radius, math.sin(radians) * radius
end

local function Place()
	local radius = (Minimap:GetWidth() or 140) / 2 + 5
	local x, y = MinimapButton.Offset(Settings().minimapPos or DEFAULT_ANGLE, radius)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function FollowCursor()
	local centreX, centreY = Minimap:GetCenter()
	local cursorX, cursorY = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale() or 1
	if not centreX or not cursorX then return end
	Settings().minimapPos = math.deg(math.atan2(cursorY / scale - centreY, cursorX / scale - centreX)) % 360
	Place()
end

local function CreateOwnButton()
	button = CreateFrame("Button", BUTTON_NAME, Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(24, 24)
	background:SetPoint("CENTER")
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(19, 19)
	icon:SetPoint("CENTER")
	button.icon = icon
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(52, 52)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", OnClick)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		AddTooltipLines(GameTooltip)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", FollowCursor)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	MinimapButton.button = button
	Place()
end

local function Library(name)
	if type(LibStub) ~= "table" or not LibStub.GetLibrary then return nil end
	return LibStub:GetLibrary(name, true)
end

local function Apply()
	local hide = Settings().hide and true or false
	if libIcon then
		if hide then libIcon:Hide(addonName) else libIcon:Show(addonName) end
	elseif button then
		button:SetShown(not hide)
	end
end

local function Setup()
	if libIcon or button then return end
	local broker, icons = Library("LibDataBroker-1.1"), Library("LibDBIcon-1.0")
	if broker and icons then
		local object = broker:NewDataObject(addonName, {
			type = "launcher",
			label = "Crafting and Farming Forever",
			text = "CFF",
			icon = ICON,
			OnClick = OnClick,
			OnTooltipShow = AddTooltipLines,
		})
		if object then
			icons:Register(addonName, object, Settings())
			libIcon = icons
		end
	end
	if not libIcon then
		if not Minimap then return end
		CreateOwnButton()
	end
	Apply()
end

function MinimapButton.Toggle()
	local settings = Settings()
	settings.hide = not settings.hide or nil
	Apply()
	ns.Print(settings.hide and "Minimap button hidden. /cff minimap shows it again." or "Minimap button shown.")
end

function MinimapButton.Kind()
	return libIcon and "LibDBIcon" or (button and "own" or "none")
end

-- At login every add-on has loaded, so the libraries are there if anything brought them.
ns.On("PLAYER_LOGIN", function() ns.WhenDataReady(Setup) end)
