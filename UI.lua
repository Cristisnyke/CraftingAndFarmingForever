-- CraftLedger :: UI
-- Four independent movable windows (Profit, Queue, Restock, Sales), the Queue button on the crafting page, the stale-price
-- prompts and the slash command.

local _, ns = ...

local UI = {}
ns.UI = UI

local ROW_HEIGHT = 22
local ROW_COUNT = 40
local WINDOW_WIDTH = 380
local WINDOW_HEIGHT = 560
local TAB_WIDTH = 112
local TAB_COUNT = 16
local COLOR_PROFIT, COLOR_LOSS, COLOR_MUTED = "ff55dd55", "ffff6655", "ff999999"

local function Color(hex, text)
	return "|c" .. hex .. text .. "|r"
end

local windows = {}
-- Selected profession tab per window; nil is the All tab.
local selectedProfession = {}
local lastOpenProfession
UI.windows = windows
local profitCache
local scanNotified = false

---------------------------------------------------------------------------
-- Profit data
---------------------------------------------------------------------------

function ns.InvalidateProfit()
	profitCache = nil
	UI.Refresh("profit")
	UI.Refresh("restock")
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
	local selected = selectedProfession.profit
	local list = {}
	for _, result in ipairs(profitCache) do
		if not selected or result.profession == selected then
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

-- priceLabel and priceOf are for lists bought with gold: the price each row's quantity was costed at.
local function AddItemRows(list, title, items, priceLabel, priceOf)
	local sorted = {}
	for itemID, count in pairs(items) do
		table.insert(sorted, {
			kind = "item", itemID = itemID, count = count, priceLabel = priceLabel, price = priceOf and priceOf(itemID),
		})
	end
	if #sorted == 0 then return end
	table.sort(sorted, function(a, b) return a.itemID < b.itemID end)
	table.insert(list, { kind = "header", text = title })
	for _, row in ipairs(sorted) do table.insert(list, row) end
end

local function BuildQueueList()
	local list = {}
	local plan = ns.plan
	if #ns.db.queue > 0 then
		local ctx = ns.NewContext()
		table.insert(list, { kind = "header", text = "Queue (mats: material cost of one craft, Quote: reply with it + 10%)" })
		for index, entry in ipairs(ns.db.queue) do
			local matCost = ns.Planner.RecipeCost(ctx, entry.recipeID)
			table.insert(list, { kind = "queue", index = index, entry = entry, matCost = matCost })
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
	AddItemRows(list, "Buy at auction house (red: dearer since last scan, green: cheaper)", plan.buy, "max", ns.Prices.AH)
	AddItemRows(list, "Buy from vendor", plan.vendor, "at", ns.Prices.Vendor)
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

local function BuildRestockList()
	local selected = selectedProfession.restock
	local list = {}
	for _, row in ipairs(ns.Restock.Rows()) do
		local recipe = ns.db.recipes[row.recipeID]
		if not selected or (recipe and recipe.p == selected) then
			table.insert(list, { kind = "restock", row = row })
		end
	end
	return list
end

local function BuildSalesList()
	local list = {}
	for _, item in ipairs(ns.Sales.AllItems()) do table.insert(list, { kind = "sales", item = item }) end
	return list
end

-- "62%" coloured by how likely it is. Grey "~62%" until there's enough data to rely on. Empty with no data.
local function ChanceText(name)
	local chance, samples = ns.Sales.Chance(name)
	if not chance then return "" end
	local percent = ("%d%%"):format(math.floor(chance * 100 + 0.5))
	if samples < ns.Sales.CONFIDENT_SAMPLES then return Color(COLOR_MUTED, "~" .. percent) end
	if chance >= 0.5 then return Color(COLOR_PROFIT, percent) end
	if chance >= 0.2 then return Color("ffffb040", percent) end
	return Color(COLOR_LOSS, percent)
end

-- The sales history block of a tooltip: chance to sell, then sold and expired per period.
local function AddSalesLines(name)
	local item = ns.Sales.Item(name)
	GameTooltip:AddLine(" ")
	if not item or item.sold + item.expired == 0 then
		GameTooltip:AddLine("No sales or expiries recorded yet.", 0.6, 0.6, 0.6)
		return
	end
	local chance, samples = ns.Sales.Chance(name)
	if chance then
		GameTooltip:AddDoubleLine("Chance to sell in 24 hours", ChanceText(name), 1, 0.82, 0)
		GameTooltip:AddLine(("Based on %d unit(s). More data makes this more accurate."):format(samples), 0.6, 0.6, 0.6, true)
	end
	GameTooltip:AddDoubleLine(" ", "sold / expired", 1, 1, 1, 0.6, 0.6, 0.6)
	for _, period in ipairs({ { "Today", 1 }, { "Last 7 days", 7 }, { "Last 30 days", 30 }, { "All time", nil } }) do
		local sold, expired = ns.Sales.Counts(item, period[2])
		GameTooltip:AddDoubleLine(period[1], sold .. " / " .. expired, 1, 1, 1, 1, 1, 1)
	end
	local _, _, gold = ns.Sales.Counts(item, nil)
	GameTooltip:AddDoubleLine("Earned, all time", ns.Money(gold), 1, 1, 1, 1, 1, 1)
end

