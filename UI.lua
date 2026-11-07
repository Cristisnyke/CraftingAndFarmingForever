-- CraftLedger :: UI
-- One tabbed window anchored to the screen (Profit, Queue, Restock, Sales; the queue can sit beside Restock), the small
-- Farm list, the Queue button on the crafting page, the stale-price prompts and the slash command.

local _, ns = ...

local UI = {}
ns.UI = UI

local ROW_HEIGHT = 22
local ROW_COUNT = 40
local MAIN_WIDTH = 620
local RESTOCK_BESIDE_WIDTH = 500 -- Restock's share with the queue open beside it; the queue keeps its full width
local WINDOW_HEIGHT = 560
local MAIN_TOP = 36 -- title and tabs
local MAIN_TAB_WIDTH, MAIN_TAB_HEIGHT = 86, 26
local MAIN_TABS = {
	{ key = "profit", title = "Profit" },
	{ key = "queue", title = "Queue" },
	{ key = "restock", title = "Restock" },
	{ key = "sales", title = "Sales" },
}
local PANE_ACTIONS_TOP = 4
local PANE_LIST_TOP = 30
local TAB_WIDTH = 112
local TAB_COUNT = 16
local MINI_WIDTH = 280
local MINI_ROW_HEIGHT = 15
local MINI_MAX_ROWS = 24 -- about twelve materials, then it scrolls
local MINI_TOP = 26
local COLOR_PROFIT, COLOR_LOSS, COLOR_MUTED = "ff55dd55", "ffff6655", "ff999999"

local function Color(hex, text)
	return "|c" .. hex .. text .. "|r"
end

local windows = {}
-- Selected profession tab per window; nil is the All tab.
local selectedProfession = {}
local lastOpenProfession
UI.windows = windows
-- The one tabbed window; each tab's contents are a pane in `windows`. Created when first opened.
local main
-- Defined further down, used by code above them.
local ActiveTab, QueueBeside, UpdateTabStrip, CreateProfitPane, CreateQueuePane, CreateRestockPane, CreateSalesPane, ShowFarm
local profitCache
local profitSearch = "" -- the Profit search box's text, trimmed and lowercase
local scanNotified = false

---------------------------------------------------------------------------
-- Profit data
---------------------------------------------------------------------------

function ns.InvalidateProfit()
	profitCache = nil
	UI.Refresh("profit")
	UI.Refresh("restock")
end

-- Every recipe known on any character that makes an item, most profitable first. Results that can't be sold on the
-- AH (bind on pickup) are flagged bound and have no sale or profit, only a cost; they follow the priced ones.
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
				local sellable = recipe and recipe.o and ns.Items.CanSellOnAH(recipe.o)
				if sellable ~= nil then
					local result = ns.Planner.Profit(ctx, recipeID)
					if result then
						result.profession = recipe.p
						if not sellable then
							result.bound = true
							result.saleUnit, result.net, result.margin = nil, nil, nil
						end
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
		if a.bound ~= b.bound then return a.bound == true end
		return a.recipeID < b.recipeID
	end)
	return results
end

UI.ComputeProfit = ComputeProfit

-- Matches what the row shows (the item) or the recipe's own name, which can differ ("Transmute: Arcanite").
-- An item name still loading falls back to the recipe name; the refresh when it arrives catches the rest.
local function MatchesProfitSearch(result)
	if profitSearch == "" then return true end
	local recipe = ns.db.recipes[result.recipeID]
	local itemName, recipeName = ns.Items.Name(result.itemID), recipe and recipe.n
	return (itemName and itemName:lower():find(profitSearch, 1, true) ~= nil)
		or (recipeName and recipeName:lower():find(profitSearch, 1, true) ~= nil)
		or false
end

local function BuildProfitList()
	profitCache = profitCache or ComputeProfit()
	local selected = selectedProfession.profit
	local list = {}
	for _, result in ipairs(profitCache) do
		if (not selected or result.profession == selected) and MatchesProfitSearch(result) then
			table.insert(list, { kind = "profit", result = result })
		end
	end
	return list
end

-- The status line's text while a search is active. The list follows the opened profession, so a search that finds
-- nothing says when another tab has it rather than looking as if the item doesn't exist.
local function ProfitSearchStatus(shown)
	if shown == 1 then return "1 recipe matches your search." end
	if shown > 0 then return shown .. " recipes match your search." end
	local elsewhere = 0
	for _, result in ipairs(profitCache) do
		if MatchesProfitSearch(result) then elsewhere = elsewhere + 1 end
	end
	if elsewhere > 0 then return ("No matches on this tab, %d on the All tab."):format(elsewhere) end
	return "No recipes match your search."
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
	if priceOf then
		local subtotal, allPriced = 0, true
		for _, row in ipairs(sorted) do
			if row.price then subtotal = subtotal + row.price * row.count else allPriced = false end
		end
		title = title:format((allPriced and "" or "at least ") .. ns.Money(subtotal))
	end
	table.insert(list, { kind = "header", text = title })
	for _, row in ipairs(sorted) do table.insert(list, row) end
end

