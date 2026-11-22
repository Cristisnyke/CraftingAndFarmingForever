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
local function Changed(prices)
	if prices then
		ns.InvalidateProfit()
		ns.RequestPlan()
	end
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

-- From the game's own options page: that window covers ours, so it closes first (the game won't allow it in combat).
function Options.Open()
	if SettingsPanel and SettingsPanel:IsShown() and not InCombatLockdown() then HideUIPanel(SettingsPanel) end
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
local function MessageBox(parent, y, labelWidth, maxBytes, read, write, default, preview)
	local box = ns.UI.SkinBox(CreateFrame("EditBox", nil, parent, "InputBoxTemplate"))
	box:SetHeight(20)
	box:SetPoint("TOPLEFT", LEFT + labelWidth + 12, -y)
	box:SetPoint("TOPRIGHT", -LEFT - 74, -y)
	box:SetAutoFocus(false)
	box:SetMaxLetters(maxBytes)

	local example = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	example:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -2, -4)
	example:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 70, -4)
	example:SetJustifyH("LEFT")
	example:SetWordWrap(false)
	box.example = example

	local function ShowExample(text)
		if not text or text:match("^%s*$") then text = default end
		example:SetText(MUTED .. "Sends: |r" .. preview(ns.CleanChatText(text, maxBytes)))
	end
	local function Save(self)
		local text = self:GetText() or ""
		if ns.CleanChatText(text, maxBytes) ~= read() then
			write(text)
			Changed()
		end
	end
	box:SetScript("OnTextChanged", function(self) ShowExample(self:GetText()) end)
	box:SetScript("OnEnterPressed", box.ClearFocus) -- losing focus saves
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(read())
		self:ClearFocus()
	end)
	-- The box then shows what was saved: the wording tidied, or the default for an empty one.
	box:SetScript("OnEditFocusLost", function(self)
		Save(self)
		self:SetText(read())
		self:SetCursorPosition(0)
	end)
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