-- "was 30c, now 40c". dearerIsBad: materials cost more (bad); for things you sell, a lower price is bad.
local function PriceChangeText(itemID, dearerIsBad)
	local old, new = ns.Prices.Change(itemID)
	if not old then return nil end
	local bad = dearerIsBad == (new > old)
	return Color(bad and COLOR_LOSS or COLOR_PROFIT, ("was %s, now %s"):format(ns.Money(old), ns.Money(new)))
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
	AddSalesLines(ns.Items.Name(result.itemID))
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
		if data.priceLabel == "max" then
			GameTooltip:AddLine(" ")
			if data.price then
				local old = ns.Prices.Change(data.itemID)
				if old then GameTooltip:AddDoubleLine("Price before this scan", ns.Money(old), 1, 1, 1, 1, 1, 1) end
				GameTooltip:AddDoubleLine("Profit assumes each costs", ns.Money(data.price), 1, 1, 1, 1, 1, 1)
				local age = ns.Prices.ItemAgeDays(data.itemID)
				if age and age > 0 then
					GameTooltip:AddLine(("That price is %d day(s) old."):format(age), 1, 0.6, 0.2)
				end
				if ns.totals.counted > 0 and ns.totals.net > 0 then
					GameTooltip:AddDoubleLine("Queue profit gone at", ns.Money(data.price + ns.totals.net / data.count), 1, 1, 1, 1, 0.6, 0.2)
					GameTooltip:AddLine("If you paid this for all of them and everything else stayed at its scan price.", 0.6, 0.6, 0.6, true)
				end
			else
				GameTooltip:AddLine("No price known, so this isn't in the total.", 1, 0.6, 0.2, true)
			end
		end
		GameTooltip:Show()
	elseif data.kind == "restock" then
		local item = data.row
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetText(RecipeName(item.recipeID))
		GameTooltip:AddDoubleLine("Profit per craft", ns.Money(item.net), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("On the AH", item.onAH and tostring(item.onAH) or "unknown", 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("In bags, banks and mail", tostring(item.owned), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("Goal", tostring(item.goal), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("Crafts needed", tostring(item.crafts), 1, 1, 1, 1, 1, 1)
		AddSalesLines(ns.Items.Name(item.itemID))
		GameTooltip:AddLine("+ and - change this item's goal (Shift for 10). A goal of 0 skips the item.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	elseif data.kind == "sales" then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetText(data.item.name)
		AddSalesLines(data.item.name)
		GameTooltip:Show()
	elseif data.kind == "queue" then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetText(RecipeName(data.entry.recipeID))
		GameTooltip:AddLine("Crafted by " .. ns.CharLabel(ns.Recipes.Crafter(data.entry.recipeID, data.entry.char)), 0.6, 0.8, 1)
		local queuedRecipe = ns.db.recipes[data.entry.recipeID]
		if queuedRecipe and queuedRecipe.o then
			local old, new = ns.Prices.Change(queuedRecipe.o)
			if old then
				GameTooltip:AddDoubleLine("Sale price before this scan", ns.Money(old), 1, 1, 1, 1, 1, 1)
				GameTooltip:AddDoubleLine("Sale price now", ns.Money(new), 1, 1, 1, 1, 1, 1)
			end
			AddSalesLines(ns.Items.Name(queuedRecipe.o))
		end
		GameTooltip:AddLine("+ adds one, Shift + adds ten, - removes one, x removes the entry.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end
end

local function RowOnClick(row)
	local data = row.data
	if data and data.kind == "profit" and ns.Recipes.Knows(ns.CharKey(), data.result.recipeID)
		and ns.Recipes.OpenRecipes()[data.result.recipeID] then
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
		elseif data.kind == "restock" then
			ns.Restock.SetGoal(data.row.itemID, data.row.goal + (IsShiftKeyDown() and 10 or 1))
			UI.Refresh("restock")
		end
	end)
	row.plus:SetPoint("RIGHT", row, "RIGHT", -2, 0)

	row.minus = SmallButton(row, "-", function(self)
		local data = self:GetParent().data
		if not data then return end
		if data.kind == "queue" then
			ns.Queue.Change(data.index, -1)
		elseif data.kind == "restock" then
			ns.Restock.SetGoal(data.row.itemID, data.row.goal - (IsShiftKeyDown() and 10 or 1))
			UI.Refresh("restock")
		end
	end)
	row.minus:SetPoint("RIGHT", row.plus, "LEFT", -1, 0)

	row.remove = SmallButton(row, "x", function(self)
		local data = self:GetParent().data
		if data and data.kind == "queue" then ns.Queue.Remove(data.index) end
	end)
	row.remove:SetPoint("RIGHT", row.minus, "LEFT", -1, 0)

	row.quote = SmallButton(row, "Quote", function(self)
		local data = self:GetParent().data
		if data and data.kind == "queue" then ns.Advertise.QuoteInWhisper(data.entry.recipeID) end
	end)
	row.quote:SetWidth(46)
	row.quote:SetPoint("RIGHT", row.remove, "LEFT", -1, 0)
	row.quote:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Quote this price")
		GameTooltip:AddLine("Fills in a reply to your last whisper with the material cost plus 10%. You press Enter to send it.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	row.quote:SetScript("OnLeave", GameTooltip_Hide)

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
	row.quote:Hide()
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
			local chance = ChanceText(ns.Items.Name(result.itemID))
			row.right:SetText((chance ~= "" and (chance .. "   ") or "")
				.. Color(result.net >= 0 and COLOR_PROFIT or COLOR_LOSS, ns.Money(result.net)))
		else
			row.right:SetText(Color(COLOR_MUTED, "no data"))
		end
	elseif data.kind == "queue" then
		local recipe = ns.db.recipes[data.entry.recipeID]
		row.icon:SetTexture(recipe and recipe.o and ns.Items.Icon(recipe.o) or 134400)
		row.left:SetText(RecipeName(data.entry.recipeID) .. " x" .. data.entry.qty
			.. (data.entry.restock and Color(COLOR_MUTED, " restock") or ""))
		row.plus:Show()
		row.minus:Show()
		row.remove:Show()
		row.quote:Show()
		row.right:ClearAllPoints()
		row.right:SetPoint("RIGHT", row.quote, "LEFT", -4, 0)
		local net = ns.totals.entries[data.index]
		local netText = net and Color(net >= 0 and COLOR_PROFIT or COLOR_LOSS, ns.Money(net)) or Color(COLOR_MUTED, "no price")
		local change = recipe and recipe.o and PriceChangeText(recipe.o, false)
		local mats = Color(COLOR_MUTED, "mats " .. (data.matCost and ns.Money(data.matCost) or "?"))
		row.right:SetText(mats .. "   " .. (change and ("sells " .. change .. "   ") or "") .. netText)
	elseif data.kind == "restock" then
		local item = data.row
		row.icon:SetTexture(ns.Items.Icon(item.itemID))
		row.left:SetText(ItemLabel(item.itemID))
		row.plus:Show()
		row.minus:Show()
		row.right:ClearAllPoints()
		row.right:SetPoint("RIGHT", row.minus, "LEFT", -4, 0)
		local text = ("AH %s, have %d, goal %d"):format(item.onAH and tostring(item.onAH) or "?", item.owned, item.goal)
		local chance = ChanceText(ns.Items.Name(item.itemID))
		local prefix = chance ~= "" and (chance .. "   ") or ""
		if item.goal == 0 then
			row.right:SetText(prefix .. Color(COLOR_MUTED, "skipped"))
		elseif item.crafts > 0 then
			row.right:SetText(prefix .. Color("ffffb040", text))
		else
			row.right:SetText(prefix .. Color(COLOR_PROFIT, text))
		end
	elseif data.kind == "sales" then
		local item = data.item
		if item.itemID then
			row.icon:SetTexture(ns.Items.Icon(item.itemID))
			row.left:SetText(ItemLabel(item.itemID))
		else
			row.icon:Hide()
			row.left:SetText(item.name)
		end
		local sold, expired = ns.Sales.Counts(item, 7)
		local chance = ChanceText(item.name)
		row.right:SetText((chance ~= "" and (chance .. "   ") or "") .. ("7 days: %d sold, %d expired"):format(sold, expired))
	elseif data.kind == "auto" then
		local recipe = ns.db.recipes[data.craft.recipeID]
		row.icon:SetTexture(recipe and recipe.o and ns.Items.Icon(recipe.o) or 134400)
		row.left:SetText(RecipeName(data.craft.recipeID) .. " x" .. data.craft.count)
		row.right:SetText(Color(COLOR_MUTED, ns.CharLabel(data.craft.char)))
	elseif data.kind == "item" then
		row.icon:SetTexture(ns.Items.Icon(data.itemID))
		row.left:SetText(ItemLabel(data.itemID))
		if data.priceLabel then
			local price = data.priceLabel == "max" and PriceChangeText(data.itemID, true)
				or (data.price and (data.priceLabel .. " " .. ns.Money(data.price)))
				or Color(COLOR_LOSS, "no price")
			row.right:SetText("x" .. data.count .. ", " .. price)
		else
			row.right:SetText("x" .. data.count)
		end
	end
	row:Show()
end

local function ScanAgeText()
	local age = ns.Prices.ScanAge()
	if not age then return "No auction house scan yet." end
	return ("Prices are %d hours old."):format(math.floor(age / 3600))
end

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------

local function RenderRows(window)
	local visible = math.min(ROW_COUNT, math.floor(window.container:GetHeight() / ROW_HEIGHT))
	local maxOffset = math.max(0, #window.list - visible)
	window.offset = math.min(window.offset, maxOffset)
	for i = 1, ROW_COUNT do
		local data = i <= visible and window.list[window.offset + i]
		if data then
			SetRow(window.rows[i], data)
		else
			window.rows[i].data = nil
			window.rows[i]:Hide()
		end
	end
	-- These can fire OnValueChanged while clamping; that must not overwrite the offset being rendered.
	window.updatingSlider = true
	window.slider:SetMinMaxValues(0, maxOffset)
	window.slider:SetValue(window.offset)
	window.updatingSlider = false
	window.slider:SetShown(maxOffset > 0)
end

local function UpdateBanner(window)
	local stale = ns.Prices.IsStale()
	window.banner:SetShown(stale)
	if not stale then return end
	local atAH = AuctionHouseFrame and AuctionHouseFrame:IsShown()
	window.banner.text:SetText(ScanAgeText() .. (atAH and "" or " Scan at the auction house."))
	window.scanButton:SetShown(atAH and true or false)
end

local function RenderTabs(window)
	local professions = ns.Recipes.KnownProfessions()
	local selected = selectedProfession[window.key]
	local stillExists = selected == nil
	for _, profession in ipairs(professions) do
		stillExists = stillExists or profession.id == selected
	end
	if not stillExists then
		selected = nil
		selectedProfession[window.key] = nil
	end
	for i = 1, TAB_COUNT do
		local tab = window.tabs[i]
		local profession = professions[i - 1]
		if i == 1 or profession then
			local id = profession and profession.id or nil
			local name = profession and profession.name or "All"
			tab.professionID = id
			if id == selected then
				tab:SetText("|cffffffff" .. name .. "|r")
				tab:LockHighlight()
			else
				tab:SetText(name)
				tab:UnlockHighlight()
			end
			tab:Show()
		else
			tab:Hide()
		end
	end
end

function UI.SelectProfession(key, professionID)
	selectedProfession[key] = professionID
	if windows[key] then windows[key].offset = 0 end
	UI.Refresh(key)
end

function UI.Refresh(key)
	local window = windows[key]
	if not window or not window.frame:IsShown() then return end
	if window.tabs then RenderTabs(window) end
	window.list = window.build()
	RenderRows(window)
	UpdateBanner(window)
	window.update(window)
end

function UI.RefreshAll()
	UI.Refresh("profit")
	UI.Refresh("queue")
	UI.Refresh("restock")
	UI.Refresh("sales")
end

-- Queue, bags or bank changed: both windows that count stock need redrawing.
function UI.RefreshQueue()
	UI.Refresh("queue")
	UI.Refresh("restock")
end

-- Where the window goes until the user moves it: profit beside the profession window, queue beside profit.
local function PlaceWindow(window)
	local frame = window.frame
	frame:ClearAllPoints()
	local saved = ns.db.ui.positions and ns.db.ui.positions[window.key]
	if saved then
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
	elseif window.key == "profit" then
		if ProfessionsFrame and ProfessionsFrame:IsShown() then
			frame:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 2, 0)
		else
			frame:SetPoint("CENTER", UIParent, "CENTER", -frame:GetWidth() / 2 - 2, 0)
		end
	elseif window.key == "restock" or window.key == "sales" then
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	elseif windows.profit and windows.profit.frame:IsShown() and windows.profit.frame:GetRight() then
		-- A fixed spot beside Profit, not an anchor to it: moving Profit must not drag this window along.
		local profit = windows.profit.frame
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", profit:GetRight() + 2, profit:GetTop())
	elseif ProfessionsFrame and ProfessionsFrame:IsShown() then
		frame:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 2, 0)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", WINDOW_WIDTH / 2 + 2, 0)
	end
end

local function SavePosition(window)
	local left, top = window.frame:GetLeft(), window.frame:GetTop()
	if not (left and top) then return end
	ns.db.ui.positions = ns.db.ui.positions or {}
	ns.db.ui.positions[window.key] = { x = left, y = top }
end

local function HeaderButton(frame, text, width, onClick)
	local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

-- footerHeight is the room kept below the list for the window's own controls. withTabs adds the column of
-- profession tabs on the left. extraWidth is for windows whose rows need more room.
local function CreateWindow(key, title, footerHeight, withTabs, extraWidth)
	local frame = CreateFrame("Frame", "CraftLedger" .. title .. "Window", UIParent, "BackdropTemplate")
	local window = { key = key, frame = frame, list = {}, offset = 0, rows = {} }
	windows[key] = window

	local listLeft = withTabs and (10 + TAB_WIDTH) or 10
	frame:SetSize(WINDOW_WIDTH + (withTabs and TAB_WIDTH or 0) + (extraWidth or 0), WINDOW_HEIGHT)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition(window)
	end)
	frame:Hide()

	local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleText:SetPoint("TOPLEFT", 12, -10)
	titleText:SetText("CraftLedger: " .. title)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 0, 0)
	close:SetScript("OnClick", function() frame:Hide() end)

	local refresh = HeaderButton(frame, "Refresh", 70, function() ns.RefreshEverything() end)
	refresh:SetHeight(20)
	refresh:SetPoint("RIGHT", close, "LEFT", -2, 0)

	local banner = CreateFrame("Frame", nil, frame)
	banner:SetPoint("TOPLEFT", 10, -56)
	banner:SetPoint("TOPRIGHT", -10, -56)
	banner:SetHeight(24)
	banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	banner.text:SetPoint("LEFT", 2, 0)
	banner.text:SetTextColor(1, 0.6, 0.2)
	window.banner = banner
	window.scanButton = HeaderButton(banner, "Scan now", 80, function() ns.Prices.StartScan() end)
	window.scanButton:SetPoint("RIGHT")

	local container = CreateFrame("Frame", nil, frame)
	container:SetPoint("TOPLEFT", listLeft, -84)
	container:SetPoint("BOTTOMRIGHT", -24, footerHeight)
	container:EnableMouseWheel(true)
	container:SetScript("OnSizeChanged", function() if frame:IsShown() then RenderRows(window) end end)
	container:SetScript("OnMouseWheel", function(_, delta)
		window.offset = math.max(0, window.offset - delta * 3)
		RenderRows(window)
	end)
	window.container = container

	for i = 1, ROW_COUNT do
		local row = CreateRow(container)
		row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
		row:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
		row:Hide()
		window.rows[i] = row
	end

	if withTabs then
		window.tabs = {}
		for i = 1, TAB_COUNT do
			local tab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
			tab:SetSize(TAB_WIDTH - 6, 24)
			tab:SetPoint("TOPLEFT", 10, -84 - (i - 1) * 26)
			tab:SetScript("OnClick", function(self) UI.SelectProfession(key, self.professionID) end)
			tab:Hide()
			window.tabs[i] = tab
		end
	end

	local slider = CreateFrame("Slider", nil, frame)
	slider:SetPoint("TOPRIGHT", -10, -84)
	slider:SetPoint("BOTTOMRIGHT", -10, footerHeight)
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
		if not window.updatingSlider and offset ~= window.offset then
			window.offset = offset
			RenderRows(window)
		end
	end)
	window.slider = slider

	frame:SetScript("OnShow", function() UI.Refresh(key) end)
	return window
end

local function CreateProfitWindow()
	local window = CreateWindow("profit", "Profit", 34, true)
	window.build = BuildProfitList

	local advertise = HeaderButton(window.frame, "Advertise", 190, function() ns.Advertise.Send(UI.AdvertisedProfession()) end)
	advertise:SetPoint("TOPLEFT", 10, -30)
	window.advertiseButton = advertise

	local openQueue = HeaderButton(window.frame, "Queue", 70, function() UI.Toggle("queue") end)
	openQueue:SetPoint("TOPRIGHT", -12, -30)

	local openRestock = HeaderButton(window.frame, "Restock", 70, function() UI.Toggle("restock") end)
	openRestock:SetPoint("RIGHT", openQueue, "LEFT", -4, 0)

	local openSales = HeaderButton(window.frame, "Sales", 70, function() UI.Toggle("sales") end)
	openSales:SetPoint("RIGHT", openRestock, "LEFT", -4, 0)

	local status = window.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("BOTTOMLEFT", 12, 12)
	status:SetPoint("BOTTOMRIGHT", -12, 12)
	status:SetJustifyH("LEFT")

	window.update = function(self)
		local professionID = UI.AdvertisedProfession()
		local canAdvertise = ns.Advertise.Reason(professionID) == nil
		advertise:SetEnabled(canAdvertise)
		local professionName = professionID and ns.Recipes.ProfessionName(professionID)
		advertise:SetText(canAdvertise and professionName and ("Advertise " .. professionName) or "Advertise")
		if #self.list == 0 then
			status:SetText("Open a profession to record its recipes.")
		else
			status:SetText(#self.list .. " sellable recipes known across your characters.")
		end
	end
end

local function CreateQueueWindow()
	local window = CreateWindow("queue", "Queue", 128, false, 240)
	window.build = BuildQueueList

	local clear = HeaderButton(window.frame, "Clear", 70, function() ns.Queue.Clear() end)
	clear:SetPoint("TOPLEFT", 10, -30)

	local openProfit = HeaderButton(window.frame, "Profit", 70, function() UI.Toggle("profit") end)
	openProfit:SetPoint("TOPRIGHT", -12, -30)

	local openRestock = HeaderButton(window.frame, "Restock", 70, function() UI.Toggle("restock") end)
	openRestock:SetPoint("RIGHT", openProfit, "LEFT", -4, 0)

	local craftButton = HeaderButton(window.frame, "Craft Next", 100, function() ns.Queue.CraftNext() end)
	craftButton:SetHeight(26)
	craftButton:ClearAllPoints()
	craftButton:SetPoint("BOTTOMLEFT", 10, 10)
	craftButton:SetPoint("BOTTOMRIGHT", -10, 10)

	local status = window.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("BOTTOMLEFT", 12, 40)
	status:SetPoint("BOTTOMRIGHT", -12, 40)
	status:SetHeight(24)
	status:SetJustifyH("LEFT")
	status:SetJustifyV("BOTTOM")

	local detail = window.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	detail:SetPoint("BOTTOMLEFT", 12, 66)
	detail:SetPoint("BOTTOMRIGHT", -12, 66)
	detail:SetHeight(26)
	detail:SetJustifyH("LEFT")
	detail:SetJustifyV("BOTTOM")

	local total = window.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	total:SetPoint("BOTTOMLEFT", 12, 96)
	total:SetPoint("BOTTOMRIGHT", -12, 96)
	total:SetJustifyH("LEFT")

	window.update = function()
		local totals = ns.totals
		if totals.counted > 0 then
			local hex = totals.net >= 0 and COLOR_PROFIT or COLOR_LOSS
			total:SetText("Total profit: " .. Color(hex, ns.Money(totals.net)))
			detail:SetText(("Sells for %s after AH cut, materials %s.\nStill to buy: %s."):format(
				ns.Money(totals.revenue), ns.Money(totals.cost), ns.Money(ns.plan.cost)))
		elseif totals.excluded > 0 then
			total:SetText("Total profit: " .. Color(COLOR_MUTED, "no price data"))
			detail:SetText(("Still to buy: %s."):format(ns.Money(ns.plan.cost)))
		else
			total:SetText("Total profit: " .. Color(COLOR_MUTED, "nothing queued"))
			detail:SetText("")
		end

		local craft, count, reason = ns.Queue.NextCraft()
		if craft then
			craftButton:SetText(("Craft Next: %s x%d"):format(RecipeName(craft.recipeID), count))
			craftButton:Enable()
		else
			craftButton:SetText("Craft Next")
			craftButton:Disable()
		end

		local notes = {}
		if reason then table.insert(notes, reason) end
		local losing = 0
		for _, net in pairs(totals.entries) do
			if net < 0 then losing = losing + 1 end
		end
		if losing > 0 then table.insert(notes, losing .. " queued item(s) would now lose money.") end
		if totals.excluded > 0 and totals.counted > 0 then
			table.insert(notes, totals.excluded .. " queued recipe(s) have no price and aren't in the total.")
		end
		local shopping = ns.Shopping.status
		if shopping.error then table.insert(notes, "List update failed. See /craftledger diag.") end
		if shopping.loading > 0 then table.insert(notes, shopping.loading .. " item name(s) loading.") end
		if not ns.Stock.HasSyndicator() then table.insert(notes, "Syndicator not active: alts not counted.") end
		status:SetText(table.concat(notes, " "))
	end
end

-- A labelled number box in the restock footer. Saves on Enter or when it loses focus.
local function NumberBox(parent, labelText, previous, read, write)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetText(labelText)
	if previous then
		label:SetPoint("LEFT", previous, "RIGHT", 12, 0)
	else
		label:SetPoint("BOTTOMLEFT", 12, 72)
	end
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(38, 20)
	box:SetPoint("LEFT", label, "RIGHT", 8, 0)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(4)
	local function Save(self)
		local value = tonumber(self:GetText())
		if value and value ~= read() then
			write(value)
			UI.Refresh("restock")
		end
	end
	box:SetScript("OnEnterPressed", function(self)
		Save(self)
		self:ClearFocus()
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:SetText(tostring(read()))
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusLost", Save)
	box.Sync = function(self)
		if not self:HasFocus() then self:SetText(tostring(read())) end
	end
	return box
end

local function CreateRestockWindow()
	local window = CreateWindow("restock", "Restock", 96, true)
	window.build = BuildRestockList

	local openQueue = HeaderButton(window.frame, "Queue", 70, function() UI.Toggle("queue") end)
	openQueue:SetPoint("TOPRIGHT", -12, -30)

	local stack = NumberBox(window.frame, "Stackable goal", nil,
		function() return ns.db.restock.stackGoal end, function(v) ns.db.restock.stackGoal = v end)
	local single = NumberBox(window.frame, "Single goal", stack,
		function() return ns.db.restock.singleGoal end, function(v) ns.db.restock.singleGoal = v end)
	local minProfit = NumberBox(window.frame, "Min profit (s)", single,
		function() return ns.db.restock.minProfitSilver end, function(v) ns.db.restock.minProfitSilver = v end)

	local status = window.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("BOTTOMLEFT", 12, 40)
	status:SetPoint("BOTTOMRIGHT", -12, 40)
	status:SetHeight(24)
	status:SetJustifyH("LEFT")
	status:SetJustifyV("BOTTOM")

	local apply = HeaderButton(window.frame, "Queue restock", 100, function()
		local rows = {}
		for _, data in ipairs(window.list) do table.insert(rows, data.row) end
		local added = ns.Restock.Apply(rows, selectedProfession.restock)
		ns.Print(("Restock: %d item(s) added to the queue."):format(added))
		UI.Show("queue")
	end)
	apply:SetHeight(26)
	apply:ClearAllPoints()
	apply:SetPoint("BOTTOMLEFT", 10, 10)
	apply:SetPoint("BOTTOMRIGHT", -10, 10)

	window.update = function(self)
		stack:Sync()
		single:Sync()
		minProfit:Sync()

		local needed, toPost = 0, 0
		for _, data in ipairs(self.list) do
			local row = data.row
			if row.crafts > 0 then needed = needed + 1 end
			if row.goal > 0 and (row.onAH or 0) < row.goal then
				toPost = toPost + math.min(row.owned, row.goal - (row.onAH or 0))
			end
		end

		if not ns.Stock.HasSyndicator() then
			apply:Disable()
			apply:SetText("Queue restock")
			status:SetText("Syndicator is needed to see your auctions. Without it this would over-craft.")
			return
		end
		apply:SetEnabled(needed > 0)
		apply:SetText(needed > 0 and ("Queue restock: %d item(s)"):format(needed) or "Fully stocked")
		local notes = { "AH counts update when you visit the auction house." }
		if toPost > 0 then table.insert(notes, 1, toPost .. " item(s) you hold are ready to post.") end
		if #self.list == 0 then notes = { "No profitable items yet. Open your professions and scan the AH." } end
		status:SetText(table.concat(notes, " "))
	end
end

local function CreateSalesWindow()
	local window = CreateWindow("sales", "Sales", 76)
	window.build = BuildSalesList

	local totals = window.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	totals:SetPoint("BOTTOMLEFT", 12, 12)
	totals:SetPoint("BOTTOMRIGHT", -12, 12)
	totals:SetHeight(56)
	totals:SetJustifyH("LEFT")
	totals:SetJustifyV("BOTTOM")

	window.update = function(self)
		local lines = {}
		if #self.list == 0 then
			table.insert(lines, "Nothing recorded yet. Sales and expiries are read from your mailbox, so open it on each character.")
		else
			for _, period in ipairs({ { "Today", 1 }, { "Last 7 days", 7 }, { "Last 30 days", 30 } }) do
				local sold, expired, gold = ns.Sales.Totals(period[2])
				table.insert(lines, ("%s: %d sold, %d expired, earned %s"):format(period[1], sold, expired, ns.Money(gold)))
			end
		end
		totals:SetText(table.concat(lines, "\n"))
	end
end

local function GetWindow(key)
	if not windows[key] then
		if key == "profit" then
			CreateProfitWindow()
		elseif key == "sales" then
			CreateSalesWindow()
		elseif key == "restock" then
			CreateRestockWindow()
		else
			CreateQueueWindow()
		end
	end
	return windows[key]
end

-- withProfession: the window closes again with the profession window. Opened by command, it stays until closed.
function UI.Show(key, withProfession)
	local window = GetWindow(key)
	if not window.frame:IsShown() then
		PlaceWindow(window)
		window.withProfession = withProfession
		window.frame:Show()
	end
	UI.Refresh(key)
end

function UI.Toggle(key)
	local window = GetWindow(key)
	if window.frame:IsShown() then
		window.frame:Hide()
	else
		UI.Show(key, ProfessionsFrame and ProfessionsFrame:IsShown())
	end
end

function UI.ToggleBoth()
	local anyShown = false
	for _, window in pairs(windows) do anyShown = anyShown or window.frame:IsShown() end
	if anyShown then
		for _, window in pairs(windows) do window.frame:Hide() end
	else
		UI.Show("profit")
		UI.Show("queue")
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

-- When a different profession opens, the Profit window moves to its tab. A tab clicked after that stays selected.
local function FollowOpenProfession()
	local openKey = ns.Recipes.OpenProfession()
	if openKey and openKey ~= lastOpenProfession then
		lastOpenProfession = openKey
		UI.SelectProfession("profit", openKey)
	end
end

local function OpenWithProfession()
	FollowOpenProfession()
	if not ns.db.ui.autoOpen then return end
	UI.Show("profit", true)
	if #ns.db.queue > 0 then UI.Show("queue", true) end
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
				UI.Show("queue", true)
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

	ProfessionsFrame:HookScript("OnShow", OpenWithProfession)
	ProfessionsFrame:HookScript("OnHide", function()
		lastOpenProfession = nil
		for _, window in pairs(windows) do
			if window.withProfession then window.frame:Hide() end
		end
		UI.RefreshAll()
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
	if ProfessionsFrame and ProfessionsFrame:IsShown() then OpenWithProfession() end
end)

function ns.OnProfessionScanned()
	FollowOpenProfession()
	ns.Advertise.UpdateButtons()
	ns.InvalidateProfit()
	UI.RefreshQueue()
end

---------------------------------------------------------------------------
-- Advertising in Trade chat
---------------------------------------------------------------------------

local Advertise = {}
ns.Advertise = Advertise

local AD_TEXT = "%s available for hire! Your materials, or I'll give you a price based on material cost."
local AD_COOLDOWN_SECONDS = 60
local lastAdvertised = 0
local pendingAdText

-- The tab's profession, or on the All tab the one that's open.
function UI.AdvertisedProfession()
	return selectedProfession.profit or (ns.Recipes.OpenProfession())
end

-- Why this profession can't be advertised on this character; nil when it can.
function Advertise.Reason(professionID)
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

-- Puts the message in the chat box, so only Enter is left to press.
local function PrefillChat(channel, message)
	OpenChatWith("/" .. channel .. " " .. message)
end

-- A reply to whoever whispered last. Never sent automatically: the user checks it and presses Enter.
function Advertise.QuoteInWhisper(recipeID)
	local text = ns.Queue.QuoteText(recipeID)
	if not text then
		ns.Print("A material has no price yet, so there's nothing to quote. Scan the auction house first.")
		return
	end
	local getTarget = (ChatFrameUtil and ChatFrameUtil.GetLastTellTarget) or ChatEdit_GetLastTellTarget
	local target = getTarget and getTarget()
	if target and target ~= "" then
		OpenChatWith("/w " .. target .. " " .. text)
	else
		OpenChatWith("/r " .. text)
	end
end

function Advertise.Send(professionID)
	local reason = Advertise.Reason(professionID)
	if reason then
		ns.Print(reason)
		return
	end
	local channel = TradeChannel()
	if not channel then
		ns.Print("You're not in Trade chat. Go to a city and try again.")
		return
	end
	local wait = AD_COOLDOWN_SECONDS - (time() - lastAdvertised)
	if wait > 0 then
		ns.Print(("Please wait %d more seconds, so Trade chat doesn't get spammed."):format(wait))
		return
	end

	local char = ns.db.chars[ns.CharKey()]
	local link = char.links and char.links[professionID]
	if not link then
		ns.Print("No profession link available yet, so this uses its name. Open the profession once to get the link.")
	end
	local message = AD_TEXT:format(link or ns.Recipes.ProfessionName(professionID) or "Crafting")
	lastAdvertised = time()
	Advertise.UpdateButtons()

	-- The game can refuse chat from add-ons. Once it has, go straight to the chat box.
	if ns.db.ui.advertiseManually then
		PrefillChat(channel, message)
		return
	end
	pendingAdText = { channel = channel, message = message }
	local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
	send(message, "CHANNEL", nil, channel)
	C_Timer.After(0.5, function() pendingAdText = nil end)
end

local function OnChatBlocked(addon, blockedFunction)
	if addon ~= ns.name or not pendingAdText then return end
	if type(blockedFunction) == "string" and not blockedFunction:find("SendChatMessage", 1, true) then return end
	local ad = pendingAdText
	pendingAdText = nil
	ns.db.ui.advertiseManually = true
	lastAdvertised = 0
	Advertise.UpdateButtons()
	PrefillChat(ad.channel, ad.message)
	ns.Print("The game won't let add-ons post in Trade chat, so your message is in the chat box. Press Enter to send it.")
end

ns.On("ADDON_ACTION_BLOCKED", OnChatBlocked)
ns.On("ADDON_ACTION_FORBIDDEN", OnChatBlocked)

-- Buttons beside the chat frame, one per crafting profession of this character. They work with no profession window
-- open, using the link saved when the profession was last opened, and show whenever this character is in Trade chat.
local AD_BUTTON_WIDTH, AD_BUTTON_HEIGHT = 170, 22
local adButtons = {}
Advertise.buttons = adButtons
local cooldownTimerRunning = false

local function AdButton(index)
	local button = adButtons[index]
	if not button then
		button = CreateFrame("Button", "CraftLedgerAdvertiseButton" .. index, UIParent, "UIPanelButtonTemplate")
		button:SetSize(AD_BUTTON_WIDTH, AD_BUTTON_HEIGHT)
		-- Past the chat frame's own scroll bar.
		button:SetPoint("BOTTOMLEFT", ChatFrame1, "BOTTOMRIGHT", 28, (index - 1) * (AD_BUTTON_HEIGHT + 2))
		button:SetScript("OnClick", function(self) Advertise.Send(self.professionID) end)
		adButtons[index] = button
	end
	return button
end

function Advertise.UpdateButtons()
	local me = ns.CharKey()
	local inTrade = me and TradeChannel()
	local shown = 0
	local wait = math.max(0, AD_COOLDOWN_SECONDS - (time() - lastAdvertised))
	if inTrade then
		for _, profession in ipairs(ns.Recipes.KnownProfessions()) do
			if Advertise.Reason(profession.id) == nil then
				shown = shown + 1
				local button = AdButton(shown)
				button.professionID = profession.id
				button:SetText(wait > 0 and ("%s (%d)"):format(profession.name, wait) or ("Advertise " .. profession.name))
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

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "CHANNEL_UI_UPDATE", "CHAT_MSG_CHANNEL_NOTICE" }) do
	ns.On(event, RequestAdButtonUpdate)
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
		UI.RefreshAll()
	end)
end)