-- What's left to get yourself, grouped by how: one row for the item, one saying where to get it.
local function AddGatherRows(list, plan, withHeaders)
	local groups = {}
	for itemID, count in pairs(plan.farm) do
		local group, line = ns.Farm.Describe(itemID)
		groups[group] = groups[group] or {}
		table.insert(groups[group], { itemID = itemID, count = count, line = line })
	end
	for _, group in ipairs(ns.Farm.GROUPS) do
		local rows = groups[group.key]
		if rows then
			table.sort(rows, function(a, b) return a.itemID < b.itemID end)
			if withHeaders then table.insert(list, { kind = "header", text = group.title }) end
			for _, row in ipairs(rows) do
				table.insert(list, { kind = "item", itemID = row.itemID, count = row.count, farm = true })
				table.insert(list, { kind = "how", itemID = row.itemID, text = row.line })
			end
		end
	end
end

-- The small Farm window: only what's still needed, item on one line and how to get it under it.
local function BuildFarmList()
	local list = {}
	local plan = ns.farmPlan

	local function AddItems(items, note)
		local sorted = {}
		for itemID, count in pairs(items) do table.insert(sorted, { itemID = itemID, count = count }) end
		table.sort(sorted, function(a, b) return a.itemID < b.itemID end)
		for _, row in ipairs(sorted) do
			table.insert(list, { kind = "item", itemID = row.itemID, count = row.count })
			table.insert(list, { kind = "note", text = note })
		end
	end

	AddGatherRows(list, plan, false)
	AddItems(plan.smelt, "Smelt with Mining")
	AddItems(plan.vendor, "Buy from a vendor")
	local names = {}
	for name in pairs(plan.fetch) do table.insert(names, name) end
	table.sort(names)
	for _, name in ipairs(names) do AddItems(plan.fetch[name], "Get from " .. name) end
	if #list == 0 then
		table.insert(list, { kind = "note", text = #ns.db.queue > 0 and "All gathered. Press Back to craft." or "The queue is empty." })
	end
	return list
end

local function BuildQueueList()
	local list = {}
	local farming = ns.db.ui.farmMode
	local plan = ns.ActivePlan()
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
				table.insert(list, { kind = "header", text = farming and "Sub-crafts (make these yourself)" or "Sub-crafts (cheaper than buying)" })
			end
			table.insert(list, { kind = "auto", craft = craft })
		end
	end
	if farming then
		AddGatherRows(list, plan, true)
		AddItemRows(list, "Smelt with Mining", plan.smelt)
	end
	AddItemRows(list, "Buy at auction house: %s (red: dearer since last scan, green: cheaper)", plan.buy, "max", ns.Prices.AH)
	AddItemRows(list, "Buy from vendor: %s", plan.vendor, "at", ns.Prices.Vendor)
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
	if result.bound then
		GameTooltip:AddLine("Bind on pickup: can't be sold on the auction house.", 1, 0.6, 0.2, true)
	else
		local sale = result.saleUnit and (ns.Money(result.saleUnit * result.yield)) or "no price"
		GameTooltip:AddDoubleLine("Sells for", sale, 1, 1, 1, 1, 1, 1)
		if result.net then
			GameTooltip:AddDoubleLine("Profit after 5% AH cut", ns.Money(result.net), 1, 1, 1, 1, 1, 1)
		end
		local age = ns.Prices.ItemAgeDays(result.itemID)
		if age and age > 0 then GameTooltip:AddLine(("Last seen on the AH %d day(s) ago."):format(age), 1, 0.6, 0.2) end
	end
	local crafters = {}
	for key in pairs(ns.db.chars) do
		if ns.Recipes.Knows(key, result.recipeID) then table.insert(crafters, ns.CharLabel(key)) end
	end
	table.sort(crafters)
	if #crafters > 0 then GameTooltip:AddLine("Known by: " .. table.concat(crafters, ", "), 0.6, 0.8, 1, true) end
	if not result.bound then AddSalesLines(ns.Items.Name(result.itemID)) end
	GameTooltip:AddLine("Click to open the recipe. + queues one, Shift + queues ten.", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function RowOnEnter(row)
	local data = row.data
	if not data then return end
	if data.kind == "profit" then
		ShowProfitTooltip(row, data.result)
	elseif data.kind == "how" or data.farm then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(data.itemID)
		local _, line, details = ns.Farm.Describe(data.itemID)
		GameTooltip:AddLine(" ")
		if #details == 0 then GameTooltip:AddLine(line, 1, 1, 1, true) end
		for _, detail in ipairs(details) do GameTooltip:AddLine(detail, 1, 1, 1, true) end
		GameTooltip:Show()
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
	elseif data.kind == "post" then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(data.row.itemID)
		AddSalesLines(ns.Items.Name(data.row.itemID))
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
		if ns.totals.boundEntries[data.index] then
			GameTooltip:AddLine("Bind on pickup: can't be sold, so it isn't in the total profit.", 1, 0.6, 0.2, true)
		elseif queuedRecipe and queuedRecipe.o then
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
	if data and data.kind == "post" then
		ns.Posting.Select(data.row.itemID)
	elseif data and data.kind == "profit" and ns.Recipes.Knows(ns.CharKey(), data.result.recipeID)
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
	if data.selected then row:LockHighlight() else row:UnlockHighlight() end

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
		if result.bound then
			row.right:SetText(result.cost and ("craft cost " .. ns.Money(result.cost)) or Color(COLOR_MUTED, "no price"))
		elseif result.net then
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
		local boundCost = ns.totals.boundEntries[data.index]
		local netText = boundCost and ("cost " .. ns.Money(boundCost))
			or net and Color(net >= 0 and COLOR_PROFIT or COLOR_LOSS, ns.Money(net))
			or Color(COLOR_MUTED, "no price")
		local change = not boundCost and recipe and recipe.o and PriceChangeText(recipe.o, false)
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
	elseif data.kind == "post" then
		local item = data.row
		row.icon:SetTexture(ns.Items.Icon(item.itemID))
		row.left:SetText(ItemLabel(item.itemID))
		local held = ("%d in bags, AH %s/%d"):format(item.inBags, item.onAH and tostring(item.onAH) or "?", item.goal)
		if item.toPost > 0 then
			row.right:SetText(Color("ffffb040", "post " .. item.toPost) .. "   " .. held)
		elseif item.goal > 0 and (item.onAH or 0) < item.goal then
			row.right:SetText(Color(COLOR_MUTED, "for the queue   " .. held))
		else
			row.right:SetText(Color(COLOR_MUTED, held))
		end
	elseif data.kind == "auto" then
		local recipe = ns.db.recipes[data.craft.recipeID]
		row.icon:SetTexture(recipe and recipe.o and ns.Items.Icon(recipe.o) or 134400)
		row.left:SetText(RecipeName(data.craft.recipeID) .. " x" .. data.craft.count)
		row.right:SetText(Color(COLOR_MUTED, ns.CharLabel(data.craft.char)))
	elseif data.kind == "how" or data.kind == "note" then
		row.icon:Hide()
		row.left:SetText(Color(COLOR_MUTED, data.text))
	elseif data.kind == "item" then
		row.icon:SetTexture(ns.Items.Icon(data.itemID))
		row.left:SetText(ItemLabel(data.itemID))
		if data.priceLabel then
			local price = data.priceLabel == "max" and PriceChangeText(data.itemID, true)
				or (data.price and (data.priceLabel .. " " .. ns.Money(data.price)))
				or Color(COLOR_LOSS, "no price")
			local total = data.price and (", total " .. ns.Money(data.price * data.count)) or ""
			row.right:SetText("x" .. data.count .. ", " .. price .. total)
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
	if window.mini then visible = math.min(#window.list, MINI_MAX_ROWS) end
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

local function UpdateBanner()
	local stale = ns.Prices.IsStale()
	main.banner:SetShown(stale)
	if not stale then return end
	local atAH = AuctionHouseFrame and AuctionHouseFrame:IsShown() and true or false
	main.banner.text:SetText(ScanAgeText() .. (atAH and "" or " Scan at the auction house."))
	main.banner.text:ClearAllPoints()
	main.banner.text:SetPoint("RIGHT", main.banner, "RIGHT", atAH and -86 or 0, 0)
	main.scanButton:SetShown(atAH)
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

-- Which tab the window shows, and whether the queue is open beside Restock.
function ActiveTab()
	return ns.db.ui.tab or "profit"
end

function QueueBeside()
	return ActiveTab() == "restock" and ns.db.ui.queueBeside and true or false
end

function UpdateTabStrip()
	if not main then return end
	local active, beside = ActiveTab(), QueueBeside()
	for _, tab in ipairs(main.tabButtons) do
		local selected = tab.key == active or (beside and tab.key == "queue")
		local title = tab.title
		if tab.key == "queue" and #ns.db.queue > 0 then title = ("%s (%d)"):format(title, #ns.db.queue) end
		tab.label:SetText(Color(selected and "ffffffff" or "ffb8b8b8", title))
		local shade = selected and 0.24 or 0.11
		tab.bg:SetColorTexture(shade, shade, shade + 0.03, 1)
		tab.accent:SetShown(selected)
	end
end

function UI.Refresh(key)
	local window = windows[key]
	if not window or not window.frame:IsVisible() then return end
	if window.tabs then RenderTabs(window) end
	window.list = window.build()
	RenderRows(window)
	if main then UpdateBanner() end
	window.update(window)
end

function UI.RefreshAll()
	UI.Refresh("profit")
	UI.Refresh("queue")
	UI.Refresh("restock")
	UI.Refresh("sales")
	UI.Refresh("posting")
	UpdateTabStrip()
end

-- Queue, bags or bank changed: everything that counts stock needs redrawing.
function UI.RefreshQueue()
	UI.Refresh("queue")
	UI.Refresh("restock")
	UI.Refresh("farm")
	UI.Refresh("posting")
	UpdateTabStrip()
end

local function SavePosition(key, frame)
	local left, top = frame:GetLeft(), frame:GetTop()
	if not (left and top) then return end
	ns.db.ui.positions = ns.db.ui.positions or {}
	ns.db.ui.positions[key] = { x = left, y = top }
end

local function HeaderButton(frame, text, width, onClick)
	local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	button:SetSize(width, 22)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

-- The look and dragging shared by the main window and the Farm list.
local function MakeMovable(frame, key)
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
		SavePosition(key, self)
	end)
	frame:Hide()
end

-- The scrolling rows. footer is the room kept below them for the window's own controls.
local function CreateListArea(window, parent, left, top, footer, rowHeight)
	local container = CreateFrame("Frame", nil, parent)
	container:SetPoint("TOPLEFT", left, -top)
	container:SetPoint("BOTTOMRIGHT", -24, footer)
	container:EnableMouseWheel(true)
	container:SetScript("OnSizeChanged", function() if parent:IsVisible() then RenderRows(window) end end)
	container:SetScript("OnMouseWheel", function(_, delta)
		window.offset = math.max(0, window.offset - delta * 3)
		RenderRows(window)
	end)
	window.container = container

	for i = 1, ROW_COUNT do
		local row = CreateRow(container)
		row:SetHeight(rowHeight)
		row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
		row:SetPoint("TOPRIGHT", 0, -(i - 1) * rowHeight)
		row:Hide()
		window.rows[i] = row
	end

	local slider = CreateFrame("Slider", nil, parent)
	slider:SetPoint("TOPRIGHT", -10, -top)
	slider:SetPoint("BOTTOMRIGHT", -10, footer)
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
end

UI.HeaderButton = HeaderButton
UI.CreateListArea = CreateListArea
UI.ROW_HEIGHT = ROW_HEIGHT

-- One tab's contents inside the main window, which sizes and places it. A row of the pane's own buttons runs along
-- its top. withTabs adds the column of profession tabs on the left.
local function CreatePane(key, footerHeight, withTabs)
	local frame = CreateFrame("Frame", nil, main.frame)
	frame:Hide()
	local window = { key = key, frame = frame, list = {}, offset = 0, rows = {} }
	windows[key] = window
	CreateListArea(window, frame, withTabs and (10 + TAB_WIDTH) or 10, PANE_LIST_TOP, footerHeight, ROW_HEIGHT)

	if withTabs then
		window.tabs = {}
		for i = 1, TAB_COUNT do
			local tab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
			tab:SetSize(TAB_WIDTH - 6, 24)
			tab:SetPoint("TOPLEFT", 10, -PANE_LIST_TOP - (i - 1) * 26)
			tab:SetScript("OnClick", function(self) UI.SelectProfession(key, self.professionID) end)
			tab:Hide()
			window.tabs[i] = tab
		end
	end
	return window
end

function CreateProfitPane()
	local window = CreatePane("profit", 34, true)
	window.build = BuildProfitList

	local advertise = HeaderButton(window.frame, "Advertise", 190, function() ns.Advertise.Send(UI.AdvertisedProfession()) end)
	advertise:SetPoint("TOPLEFT", 10, -PANE_ACTIONS_TOP)
	window.advertiseButton = advertise

	local search = CreateFrame("EditBox", nil, window.frame, "InputBoxTemplate")
	search:SetSize(200, 20)
	search:SetPoint("BOTTOMRIGHT", -24, 7) -- in the footer: the stale-price banner has the right of the top row
	search:SetAutoFocus(false)
	local placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	placeholder:SetPoint("LEFT", 2, 0)
	placeholder:SetText(Color(COLOR_MUTED, "Search items (Esc clears)"))
	search:SetScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		placeholder:SetShown(text == "")
		local query = text:match("^%s*(.-)%s*$"):lower()
		if query == profitSearch then return end
		profitSearch = query
		window.offset = 0
		UI.Refresh("profit")
	end)
	search:SetScript("OnEnterPressed", search.ClearFocus)
	search:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	search:SetScript("OnHide", search.ClearFocus)
	window.searchBox = search

	local status = window.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("BOTTOMLEFT", 12, 12)
	status:SetPoint("BOTTOMRIGHT", -236, 12)
	status:SetJustifyH("LEFT")
	window.status = status

	window.update = function(self)
		local professionID = UI.AdvertisedProfession()
		local canAdvertise = ns.Advertise.Reason(professionID) == nil
		advertise:SetEnabled(canAdvertise)
		local professionName = professionID and ns.Recipes.ProfessionName(professionID)
		advertise:SetText(canAdvertise and professionName and ("Advertise " .. professionName) or "Advertise")
		if profitSearch ~= "" then
			status:SetText(ProfitSearchStatus(#self.list))
		elseif #self.list == 0 then
			status:SetText("Open a profession to record its recipes.")
		else
			status:SetText(#self.list .. " recipes known across your characters.")
		end
	end
end

-- What's left to spend, against the gold this character is carrying.
function UI.StillToBuyText()
	local plan = ns.ActivePlan()
	local cost = plan.cost
	local text = "Still to buy: " .. (plan.unpriced and "at least " or "") .. ns.Money(cost) .. "."
	if cost <= 0 and not plan.unpriced then return text end
	local money = GetMoney()
	if money >= cost then
		return text .. " " .. Color(COLOR_PROFIT, "You have " .. ns.Money(money) .. ".")
	end
	return text .. " " .. Color(COLOR_LOSS, ("You have %s, %s short."):format(ns.Money(money), ns.Money(cost - money)))
end

function CreateQueuePane()
	local window = CreatePane("queue", 128)
	window.build = BuildQueueList

	local clear = HeaderButton(window.frame, "Clear", 70, function() ns.Queue.Clear() end)
	clear:SetPoint("TOPLEFT", 10, -PANE_ACTIONS_TOP)

	local farmButton = HeaderButton(window.frame, "Farm It", 70, function() ns.ToggleFarmMode() end)
	farmButton:SetPoint("LEFT", clear, "RIGHT", 4, 0)

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
	window.totalText = total
	total:SetPoint("BOTTOMLEFT", 12, 96)
	total:SetPoint("BOTTOMRIGHT", -12, 96)
	total:SetJustifyH("LEFT")

	window.update = function()
		local totals = ns.totals
		local farming = ns.db.ui.farmMode
		farmButton:SetText(farming and "Buy It" or "Farm It")
		if farming and totals.counted > 0 then
			-- Farmed materials cost no gold, so this is what the batch leaves in your pocket.
			local keeps = totals.revenue - ns.farmPlan.cost
			total:SetText("Gold if farmed: " .. Color(keeps >= 0 and COLOR_PROFIT or COLOR_LOSS, ns.Money(keeps)))
			detail:SetText(("Sells for %s after AH cut. Materials would cost %s at AH prices.\n%s"):format(
				ns.Money(totals.revenue), ns.Money(totals.cost), UI.StillToBuyText()))
		elseif totals.counted > 0 then
			local hex = totals.net >= 0 and COLOR_PROFIT or COLOR_LOSS
			total:SetText("Total profit: " .. Color(hex, ns.Money(totals.net)))
			detail:SetText(("Sells for %s after AH cut, materials %s.\n%s"):format(
				ns.Money(totals.revenue), ns.Money(totals.cost), UI.StillToBuyText()))
		elseif totals.bound > 0 then
			total:SetText("Crafting cost: " .. ns.Money(totals.boundCost))
			detail:SetText("Bind on pickup, so there's no sale or profit.\n" .. UI.StillToBuyText())
		elseif totals.excluded > 0 then
			total:SetText("Total profit: " .. Color(COLOR_MUTED, "no price data"))
			detail:SetText(UI.StillToBuyText())
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
		if totals.excluded > 0 and (totals.counted > 0 or totals.bound > 0) then
			table.insert(notes, totals.excluded .. " queued recipe(s) have no price and aren't in the total.")
		end
		if totals.bound > 0 and totals.counted > 0 then
			table.insert(notes, ("%d bind-on-pickup craft(s) cost %s and aren't in the profit."):format(totals.bound, ns.Money(totals.boundCost)))
		end
		local shopping = ns.Shopping.status
		if shopping.error then table.insert(notes, "List update failed. See /craftledger diag.") end
		if shopping.loading > 0 then table.insert(notes, shopping.loading .. " item name(s) loading.") end
		if not ns.Stock.HasSyndicator() then table.insert(notes, "Syndicator not active: alts not counted.") end
		status:SetText(table.concat(notes, " "))
	end
end

-- The small list to leave on screen while gathering. It's the one thing that isn't a tab: the main window is too big
-- to keep up while out in the world.
local function CreateFarmWindow()
	local frame = CreateFrame("Frame", "CraftLedgerFarmWindow", UIParent, "BackdropTemplate")
	local window = { key = "farm", frame = frame, list = {}, offset = 0, rows = {}, mini = true }
	windows.farm = window
	MakeMovable(frame, "farm")
	frame:SetSize(MINI_WIDTH, WINDOW_HEIGHT)
	frame:SetBackdropColor(0.05, 0.05, 0.07, 0.8)

	local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleText:SetPoint("TOPLEFT", 12, -10)
	titleText:SetText("Farm")

	-- Closing it is leaving farm mode too, or Craft Next would keep following a list you can't see.
	window.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	window.close:SetPoint("TOPRIGHT", 0, 0)
	window.close:SetScript("OnClick", function()
		ns.db.ui.farmMode = nil
		frame:Hide()
		UI.RefreshQueue()
	end)

	local back = HeaderButton(frame, "Back", 56, function() ns.ToggleFarmMode() end)
	back:SetHeight(20)
	back:SetPoint("RIGHT", window.close, "LEFT", -2, 0)

	CreateListArea(window, frame, 10, MINI_TOP, 6, MINI_ROW_HEIGHT)
	for _, row in ipairs(window.rows) do row.icon:SetSize(14, 14) end

	window.build = function()
		local list = BuildFarmList()
		frame:SetHeight(MINI_TOP + math.min(#list, MINI_MAX_ROWS) * MINI_ROW_HEIGHT + 8)
		return list
	end
	window.update = function() end
end

function ShowFarm()
	if not windows.farm then CreateFarmWindow() end
	local frame = windows.farm.frame
	if not frame:IsShown() then
		local saved = ns.db.ui.positions and ns.db.ui.positions.farm
		frame:ClearAllPoints()
		if saved then
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
		else
			frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120)
		end
		frame:Show()
	end
	UI.Refresh("farm")
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

function CreateRestockPane()
	local window = CreatePane("restock", 96, true)
	window.build = BuildRestockList

	local showQueue = HeaderButton(window.frame, "Show Queue", 100, function() UI.ToggleQueueBeside() end)
	showQueue:SetPoint("TOPLEFT", 10, -PANE_ACTIONS_TOP)
	showQueue:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Queue beside Restock")
		GameTooltip:AddLine("Keeps the queue on screen while you work through your goals.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	showQueue:SetScript("OnLeave", GameTooltip_Hide)

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
		showQueue:SetText(ns.db.ui.queueBeside and "Hide Queue" or "Show Queue")
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
		if toPost > 0 then table.insert(notes, 1, toPost .. " item(s) you hold are ready to post, from the auction house's Restocking tab.") end
		if #self.list == 0 then notes = { "No profitable items yet. Open your professions and scan the AH." } end
		status:SetText(table.concat(notes, " "))
	end
end

function CreateSalesPane()
	local window = CreatePane("sales", 76)
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

---------------------------------------------------------------------------
-- The main window
---------------------------------------------------------------------------

local function GetPane(key)
	if not windows[key] then
		if key == "profit" then
			CreateProfitPane()
		elseif key == "queue" then
			CreateQueuePane()
		elseif key == "restock" then
			CreateRestockPane()
		else
			CreateSalesPane()
		end
	end
	return windows[key]
end

-- Only ever placed against the screen, never another window: Blizzard slides its panels around as others open, and
-- anything anchored to one moves with it. The left edge stays put; it only shifts when a wider view wouldn't fit.
local function PlaceMain()
	local frame = main.frame
	local saved = ns.db.ui.positions and ns.db.ui.positions.main
	local x = saved and saved.x or (UIParent:GetWidth() - MAIN_WIDTH - 40)
	local y = saved and saved.y or (UIParent:GetHeight() - 120)
	x = math.max(0, math.min(x, UIParent:GetWidth() - frame:GetWidth()))
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

local function PlacePane(pane, left, right)
	pane.frame:ClearAllPoints()
	pane.frame:SetPoint("TOPLEFT", main.frame, "TOPLEFT", left, -MAIN_TOP)
	if right then
		pane.frame:SetPoint("BOTTOMRIGHT", main.frame, "BOTTOMLEFT", right, 0)
	else
		pane.frame:SetPoint("BOTTOMRIGHT", main.frame, "BOTTOMRIGHT", 0, 0)
	end
end

-- Shows the selected tab's pane, with the queue beside Restock when asked for, and redraws what's showing.
local function Layout()
	local active, beside = ActiveTab(), QueueBeside()
	main.frame:SetWidth(beside and (RESTOCK_BESIDE_WIDTH + MAIN_WIDTH) or MAIN_WIDTH)
	PlaceMain()
	main.divider:SetShown(beside)
	for _, tab in ipairs(MAIN_TABS) do
		local key = tab.key
		if key == active or (beside and key == "queue") then
			local pane = GetPane(key)
			if not beside then
				PlacePane(pane, 0)
			elseif key == "restock" then
				PlacePane(pane, 0, RESTOCK_BESIDE_WIDTH)
			else
				PlacePane(pane, RESTOCK_BESIDE_WIDTH)
			end
			pane.frame:Show()
			UI.Refresh(key)
		elseif windows[key] then
			windows[key].frame:Hide()
		end
	end
	UpdateTabStrip()
end

local function CreateMain()
	local frame = CreateFrame("Frame", "CraftLedgerWindow", UIParent, "BackdropTemplate")
	main = { frame = frame, tabButtons = {} }
	UI.main = main
	MakeMovable(frame, "main")
	frame:SetSize(MAIN_WIDTH, WINDOW_HEIGHT)
	table.insert(UISpecialFrames, "CraftLedgerWindow") -- Escape closes it, like the game's own windows

	local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleText:SetPoint("TOPLEFT", 12, -14)
	titleText:SetText("CraftLedger")

	for index, info in ipairs(MAIN_TABS) do
		local tab = CreateFrame("Button", nil, frame)
		tab:SetSize(MAIN_TAB_WIDTH, MAIN_TAB_HEIGHT)
		tab:SetPoint("TOPLEFT", 96 + (index - 1) * (MAIN_TAB_WIDTH + 2), -7)
		tab:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		tab:SetScript("OnClick", function() UI.Select(info.key) end)
		tab.key, tab.title = info.key, info.title
		tab.bg = tab:CreateTexture(nil, "BACKGROUND")
		tab.bg:SetAllPoints()
		tab.accent = tab:CreateTexture(nil, "ARTWORK")
		tab.accent:SetColorTexture(1, 0.82, 0, 1)
		tab.accent:SetHeight(2)
		tab.accent:SetPoint("BOTTOMLEFT")
		tab.accent:SetPoint("BOTTOMRIGHT")
		tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		tab.label:SetPoint("CENTER")
		main.tabButtons[index] = tab
	end

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 0, 0)
	close:SetScript("OnClick", function() frame:Hide() end)

	local refresh = HeaderButton(frame, "Refresh", 70, function() ns.RefreshEverything() end)
	refresh:SetHeight(20)
	refresh:SetPoint("RIGHT", close, "LEFT", -2, 0)

	local rule = frame:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(0.5, 0.5, 0.5, 0.5)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 6, -MAIN_TOP + 1)
	rule:SetPoint("TOPRIGHT", -6, -MAIN_TOP + 1)

	main.divider = frame:CreateTexture(nil, "ARTWORK")
	main.divider:SetColorTexture(0.5, 0.5, 0.5, 0.5)
	main.divider:SetWidth(1)
	main.divider:SetPoint("TOPLEFT", RESTOCK_BESIDE_WIDTH, -MAIN_TOP)
	main.divider:SetPoint("BOTTOMLEFT", RESTOCK_BESIDE_WIDTH, 6)

	-- In the row the panes keep their buttons in, on the right where none of them have any.
	local banner = CreateFrame("Frame", nil, frame)
	banner:SetPoint("TOPRIGHT", -12, -MAIN_TOP - 2)
	banner:SetSize(360, 24)
	banner:Hide()
	banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	banner.text:SetTextColor(1, 0.6, 0.2)
	main.banner = banner
	main.scanButton = HeaderButton(banner, "Scan now", 80, function() ns.Prices.StartScan() end)
	main.scanButton:SetPoint("RIGHT")

	frame:SetScript("OnShow", Layout)
end

function UI.IsOpen()
	return main ~= nil and main.frame:IsShown()
end

function UI.Hide()
	if main then main.frame:Hide() end
end

function UI.Select(key)
	ns.db.ui.tab = key
	if UI.IsOpen() then Layout() end
end

function UI.ToggleQueueBeside()
	ns.db.ui.queueBeside = not ns.db.ui.queueBeside
	Layout()
end

-- Opens the window on that tab. Already open and already showing it, nothing moves.
-- withProfession: the window closes again with the profession window. Opened by command, it stays until closed.
function UI.Show(key, withProfession)
	if key == "farm" then
		ShowFarm()
		return
	end
	if not main then CreateMain() end
	if not UI.IsOpen() then
		ns.db.ui.tab = key
		main.withProfession = withProfession
		main.frame:Show()
	elseif key == ActiveTab() or (key == "queue" and QueueBeside()) then
		UI.Refresh(key)
	else
		UI.Select(key)
	end
end

function UI.Toggle(key)
	if UI.IsOpen() and key == ActiveTab() then
		UI.Hide()
	else
		UI.Show(key, ProfessionsFrame and ProfessionsFrame:IsShown())
	end
end

-- The Farm list stays up on its own, so this leaves it alone.
function UI.ToggleMain()
	if UI.IsOpen() then
		UI.Hide()
	else
		UI.Show(ActiveTab())
	end
end

-- Farm It swaps the main window for the small list, and Back swaps them again.
function UI.FarmModeChanged()
	if ns.db.ui.farmMode then
		UI.Hide()
		UI.Show("farm")
	else
		if windows.farm then windows.farm.frame:Hide() end
		UI.Show("queue")
	end
	UI.RefreshQueue()
end

ns.On("ZONE_CHANGED_NEW_AREA", function() UI.RefreshQueue() end)

-- Still farming from last session: bring the list back. Saved data can arrive just after login.
ns.On("PLAYER_LOGIN", function()
	ns.Debounce("farmlist", 1, function()
		if ns.db.ui.farmMode then UI.Show("farm") end
	end)
end)

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
	if ns.db.ui.autoOpen and not UI.IsOpen() then UI.Show(ActiveTab(), true) end
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
				-- Already open: stay on the tab being used, and the Queue tab's count shows it worked.
				if not UI.IsOpen() then UI.Show("queue", true) end
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
		-- Walking from the profession window to the auction house keeps it up, for the queue and the shopping list.
		local atAH = AuctionHouseFrame and AuctionHouseFrame:IsShown()
		if main and main.withProfession and not atAH then UI.Hide() end
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
local lastAdvertised = {} -- by destination

-- Where an ad can go. The slash command is for the chat box fallback; Trade's depends on its channel number.
local DESTINATIONS = {
	{ key = "TRADE", label = "Trade", chatType = "CHANNEL" },
	{ key = "GUILD", label = "Guild", chatType = "GUILD", slash = "/g" },
	{ key = "SAY", label = "Say", chatType = "SAY", slash = "/s" },
	{ key = "YELL", label = "Yell", chatType = "YELL", slash = "/y" },
}

local function CurrentDestination()
	local selected = ns.db.ui.adDestination
	for _, destination in ipairs(DESTINATIONS) do
		if destination.key == selected then return destination end
	end
	return DESTINATIONS[1]
end

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
	return math.max(0, AD_COOLDOWN_SECONDS - (time() - (lastAdvertised[destination.key] or 0)))
end

-- The chat command for an ad, or nil and the reason there can't be one right now.
local function AdCommand(professionID, destination)
	local reason = Advertise.Reason(professionID)
	if reason then return nil, reason end
	local available, channel, why = DestinationState(destination)
	if not available then return nil, why end
	local char = ns.db.chars[ns.CharKey()]
	local link = char.links and char.links[professionID]
	local message = AD_TEXT:format(link or ns.Recipes.ProfessionName(professionID) or "Crafting")
	return (destination.slash or ("/" .. tostring(channel))) .. " " .. message, nil, link ~= nil
end

local NO_LINK_NOTE = "No profession link saved yet, so this uses its name. Open the profession once to get the link."

-- For the Profit window button and the slash command. The game blocks add-ons from sending chat, and only the secure
-- buttons beside the chat window can post on one click, so this fills in the chat box for Enter to send.
function Advertise.Send(professionID)
	local destination = CurrentDestination()
	local command, why, hasLink = AdCommand(professionID, destination)
	if not command then
		ns.Print(why)
		return
	end
	local wait = CooldownLeft(destination)
	if wait > 0 then
		ns.Print(("Please wait %d more seconds, so %s doesn't get spammed."):format(wait, destination.label))
		return
	end
	if not hasLink then ns.Print(NO_LINK_NOTE) end
	lastAdvertised[destination.key] = time()
	Advertise.UpdateButtons()
	OpenChatWith(command)
end

-- Beside the chat frame: one small box that opens a destination picker and a button per crafting profession of this
-- character. They work with no profession window open, using the link saved when the profession was last opened, and
-- show whenever the chosen destination can take a post. Posting closes them again.
local AD_BOX_WIDTH, AD_BOX_HEIGHT = 26, 20
local AD_BUTTON_WIDTH, AD_BUTTON_HEIGHT = 130, 20
local adButtons = {}
Advertise.buttons = adButtons
local cooldownTimerRunning = false
local adBox, destinationButton, destinationMenu
local adOpen = false

local function CreateDestinationPicker()
	adBox = CreateFrame("Button", "CraftLedgerAdBox", UIParent, "UIPanelButtonTemplate")
	adBox:SetSize(AD_BOX_WIDTH, AD_BOX_HEIGHT)
	-- Past the chat frame's own scroll bar.
	adBox:SetPoint("BOTTOMLEFT", ChatFrame1, "BOTTOMRIGHT", 28, 0)
	adBox:SetText("Ad")
	adBox:SetScript("OnClick", function()
		-- The profession buttons are secure, so they can't appear or hide during combat.
		if InCombatLockdown() then
			ns.Print("Advertising buttons can't open during combat.")
			return
		end
		adOpen = not adOpen
		Advertise.UpdateButtons()
	end)
	Advertise.box = adBox

	destinationButton = CreateFrame("Button", "CraftLedgerAdDestination", UIParent, "UIPanelButtonTemplate")
	destinationButton:SetSize(AD_BUTTON_WIDTH, AD_BUTTON_HEIGHT)
	destinationButton:SetPoint("BOTTOMLEFT", adBox, "TOPLEFT", 0, 2)
	destinationButton:Hide()
	Advertise.destinationButton = destinationButton

	destinationMenu = CreateFrame("Frame", nil, destinationButton)
	destinationMenu:SetSize(60, #DESTINATIONS * AD_BUTTON_HEIGHT)
	destinationMenu:SetPoint("BOTTOMLEFT", destinationButton, "BOTTOMRIGHT", 2, 0)
	destinationMenu:Hide()
	Advertise.destinationMenu = destinationMenu
	destinationMenu.options = {}
	for index, destination in ipairs(DESTINATIONS) do
		local option = CreateFrame("Button", nil, destinationMenu, "UIPanelButtonTemplate")
		option:SetSize(60, AD_BUTTON_HEIGHT)
		option:SetPoint("BOTTOMLEFT", 0, (index - 1) * AD_BUTTON_HEIGHT)
		option:SetText(destination.label)
		option:SetScript("OnClick", function()
			ns.db.ui.adDestination = destination.key
			destinationMenu:Hide()
			Advertise.UpdateButtons()
			ns.UI.Refresh("profit")
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
		button = CreateFrame("Button", "CraftLedgerAdvertiseButton" .. index, UIParent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
		button:SetSize(AD_BUTTON_WIDTH, AD_BUTTON_HEIGHT)
		button:RegisterForClicks("AnyUp", "AnyDown")
		button:SetAttribute("type", "macro")
		button:SetScript("PostClick", function(self, _, down)
			-- With both directions registered, the macro only runs on the one matching this setting.
			if (down and true or false) ~= (GetCVarBool("ActionButtonUseKeyDown") and true or false) then return end
			if not self.hasLink then ns.Print(NO_LINK_NOTE) end
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
	local top = adBox and adBox:GetTop() and (adBox:GetTop() + AD_BUTTON_HEIGHT + 2)
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
				button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, top + 2 + (shown - 1) * (AD_BUTTON_HEIGHT + 2))
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

ns.On("PLAYER_MONEY", UI.RefreshQueue)

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
	Add(("queue profit: %s from %d entries, %d without a price, %d bind on pickup"):format(ns.Money(ns.totals.net), ns.totals.counted, ns.totals.excluded, ns.totals.bound))
	local openKey = ns.Recipes.OpenProfession()
	Add("open profession: " .. tostring(openKey) .. ", recipes in window: " .. CountKeys(ns.Recipes.OpenRecipes()))
	Add("Queue button on crafting page: " .. tostring(queueButton ~= nil))
	Add(("auction durations: %dh, %dh, %dh; client text: %s"):format(ns.Sales.DurationHours(1), ns.Sales.DurationHours(2),
		ns.Sales.DurationHours(3), tostring(_G.AUCTION_DURATION_ONE)))
	Add("Restocking tab created: " .. tostring(windows.posting ~= nil))
	Add("profession link API: " .. tostring(C_TradeSkillUI.GetTradeSkillListLink ~= nil)
		.. ", posting to: " .. tostring(ns.db.ui.adDestination or "TRADE"))
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
		UI.ToggleMain()
	else
		ns.Print("/craftledger [profit | queue | restock | sales | advertise | refresh | clear | auto | diag]")
	end
end
