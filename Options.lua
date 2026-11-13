-- Crafting and Farming Forever :: Options
-- The Options tab: what the add-on shows and how its chat messages are worded. The same controls are built twice,
-- once in the main window's Options tab and once in the game's own Options > AddOns list, and both stay in step.

local _, ns = ...

local Options = {}
ns.Options = Options

local TITLE = "Crafting and Farming Forever"
local LEFT = 16
local MUTED = "|cff999999"
local built = {} -- every set of controls made, as { parent, update }

-- A setting changed: everything it can show or hide is redrawn, and the other copy of the controls follows.
local function Changed()
	ns.Advertise.UpdateButtons()
	ns.UI.RefreshQueue()
	ns.UI.Refresh("profit")
	Options.Sync()
end

function Options.Sync()
	for _, entry in ipairs(built) do
		if entry.parent:IsVisible() then entry.update() end
	end
end

function Options.Open()
	ns.UI.Show("options")
end

local function Tip(frame, title, text)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:SetText(title)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
end

local function Heading(parent, text, y)
	local heading = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	heading:SetPoint("TOPLEFT", LEFT, -y)
	heading:SetText(text)
	local rule = parent:CreateTexture(nil, "ARTWORK")
	local accent = ns.UI.THEME.border
	rule:SetColorTexture(accent[1], accent[2], accent[3], 1)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", LEFT, -y - 16)
	rule:SetPoint("TOPRIGHT", -LEFT, -y - 16)
	return heading
end

local function Label(parent, text, y)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("TOPLEFT", LEFT + 4, -y - 5)
	label:SetText(text)
	return label
end

-- A tick box with its label, which is clickable too.
local function Check(parent, text, tip, y, read, write)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check:SetPoint("TOPLEFT", LEFT, -y)
	check:SetHitRectInsets(0, -360, 0, 0)
	local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", check, "RIGHT", 2, 1)
	label:SetText(text)
	check:SetScript("OnClick", function(self)
		write(self:GetChecked() and true or false)
		Changed()
	end)
	Tip(check, text, tip)
	check.Sync = function(self) self:SetChecked(read() and true or false) end
	return check
end

