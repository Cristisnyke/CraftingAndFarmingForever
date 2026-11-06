-- CraftLedger :: UI
-- The panel docked to the profession window (also available on its own with /craftledger), the Queue button on
-- the crafting page, the stale-price prompts and the slash command.

local _, ns = ...

local UI = {}
ns.UI = UI

local ROW_HEIGHT = 22
local ROW_COUNT = 40
local PANEL_WIDTH = 380
local COLOR_PROFIT, COLOR_LOSS, COLOR_MUTED = "ff55dd55", "ffff6655", "ff999999"

local function Color(hex, text)
	return "|c" .. hex .. text .. "|r"
end

local panel, rows, slider, craftButton, statusText, banner, scanButton, tabProfit, tabQueue, filterButton, clearButton
local currentTab = "profit"
local allProfessions = false
local listData = {}
local scrollOffset = 0
local profitCache
local attached = false
local scanNotified = false
local updatingSlider = false

---------------------------------------------------------------------------
-- Profit data
---------------------------------------------------------------------------

function ns.InvalidateProfit()
	profitCache = nil
	if panel and panel:IsShown() and currentTab == "profit" then UI.Refresh() end
end

-- Every recipe known on any character whose result can be sold on the AH, most profitable first.
local function ComputeProfit()
	local ctx = ns.NewContext()
	local results = {}
	local seen = {}
	for _, char in pairs(ns.db.chars) do
		for recipeID in pairs(char.recipes) do
			if not seen[recipeID] then
				seen[recipeID] = true
				local recipe = ns.db.recipes[recipeID]
				-- CanSellOnAH is nil while loading: left out now, added by the refresh when the data arrives.
				if recipe and recipe.o and ns.Items.CanSellOnAH(recipe.o) then
					local result = ns.Planner.Profit(ctx, recipeID)
					if result then
						result.profession = recipe.p
						table.insert(results, result)
					end
				end
			end
		end
	end
	table.sort(results, function(a, b)
		if a.net and b.net then
			if a.net ~= b.net then return a.net > b.net end
			return a.recipeID < b.recipeID
		end
		if a.net or b.net then return a.net ~= nil end
		return a.recipeID < b.recipeID
	end)
	return results
end

UI.ComputeProfit = ComputeProfit

local function BuildProfitList()
	profitCache = profitCache or ComputeProfit()
	local openProfession = ns.Recipes.OpenProfession()
	local list = {}
	for _, result in ipairs(profitCache) do
		if allProfessions or not openProfession or result.profession == openProfession then
			table.insert(list, { kind = "profit", result = result })
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Queue data
---------------------------------------------------------------------------

local function RecipeName(recipeID)
	local recipe = ns.db.recipes[recipeID]
	return recipe and recipe.n or ("Recipe " .. tostring(recipeID))
end

local function AddItemRows(list, title, items)
	local sorted = {}
	for itemID, count in pairs(items) do table.insert(sorted, { kind = "item", itemID = itemID, count = count }) end
	if #sorted == 0 then return end
	table.sort(sorted, function(a, b) return a.itemID < b.itemID end)
	table.insert(list, { kind = "header", text = title })
	for _, row in ipairs(sorted) do table.insert(list, row) end
end

local function BuildQueueList()
	local list = {}
	local plan = ns.plan
	if #ns.db.queue > 0 then
		table.insert(list, { kind = "header", text = "Queue" })
		for index, entry in ipairs(ns.db.queue) do
			table.insert(list, { kind = "queue", index = index, entry = entry })
		end
	end
	local autoHeader = false
	for _, craft in ipairs(plan.crafts) do
		if craft.auto then
			if not autoHeader then
				autoHeader = true
				table.insert(list, { kind = "header", text = "Sub-crafts (cheaper than buying)" })
			end
			table.insert(list, { kind = "auto", craft = craft })
		end
	end
	AddItemRows(list, "Buy at auction house", plan.buy)
	AddItemRows(list, "Buy from vendor", plan.vendor)
	local names = {}
	for name in pairs(plan.fetch) do table.insert(names, name) end
	table.sort(names)
	for _, name in ipairs(names) do AddItemRows(list, "Get from " .. name, plan.fetch[name]) end
	return list
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function ItemLabel(itemID)
	local name = ns.Items.Name(itemID)
	if not name then return Color(COLOR_MUTED, "Loading...") end
	local quality = ns.Items.Quality(itemID)
	local hex = quality and C_Item.GetItemQualityColor and select(4, C_Item.GetItemQualityColor(quality))
	return hex and ("|c" .. hex .. name .. "|r") or name