ns.On("AUCTION_HOUSE_CLOSED", function()
	StaticPopup_Hide("CRAFTLEDGER_SCAN")
	UI.RefreshAll()
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
	local soldTotal, expiredTotal = ns.Sales.Totals(nil)
	Add(("sales recorded: %d sold, %d expired; open posts tracked: %d"):format(soldTotal, expiredTotal, #ns.db.sales.lots))
	Add(("list '%s': %d items, %d loading, error: %s"):format(ns.LIST_NAME, status.items, status.loading, tostring(status.error)))
	Add(("queue profit: %s from %d entries, %d without a price"):format(ns.Money(ns.totals.net), ns.totals.counted, ns.totals.excluded))
	local openKey = ns.Recipes.OpenProfession()
	Add("open profession: " .. tostring(openKey) .. ", recipes in window: " .. CountKeys(ns.Recipes.OpenRecipes()))
	Add("Queue button on crafting page: " .. tostring(queueButton ~= nil))
	Add("profession link API: " .. tostring(C_TradeSkillUI.GetTradeSkillListLink ~= nil)
		.. ", advertise through chat box: " .. tostring(ns.db.ui.advertiseManually == true))
	ns.db.lastDiag = lines
end

SLASH_CRAFTLEDGER1 = "/craftledger"
SLASH_CRAFTLEDGER2 = "/cledger"
SlashCmdList.CRAFTLEDGER = function(input)
	local command = (input or ""):lower():match("^%s*(%S*)")
	if command == "queue" or command == "profit" or command == "restock" or command == "sales" then
		UI.Toggle(command)
	elseif command == "advertise" then
		ns.Advertise.Send(UI.AdvertisedProfession())
	elseif command == "refresh" then
		ns.RefreshEverything()
	elseif command == "clear" then
		ns.Queue.Clear()
	elseif command == "auto" then
		ns.db.ui.autoOpen = not ns.db.ui.autoOpen
		ns.Print("Open with the profession window: " .. tostring(ns.db.ui.autoOpen))
	elseif command == "diag" then
		Diagnostics()
	elseif command == "" then
		UI.ToggleBoth()
	else
		ns.Print("/craftledger [queue | profit | restock | sales | advertise | refresh | clear | auto | diag]")
	end
end