-- A one-line box for a chat message, with a Default button and a preview line under it. Saves on Enter or when it
-- loses focus; Escape puts back what was saved.
local function MessageBox(parent, y, labelWidth, maxLetters, read, write, default, preview)
	local box = ns.UI.SkinBox(CreateFrame("EditBox", nil, parent, "InputBoxTemplate"))
	box:SetHeight(20)
	box:SetPoint("TOPLEFT", LEFT + labelWidth + 12, -y)
	box:SetPoint("TOPRIGHT", -LEFT - 74, -y)
	box:SetAutoFocus(false)
	box:SetMaxLetters(maxLetters)

	local example = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	example:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -2, -4)
	example:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 70, -4)
	example:SetJustifyH("LEFT")
	example:SetWordWrap(false)
	box.example = example

	local function ShowExample(text)
		if not text or text:match("^%s*$") then text = default end
		example:SetText(MUTED .. "Sends: |r" .. preview(ns.CleanChatText(text, maxLetters)))
	end
	local function Save(self)
		local text = self:GetText() or ""
		if ns.CleanChatText(text, maxLetters) ~= read() then
			write(text)
			Changed()
		end
	end
	box:SetScript("OnTextChanged", function(self) ShowExample(self:GetText()) end)
	box:SetScript("OnEnterPressed", function(self)
		Save(self)
		self:ClearFocus()
		self:Sync()
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(read())
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusLost", Save)
	box.Sync = function(self)
		if self:HasFocus() then return end
		self:SetText(read())
		self:SetCursorPosition(0)
		ShowExample(read())
	end

	local reset = ns.UI.FlatButton(parent, "Default", 64, 20)
	reset:SetPoint("LEFT", box, "RIGHT", 8, 0)
	reset:SetScript("OnClick", function()
		box:ClearFocus()
		write(default)
		Changed()
		box:Sync()
	end)
	Tip(reset, "Default", "Puts back the add-on's own wording.")
	box.reset = reset
	return box
end

-- The profession an example ad shows: one of this character's, as its name in brackets.
local function ExampleProfession()
	for _, profession in ipairs(ns.Recipes.KnownProfessions()) do
		if ns.Recipes.IsCraftingProfession(profession.id) and ns.Recipes.CharHasProfession(ns.CharKey(), profession.id) then
			return "[" .. profession.name .. "]"
		end
	end
	return "[Tailoring]"
end

-- Builds the controls on `parent`, starting `top` below its top edge. Returns the function that shows the saved
-- values; `controls` on the result of Options.Controls(parent) is for the tests.
function Options.Build(parent, top)
	local controls = {}
	local y = top + 4

	Heading(parent, "General", y)
	y = y + 22
	local function AddCheck(key, text, tip, read, write)
		controls[key] = Check(parent, text, tip, y, read or function() return ns.Option(key) end,
			write or function(on) ns.SetOption(key, on) end)
		y = y + 22
	end
	AddCheck("autoOpen", "Open with the profession window",
		"The window opens when you open a profession, and closes with it.")
	AddCheck("minimap", "Show the minimap button", "The button on the minimap that opens this window.",
		ns.MinimapButton.Shown, ns.MinimapButton.SetShown)
	AddCheck("nextStep", "Show the Next step bar",
		"The small bar that shows what to do next while there's something in the queue. Without it, the Queue tab "
			.. "is your list, also when farming.")
	AddCheck("scanPopup", "Ask to scan at the auction house when prices are old",
		"The Yes or No box that offers a new scan when your prices are more than a day old. The orange note in this "
			.. "window stays either way.")
	AddCheck("chatTips", "Reminders in chat",
		"The chat lines about old prices at login, and where the shopping list is at the auction house. Warnings on a "
			.. "quote and sale messages stay either way.")

	y = y + 10
	Heading(parent, "Advertising", y)
	y = y + 22
	AddCheck("adEnabled", "Advertise my professions",
		"Off removes the Ad box beside the chat and the Advertise button on the Profit tab.")
	y = y + 2
	local postTo = Label(parent, "Post to", y)
	controls.destinations = {}
	local previous
	for _, destination in ipairs(ns.Advertise.Destinations()) do
		local button = ns.UI.FlatButton(parent, destination.label, 60, 20)
		if previous then
			button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
		else
			button:SetPoint("TOPLEFT", LEFT + 72, -y)
		end
		button:SetScript("OnClick", function()
			ns.Advertise.SetDestination(destination.key)
			Changed()
		end)
		button.label = destination.label
		controls.destinations[destination.key] = button
		previous = button
	end
	y = y + 26
	local adLabel = Label(parent, "Message", y)
	controls.adText = MessageBox(parent, y, 60, ns.Advertise.TEXT_MAX, ns.Advertise.Text, ns.Advertise.SetText,
		ns.Advertise.DEFAULT_TEXT, function(text) return ns.Fill(text, { profession = ExampleProfession() }) end)
	Tip(controls.adText, "Advertising message",
		"What the Ad box and the Advertise button post. Write {profession} where your profession link should go. "
			.. "Press Enter to save.")
	y = y + 42

	Heading(parent, "Quotes", y)
	y = y + 24
	local marginLabel = Label(parent, "Margin %", y)
	local margin = ns.UI.SkinBox(CreateFrame("EditBox", nil, parent, "InputBoxTemplate"))
	margin:SetSize(44, 20)
	margin:SetPoint("TOPLEFT", LEFT + 72, -y)
	margin:SetAutoFocus(false)
	margin:SetNumeric(true)
	margin:SetMaxLetters(4)
	local function SaveMargin(self)
		local value = tonumber(self:GetText())
		if value and value ~= ns.Queue.QuoteMargin() then
			ns.Queue.SetQuoteMargin(value)
			Changed()
		end
	end
	margin:SetScript("OnEnterPressed", function(self)
		SaveMargin(self)
		self:ClearFocus()
		self:Sync()
	end)
	margin:SetScript("OnEscapePressed", function(self)
		self:SetText(tostring(ns.Queue.QuoteMargin()))
		self:ClearFocus()
	end)
	margin:SetScript("OnEditFocusLost", SaveMargin)
	margin.Sync = function(self)
		if not self:HasFocus() then self:SetText(tostring(ns.Queue.QuoteMargin())) end
	end
	Tip(margin, "Quote margin", ("Added to the material cost when you press Quote on the Queue tab. 0 to %d%%; "
		.. "press Enter to save."):format(ns.Queue.QUOTE_MARGIN_MAX))
	controls.margin = margin
	local marginNote = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	marginNote:SetPoint("LEFT", margin, "RIGHT", 10, 0)
	marginNote:SetText(MUTED .. "added to the material cost when you press Quote|r")
	y = y + 26
	local quoteLabel = Label(parent, "Message", y)
	controls.quoteText = MessageBox(parent, y, 60, ns.Queue.QUOTE_TEXT_MAX, ns.Queue.QuoteTemplate,
		ns.Queue.SetQuoteTemplate, ns.Queue.DEFAULT_QUOTE_TEXT, function(text)
			return ns.Fill(text, { item = "[Healing Potion]", count = 20, price = ns.Money(52000) })
		end)
	Tip(controls.quoteText, "Quote message",
		"What Quote whispers. {item} is the item's link, {count} how many you'd make and {price} the price for all "
			.. "of them. Press Enter to save.")
	y = y + 42

	controls.labels = { postTo, adLabel, marginLabel, quoteLabel }
	controls.height = y

	local function Update()
		for _, key in ipairs({ "autoOpen", "minimap", "nextStep", "scanPopup", "chatTips", "adEnabled" }) do
			controls[key]:Sync()
		end
		local current = ns.Advertise.DestinationLabel()
		for _, button in pairs(controls.destinations) do
			if button.label == current then
				button:SetText("|cffffffff" .. button.label .. "|r")
				button:LockHighlight()
			else
				button:SetText(button.label)
				button:UnlockHighlight()
			end
		end
		controls.adText:Sync()
		controls.margin:Sync()
		controls.quoteText:Sync()
	end
	table.insert(built, { parent = parent, update = Update, controls = controls })
	return Update
end

function Options.Controls(parent)
	for _, entry in ipairs(built) do
		if entry.parent == parent then return entry.controls end
	end
end

---------------------------------------------------------------------------
-- The game's Options > AddOns list
---------------------------------------------------------------------------

-- The same controls on a page of the game's own options. Built the first time the page is opened.
local function Register()
	if Options.panel then return end
	local register = type(Settings) == "table" and Settings.RegisterCanvasLayoutCategory
	if not register and not InterfaceOptions_AddCategory then return end

	local panel = CreateFrame("Frame")
	panel.name = TITLE
	panel:Hide()
	-- The game calls these on its own buttons; every change here is saved as it's made.
	panel.OnCommit, panel.OnDefault, panel.OnRefresh = function() end, function() end, function() end
	local update
	panel:SetScript("OnShow", function(self)
		if not update then
			local title = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
			title:SetPoint("TOPLEFT", LEFT, -14)
			title:SetText(TITLE)
			local open = ns.UI.FlatButton(self, "Open the window", 130, 22, true)
			open:SetPoint("TOPRIGHT", -LEFT, -10)
			open:SetScript("OnClick", Options.Open)
			update = Options.Build(self, 40)
		end
		update()
	end)
	Options.panel = panel

	-- If this client's options list works differently, the tab and the minimap button still open the options.
	pcall(function()
		if register then
			local category = register(panel, TITLE)
			Settings.RegisterAddOnCategory(category)
			Options.category = category
		else
			InterfaceOptions_AddCategory(panel)
		end
	end)
end

ns.On("PLAYER_LOGIN", function() ns.WhenDataReady(Register) end)