end

local KIND_LABEL = { ah = "AH", vendor = "vendor", craft = "craft" }

local function ShowProfitTooltip(row, result)
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetText(RecipeName(result.recipeID))
	for _, part in ipairs(result.parts or {}) do
		local name = ns.Items.Name(part.itemID) or "Loading..."
		local value = part.unit and (ns.Money(part.unit * part.qty) .. " (" .. (KIND_LABEL[part.kind] or "?") .. ")") or "no price"
		GameTooltip:AddDoubleLine(part.qty .. " x " .. name, value, 0.85, 0.85, 0.85, 1, 1, 1)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine("Cost", result.cost and ns.Money(result.cost) or "no price", 1, 1, 1, 1, 1, 1)
	local sale = result.saleUnit and (ns.Money(result.saleUnit * result.yield)) or "no price"
	GameTooltip:AddDoubleLine("Sells for", sale, 1, 1, 1, 1, 1, 1)
	if result.net then
		GameTooltip:AddDoubleLine("Profit after 5% AH cut", ns.Money(result.net), 1, 1, 1, 1, 1, 1)
	end
	local age = ns.Prices.ItemAgeDays(result.itemID)
	if age and age > 0 then GameTooltip:AddLine(("Last seen on the AH %d day(s) ago."):format(age), 1, 0.6, 0.2) end
	local crafters = {}
	for key in pairs(ns.db.chars) do
		if ns.Recipes.Knows(key, result.recipeID) then table.insert(crafters, ns.CharLabel(key)) end
	end
	table.sort(crafters)
	if #crafters > 0 then GameTooltip:AddLine("Known by: " .. table.concat(crafters, ", "), 0.6, 0.8, 1, true) end
	GameTooltip:AddLine("Click to open the recipe. + queues one, Shift + queues ten.", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function RowOnEnter(row)
	local data = row.data
	if not data then return end
	if data.kind == "profit" then
		ShowProfitTooltip(row, data.result)
	elseif data.kind == "item" then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(data.itemID)
		GameTooltip:Show()
	end
end

local function RowOnClick(row)
	local data = row.data
	if data and data.kind == "profit" and ns.Recipes.Knows(ns.CharKey(), data.result.recipeID)
		and ns.Recipes.OpenProfession() == data.result.profession then
		C_TradeSkillUI.OpenRecipe(data.result.recipeID)
	end
end

local function SmallButton(parent, text, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(20, 18)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function CreateRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_HEIGHT)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row:SetScript("OnEnter", RowOnEnter)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnClick", RowOnClick)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(18, 18)
	row.icon:SetPoint("LEFT", 2, 0)

	row.plus = SmallButton(row, "+", function(self)
		local data = self:GetParent().data
		if not data then return end
		if data.kind == "profit" then
			ns.Queue.Add(data.result.recipeID, IsShiftKeyDown() and 10 or 1)
		elseif data.kind == "queue" then
			ns.Queue.Change(data.index, IsShiftKeyDown() and 10 or 1)
		end
	end)
	row.plus:SetPoint("RIGHT", row, "RIGHT", -2, 0)

	row.minus = SmallButton(row, "-", function(self)
		local data = self:GetParent().data
		if data and data.kind == "queue" then ns.Queue.Change(data.index, -1) end
	end)
	row.minus:SetPoint("RIGHT", row.plus, "LEFT", -1, 0)

	row.remove = SmallButton(row, "x", function(self)
		local data = self:GetParent().data
		if data and data.kind == "queue" then ns.Queue.Remove(data.index) end
	end)
	row.remove:SetPoint("RIGHT", row.minus, "LEFT", -1, 0)

	row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.right:SetJustifyH("RIGHT")
	row.right:SetWordWrap(false)

	row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.left:SetJustifyH("LEFT")
	row.left:SetWordWrap(false)
	row.left:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
	row.left:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
	return row
end

local function SetRow(row, data)
	row.data = data
	row.plus:Hide()
	row.minus:Hide()
	row.remove:Hide()
	row.icon:Show()
	row.right:ClearAllPoints()
	row.right:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.right:SetText("")

	if data.kind == "header" then
		row.icon:Hide()
		row.left:SetText(Color("ffffd100", data.text))
	elseif data.kind == "profit" then
		local result = data.result
		row.icon:SetTexture(ns.Items.Icon(result.itemID))
		row.left:SetText(ItemLabel(result.itemID))
		row.plus:Show()
		row.right:ClearAllPoints()
		row.right:SetPoint("RIGHT", row.plus, "LEFT", -4, 0)
		if result.net then
			row.right:SetText(Color(result.net >= 0 and COLOR_PROFIT or COLOR_LOSS, ns.Money(result.net)))
		else
			row.right:SetText(Color(COLOR_MUTED, "no data"))
		end
	elseif data.kind == "queue" then
		local recipe = ns.db.recipes[data.entry.recipeID]
		row.icon:SetTexture(recipe and recipe.o and ns.Items.Icon(recipe.o) or 134400)
		row.left:SetText(RecipeName(data.entry.recipeID) .. " x" .. data.entry.qty)
		row.plus:Show()
		row.minus:Show()
		row.remove:Show()
		row.right:ClearAllPoints()
		row.right:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
		row.right:SetText(Color(COLOR_MUTED, ns.CharLabel(ns.Recipes.Crafter(data.entry.recipeID, data.entry.char))))
	elseif data.kind == "auto" then
		local recipe = ns.db.recipes[data.craft.recipeID]
		row.icon:SetTexture(recipe and recipe.o and ns.Items.Icon(recipe.o) or 134400)
		row.left:SetText(RecipeName(data.craft.recipeID) .. " x" .. data.craft.count)
		row.right:SetText(Color(COLOR_MUTED, ns.CharLabel(data.craft.char)))
	elseif data.kind == "item" then
		row.icon:SetTexture(ns.Items.Icon(data.itemID))
		row.left:SetText(ItemLabel(data.itemID))
		row.right:SetText("x" .. data.count)
	end
	row:Show()
end

local function VisibleRowCount()
	if not panel then return 0 end
	return math.min(ROW_COUNT, math.floor(rows.container:GetHeight() / ROW_HEIGHT))
end

local function RenderRows()
	local visible = VisibleRowCount()
	local maxOffset = math.max(0, #listData - visible)
	scrollOffset = math.min(scrollOffset, maxOffset)
	for i = 1, ROW_COUNT do
		local data = i <= visible and listData[scrollOffset + i]
		if data then SetRow(rows[i], data) else rows[i].data = nil; rows[i]:Hide() end
	end
	-- These can fire OnValueChanged while clamping; that must not overwrite the offset being rendered.
	updatingSlider = true
	slider:SetMinMaxValues(0, maxOffset)
	slider:SetValue(scrollOffset)
	updatingSlider = false
	slider:SetShown(maxOffset > 0)
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

local function ScanAgeText()
	local age = ns.Prices.ScanAge()
	if not age then return "No auction house scan yet." end
	return ("Prices are %d hours old."):format(math.floor(age / 3600))
end

local function UpdateBanner()
	local stale = ns.Prices.IsStale()
	banner:SetShown(stale)
	if not stale then return end
	local atAH = AuctionHouseFrame and AuctionHouseFrame:IsShown()
	banner.text:SetText(ScanAgeText() .. (atAH and "" or " Scan at the auction house."))
	scanButton:SetShown(atAH and true or false)
end

local function UpdateCraftButton()
	if currentTab ~= "queue" then return end
	local craft, count, reason = ns.Queue.NextCraft()
	if craft then
		craftButton:SetText(("Craft Next: %s x%d"):format(RecipeName(craft.recipeID), count))
		craftButton:Enable()
		statusText:SetText("")
	else
		craftButton:SetText("Craft Next")
		craftButton:Disable()
		statusText:SetText(reason or "")
	end
end

local function UpdateFooter()
	local isQueue = currentTab == "queue"
	craftButton:SetShown(isQueue)
	clearButton:SetShown(isQueue)
	filterButton:SetShown(not isQueue)
	filterButton:SetText(allProfessions and "All professions" or "This profession")
	tabProfit:SetEnabled(isQueue)
	tabQueue:SetEnabled(not isQueue)
	if isQueue then
		UpdateCraftButton()
		local status = ns.Shopping.status
		local parts = {}
		if status.error then table.insert(parts, "List update failed. See /craftledger diag.") end
		if status.loading > 0 then table.insert(parts, status.loading .. " item name(s) loading.") end
		if not ns.Stock.HasSyndicator() then table.insert(parts, "Syndicator not active: alts not counted.") end
		if #parts > 0 then
			local current = statusText:GetText()
			statusText:SetText(((current and current ~= "") and (current .. " ") or "") .. table.concat(parts, " "))
		end
	else
		local count = #listData
		if count == 0 then
			statusText:SetText(next(ns.db.chars) and "Open a profession to record its recipes." or "")
		else
			statusText:SetText(count .. " sellable recipes known across your characters.")
		end
	end
end

function UI.Refresh()
	if not panel or not panel:IsShown() then return end
	listData = currentTab == "profit" and BuildProfitList() or BuildQueueList()
	RenderRows()
	UpdateBanner()
	UpdateFooter()
end

function UI.RefreshQueue()
	if panel and panel:IsShown() and currentTab == "queue" then UI.Refresh() end
end

local function SetTab(tab)
	currentTab = tab
	scrollOffset = 0
	UI.Refresh()
end

local function CreatePanel()
	panel = CreateFrame("Frame", "CraftLedgerPanel", UIParent, "BackdropTemplate")
	panel:SetSize(PANEL_WIDTH, 560)
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("HIGH")
	panel:SetClampedToScreen(true)
	panel:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	panel:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", function(self) if not attached then self:StartMoving() end end)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	panel:Hide()

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText("CraftLedger")

	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 0, 0)
	close:SetScript("OnClick", function() panel:Hide() end)

	tabProfit = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	tabProfit:SetSize(70, 22)
	tabProfit:SetPoint("TOPLEFT", 10, -30)
	tabProfit:SetText("Profit")
	tabProfit:SetScript("OnClick", function() SetTab("profit") end)

	tabQueue = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	tabQueue:SetSize(70, 22)
	tabQueue:SetPoint("LEFT", tabProfit, "RIGHT", 4, 0)
	tabQueue:SetText("Queue")
	tabQueue:SetScript("OnClick", function() SetTab("queue") end)

	filterButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	filterButton:SetSize(120, 22)
	filterButton:SetPoint("TOPRIGHT", -12, -30)
	filterButton:SetScript("OnClick", function()
		allProfessions = not allProfessions
		scrollOffset = 0
		UI.Refresh()
	end)

	clearButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	clearButton:SetSize(70, 22)
	clearButton:SetPoint("TOPRIGHT", -12, -30)
	clearButton:SetText("Clear")
	clearButton:SetScript("OnClick", function() ns.Queue.Clear() end)

	banner = CreateFrame("Frame", nil, panel)
	banner:SetPoint("TOPLEFT", 10, -56)
	banner:SetPoint("TOPRIGHT", -10, -56)
	banner:SetHeight(24)
	banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	banner.text:SetPoint("LEFT", 2, 0)
	banner.text:SetTextColor(1, 0.6, 0.2)
	scanButton = CreateFrame("Button", nil, banner, "UIPanelButtonTemplate")
	scanButton:SetSize(80, 20)
	scanButton:SetPoint("RIGHT")
	scanButton:SetText("Scan now")
	scanButton:SetScript("OnClick", function() ns.Prices.StartScan() end)

	craftButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	craftButton:SetHeight(26)
	craftButton:SetPoint("BOTTOMLEFT", 10, 10)
	craftButton:SetPoint("BOTTOMRIGHT", -10, 10)
	craftButton:SetText("Craft Next")
	craftButton:SetScript("OnClick", function() ns.Queue.CraftNext() end)

	statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("BOTTOMLEFT", 12, 42)
	statusText:SetPoint("BOTTOMRIGHT", -12, 42)
	statusText:SetJustifyH("LEFT")
	statusText:SetHeight(24)

	local container = CreateFrame("Frame", nil, panel)
	container:SetPoint("TOPLEFT", 10, -84)
	container:SetPoint("BOTTOMRIGHT", -24, 70)
	container:EnableMouseWheel(true)
	container:SetScript("OnSizeChanged", function() if panel:IsShown() then RenderRows() end end)
	container:SetScript("OnMouseWheel", function(_, delta)
		scrollOffset = math.max(0, scrollOffset - delta * 3)
		RenderRows()
	end)

	rows = { container = container }
	for i = 1, ROW_COUNT do
		local row = CreateRow(container)
		row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
		row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
		row:Hide()
		rows[i] = row
	end

	slider = CreateFrame("Slider", nil, panel)
	slider:SetPoint("TOPRIGHT", -10, -84)
	slider:SetPoint("BOTTOMRIGHT", -10, 70)
	slider:SetWidth(10)
	slider:SetOrientation("VERTICAL")
	slider:SetValueStep(1)
	slider:SetObeyStepOnDrag(true)
	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(0.6, 0.6, 0.6, 0.8)
	thumb:SetSize(10, 36)
	slider:SetThumbTexture(thumb)
	slider:SetScript("OnValueChanged", function(_, value)
		local offset = math.floor(value + 0.5)
		if not updatingSlider and offset ~= scrollOffset then
			scrollOffset = offset
			RenderRows()
		end
	end)

	panel:SetScript("OnShow", UI.Refresh)
end

local function Attach()
	if not panel then CreatePanel() end
	attached = true
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 2, 0)
	panel:SetPoint("BOTTOMLEFT", ProfessionsFrame, "BOTTOMRIGHT", 2, 0)