-- What the Leave out button says: who's left out, by name when it's one.
local function LeftOutText()
	local names = {}
	for _, entry in ipairs(ns.Stock.Characters()) do
		if ns.Stock.IsLeftOut(entry) then table.insert(names, entry.label) end
	end
	if #names == 0 then return "Every character counts", names end
	if #names == 1 then return "Left out: " .. names[1], names end
	return ("Left out: %d characters"):format(#names), names
end

-- A button that opens a list of your characters: click one to tick it (left out) or untick it; Count every
-- character clears them all.
local CHAR_ROWS, CHAR_WIDTH, CHAR_HEIGHT = 14, 190, 18
local function CharacterPicker(parent, x, y)
	local button = ns.UI.FlatButton(parent, "", 200, 20)
	button:SetPoint("TOPLEFT", x, -y)
	local menu = CreateFrame("Frame", nil, button, "BackdropTemplate")
	menu:SetFrameStrata("DIALOG")
	menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
	ns.UI.FlatBox(menu, ns.UI.THEME.header, ns.UI.THEME.border)
	menu:Hide()
	menu.options = {}
	button.menu = menu

	local function Pick(entry)
		if entry then
			ns.Stock.SetLeftOut(entry, not ns.Stock.IsLeftOut(entry))
		else
			ns.db.ui.excludedChars = nil
		end
		Changed(true)
	end
	menu.Fill = function(self)
		local entries = ns.Stock.Characters()
		table.insert(entries, 1, false)
		for index, entry in ipairs(entries) do
			local option = self.options[index]
			if not option then
				option = ns.UI.FlatButton(self, "-", CHAR_WIDTH, CHAR_HEIGHT)
				local text = option:GetFontString()
				if text then
					text:ClearAllPoints()
					text:SetPoint("LEFT", 6, 0)
					text:SetPoint("RIGHT", -20, 0)
					text:SetJustifyH("LEFT")
				end
				local column, line = math.floor((index - 1) / CHAR_ROWS), (index - 1) % CHAR_ROWS
				option:SetPoint("TOPLEFT", 4 + column * (CHAR_WIDTH + 2), -4 - line * CHAR_HEIGHT)
				option:SetScript("OnClick", function(clicked) Pick(clicked.entry or nil) end)
				option.check = option:CreateTexture(nil, "OVERLAY")
				-- A cross, not a tick: a marked character is left out.
				option.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
				option.check:SetSize(14, 14)
				option.check:SetPoint("RIGHT", -2, 0)
				self.options[index] = option
			end
			option.entry = entry
			local excluded = ns.db.ui.excludedChars
			local on
			if entry then
				on = ns.Stock.IsLeftOut(entry)
				option:SetText(entry.label .. (entry.me and (MUTED .. "  you|r") or ""))
			else
				on = not excluded
				option:SetText("Count every character")
			end
			if on then option:LockHighlight() else option:UnlockHighlight() end
			option.check:SetShown(on and entry and true or false)
			option:Show()
		end
		for index = #entries + 1, #self.options do self.options[index]:Hide() end
		local columns = math.ceil(#entries / CHAR_ROWS)
		self:SetSize(8 + columns * (CHAR_WIDTH + 2) - 2, 8 + math.min(#entries, CHAR_ROWS) * CHAR_HEIGHT)
	end
	button:SetScript("OnClick", function()
		if menu:IsShown() then menu:Hide() return end
		menu:Fill()
		menu:Show()
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:SetText("Leave characters out")
		GameTooltip:AddLine("Click characters to cross them out and leave them out of everything: their recipes don't show on the Profit "
			.. "tab and they're never picked to craft, and what's in their bags, bank, mail and auctions isn't counted "
			.. "for the queue, the shopping list or restocking. The character you're playing always counts.", 1, 1, 1,
			true)
		local _, names = LeftOutText()
		if #names > 0 then GameTooltip:AddLine("Left out: " .. table.concat(names, ", "), 1, 0.82, 0, true) end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	parent:HookScript("OnHide", function() menu:Hide() end)
	button.Sync = function(self)
		local text = LeftOutText()
		self:SetText(text)
		if ns.db.ui.excludedChars then self:LockHighlight() else self:UnlockHighlight() end
		if menu:IsShown() then menu:Fill() end
	end
	return button
end

-- Builds the controls on `parent`, starting `top` below its top edge. Returns the function that shows the saved
-- values. Options.Controls(parent) hands the controls to the tests.
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
	-- Beside the first tick box, in the second column: which characters count.
	local leaveOut = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	leaveOut:SetPoint("TOPLEFT", LEFT + 384, -y - 5)
	leaveOut:SetText("Characters")
	controls.characters = CharacterPicker(parent, LEFT + 450, y + 1)
	AddCheck("autoOpen", "Open with the profession window",
		"The window opens when you open a profession, and closes with it.")
	controls.autoOpen:SetHitRectInsets(0, -340, 0, 0)
	AddCheck("minimap", "Show the minimap button", "The button on the minimap that opens this window.",
		ns.MinimapButton.Shown, ns.MinimapButton.SetShown)
	AddCheck("nextStep", "Show the Next step bar",
		"The small bar that shows what to do next while there's something in the queue. Without it, the Queue tab "
			.. "is your list, also when farming.")
	-- Beside it, in a second column: the window has no room for another row.
	controls.bagSpace = Check(parent, "Plan around bag space",
		"When the queue's materials won't fit in your bags, the Queue tab says what to put in the bank first and, if "
			.. "that isn't enough, splits the queue into runs that fit, crafts using up the most room first.", y - 22,
		function() return ns.Option("bagSpace") end, function(on)
			ns.SetOption("bagSpace", on)
			ns.RequestPlan()
		end)
	controls.bagSpace:ClearAllPoints()
	controls.bagSpace:SetPoint("TOPLEFT", LEFT + 380, -(y - 22))
	controls.bagSpace:SetHitRectInsets(0, -200, 0, 0)
	controls.nextStep:SetHitRectInsets(0, -340, 0, 0)
	AddCheck("scanPopup", "Ask to scan at the auction house when prices are old",
		"The Yes or No box that offers a new scan when your prices are more than a day old. The orange note in this "
			.. "window stays either way.")
	-- Every kind of chat line the add-on writes, in a small menu of its own: the pane has no room for five rows.
	local chat = ns.UI.FlatButton(parent, "", 220, 22)
	local menu
	chat:SetPoint("TOPLEFT", LEFT + 4, -y - 1)
	Tip(chat, "Chat messages", "Pick which kinds of messages the add-on writes in chat. What you ask for with a "
		.. "command (/cff diag, /cff alone) always answers.")
	chat.Sync = function(self)
		local on = 0
		for _, kind in ipairs(ns.CHAT_KINDS) do
			if ns.Option(kind.key) then on = on + 1 end
		end
		self:SetText(("Chat messages: %s  >"):format(on == #ns.CHAT_KINDS and "all on" or on == 0 and "all off"
			or ("%d of %d on"):format(on, #ns.CHAT_KINDS)))
		if menu and menu:IsShown() then
			for _, check in ipairs(controls.chatChecks) do check:Sync() end
		end
	end
	chat:SetScript("OnClick", function(self)
		if not menu then
			menu = CreateFrame("Frame", nil, parent, "BackdropTemplate")
			menu:SetFrameStrata("DIALOG")
			menu:SetSize(330, 40 + 24 * #ns.CHAT_KINDS)
			menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", -4, -2)
			menu:EnableMouse(true)
			ns.UI.ThemeBackdrop(menu, 0.97)
			local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			title:SetPoint("TOPLEFT", 12, -10)
			title:SetText("Write in chat")
			local close = ns.UI.FlatButton(menu, "x", 20, 18)
			close:SetPoint("TOPRIGHT", -6, -6)
			close:SetScript("OnClick", function() menu:Hide() end)
			controls.chatChecks = {}
			for index, kind in ipairs(ns.CHAT_KINDS) do
				local check = Check(menu, kind.label, kind.tip, 8 + 24 * index,
					function() return ns.Option(kind.key) end, function(on) ns.SetOption(kind.key, on) end)
				check:SetHitRectInsets(0, -280, 0, 0)
				controls.chatChecks[index] = check
			end
			parent:HookScript("OnHide", function() menu:Hide() end)
			controls.chatMenu = menu
			menu:Hide()
		end
		menu:SetShown(not menu:IsShown())
		self:Sync()
	end)
	controls.chat = chat
	y = y + 22
	-- Beside it, in the second column.
	controls.depthCheck = Check(parent, "Read listings at the auction house",
		"A price scan only knows each material's cheapest listing. At the auction house the add-on looks up every "
			.. "listing of what your queue would buy, so buying 50 counts at what 50 really cost, and a queued restock "
			.. "is cut where it stops paying. It waits for your own searches, and locks the screen for the few "
			.. "seconds it reads. Off: only the listings of items you open yourself are read.", y - 22,
		function() return ns.Option("depthCheck") end, function(on)
			ns.SetOption("depthCheck", on)
			ns.Depth.CheckWanted()
		end)
	controls.depthCheck:ClearAllPoints()
	controls.depthCheck:SetPoint("TOPLEFT", LEFT + 380, -(y - 22))
	controls.depthCheck:SetHitRectInsets(0, -230, 0, 0)

	y = y + 10
	Heading(parent, "Profit", y)
	y = y + 22
	controls.priceCap = Check(parent, "Limit suspicious sale prices",
		"One odd listing (7s of materials posted for 20g) would show a huge profit. A crafted item listed above the "
			.. "limit counts at the normal mark-up instead, and its row says check price.", y,
		function() return ns.Option("priceCap") end, function(on) ns.SetOption("priceCap", on) end)
	controls.priceCap:SetScript("OnClick", function(self)
		ns.SetOption("priceCap", self:GetChecked() and true or false)
		Changed(true)
	end)
	controls.priceCap:SetHitRectInsets(0, -330, 0, 0)
	controls.normalPrice = Check(parent, "Count price spikes at the usual price",
		"The add-on notes each item's lowest price every day you scan. After 3 days, the middle of the last 14 days "
			.. "is its usual price. A crafted item listed above it counts at the usual price, so a short spike can't "
			.. "make you craft something that sells for less once the spike ends. Items at 130% or more say so on "
			.. "their row.", y,
		function() return ns.Option("normalPrice") end, function(on) ns.SetOption("normalPrice", on) end)
	controls.normalPrice:SetScript("OnClick", function(self)
		ns.SetOption("normalPrice", self:GetChecked() and true or false)
		Changed(true)
	end)
	controls.normalPrice:ClearAllPoints()
	controls.normalPrice:SetPoint("TOPLEFT", LEFT + 380, -y)
	controls.normalPrice:SetHitRectInsets(0, -230, 0, 0)
	y = y + 26
	-- "Above [400]% of material cost, count it as [200]%", on one line.
	local function PercentBox(anchor, label, read, write, title, tip)
		local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		if anchor then
			text:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
		else
			text:SetPoint("TOPLEFT", LEFT + 4, -y - 5)
		end
		text:SetText(label)
		local box = ns.UI.SkinBox(CreateFrame("EditBox", nil, parent, "InputBoxTemplate"))
		box:SetSize(46, 20)
		box:SetPoint("LEFT", text, "RIGHT", 8, 0)
		box:SetAutoFocus(false)
		box:SetNumeric(true)
		box:SetMaxLetters(5)
		local function Save(self)
			local value = tonumber(self:GetText())
			if value and value ~= read() then
				write(value)
				Changed(true)
			end
		end
		box:SetScript("OnEnterPressed", function(self)
			Save(self)
			self:ClearFocus()
			self:Sync()
		end)
		box:SetScript("OnEscapePressed", function(self)
			self:SetText(tostring(read()))
			self:ClearFocus()
		end)
		box:SetScript("OnEditFocusLost", Save)
		box.Sync = function(self)
			if not self:HasFocus() then self:SetText(tostring(read())) end
		end
		Tip(box, title, tip)
		local percent = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		percent:SetPoint("LEFT", box, "RIGHT", 2, 0)
		box.percent = percent
		return box
	end
	controls.capMax = PercentBox(nil, "Above", function() return (ns.Queue.PriceCapPercents()) end,
		function(value) ns.Queue.SetPriceCapPercents(value, nil) end, "Highest believable price",
		"A sale price above this % of the material cost is suspicious. Default 400. Press Enter to save.")
	controls.capMax.percent:SetText("% of material cost,")
	controls.capNormal = PercentBox(controls.capMax.percent, "count it as",
		function() return select(2, ns.Queue.PriceCapPercents()) end,
		function(value) ns.Queue.SetPriceCapPercents(nil, value) end, "Suspicious price counted as",
		"What profit uses instead, as % of the material cost. Default 200, never above the first number. Press "
			.. "Enter to save.")
	controls.capNormal.percent:SetText("%")
	y = y + 32

	Heading(parent, "Restock", y)
	y = y + 22
	AddCheck("smartRestock", "Smart restock goals",
		"Goals follow your auctions: a step up each day an item sells out, down when it expires, daggers in pairs, "
			.. "and never more than a quarter of your gold on one item. They keep adjusting as you sell. Without the gold for a full "
			.. "restock you get a partial one, the most profitable part. A goal you set yourself always stays. Off: "
			.. "every item uses the default goals.",
		nil, function(on)
			ns.SetOption("smartRestock", on)
			ns.Restock.ForgetSmart()
			ns.UI.Refresh("restock")
			ns.UI.Refresh("posting")
		end)
	-- Beside it, in the second column: bank alt mode, a tick and the bank alt's name under it.
	local bankAltTip = "One character sells everything: your bank alt. Your other characters craft and mail what they "
		.. "make to it: at a mailbox they attach and send it by themselves (or with the Send crafts button if the game "
		.. "doesn't allow that), whole stacks, 12 to a mail, and crafts in their bank come out on the bank step. What "
		.. "the queue still needs and tools stay; materials a crafter uses itself are only sent as far as the auction "
		.. "house lacks them. Crafters' Restocking tab stops suggesting posts; the bank alt's posts it all. Postage, "
		.. ("%dc per stack, comes off the profit. The bank alt's materials and gold stay out of the crafters' shopping: "
		.. "send gold over yourself."):format(ns.Planner.POSTAGE)
	controls.bankAltMode = Check(parent, "Bank alt mode", bankAltTip, y - 22,
		function() return ns.db.ui.bankAltMode == true end, function(on)
			ns.db.ui.bankAltMode = on or nil
			if on then ns.db.ui.noAutoMail = nil end -- sending by itself gets another try
		end)
	controls.bankAltMode:SetScript("OnClick", function(self)
		ns.db.ui.bankAltMode = self:GetChecked() and true or nil
		if ns.db.ui.bankAltMode then ns.db.ui.noAutoMail = nil end
		Changed(true)
	end)
	controls.bankAltMode:ClearAllPoints()
	controls.bankAltMode:SetPoint("TOPLEFT", LEFT + 380, -(y - 22))
	controls.bankAltMode:SetHitRectInsets(0, -230, 0, 0)
	y = y + 4
	local altLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	altLabel:SetPoint("TOPLEFT", LEFT + 384, -y - 5)
	altLabel:SetText("Bank alt")
	local altName = ns.UI.SkinBox(CreateFrame("EditBox", nil, parent, "InputBoxTemplate"))
	altName:SetSize(130, 20)
	altName:SetPoint("TOPLEFT", LEFT + 440, -y)
	altName:SetAutoFocus(false)
	altName:SetMaxLetters(48)
	local function SaveAlt(self)
		local text = (self:GetText() or ""):match("^%s*(.-)%s*$")
		if text ~= (ns.db.ui.bankAltName or "") then
			ns.db.ui.bankAltName = text ~= "" and text or nil
			Changed(true)
		end
	end
	altName:SetScript("OnEnterPressed", function(self)
		SaveAlt(self)
		self:ClearFocus()
	end)
	altName:SetScript("OnEscapePressed", function(self)
		self:SetText(ns.db.ui.bankAltName or "")
		self:ClearFocus()
	end)
	altName:SetScript("OnEditFocusLost", SaveAlt)
	altName.Sync = function(self)
		if not self:HasFocus() then self:SetText(ns.db.ui.bankAltName or "") end
	end
	Tip(altName, "Bank alt", "The name of the character that sells everything, as you'd write it on a mail (add "
		.. "-Realm for another realm). Press Enter to save.")
	controls.bankAltName = altName
	-- How much of a day's sales to stock: a slider from careful to plenty.
	Label(parent, "Stock level", y)
	local level = ns.UI.StockLevelSlider(parent, 220)
	level:SetPoint("TOPLEFT", LEFT + 84, -y - 3)
	controls.smartLevel = level
	y = y + 22

	-- How much gold a restock never touches.
	Label(parent, "Gold kept", y)
	local keep = ns.UI.SkinBox(CreateFrame("EditBox", nil, parent, "InputBoxTemplate"))
	keep:SetSize(96, 20)
	keep:SetPoint("TOPLEFT", LEFT + 84, -y)
	keep:SetAutoFocus(false)
	keep:SetMaxLetters(20)
	local keepText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	keepText:SetPoint("LEFT", keep, "RIGHT", 6, 0)
	keepText:SetText(MUTED .. "a restock never spends, like 1g 50s 20c|r")
	local function SaveKeep(self)
		local value = ns.Planner.ParseMoney(self:GetText())
		if value and value ~= ns.Restock.KeepGold() then
			ns.Restock.SetKeepGold(value)
			ns.UI.Refresh("restock")
		end
	end
	keep:SetScript("OnEnterPressed", function(self)
		SaveKeep(self)
		self:ClearFocus()
		self:Sync()
	end)
	keep:SetScript("OnEscapePressed", function(self)
		self:SetText(ns.Planner.MoneyText(ns.Restock.KeepGold()))
		self:ClearFocus()
	end)
	keep:SetScript("OnEditFocusLost", function(self)
		SaveKeep(self)
		self:SetText(ns.Planner.MoneyText(ns.Restock.KeepGold()))
	end)
	keep.Sync = function(self)
		if not self:HasFocus() then self:SetText(ns.Planner.MoneyText(ns.Restock.KeepGold())) end
	end
	Tip(keep, "Gold kept", "Gold a restock never plans to spend, on top of the deposits for posting. Type it as gold, silver and "
		.. "copper, like 1g 50s 20c; any part alone works (75s), and a bare number is gold. Buying materials "
		.. "usually costs more than the last scan said, because only the cheapest listing's price is known. "
		.. "This is what's left for that, and for posting again when auctions expire.")
	controls.keepGold = keep
	y = y + 24 + 10

	Heading(parent, "Advertising", y)
	y = y + 22
	AddCheck("adEnabled", "Advertise my professions",
		"Off removes the Ad box beside the chat and the Advertise button on the Profit tab.")
	y = y + 2
	Label(parent, "Post to", y)
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
	Label(parent, "Message", y)
	controls.adText = MessageBox(parent, y, 60, ns.Advertise.TEXT_MAX, ns.Advertise.Text, ns.Advertise.SetText,
		ns.Advertise.DEFAULT_TEXT, function(text) return ns.Fill(text, { profession = ExampleProfession() }) end)
	Tip(controls.adText, "Advertising message",
		"What the Ad box and the Advertise button post. Write {profession} where your profession link should go. "
			.. "Press Enter to save.")
	y = y + 42

	Heading(parent, "Quotes", y)
	y = y + 24
	Label(parent, "Margin %", y)
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
	Label(parent, "Message", y)
	controls.quoteText = MessageBox(parent, y, 60, ns.Queue.QUOTE_TEXT_MAX, ns.Queue.QuoteTemplate,
		ns.Queue.SetQuoteTemplate, ns.Queue.DEFAULT_QUOTE_TEXT, function(text)
			return ns.Fill(text, { item = "[Healing Potion]", count = 20, price = ns.Money(52000) })
		end)
	Tip(controls.quoteText, "Quote message",
		"What Quote whispers. {item} is the item's link, {count} how many you'd make and {price} the price for all "
			.. "of them. Press Enter to save.")

	local function Update()
		for _, key in ipairs({ "autoOpen", "minimap", "nextStep", "scanPopup", "chat", "bagSpace", "depthCheck", "smartRestock", "adEnabled" }) do
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
		controls.characters:Sync()
		controls.smartLevel:Sync()
		controls.keepGold:Sync()
		controls.bankAltMode:Sync()
		controls.bankAltName:Sync()
		controls.priceCap:Sync()
		controls.normalPrice:Sync()
		controls.capMax:Sync()
		controls.capNormal:Sync()
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