end

function UI.ShowStandalone(tab)
	if not panel then CreatePanel() end
	if ProfessionsFrame and ProfessionsFrame:IsShown() then
		Attach()
	else
		attached = false
		panel:ClearAllPoints()
		panel:SetSize(PANEL_WIDTH, 560)
		panel:SetPoint("CENTER")
	end
	if tab then currentTab = tab end
	panel:Show()
	UI.Refresh()
end

function UI.Toggle(tab)
	if panel and panel:IsShown() and (not tab or tab == currentTab) then
		panel:Hide()
	else
		UI.ShowStandalone(tab)
	end
end

---------------------------------------------------------------------------
-- Profession window integration
---------------------------------------------------------------------------

local queueButton
local hooked = false

local function SelectedRecipe()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	local form = page and page.SchematicForm
	return form and form.GetRecipeInfo and form:GetRecipeInfo() or nil
end

local function CraftCountFromInput()
	local box = ProfessionsFrame.CraftingPage.CreateMultipleInputBox
	local value = box and box.GetValue and box:GetValue()
	return type(value) == "number" and value >= 1 and value or 1
end

local function HookProfessionWindow()
	if hooked or not (ProfessionsFrame and ProfessionsFrame.CraftingPage) then return end
	hooked = true
	local page = ProfessionsFrame.CraftingPage

	local anchor = page.CreateAllButton or page.CreateButton
	if anchor then
		queueButton = CreateFrame("Button", "CraftLedgerQueueButton", page, "UIPanelButtonTemplate")
		queueButton:SetSize(80, anchor:GetHeight() > 0 and anchor:GetHeight() or 22)
		queueButton:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
		queueButton:SetText("Queue")
		queueButton:SetScript("OnClick", function()
			local info = SelectedRecipe()
			if not info or not info.recipeID then
				ns.Print("Select a recipe first.")
			elseif not info.learned then
				ns.Print("You have not learned that recipe.")
			else
				ns.Queue.Add(info.recipeID, CraftCountFromInput())
				UI.ShowStandalone("queue")
			end
		end)
		queueButton:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText("Add to CraftLedger queue")
			GameTooltip:AddLine("Uses the amount in the box next to Create.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		queueButton:SetScript("OnLeave", GameTooltip_Hide)
	end

	ProfessionsFrame:HookScript("OnShow", function()
		if ns.db.ui.autoOpen then UI.ShowStandalone() end
	end)
	ProfessionsFrame:HookScript("OnHide", function()
		if panel and attached then
			panel:Hide()
			attached = false
		end
	end)
end

ns.On("ADDON_LOADED", function(name)
	if name == "Blizzard_Professions" then HookProfessionWindow() end
end)

local function NotifyStale()
	if scanNotified or not ns.Prices.IsStale() then return end
	scanNotified = true
	ns.Print(ScanAgeText() .. " Scan at the auction house for accurate profit.")
end

ns.On("TRADE_SKILL_SHOW", function()
	HookProfessionWindow()
	NotifyStale()
	if ns.db.ui.autoOpen and ProfessionsFrame and ProfessionsFrame:IsShown() then UI.ShowStandalone() end
end)

function ns.OnProfessionScanned()
	ns.InvalidateProfit()
	UI.Refresh()
end

---------------------------------------------------------------------------
-- Scan prompt
---------------------------------------------------------------------------

StaticPopupDialogs["CRAFTLEDGER_SCAN"] = {
	text = "CraftLedger: %s Run a new auction house scan now?",
	button1 = YES,
	button2 = NO,
	OnAccept = function() ns.Prices.StartScan() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

ns.On("AUCTION_HOUSE_SHOW", function()
	-- Auctionator creates its scan frames as the auction house opens, so wait for them.
	C_Timer.After(1.5, function()
		if ns.Prices.IsStale() and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
			StaticPopup_Show("CRAFTLEDGER_SCAN", ScanAgeText())
		end
		UI.Refresh()
	end)
end)

ns.On("AUCTION_HOUSE_CLOSED", function()
	StaticPopup_Hide("CRAFTLEDGER_SCAN")
	UI.Refresh()
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

local function CountKeys(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

local function Diagnostics()
	local lines = {}
	local function Add(text) table.insert(lines, text); ns.Print(text) end
	Add("characters: " .. CountKeys(ns.db.chars) .. ", recipes stored: " .. CountKeys(ns.db.recipes))
	local me = ns.db.chars[ns.CharKey()]
	Add("this character knows: " .. (me and CountKeys(me.recipes) or 0))
	Add("scan age: " .. (ns.Prices.ScanAge() and (ns.Prices.ScanAge() .. "s") or "never"))
	Add("Syndicator active: " .. tostring(ns.Stock.HasSyndicator()))
	Add("queue entries: " .. #ns.db.queue .. ", crafts planned: " .. #ns.plan.crafts)
	Add("to buy: " .. CountKeys(ns.plan.buy) .. ", vendor: " .. CountKeys(ns.plan.vendor))
	local status = ns.Shopping.status
	Add(("list '%s': %d items, %d loading, error: %s"):format(ns.LIST_NAME, status.items, status.loading, tostring(status.error)))
	Add("Queue button on crafting page: " .. tostring(queueButton ~= nil))
	ns.db.lastDiag = lines
end

SLASH_CRAFTLEDGER1 = "/craftledger"
SLASH_CRAFTLEDGER2 = "/cledger"
SlashCmdList.CRAFTLEDGER = function(input)
	local command = (input or ""):lower():match("^%s*(%S*)")
	if command == "queue" or command == "profit" then
		UI.ShowStandalone(command)
	elseif command == "clear" then
		ns.Queue.Clear()
	elseif command == "auto" then
		ns.db.ui.autoOpen = not ns.db.ui.autoOpen
		ns.Print("Open with the profession window: " .. tostring(ns.db.ui.autoOpen))
	elseif command == "diag" then
		Diagnostics()
	elseif command == "" then
		UI.Toggle()
	else
		ns.Print("/craftledger [queue | profit | clear | auto | diag]")
	end
end
