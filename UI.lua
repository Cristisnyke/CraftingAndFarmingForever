-- Crafting and Farming Forever :: UI
-- One tabbed window anchored to the screen (Profit, Queue, Restock, Sales, Changelog; the queue can sit beside Restock), the small
-- Next step bar, the Queue button on the crafting page, the stale-price prompts and the slash command.

local _, ns = ...

local UI = {}
ns.UI = UI

local ROW_HEIGHT = 22
local ROW_COUNT = 48 -- enough for the tallest window
local MAIN_WIDTH = 680 -- default and narrowest width: five tabs beside Refresh
local BESIDE_WIDTH = 1240 -- default width with the queue beside Restock
local BESIDE_MIN_WIDTH = 1180
local RESTOCK_SHARE = 0.45 -- Restock's share of the width with the queue beside it
local WINDOW_HEIGHT = 560
local MIN_HEIGHT, MAX_HEIGHT = 460, 1100
local MAIN_TOP = 36 -- title and tabs
local MAIN_TAB_WIDTH, MAIN_TAB_HEIGHT = 82, 26
local LOGO_TEXTURE = "Interface\\AddOns\\CraftingAndFarmingForever\\Media\\Logo"
local MAIN_TABS = {
	{ key = "profit", title = "Profit" },
	{ key = "queue", title = "Queue" },
	{ key = "restock", title = "Restock" },
	{ key = "sales", title = "Sales" },
	{ key = "changelog", title = "Changelog" },
}
local PANE_ACTIONS_TOP = 4
local PANE_LIST_TOP = 30
local TAB_WIDTH = 112
local TAB_COUNT = 16
local MINI_ROW_HEIGHT = 15
local MINI_TOP = 26
local COLOR_PROFIT, COLOR_LOSS, COLOR_MUTED = "ff55dd55", "ffff6655", "ff999999"

local function Color(hex, text)
	return "|c" .. hex .. text .. "|r"
end

local COLOR_WARN = "ffff9933"

local function ScanAgeText()
	local age = ns.Prices.ScanAge()
	if not age then return "No auction house scan yet." end
	return ("Prices are %d hours old."):format(math.floor(age / 3600))
end
UI.ScanAgeText = ScanAgeText

local windows = {}
-- Selected profession tab per window; nil is the All tab.
local selectedProfession = {}
local lastOpenProfession
UI.windows = windows
-- The one tabbed window; each tab's contents are a pane in `windows`. Created when first opened.
local main
-- Defined further down, used by code above them.
local ActiveTab, QueueBeside, UpdateTabStrip, CreateProfitPane, CreateQueuePane, CreateRestockPane, CreateSalesPane
local UpdateNextStep
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
	local itemName, recipeName = result.itemID and ns.Items.Name(result.itemID), recipe and recipe.n
	return (itemName and itemName:lower():find(profitSearch, 1, true) ~= nil)
		or (recipeName and recipeName:lower():find(profitSearch, 1, true) ~= nil)
		or false
end

-- Sorting, per mode of the Profit tab: a column and a direction, saved. Clicking a heading picks its column in its
-- natural direction; clicking it again reverses. Profit: names A to Z, the rest highest first, by profit at first.
-- Skill up: names A to Z, chance highest first, costs lowest first, by cost per skill point at first.
local SORTS = {
	profit = { key = "profitSort", asc = "profitSortAsc", default = "profit",
		ascending = { name = true, chance = false, profit = false } },
	skill = { key = "skillSort", asc = "skillSortAsc", default = "profit",
		ascending = { name = true, chance = false, cost = true, profit = true } },
}
UI.SORTS = SORTS

function UI.ListSort(mode)
	local sort = SORTS[mode]
	local key = ns.db.ui[sort.key]
	if sort.ascending[key] == nil then key = sort.default end
	local ascending = ns.db.ui[sort.asc]
	if ascending == nil or ns.db.ui[sort.key] ~= key then ascending = sort.ascending[key] end
	return key, ascending and true or false
end

function UI.SortList(mode, key)
	local sort = SORTS[mode]
	local current, ascending = UI.ListSort(mode)
	if key == current then
		ns.db.ui[sort.key], ns.db.ui[sort.asc] = key, not ascending
	else
		ns.db.ui[sort.key], ns.db.ui[sort.asc] = key, sort.ascending[key]
	end
	if windows.profit then windows.profit.offset = 0 end
	UI.Refresh("profit")
end

function UI.ProfitSort() return UI.ListSort("profit") end
function UI.SortProfit(key) UI.SortList("profit", key) end

-- What a recipe sorts by. Nil (no price, no sales data, name still loading) always goes last.
local function SortValue(result, key)
	local name = ns.Items.Name(result.itemID)
	if key == "name" then return name and name:lower() end
	if key == "chance" then return not result.bound and name and ns.Sales.Chance(name) or nil end
	return result.net
end

-- Levelling mode: recipe colours as the game shows them, and what each colour means here.
local SKILL_COLORS = { [0] = "ffff8040", [1] = "ffffff00", [2] = "ff40bf40" }
local SKILL_CHANCE_TEXT = { [0] = "100%", [1] = "~50%", [2] = "~25%" }
local SKILL_NAMES = { [0] = "Orange", [1] = "Yellow", [2] = "Green" }

-- The profession levelling looks at: the selected tab, or on All the one that's open.
function UI.SkillProfession()
	return selectedProfession.profit or ns.Recipes.OpenProfession()
end

-- Recipes this character knows in that profession that can still give skill, cheapest per skill point first.
-- Colours are per character and only known from the last time the profession was open on it.
local function BuildSkillList()
	local professionID = UI.SkillProfession()
	local list = { skill = true, trivial = 0 }
	if not professionID then
		table.insert(list, { kind = "note", text = "Pick a profession on the left, or open one, to see its cheapest skill points." })
		return list
	end
	local char = ns.db.chars[ns.CharKey()]
	local entries, recorded = {}, 0
	for recipeID, info in pairs(char and char.skillUps or {}) do
		local recipe = ns.db.recipes[recipeID]
		if recipe and recipe.p == professionID and char.recipes[recipeID] then
			recorded = recorded + 1
			if info.d == 3 then
				list.trivial = list.trivial + 1
			elseif MatchesProfitSearch({ recipeID = recipeID, itemID = recipe.o }) then
				table.insert(entries, { recipeID = recipeID, difficulty = info.d, skillUps = info.n })
			end
		end
	end
	local rows = ns.Planner.SkillUpRows(ns.NewContext(), entries)
	-- The planner's order (cheapest per skill point) is the default and the tie-break.
	local key, ascending = UI.ListSort("skill")
	if key ~= "profit" or not ascending then
		local order, values = {}, {}
		for index, row in ipairs(rows) do
			local recipe = ns.db.recipes[row.recipeID]
			order[row] = index
			values[row] = key == "name" and recipe and recipe.n and recipe.n:lower()
				or key == "chance" and row.chance
				or key == "cost" and row.cost
				or key == "profit" and row.perPoint
				or nil
		end
		table.sort(rows, function(a, b)
			local va, vb = values[a], values[b]
			if va ~= nil and vb ~= nil and va ~= vb then
				if ascending then return va < vb end
				return va > vb
			end
			if (va == nil) ~= (vb == nil) then return va ~= nil end
			return order[a] < order[b]
		end)
	end
	if #rows == 0 then
		local text = recorded == 0 and "Open this profession on this character to read its recipe colours."
			or list.trivial == recorded and "Every recipe is grey: none can give a skill point. Learn new ones from a trainer."
			or "No recipes match your search."
		table.insert(list, { kind = "note", text = text })
		return list
	end
	table.insert(list, { kind = "header", text = "Recipe", columns = "skill" })
	for _, row in ipairs(rows) do table.insert(list, { kind = "skill", row = row }) end
	return list
end

local function BuildProfitList()
	if ns.db.ui.profitMode == "skill" then return BuildSkillList() end
	profitCache = profitCache or ComputeProfit()
	local selected = selectedProfession.profit
	local hideUnprofitable = ns.db.ui.hideUnprofitable
	local results, order, values = {}, {}, {}
	local key, ascending = UI.ProfitSort()
	local hidden = 0
	for index, result in ipairs(profitCache) do
		if (not selected or result.profession == selected) and MatchesProfitSearch(result) then
			-- Unprofitable: no profit at all, so a break-even recipe goes too. Unpriced and bind-on-pickup ones stay.
			if hideUnprofitable and result.net and result.net <= 0 then
				hidden = hidden + 1
			else
				table.insert(results, result)
				order[result], values[result] = index, SortValue(result, key)
			end
		end
	end
	-- The cache is already highest profit first, so that order is the tie-break and the default.
	if key ~= "profit" or ascending then
		table.sort(results, function(a, b)
			local va, vb = values[a], values[b]
			if va ~= nil and vb ~= nil and va ~= vb then
				if ascending then return va < vb end
				return va > vb
			end
			if (va == nil) ~= (vb == nil) then return va ~= nil end
			return order[a] < order[b]
		end)
	end
	local list = { hiddenUnprofitable = hidden }
	for _, result in ipairs(results) do table.insert(list, { kind = "profit", result = result }) end
	if #list > 0 then table.insert(list, 1, { kind = "header", text = "Recipe", columns = "profit" }) end
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

-- What's left to get yourself, grouped by how, each group a numbered step: one row for the item, one saying where to
-- get it.
local function AddGatherRows(list, plan, step)
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
			table.insert(list, { kind = "header", text = step() .. group.title, gather = true })
			for _, row in ipairs(rows) do
				table.insert(list, { kind = "item", itemID = row.itemID, count = row.count, farm = true })
				table.insert(list, { kind = "how", itemID = row.itemID, text = row.line })
			end
		end
	end
end

-- Where to buy, under the auction house step and in chat when the auction house opens.
UI.SHOPPING_HOW = {
	"At the auction house, open the Shopping tab",
	"(Auctionator) and click the list",
	'"' .. ns.LIST_NAME .. '".',
}

-- The Queue tab is a to-do list in the order you'd work through it, numbered: fetch from alts, the bank, the auction
-- house and the mailbox beside it, vendors, gather and smelt, sub-crafts, and only then the queued crafts themselves, so you reach the crafting station with
-- everything on you.
local function BuildQueueList()
	local list = {}
	local farming = ns.db.ui.farmMode
	local plan = ns.ActivePlan()
	local number = 0
	local function Step()
		number = number + 1
		return number .. ". "
	end

	local function Section(title, items, ...)
		if not items or next(items) == nil then return end
		AddItemRows(list, Step() .. title, items, ...)
	end

	local names = {}
	for name in pairs(plan.fetch) do table.insert(names, name) end
	table.sort(names)
	for _, name in ipairs(names) do Section("Get from " .. name .. " (log in there and mail them over)", plan.fetch[name]) end
	Section("Take from your bank", plan.bank)
	local beforeBuy = #list
	Section("Buy at auction house: %s (red: dearer since last scan, green: cheaper)", plan.buy, "max", ns.Prices.AH)
	-- New players don't know where the list is: say it under the heading, short enough for the Next step bar.
	if #list > beforeBuy then
		for offset, text in ipairs(UI.SHOPPING_HOW) do
			table.insert(list, beforeBuy + 1 + offset, { kind = "tip", text = text })
		end
	end
	-- Right after the auction house, which always has a mailbox beside it; not before, as purchases land there one by
	-- one and collecting halfway through would send you away with things still to buy.
	Section("Collect from your mailbox", plan.mail)
	Section("Buy from vendor: %s", plan.vendor, "at", ns.Prices.Vendor)
	if farming then
		AddGatherRows(list, plan, Step)
		Section("Smelt with Mining", plan.smelt)
	end
	local autoHeader = false
	for _, craft in ipairs(plan.crafts) do
		if (craft.subCount or 0) > 0 then
			if not autoHeader then
				autoHeader = true
				table.insert(list, { kind = "header", crafting = true,
					text = Step() .. (farming and "Sub-crafts (make these yourself)" or "Sub-crafts (cheaper than buying)") })
			end
			table.insert(list, { kind = "auto", craft = craft })
		end
	end
	-- Your own queued crafts, then one step per other character: log in there, where their list continues with
	-- what they need to get and buy.
	if #ns.db.queue > 0 then
		local ctx = ns.NewContext()
		local me = ns.CharKey()
		local mine, others, order = {}, {}, {}
		for index, entry in ipairs(ns.db.queue) do
			local row = { kind = "queue", index = index, entry = entry, matCost = ns.Planner.RecipeCost(ctx, entry.recipeID) }
			local crafter = ns.Recipes.Crafter(entry.recipeID, entry.char)
			if crafter == me then
				table.insert(mine, row)
			else
				if not others[crafter] then
					others[crafter] = {}
					table.insert(order, crafter)
				end
				table.insert(others[crafter], row)
			end
		end
		local function NumberedStep()
			return (number > 0 or #order > 0) and Step() or ""
		end
		if #mine > 0 then
			table.insert(list, { kind = "header", text = NumberedStep() .. "Craft your queue", columns = "queue", crafting = true })
			for _, row in ipairs(mine) do table.insert(list, row) end
		end
		table.sort(order, function(a, b) return ns.CharLabel(a) < ns.CharLabel(b) end)
		for _, crafter in ipairs(order) do
			table.insert(list, { kind = "header", columns = "queue", elsewhere = crafter,
				text = Step() .. "Log in to " .. ns.CharLabel(crafter) .. " (their materials are bought and made there)" })
			for _, row in ipairs(others[crafter]) do table.insert(list, row) end
		end
	end
	if #list == 0 then
		table.insert(list, { kind = "note", text = "The queue is empty." })
		table.insert(list, { kind = "note", text = "Press + on the Profit tab, or Queue on a recipe's page (under the favourite star)." })
	end
	return list
end

-- "3. Buy at auction house: 1g (red: dearer ...)" becomes "Buy at auction house: 1g".
local function ShortStepTitle(text)
	local short = text:gsub("^%d+%. ", ""):gsub("%s*%b()$", "")
	return short
end

-- The Next step bar: the first step of the Queue tab's to-do list, cut down to fit a small window. Every header in
-- that list is a step, except that the gathering groups (Mine, Pick herbs, ...) count as one: you gather whatever
-- you come across, so they're shown together, each under its own heading. Returns the step's header, how many steps
-- there are, and its rows: items without prices, queue entries as plain crafts.
local function BuildNextStep()
	local current, steps, rows = nil, 0, {}
	local lastGather = false
	for _, data in ipairs(BuildQueueList()) do
		if data.kind == "header" then
			if not (data.gather and lastGather) then steps = steps + 1 end
			lastGather = data.gather or false
			if steps == 1 then
				if not current then
					current = data
				else
					table.insert(rows, { kind = "header", text = ShortStepTitle(data.text) })
				end
			end
		elseif steps == 1 then
			if data.kind == "queue" then
				table.insert(rows, { kind = "next", recipeID = data.entry.recipeID, count = data.entry.qty, char = data.entry.char })
			elseif data.kind == "item" then
				local copy = {}
				for key, value in pairs(data) do copy[key] = value end
				copy.priceLabel, copy.price = nil, nil
				table.insert(rows, copy)
			else
				table.insert(rows, data)
			end
		end
	end
	return current, steps, rows
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
	if #list > 0 then table.insert(list, 1, { kind = "header", text = "Item", columns = "restock" }) end
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
	if chance >= 0.5 then return Color("ffffffff", percent) end
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
		GameTooltip:AddLine(("Based on %s. More data makes this more accurate."):format(ns.Plural(samples, "unit", "units")),
			0.6, 0.6, 0.6, true)
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

-- Starts a tooltip with the game's own item tooltip (stats, binding, other add-ons' lines), then a gap for ours.
-- The recipe name is added only when it differs from the item's, e.g. an enchant whose result is a scroll.
local function StartItemTooltip(owner, itemID, recipeID)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if not itemID then
		GameTooltip:SetText(recipeID and RecipeName(recipeID) or "?")
		return
	end
	GameTooltip:SetItemByID(itemID)
	GameTooltip:AddLine(" ")
	if recipeID then
		local recipeName = RecipeName(recipeID)
		if recipeName ~= ns.Items.Name(itemID) then GameTooltip:AddLine("Recipe: " .. recipeName, 1, 0.82, 0) end
	end
end

-- Materials with their cost. An auction house price that's a day or more old says so, in orange: a recent scan can
-- still have missed an item that had no listings at the time.
local function AddPartLines(parts)
	for _, part in ipairs(parts or {}) do
		local name = ns.Items.Name(part.itemID) or "Loading..."
		local value = part.unit and (ns.Money(part.unit * part.qty) .. " (" .. (KIND_LABEL[part.kind] or "?") .. ")") or "no price"
		local age = part.kind == "ah" and ns.Prices.ItemAgeDays(part.itemID)
		if age and age > 0 then value = value .. Color(COLOR_WARN, (" %dd old"):format(age)) end
		GameTooltip:AddDoubleLine(part.qty .. " x " .. name, value, 0.85, 0.85, 0.85, 1, 1, 1)
	end
end

local function ShowSkillTooltip(row, item)
	StartItemTooltip(row, item.itemID, item.recipeID)
	AddPartLines(item.parts)
	GameTooltip:AddLine(" ")
	local hex = SKILL_COLORS[item.difficulty]
	GameTooltip:AddDoubleLine("Colour", Color(hex, SKILL_NAMES[item.difficulty]), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Chance of a skill point", Color(hex, SKILL_CHANCE_TEXT[item.difficulty]), 1, 1, 1, 1, 1, 1)
	if item.points > 1 then GameTooltip:AddDoubleLine("Skill points per craft", tostring(item.points), 1, 1, 1, 1, 1, 1) end
	GameTooltip:AddDoubleLine("Materials per craft", item.cost and ns.Money(item.cost) or "no price", 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Expected cost per skill point", item.perPoint and ns.Money(item.perPoint) or "no price",
		1, 1, 1, 1, 1, 1)
	GameTooltip:AddLine("Orange always gives a skill point. Yellow and green are estimates: yellow about half the time, "
		.. "green less often, and both get less likely as your skill rises.", 0.6, 0.6, 0.6, true)
	GameTooltip:AddLine("Click to open the recipe. + queues one, Shift + queues ten, right-click + to type an amount.",
		0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function ShowProfitTooltip(row, result)
	StartItemTooltip(row, result.itemID, result.recipeID)
	AddPartLines(result.parts)
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
		if age and age > 0 then GameTooltip:AddLine(("Last seen on the AH %s ago."):format(ns.Plural(age, "day", "days")), 1, 0.6, 0.2) end
	end
	local crafters = {}
	for key in pairs(ns.db.chars) do
		if ns.Recipes.Knows(key, result.recipeID) then table.insert(crafters, ns.CharLabel(key)) end
	end
	table.sort(crafters)
	if #crafters > 0 then GameTooltip:AddLine("Known by: " .. table.concat(crafters, ", "), 0.6, 0.8, 1, true) end
	if not result.bound then AddSalesLines(ns.Items.Name(result.itemID)) end
	GameTooltip:AddLine("Click to open the recipe. + queues one, Shift + queues ten, right-click + to type an amount.",
		0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local COLUMN_TIPS = {
	profit = {
		"Sells: the chance one sells within 24 hours, from your sales history. Grey with ~ is a rough guess from under "
			.. "5 units; orange is under 50%, red under 20%.",
		"Profit: for one craft, after the 5% auction house cut, with materials by the cheapest path.",
		"Click Recipe, Sells or Profit to sort by it; click again to reverse.",
	},
	skill = {
		"Recipes are coloured as in the profession window. Grey ones can't give skill and aren't listed.",
		"Chance: of a skill point per craft. Orange always; yellow about half the time and green less often "
			.. "(estimates).",
		"Craft: materials for one craft at market prices, by the cheapest path.",
		"Per point: what a skill point is expected to cost with that recipe. The list starts cheapest first.",
		"Click Recipe, Chance, Craft or Per point to sort by it; click again to reverse.",
	},
	restock = {
		"Sells: the chance one sells within 24 hours, from your sales history.",
		"AH: how many you have on the auction house, across your characters. Updates when you visit the auction house.",
		"Have: how many your characters hold in bags, banks and mail.",
		"Craft: how many crafts Queue restock would add. Grey 'skip' means the goal is 0.",
		"Goal: how many you want on the auction house. Grey goals follow the defaults at the bottom; white ones are "
			.. "your own for that item. The arrow button puts an item back on the default.",
	},
	queue = {
		"Materials: what every queued craft's materials cost at market prices.",
		"Profit: sale after the 5% auction house cut, minus those materials, for the whole entry.",
		"Crafts: how many are queued. Type a number in the box, or use - and +.",
	},
}

local function RowOnEnter(row)
	local data = row.data
	if not data then return end
	if data.kind == "header" and COLUMN_TIPS[data.columns] then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetText("Columns")
		for _, line in ipairs(COLUMN_TIPS[data.columns]) do GameTooltip:AddLine(line, 1, 1, 1, true) end
		GameTooltip:Show()
	elseif data.kind == "profit" then
		ShowProfitTooltip(row, data.result)
	elseif data.kind == "skill" then
		ShowSkillTooltip(row, data.row)
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
					GameTooltip:AddLine(("That price is %s old."):format(ns.Plural(age, "day", "days")), 1, 0.6, 0.2)
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
		StartItemTooltip(row, item.itemID, item.recipeID)
		GameTooltip:AddDoubleLine("Profit per craft", ns.Money(item.net), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("On the AH", item.onAH and tostring(item.onAH) or "unknown", 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("In bags, banks and mail", tostring(item.owned), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine(ns.Restock.IsCustom(item.itemID) and "Goal (your own)" or "Goal (default)",
			tostring(item.goal), 1, 1, 1, 1, 1, 1)
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
		if data.item.itemID then
			StartItemTooltip(row, data.item.itemID)
		else
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:SetText(data.item.name)
		end
		AddSalesLines(data.item.name)
		GameTooltip:Show()
	elseif data.kind == "queue" then
		local queuedRecipe = ns.db.recipes[data.entry.recipeID]
		StartItemTooltip(row, queuedRecipe and queuedRecipe.o, data.entry.recipeID)
		GameTooltip:AddLine("Crafted by " .. ns.CharLabel(ns.Recipes.Crafter(data.entry.recipeID, data.entry.char)), 0.6, 0.8, 1)
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
		GameTooltip:AddLine("Type the number of crafts in the box, or use - and + (Shift: ten). The red cross removes the entry.",
			0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	elseif data.kind == "tip" then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetText("Buying your materials")
		GameTooltip:AddLine("1. Go to an auction house and talk to the auctioneer.", 1, 1, 1, true)
		GameTooltip:AddLine("2. At the bottom of the auction house window, click the Shopping tab. Auctionator adds it.", 1, 1, 1, true)
		GameTooltip:AddLine(('3. In the list of shopping lists, click "%s". It searches everything on it.'):format(ns.LIST_NAME), 1, 1, 1, true)
		GameTooltip:AddLine("4. Click a result to buy it. What you buy leaves the list right away.", 1, 1, 1, true)
		GameTooltip:AddLine("The list only holds what you still need after your bags, bank, mailbox and alts.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	elseif data.kind == "next" then
		local recipe = ns.db.recipes[data.recipeID]
		StartItemTooltip(row, recipe and recipe.o, data.recipeID)
		GameTooltip:AddLine("Crafted by " .. ns.CharLabel(ns.Recipes.Crafter(data.recipeID, data.char)), 0.6, 0.8, 1)
		GameTooltip:Show()
	elseif data.kind == "auto" then
		local recipe = ns.db.recipes[data.craft.recipeID]
		StartItemTooltip(row, recipe and recipe.o, data.craft.recipeID)
		GameTooltip:AddLine(("Sub-craft: %d needed by the queue, made by %s."):format(data.craft.subCount,
			ns.CharLabel(data.craft.char)), 0.6, 0.8, 1, true)
		local queued = data.craft.count - data.craft.subCount
		if queued > 0 then
			GameTooltip:AddLine(("You also queued %d yourself, so Craft Next makes %d in all."):format(queued,
				data.craft.count), 1, 1, 1, true)
		end
		GameTooltip:Show()
	end
end

local function RowOnClick(row)
	local data = row.data
	if data and data.kind == "post" then
		ns.Posting.Select(data.row.itemID)
	elseif data and (data.kind == "profit" or data.kind == "skill") then
		local recipeID = data.kind == "profit" and data.result.recipeID or data.row.recipeID
		if ns.Recipes.Knows(ns.CharKey(), recipeID) and ns.Recipes.OpenRecipes()[recipeID] then
			C_TradeSkillUI.OpenRecipe(recipeID)
		end
	end
end

local function SmallButton(parent, text, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(20, 18)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local QUEUE_COLUMN_WIDTH = 80
local PROFIT_COLUMN_WIDTH = 110 -- fits "cost 12g 34s 56c" for bind-on-pickup crafts
local CHANCE_COLUMN_WIDTH = 44

-- Tooltips for + and -, by the kind of row they're on: title, then the help line.
local PLUS_TIPS = {
	profit = { "Queue one craft", "Shift: ten. Right-click or Ctrl-click: type an amount." },
	skill = { "Queue one craft", "Shift: ten. Right-click or Ctrl-click: type an amount." },
	queue = { "Add one craft", "Shift: ten. Or type the amount in the box." },
	restock = { "Raise the goal by one", "Shift: ten. Or type the goal in the box." },
}
local MINUS_TIPS = {
	queue = { "Remove one craft", "Shift: ten, down to one. At one, - removes the entry." },
	restock = { "Lower the goal by one", "Shift: ten. 0 skips the item." },
}

local function ButtonTip(button, tips)
	local data = button:GetParent().data
	local tip = data and tips[data.kind]
	if not tip then return end
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	GameTooltip:SetText(tip[1])
	GameTooltip:AddLine(tip[2], 1, 1, 1, true)
	GameTooltip:Show()
end

-- What a row's amount box edits: a queue entry (kept by reference, since entries above it can be removed while you
-- type) or one item's restock goal.
local function AmountTarget(data)
	if data and data.kind == "queue" then return { entry = data.entry } end
	if data and data.kind == "restock" then return { itemID = data.row.itemID } end
end

local function AmountValue(target)
	if target.entry then return target.entry.qty end
	return ns.Restock.Goal(target.itemID) or 0
end

-- Saves the box's amount to what it was editing. Saving the same value again does nothing, so Enter followed by the
-- focus loss it causes saves once.
local function CommitAmount(box)
	local target = box.target or AmountTarget(box:GetParent().data)
	box.target = nil
	if not target then return end
	local value = tonumber(box:GetText() or "")
	if not value then
		box:SetText(tostring(AmountValue(target)))
		return
	end
	if value == AmountValue(target) then return end
	if target.entry then
		for index, entry in ipairs(ns.db.queue) do
			if entry == target.entry then
				ns.Queue.Set(index, value)
				return
			end
		end
	else
		ns.Restock.SetGoal(target.itemID, value)
		-- Not right away: this can run while the rows are being drawn, when a row is reused for another entry.
		ns.Debounce("restockGoal", 0, function() UI.Refresh("restock") end)
	end
end

-- Puts the amount in the row's box, unless you're typing in it for this same entry: plans are rebuilt whenever bags
-- change, and that mustn't wipe what you've typed.
local function ShowAmount(row, data, value)
	local box = row.amount
	if box:HasFocus() then
		local target = box.target
		local other = AmountTarget(data)
		if target and other and target.entry == other.entry and target.itemID == other.itemID then
			box:Show()
			return
		end
		box:ClearFocus()
	end
	box:SetText(tostring(value))
	box:Show()
end

-- Lines controls up from the row's right edge, each { region, gap to the one before }, and puts the row's right-hand
-- text left of the last one. show = false only places them, for column headings over hidden controls.
local function PlaceRight(row, controls, show)
	local anchor
	for _, control in ipairs(controls) do
		local region, gap = control[1], control[2]
		region:ClearAllPoints()
		if anchor then
			region:SetPoint("RIGHT", anchor, "LEFT", -gap, 0)
		else
			region:SetPoint("RIGHT", row, "RIGHT", -gap, 0)
		end
		if show then region:Show() end
		anchor = region
	end
	row.right:ClearAllPoints()
	row.right:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
end

local function ProfitControls(row)
	row.profit:SetWidth(PROFIT_COLUMN_WIDTH)
	return { { row.plus, 2 }, { row.profit, 6 }, { row.chance, 6 } }
end

local function SkillControls(row)
	row.profit:SetWidth(QUEUE_COLUMN_WIDTH)
	return { { row.plus, 2 }, { row.profit, 6 }, { row.cost, 6 }, { row.chance, 6 } }
end

local RESTOCK_COLUMN_WIDTH = 38

local function RestockControls(row)
	return {
		{ row.plus, 2 }, { row.amount, 6 }, { row.minus, 8 }, { row.reset, 4 },
		{ row.colCraft, 4 }, { row.colHave, 6 }, { row.colAH, 6 }, { row.chance, 6 },
	}
end

local function QueueControls(row)
	row.profit:SetWidth(QUEUE_COLUMN_WIDTH)
	return {
		{ row.remove, 4 }, { row.quote, 8 }, { row.plus, 6 }, { row.amount, 6 }, { row.minus, 8 },
		{ row.profit, 8 }, { row.cost, 4 },
	}
end

-- Right-click or Ctrl-click on a Profit row's +: a small box to type how many crafts to queue.
local amountPopup
local function AskQueueAmount(owner, recipeID)
	if not amountPopup then
		local frame = CreateFrame("Frame", "CFFAmountPopup", main.frame, "BackdropTemplate")
		frame:SetSize(220, 60)
		frame:SetFrameStrata("DIALOG")
		frame:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		frame:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
		frame:EnableMouse(true)

		frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		frame.title:SetPoint("TOPLEFT", 10, -9)
		frame.title:SetPoint("TOPRIGHT", -10, -9)
		frame.title:SetJustifyH("LEFT")
		frame.title:SetWordWrap(false)

		local box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
		box:SetSize(56, 20)
		box:SetPoint("BOTTOMLEFT", 16, 9)
		box:SetAutoFocus(false)
		box:SetNumeric(true)
		box:SetMaxLetters(4)
		frame.box = box

		local function Accept()
			local count = tonumber(box:GetText() or "")
			if count and count > 0 then ns.Queue.Add(frame.recipeID, count) end
			frame:Hide()
		end
		local queue = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		queue:SetSize(64, 22)
		queue:SetText("Queue")
		queue:SetPoint("LEFT", box, "RIGHT", 8, 0)
		queue:SetScript("OnClick", Accept)
		local cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		cancel:SetSize(64, 22)
		cancel:SetText(CANCEL or "Cancel")
		cancel:SetPoint("LEFT", queue, "RIGHT", 4, 0)
		cancel:SetScript("OnClick", function() frame:Hide() end)

		box:SetScript("OnEnterPressed", Accept)
		box:SetScript("OnEscapePressed", function() frame:Hide() end)
		frame:SetScript("OnHide", function() box:ClearFocus() end)
		amountPopup = frame
		UI.amountPopup = frame
	end
	amountPopup.recipeID = recipeID
	amountPopup.title:SetText("Crafts of " .. RecipeName(recipeID) .. " to queue:")
	amountPopup:ClearAllPoints()
	amountPopup:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
	amountPopup:Show()
	amountPopup.box:SetText("1")
	amountPopup.box:SetFocus()
	amountPopup.box:HighlightText()
end
UI.AskQueueAmount = AskQueueAmount

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

	row.plus = SmallButton(row, "+", function(self, button)
		local data = self:GetParent().data
		if not data then return end
		if data.kind == "profit" or data.kind == "skill" then
			local recipeID = data.kind == "profit" and data.result.recipeID or data.row.recipeID
			if button == "RightButton" or IsControlKeyDown() then
				AskQueueAmount(self, recipeID)
			else
				ns.Queue.Add(recipeID, IsShiftKeyDown() and 10 or 1)
			end
		elseif data.kind == "queue" then
			ns.Queue.Change(data.index, IsShiftKeyDown() and 10 or 1)
		elseif data.kind == "restock" then
			ns.Restock.SetGoal(data.row.itemID, data.row.goal + (IsShiftKeyDown() and 10 or 1))
			UI.Refresh("restock")
		end
	end)
	row.plus:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.plus:SetScript("OnEnter", function(self) ButtonTip(self, PLUS_TIPS) end)
	row.plus:SetScript("OnLeave", GameTooltip_Hide)

	row.minus = SmallButton(row, "-", function(self)
		local data = self:GetParent().data
		if not data then return end
		if data.kind == "queue" then
			-- Shift takes ten but stops at one, so a big step can't drop the whole entry by surprise.
			local step = IsShiftKeyDown() and math.min(10, data.entry.qty - 1) or 1
			if step > 0 then ns.Queue.Change(data.index, -step) end
		elseif data.kind == "restock" then
			ns.Restock.SetGoal(data.row.itemID, data.row.goal - (IsShiftKeyDown() and 10 or 1))
			UI.Refresh("restock")
		end
	end)
	row.minus:SetScript("OnEnter", function(self) ButtonTip(self, MINUS_TIPS) end)
	row.minus:SetScript("OnLeave", GameTooltip_Hide)

	-- The amount between - and +: queued crafts, or a restock goal. Saved on Enter or when it loses focus.
	local amount = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
	amount:SetSize(34, 18)
	amount:SetAutoFocus(false)
	amount:SetNumeric(true)
	amount:SetMaxLetters(4)
	amount:SetJustifyH("CENTER")
	amount:SetScript("OnEditFocusGained", function(self)
		self.target = AmountTarget(self:GetParent().data)
		self:HighlightText()
	end)
	amount:SetScript("OnEditFocusLost", function(self)
		self:HighlightText(0, 0)
		CommitAmount(self)
	end)
	amount:SetScript("OnEnterPressed", function(self)
		CommitAmount(self)
		self:ClearFocus()
	end)
	amount:SetScript("OnEscapePressed", function(self)
		local target = self.target or AmountTarget(self:GetParent().data)
		if target then self:SetText(tostring(AmountValue(target))) end
		self:ClearFocus()
	end)
	amount:SetScript("OnHide", function(self)
		if self:HasFocus() then self:ClearFocus() end
	end)
	amount:Hide()
	row.amount = amount
	row.amountLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.amountLabel:SetPoint("CENTER", amount, "CENTER", 0, 0)

	-- A red cross well away from - and the amount, so removing an entry can't be a slip.
	row.remove = CreateFrame("Button", nil, row)
	row.remove:SetSize(16, 16)
	row.remove:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
	row.remove:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
	row.remove:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
	row.remove:SetScript("OnClick", function(self)
		local data = self:GetParent().data
		if data and data.kind == "queue" then ns.Queue.Remove(data.index) end
	end)
	row.remove:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Remove from the queue")
		GameTooltip:Show()
	end)
	row.remove:SetScript("OnLeave", GameTooltip_Hide)

	-- Behind a queue entry that would lose money.
	row.tint = row:CreateTexture(nil, "BACKGROUND")
	row.tint:SetAllPoints()
	row.tint:SetColorTexture(0.8, 0.1, 0.1, 0.18)
	row.tint:Hide()

	-- Columns: the queue's materials and profit for the whole entry, the Profit tab's sell chance and profit.
	for _, key in ipairs({ "cost", "profit", "chance" }) do
		row[key] = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row[key]:SetWidth(key == "chance" and CHANCE_COLUMN_WIDTH or QUEUE_COLUMN_WIDTH)
		row[key]:SetJustifyH("RIGHT")
		row[key]:SetWordWrap(false)
	end

	-- Restock's columns: on the AH, held, crafts to queue.
	for _, key in ipairs({ "colAH", "colHave", "colCraft" }) do
		row[key] = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row[key]:SetWidth(RESTOCK_COLUMN_WIDTH)
		row[key]:SetJustifyH("RIGHT")
		row[key]:SetWordWrap(false)
	end

	-- Puts an item's own restock goal back on the default. Only on items with their own goal.
	row.reset = CreateFrame("Button", nil, row)
	row.reset:SetSize(16, 16)
	row.reset:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
	row.reset:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	row.reset:SetScript("OnClick", function(self)
		local data = self:GetParent().data
		if not (data and data.kind == "restock") then return end
		ns.Restock.ResetGoal(data.row.itemID)
		UI.Refresh("restock")
	end)
	row.reset:SetScript("OnEnter", function(self)
		local data = self:GetParent().data
		if not (data and data.kind == "restock") then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Use the default goal")
		local default = ns.Restock.DefaultGoal(data.row.itemID)
		GameTooltip:AddLine(("This item has its own goal. Click to go back to the default%s, which follows the boxes "
			.. "at the bottom."):format(default and (" (" .. default .. ")") or ""), 1, 1, 1, true)
		GameTooltip:Show()
	end)
	row.reset:SetScript("OnLeave", GameTooltip_Hide)

	-- The Profit headings are buttons, styled like the column headers of the game's own lists: a shaded box that lights
	-- up under the mouse, and an arrow on every one (bright on the sorted column, faint on the others).
	row.sortHeadings = {}
	for _, key in ipairs({ "name", "chance", "cost", "profit" }) do
		local heading = CreateFrame("Button", nil, row)
		heading:SetHeight(ROW_HEIGHT - 4)
		heading.key = key
		local bg = heading:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(1, 1, 1, 0.07)
		local glow = heading:CreateTexture(nil, "HIGHLIGHT")
		glow:SetAllPoints()
		glow:SetColorTexture(1, 0.82, 0, 0.2)
		heading.edge = heading:CreateTexture(nil, "ARTWORK")
		heading.edge:SetColorTexture(1, 0.82, 0, 0.9)
		heading.edge:SetHeight(1)
		heading.edge:SetPoint("BOTTOMLEFT")
		heading.edge:SetPoint("BOTTOMRIGHT")
		heading.arrow = heading:CreateTexture(nil, "OVERLAY")
		heading.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
		heading.arrow:SetSize(9, 10)
		heading.label = heading:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		if key == "name" then
			heading.label:SetPoint("LEFT", 5, 0)
			heading.arrow:SetPoint("LEFT", heading.label, "RIGHT", 4, 0)
		else
			heading.label:SetPoint("RIGHT", -4, 0)
			heading.arrow:SetPoint("RIGHT", heading.label, "LEFT", -3, 0)
		end
		heading:SetScript("OnClick", function(self) UI.SortList(self.mode, self.key) end)
		heading:SetScript("OnEnter", function(self)
			self.label:SetTextColor(1, 1, 1)
			self.arrow:SetAlpha(1)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText("Columns")
			for _, line in ipairs(COLUMN_TIPS[self.mode] or {}) do GameTooltip:AddLine(line, 1, 1, 1, true) end
			GameTooltip:Show()
		end)
		heading:SetScript("OnLeave", function(self)
			self.label:SetTextColor(1, 0.82, 0)
			self.arrow:SetAlpha(self.sorted and 1 or 0.3)
			GameTooltip:Hide()
		end)
		heading:Hide()
		row.sortHeadings[key] = heading
	end

	row.quote = SmallButton(row, "Quote", function(self)
		local data = self:GetParent().data
		if data and data.kind == "queue" then ns.Advertise.QuoteInWhisper(data.entry.recipeID, data.entry.qty) end
	end)
	row.quote:SetWidth(46)
	row.quote:SetScript("OnEnter", function(self)
		local data = self:GetParent().data
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Quote this order")
		local price, cost
		if data and data.kind == "queue" then price, cost = ns.Queue.QuotePrice(data.entry.recipeID, data.entry.qty) end
		if price then
			GameTooltip:AddDoubleLine(("Materials for x%d"):format(data.entry.qty), ns.Money(cost), 1, 1, 1, 1, 1, 1)
			GameTooltip:AddDoubleLine(("Quote (+%d%%)"):format(ns.Queue.QuoteMargin()), ns.Money(price), 1, 1, 1, 1, 1, 1)
		end
		if ns.Prices.IsStale() then
			GameTooltip:AddLine(ScanAgeText() .. " The quote may be off: scan the auction house first.", 1, 0.6, 0.2, true)
		end
		GameTooltip:AddLine("Fills in a reply to your last whisper with the price for the whole queued amount. "
			.. ("The margin is %d%%; change it in the box at the bottom. You press Enter to send it."):format(ns.Queue.QuoteMargin()),
			1, 1, 1, true)
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
	row.cost:Hide()
	row.profit:Hide()
	row.chance:Hide()
	row.colAH:Hide()
	row.colHave:Hide()
	row.colCraft:Hide()
	row.reset:Hide()
	for _, heading in pairs(row.sortHeadings) do heading:Hide() end
	-- The Profit headings light up one by one, so the row as a whole doesn't.
	local rowGlow = row:GetHighlightTexture()
	local sortable = data.kind == "header" and SORTS[data.columns] ~= nil
	if rowGlow then rowGlow:SetAlpha(sortable and 0 or 1) end
	row.tint:Hide()
	row.amountLabel:Hide()
	row.amount:SetTextColor(1, 1, 1)
	-- Left alone on rows that keep it, so a redraw doesn't take the focus from someone typing in it.
	if data.kind ~= "queue" and data.kind ~= "restock" then row.amount:Hide() end
	row.icon:Show()
	row.right:ClearAllPoints()
	row.right:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.right:SetText("")
	if data.selected then row:LockHighlight() else row:UnlockHighlight() end

	if data.kind == "header" then
		row.icon:Hide()
		row.left:SetText(Color("ffffd100", data.text))
		if sortable then
			-- Sortable headings: Profit has Recipe, Sells, Profit; Skill up has Recipe, Chance, Craft, Per point.
			local mode = data.columns
			PlaceRight(row, mode == "profit" and ProfitControls(row) or SkillControls(row), false)
			row.left:SetText("")
			local columns = mode == "profit"
				and { chance = { row.chance, "Sells" }, profit = { row.profit, "Profit" } }
				or { chance = { row.chance, "Chance" }, cost = { row.cost, "Craft" }, profit = { row.profit, "Per point" } }
			local sortKey, ascending = UI.ListSort(mode)
			local headings = row.sortHeadings
			headings.name.label:SetText(data.text)
			headings.name:ClearAllPoints()
			headings.name:SetPoint("LEFT", row, "LEFT", 0, 0)
			headings.name:SetWidth((headings.name.label:GetStringWidth() or 40) + 26)
			for key, column in pairs(columns) do
				headings[key].label:SetText(column[2])
				headings[key]:ClearAllPoints()
				headings[key]:SetPoint("LEFT", column[1], "LEFT", -2, 0)
				headings[key]:SetPoint("RIGHT", column[1], "RIGHT", 2, 0)
			end
			for key, heading in pairs(headings) do
				if key == "name" or columns[key] then
					local sorted = key == sortKey
					-- Up for ascending. Unsorted columns point the way a first click would sort them.
					local up
					if sorted then up = ascending else up = SORTS[mode].ascending[key] end
					if up then heading.arrow:SetTexCoord(0, 0.5625, 1, 0) else heading.arrow:SetTexCoord(0, 0.5625, 0, 1) end
					heading.mode, heading.sorted = mode, sorted
					heading.arrow:SetAlpha(sorted and 1 or 0.3)
					heading.edge:SetShown(sorted)
					heading.label:SetTextColor(1, 0.82, 0)
					heading:Show()
				end
			end
		elseif data.columns == "restock" then
			PlaceRight(row, RestockControls(row), false)
			row.chance:SetText(Color("ffffd100", "Sells"))
			row.colAH:SetText(Color("ffffd100", "AH"))
			row.colHave:SetText(Color("ffffd100", "Have"))
			row.colCraft:SetText(Color("ffffd100", "Craft"))
			row.amountLabel:SetText("Goal")
			for _, region in ipairs({ row.chance, row.colAH, row.colHave, row.colCraft, row.amountLabel }) do
				region:Show()
			end
		elseif data.columns == "queue" then
			PlaceRight(row, QueueControls(row), false)
			row.cost:SetText(Color("ffffd100", "Materials"))
			row.profit:SetText(Color("ffffd100", "Profit"))
			row.amountLabel:SetText("Crafts")
			row.cost:Show()
			row.profit:Show()
			row.amountLabel:Show()
		end
	elseif data.kind == "profit" then
		local result = data.result
		row.icon:SetTexture(ns.Items.Icon(result.itemID))
		row.left:SetText(ItemLabel(result.itemID))
		PlaceRight(row, ProfitControls(row), true)
		if result.bound then
			row.profit:SetText(result.cost and (Color(COLOR_MUTED, "cost ") .. ns.Money(result.cost)) or Color(COLOR_MUTED, "no price"))
		elseif result.net then
			row.chance:SetText(ChanceText(ns.Items.Name(result.itemID)))
			row.profit:SetText(Color(result.net >= 0 and COLOR_PROFIT or COLOR_LOSS, ns.Money(result.net)))
		else
			row.profit:SetText(Color(COLOR_MUTED, "no data"))
		end
	elseif data.kind == "skill" then
		local item = data.row
		local recipe = ns.db.recipes[item.recipeID]
		local spellIcon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(item.recipeID))
			or (GetSpellTexture and GetSpellTexture(item.recipeID))
		row.icon:SetTexture(item.itemID and ns.Items.Icon(item.itemID) or spellIcon or 134400)
		local hex = SKILL_COLORS[item.difficulty]
		row.left:SetText(Color(hex, recipe and recipe.n or "?")
			.. (item.points > 1 and Color(COLOR_MUTED, (" +%d per craft"):format(item.points)) or ""))
		PlaceRight(row, SkillControls(row), true)
		row.chance:SetText(Color(hex, SKILL_CHANCE_TEXT[item.difficulty]))
		row.cost:SetText(item.cost and ns.Money(item.cost) or Color(COLOR_MUTED, "no price"))
		row.profit:SetText(item.perPoint and ns.Money(item.perPoint) or Color(COLOR_MUTED, "?"))
	elseif data.kind == "queue" then
		local entry = data.entry
		local recipe = ns.db.recipes[entry.recipeID]
		row.icon:SetTexture(recipe and recipe.o and ns.Items.Icon(recipe.o) or 134400)
		local net = ns.totals.entries[data.index]
		local boundCost = ns.totals.boundEntries[data.index]
		local change = not boundCost and recipe and recipe.o and PriceChangeText(recipe.o, false)
		-- Who crafts it, when that isn't the character you're on.
		local crafter = ns.Recipes.Crafter(entry.recipeID, entry.char)
		local onAlt = crafter ~= ns.CharKey() and Color("ff99ccff", "  " .. ns.CharLabel(crafter)) or ""
		row.left:SetText(RecipeName(entry.recipeID) .. onAlt
			.. (entry.restock and Color(COLOR_MUTED, " restock") or "")
			.. (change and ("   " .. Color(COLOR_MUTED, "sells ") .. change) or ""))
		PlaceRight(row, QueueControls(row), true)
		ShowAmount(row, data, entry.qty)
		-- Both columns are for the whole entry, every queued craft.
		local cost = boundCost or (data.matCost and data.matCost * entry.qty)
		row.cost:SetText(cost and ns.Money(cost) or Color(COLOR_MUTED, "?"))
		row.tint:SetShown(net ~= nil and net < 0 and not boundCost)
		row.profit:SetText(boundCost and Color(COLOR_MUTED, "can't sell")
			or net and Color(net >= 0 and COLOR_PROFIT or COLOR_LOSS, ns.Money(net))
			or Color(COLOR_MUTED, "no price"))
	elseif data.kind == "restock" then
		local item = data.row
		row.icon:SetTexture(ns.Items.Icon(item.itemID))
		row.left:SetText(ItemLabel(item.itemID))
		PlaceRight(row, RestockControls(row), true)
		ShowAmount(row, data, item.goal)
		-- Grey: follows the default. White, with the reset arrow: the player's own goal for this item.
		local custom = ns.Restock.IsCustom(item.itemID)
		row.reset:SetShown(custom)
		if custom then row.amount:SetTextColor(1, 1, 1) else row.amount:SetTextColor(0.6, 0.6, 0.6) end
		row.chance:SetText(ChanceText(ns.Items.Name(item.itemID)))
		row.colAH:SetText(item.onAH and tostring(item.onAH) or Color(COLOR_MUTED, "?"))
		row.colHave:SetText(tostring(item.owned))
		if item.goal == 0 then
			row.colCraft:SetText(Color(COLOR_MUTED, "skip"))
		elseif item.crafts > 0 then
			row.colCraft:SetText(Color("ffffb040", tostring(item.crafts)))
		else
			row.colCraft:SetText(Color(COLOR_PROFIT, "0"))
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
		local text = RecipeName(data.craft.recipeID) .. " x" .. data.craft.subCount
		if data.craft.count > data.craft.subCount then
			text = text .. Color(COLOR_MUTED, (" (+%d queued)"):format(data.craft.count - data.craft.subCount))
		end
		row.left:SetText(text)
		row.right:SetText(Color(COLOR_MUTED, ns.CharLabel(data.craft.char)))
	elseif data.kind == "next" then
		local recipe = ns.db.recipes[data.recipeID]
		row.icon:SetTexture(recipe and recipe.o and ns.Items.Icon(recipe.o) or 134400)
		row.left:SetText(RecipeName(data.recipeID))
		local crafter = ns.Recipes.Crafter(data.recipeID, data.char)
		row.right:SetText("x" .. data.count
			.. (crafter ~= ns.CharKey() and ("  " .. Color("ff99ccff", ns.CharLabel(crafter))) or ""))
	elseif data.kind == "how" or data.kind == "note" then
		row.icon:Hide()
		row.left:SetText(Color(COLOR_MUTED, data.text))
	elseif data.kind == "warn" then
		row.icon:Hide()
		row.left:SetText(Color(COLOR_WARN, data.text))
	elseif data.kind == "tip" then
		row.icon:Hide()
		row.left:SetText(Color("ff66ccff", data.text))
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

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------

local function RenderRows(window)
	local visible = math.min(ROW_COUNT, math.floor(window.container:GetHeight() / ROW_HEIGHT))
	if window.mini then visible = math.min(#window.list, window.maxRows) end
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
		-- Notes for this version not opened yet: the tab is green with a dot, nothing pops up.
		local unseen = tab.key == "changelog" and ns.WhatsNew and ns.WhatsNew.HasUnseen()
		tab.label:SetText(Color(selected and "ffffffff" or (unseen and "ff55dd55" or "ffb8b8b8"), title))
		tab.badge:SetShown(unseen and true or false)
		local shade = selected and 0.24 or 0.11
		tab.bg:SetColorTexture(shade, shade, shade + 0.03, 1)
		tab.accent:SetShown(selected)
	end
end

function UI.Refresh(key)
	local window = windows[key]
	if not window or not window.frame:IsVisible() then return end
	if window.tabs then RenderTabs(window) end
	if window.build then -- the Changelog pane is text, not rows
		window.list = window.build()
		RenderRows(window)
	end
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

function UI.RefreshTabs()
	UpdateTabStrip()
end

-- Queue, bags or bank changed: everything that counts stock needs redrawing.
function UI.RefreshQueue()
	UI.Refresh("queue")
	UI.Refresh("restock")
	UI.Refresh("posting")
	UpdateTabStrip()
	UpdateNextStep()
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

-- The look and dragging shared by the main window and the Next step bar.
local function MakeMovable(frame, key)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	-- A plain white texture tinted dark, not the tooltip background: that texture is itself see-through, so the game
	-- world and other windows showed through the lists at any opacity.
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

	-- Under the profession tabs, since it advertises the selected one.
	local advertise = HeaderButton(window.frame, "Advertise", TAB_WIDTH - 6, function()
		ns.Advertise.Send(UI.AdvertisedProfession())
	end)
	advertise:SetPoint("BOTTOMLEFT", 10, 7)
	if advertise.SetMotionScriptsWhileDisabled then advertise:SetMotionScriptsWhileDisabled(true) end
	advertise:SetScript("OnEnter", function(self)
		local professionID = UI.AdvertisedProfession()
		local professionName = professionID and ns.Recipes.ProfessionName(professionID)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(professionName and ("Advertise " .. professionName) or "Advertise")
		local reason = ns.Advertise.Reason(professionID)
		if reason then
			GameTooltip:AddLine(reason, 1, 0.6, 0.2, true)
		else
			GameTooltip:AddLine(("Fills in your %s link for %s. You press Enter to send it. Choose where to post "
				.. "with the Ad box beside the chat."):format(professionName or "profession", ns.Advertise.DestinationLabel()),
				1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	advertise:SetScript("OnLeave", GameTooltip_Hide)
	window.advertiseButton = advertise

	-- Profit or Skill up, the current one lit, like Buy It and Farm It on the Queue tab.
	local modes = {}
	for index, mode in ipairs({
		{ key = "profit", label = "Profit", tip = "Every recipe ranked by what it earns on the auction house." },
		{ key = "skill", label = "Skill up", tip = "Levelling: the selected profession's recipes that can still give "
			.. "a skill point, cheapest per point first, coloured as in the profession window." },
	}) do
		local button = HeaderButton(window.frame, mode.label, 70, function()
			ns.db.ui.profitMode = mode.key
			window.offset = 0
			UI.Refresh("profit")
		end)
		if index == 1 then
			button:SetPoint("TOPLEFT", 10, -PANE_ACTIONS_TOP)
		else
			button:SetPoint("LEFT", modes[1], "RIGHT", 0, 0)
		end
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(mode.label)
			GameTooltip:AddLine(mode.tip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
		button.mode = mode
		modes[index] = button
	end
	window.modeButtons = modes

	local hideUnprofitable = CreateFrame("CheckButton", nil, window.frame, "UICheckButtonTemplate")
	hideUnprofitable:SetSize(24, 24)
	hideUnprofitable:SetPoint("LEFT", modes[2], "RIGHT", 10, 0)
	hideUnprofitable:SetHitRectInsets(0, -150, 0, 0) -- the label is clickable too
	local hideLabel = hideUnprofitable:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hideLabel:SetPoint("LEFT", hideUnprofitable, "RIGHT", 2, 1)
	hideLabel:SetText("Hide unprofitable recipes")
	hideUnprofitable:SetScript("OnClick", function(self)
		ns.db.ui.hideUnprofitable = self:GetChecked() and true or false
		window.offset = 0
		UI.Refresh("profit")
	end)
	window.hideUnprofitable = hideUnprofitable

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
	status:SetPoint("BOTTOMLEFT", 12 + TAB_WIDTH, 12)
	status:SetPoint("BOTTOMRIGHT", -236, 12)
	status:SetJustifyH("LEFT")
	status:SetWordWrap(false)
	window.status = status

	window.update = function(self)
		advertise:SetEnabled(ns.Advertise.Reason(UI.AdvertisedProfession()) == nil)
		local skillMode = ns.db.ui.profitMode == "skill"
		for _, button in ipairs(modes) do
			local on = (button.mode.key == "skill") == skillMode
			button:SetText(on and ("|cffffffff" .. button.mode.label .. "|r") or button.mode.label)
			if on then button:LockHighlight() else button:UnlockHighlight() end
		end
		hideUnprofitable:SetShown(not skillMode)
		hideUnprofitable:SetChecked(ns.db.ui.hideUnprofitable and true or false)
		if self.list.skill then
			local professionID = UI.SkillProfession()
			local char = ns.db.chars[ns.CharKey()]
			local level = professionID and char and char.skill and char.skill[professionID]
			local parts = {}
			if level then
				table.insert(parts, ("%s %d/%d."):format(ns.Recipes.ProfessionName(professionID) or "Skill", level.level, level.max))
			end
			if self.list.trivial > 0 then
				table.insert(parts, Color(COLOR_MUTED, ("%d grey not shown."):format(self.list.trivial)))
			end
			status:SetText(table.concat(parts, " "))
			return
		end
		local shown = math.max(0, #self.list - 1) -- less the column headings
		local hidden = self.list.hiddenUnprofitable or 0
		local text
		if profitSearch ~= "" then
			text = ProfitSearchStatus(shown)
		elseif shown == 0 and hidden == 0 then
			text = "Open a profession to record its recipes."
		else
			text = ns.Plural(shown, "recipe", "recipes") .. " known across your characters."
		end
		if hidden > 0 then text = text .. " " .. Color(COLOR_MUTED, ("%d unprofitable hidden."):format(hidden)) end
		status:SetText(text)
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

local function NumberBox(parent, labelText, previous, read, write, paneKey)
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
			UI.Refresh(paneKey or "restock")
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
	return box, label
end

-- "Craft Next: Smelt Bronze x12"; "Open Mining: Smelt Bronze x12" when Craft Next opens its profession first; or,
-- while that craft can't be made, "Finish Smelt Bronze: 8 left" (disabled).
function UI.CraftButtonText(craft, count, blocking, open)
	if craft then return ("Craft Next: %s x%d"):format(RecipeName(craft.recipeID), count) end
	if blocking and open then
		local recipe = ns.db.recipes[blocking.recipeID]
		return ("Open %s: %s x%d"):format((recipe and recipe.pn) or "profession", RecipeName(blocking.recipeID),
			blocking.count)
	end
	if blocking then return ("Finish %s: %d left"):format(RecipeName(blocking.recipeID), blocking.count) end
	return "Craft Next"
end

-- The Craft Next bar: the Craft Next button and a progress bar in one. Idle it glows green and says what Craft Next
-- makes and how long that takes; while you craft it fills amber through the crafts of that recipe (7 of 20), with
-- the time left on them and on all your crafts, and a thin blue line under it fills through all crafts.
-- Flat fills on a dark slate track with a thin border in the state's colour: no textured status bar, no white sheen.
local CRAFT_BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local CRAFT_BAR_TRACK = { 0.055, 0.065, 0.085 }
local CRAFT_BAR_STYLES = {
	--            fill from             fill to               border
	ready    = { { 0.04, 0.30, 0.16 }, { 0.12, 0.62, 0.32 }, { 0.20, 0.70, 0.40 } },
	crafting = { { 0.78, 0.36, 0.04 }, { 1.00, 0.72, 0.18 }, { 0.95, 0.62, 0.15 } },
	paused   = { { 0.40, 0.22, 0.06 }, { 0.62, 0.40, 0.12 }, { 0.62, 0.42, 0.16 } },
	blocked  = { { 0.13, 0.15, 0.20 }, { 0.17, 0.20, 0.27 }, { 0.24, 0.27, 0.35 } },
}
-- The all-crafts line: deep blue to cyan on a darker blue track.
local CRAFT_ALL_FROM, CRAFT_ALL_TO, CRAFT_ALL_TRACK = { 0.10, 0.35, 0.90 }, { 0.30, 0.85, 1.00 }, { 0.04, 0.08, 0.15 }
local craftBars = {}

local function PaintFill(statusBar, from, to)
	local texture = statusBar:GetStatusBarTexture()
	if texture and texture.SetGradient and CreateColor then
		local ok = pcall(texture.SetGradient, texture, "HORIZONTAL",
			CreateColor(from[1], from[2], from[3], 1), CreateColor(to[1], to[2], to[3], 1))
		if ok then
			texture:SetVertexColor(1, 1, 1, 1)
			return
		end
	end
	statusBar:SetStatusBarColor(to[1], to[2], to[3])
end

local function CraftIcon(recipeID)
	local recipe = recipeID and ns.db.recipes[recipeID]
	if recipe and recipe.o then return ns.Items.Icon(recipe.o) end
	return recipeID and ((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(recipeID))
		or (GetSpellTexture and GetSpellTexture(recipeID))) or nil
end

-- "all crafts 3:10 (45)", or nothing when the recipe on the bar is all there is.
local function AllCraftsText(progress, onlyThis)
	if not progress.allSeconds or progress.allCount == 0 then return nil end
	if onlyThis then return Color(COLOR_MUTED, "nothing else queued") end
	return ("all crafts %s %s"):format(Color("ffffffff", ns.Planner.FormatDuration(progress.allSeconds)),
		Color(COLOR_MUTED, ("(%d)"):format(progress.allCount)))
end

local function RenderCraftBar(bar)
	local progress = ns.Queue.CraftProgress()
	local craft, count, blocking, open = bar.cf.craft, bar.cf.count, bar.cf.blocking, bar.cf.open
	local state, fill, title, detail, iconRecipe
	local onlyThis = progress.runSeconds and math.abs(progress.runSeconds - progress.allSeconds) < 0.5
	if progress.casting or progress.betweenCasts then
		state, iconRecipe = "crafting", progress.recipeID
		fill = (progress.done + (progress.castFraction or 0)) / math.max(progress.total, 1)
		title = ("%s  %s"):format(RecipeName(progress.recipeID),
			Color("ffffffff", ("%d / %d"):format(progress.done + 1, progress.total)))
		detail = Color("ffffffff", ns.Planner.FormatDuration(progress.runSeconds)) .. " left"
	elseif craft then
		local paused = progress.recipeID == craft.recipeID and progress.done > 0
		state, iconRecipe = paused and "paused" or "ready", craft.recipeID
		fill = paused and progress.done / progress.total or 1
		title = UI.CraftButtonText(craft, count)
		local seconds = count * ns.Queue.CraftSeconds(craft.recipeID)
		detail = ("x%d takes %s"):format(count, Color("ffffffff", ns.Planner.FormatDuration(seconds)))
		if paused then
			detail = Color(COLOR_MUTED, ("%d / %d done"):format(progress.done, progress.total)) .. "  " .. detail
		end
		onlyThis = math.abs(craft.count * ns.Queue.CraftSeconds(craft.recipeID) - (progress.allSeconds or 0)) < 0.5
	elseif blocking and open then
		-- Clicking opens the profession and starts crafting.
		state, iconRecipe = "ready", blocking.recipeID
		fill = 1
		title = UI.CraftButtonText(nil, nil, blocking, open)
		local seconds = blocking.count * ns.Queue.CraftSeconds(blocking.recipeID)
		detail = ("x%d takes %s"):format(blocking.count, Color("ffffffff", ns.Planner.FormatDuration(seconds)))
		onlyThis = math.abs(seconds - (progress.allSeconds or 0)) < 0.5
	else
		state, iconRecipe = "blocked", blocking and blocking.recipeID
		fill = (blocking and progress.recipeID == blocking.recipeID) and progress.done / progress.total or 0
		title = UI.CraftButtonText(nil, nil, blocking)
		onlyThis = false
	end
	local all = AllCraftsText(progress, onlyThis)
	if all then detail = detail and (detail .. "   " .. all) or all end

	bar.cf.state = state
	local style = CRAFT_BAR_STYLES[state]
	if bar.cf.paintedState ~= state then
		bar.cf.paintedState = state
		PaintFill(bar.fill, style[1], style[2])
		bar:SetBackdropBorderColor(style[3][1], style[3][2], style[3][3], 1)
		bar.glow:SetVertexColor(style[2][1], style[2][2], style[2][3])
		if bar.cf.pulse then
			if state == "ready" then bar.cf.pulse:Play() else bar.cf.pulse:Stop() end
		end
		bar.glow:SetShown(state == "ready")
		bar.fill:SetAlpha(state == "ready" and 0.9 or 1)
	end
	bar.fill:SetValue(fill)
	bar.spark:SetShown(state == "crafting" and fill > 0.01 and fill < 0.995)
	bar.allStrip:SetShown(progress.allFraction ~= nil)
	if progress.allFraction then bar.allStrip:SetValue(progress.allFraction) end
	bar.icon:SetTexture(CraftIcon(iconRecipe))
	bar.icon:SetShown(iconRecipe ~= nil)
	bar.icon:SetDesaturated(state == "blocked")
	bar:SetText(title)
	bar.detail:SetText(detail or "")
	bar.cf.progress = progress

	-- Animate only while crafting: the fill moves every frame, the times every quarter second.
	if progress.casting or progress.betweenCasts then
		if not bar.cf.animating then
			bar.cf.animating = true
			bar.cf.sinceText = 0
			bar:SetScript("OnUpdate", function(self, elapsed)
				self.cf.sinceText = self.cf.sinceText + elapsed
				if self.cf.sinceText >= 0.25 then
					self.cf.sinceText = 0
					RenderCraftBar(self)
					return
				end
				local p = ns.Queue.CraftProgress()
				if not p.casting then return end
				self.fill:SetValue((p.done + p.castFraction) / math.max(p.total, 1))
				if p.allFraction then self.allStrip:SetValue(p.allFraction) end
			end)
		end
	elseif bar.cf.animating then
		bar.cf.animating = false
		bar:SetScript("OnUpdate", nil)
	end
end

local function CraftBarTooltip(bar)
	GameTooltip:SetOwner(bar, "ANCHOR_TOP")
	GameTooltip:SetText("Craft Next")
	local progress = bar.cf.progress or ns.Queue.CraftProgress()
	if bar.cf.state == "crafting" then
		GameTooltip:AddLine(("Crafting %s: %d of %d, %s left."):format(RecipeName(progress.recipeID), progress.done + 1,
			progress.total, ns.Planner.FormatDuration(progress.runSeconds)), 1, 1, 1, true)
	elseif bar.cf.craft then
		GameTooltip:AddLine(("Click to craft %s x%d."):format(RecipeName(bar.cf.craft.recipeID), bar.cf.count), 1, 1, 1, true)
	elseif bar.cf.blocking and bar.cf.open then
		local recipe = ns.db.recipes[bar.cf.blocking.recipeID]
		GameTooltip:AddLine(("Click to open %s and craft %s."):format((recipe and recipe.pn) or "the profession",
			RecipeName(bar.cf.blocking.recipeID)), 1, 1, 1, true)
	elseif bar.cf.blocking then
		GameTooltip:AddLine(("%s has to be finished first: %d left."):format(RecipeName(bar.cf.blocking.recipeID),
			bar.cf.blocking.count), 1, 1, 1, true)
	end
	local me = ns.CharKey()
	local lines = 0
	for _, craft in ipairs(ns.ActivePlan().crafts) do
		if craft.char == me and craft.count > 0 then
			if lines == 0 then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine("Still to craft here")
			end
			lines = lines + 1
			if lines <= 12 then
				GameTooltip:AddDoubleLine(("%s x%d"):format(RecipeName(craft.recipeID), craft.count),
					ns.Planner.FormatDuration(craft.count * ns.Queue.CraftSeconds(craft.recipeID)), 1, 1, 1, 1, 1, 1)
			end
		end
	end
	if lines > 12 then GameTooltip:AddLine(("and %d more"):format(lines - 12), 0.6, 0.6, 0.6) end
	if lines > 0 then
		GameTooltip:AddDoubleLine("All crafts", ns.Planner.FormatDuration(progress.allSeconds), 1, 0.82, 0, 1, 0.82, 0)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("The amber fill is the recipe you're crafting, the blue line under it all your crafts. Times "
		.. "come from your own casts; a recipe you haven't cast yet uses its spell's cast time. Crafts on other "
		.. "characters aren't counted.", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function CreateCraftBar(parent, height)
	local bar = CreateFrame("Button", nil, parent, "BackdropTemplate")
	bar.cf = {} -- the bar's own state, apart from the frame's fields
	bar:SetHeight(height)
	bar:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	bar:SetBackdropColor(CRAFT_BAR_TRACK[1], CRAFT_BAR_TRACK[2], CRAFT_BAR_TRACK[3], 0.97)
	bar:RegisterForClicks("LeftButtonUp")
	bar:SetScript("OnClick", function(self)
		if self.cf.state == "ready" or self.cf.state == "paused" then ns.Queue.CraftNext() end
	end)

	local fill = CreateFrame("StatusBar", nil, bar)
	fill:SetPoint("TOPLEFT", 2, -2)
	fill:SetPoint("BOTTOMRIGHT", -2, 2)
	fill:SetStatusBarTexture(CRAFT_BAR_TEXTURE)
	fill:SetMinMaxValues(0, 1)
	fill:SetValue(0)
	bar.fill = fill

	-- Everything drawn over the fill sits on its own layer above it.
	local over = CreateFrame("Frame", nil, bar)
	over:SetAllPoints(fill)
	over:SetFrameLevel((fill:GetFrameLevel() or 0) + 2)

	-- A soft shade at the bottom gives the flat fill some depth without greying it.
	local shade = over:CreateTexture(nil, "BACKGROUND")
	shade:SetTexture("Interface\\Buttons\\WHITE8X8")
	shade:SetPoint("BOTTOMLEFT")
	shade:SetPoint("BOTTOMRIGHT")
	shade:SetHeight(math.floor((height - 4) / 2))
	shade:SetVertexColor(0, 0, 0, 0.18)
	if shade.SetGradient and CreateColor then
		pcall(shade.SetGradient, shade, "VERTICAL", CreateColor(0, 0, 0, 0.28), CreateColor(0, 0, 0, 0))
	end

	local glow = over:CreateTexture(nil, "ARTWORK")
	glow:SetTexture("Interface\\Buttons\\WHITE8X8")
	glow:SetAllPoints()
	glow:SetBlendMode("ADD")
	glow:SetAlpha(0.12)
	bar.glow = glow
	local pulse = glow.CreateAnimationGroup and glow:CreateAnimationGroup()
	if pulse then
		pulse:SetLooping("BOUNCE")
		local fade = pulse:CreateAnimation("Alpha")
		fade:SetFromAlpha(0.03)
		fade:SetToAlpha(0.2)
		fade:SetDuration(1.1)
		if fade.SetSmoothing then fade:SetSmoothing("IN_OUT") end
		bar.cf.pulse = pulse
	end

	local spark = over:CreateTexture(nil, "OVERLAY")
	spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	spark:SetBlendMode("ADD")
	spark:SetSize(20, (height - 4) * 1.9)
	local fillTexture = fill:GetStatusBarTexture()
	if fillTexture then spark:SetPoint("CENTER", fillTexture, "RIGHT", 0, 0) end
	spark:Hide()
	bar.spark = spark

	local allStrip = CreateFrame("StatusBar", nil, over)
	allStrip:SetPoint("BOTTOMLEFT", 0, 0)
	allStrip:SetPoint("BOTTOMRIGHT", 0, 0)
	allStrip:SetHeight(4)
	allStrip:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	allStrip:SetMinMaxValues(0, 1)
	local allTrack = allStrip:CreateTexture(nil, "BACKGROUND")
	allTrack:SetTexture("Interface\\Buttons\\WHITE8X8")
	allTrack:SetAllPoints()
	allTrack:SetVertexColor(CRAFT_ALL_TRACK[1], CRAFT_ALL_TRACK[2], CRAFT_ALL_TRACK[3], 0.9)
	PaintFill(allStrip, CRAFT_ALL_FROM, CRAFT_ALL_TO)
	allStrip:Hide()
	bar.allStrip = allStrip

	local icon = over:CreateTexture(nil, "OVERLAY")
	local iconSize = height - 12
	icon:SetSize(iconSize, iconSize)
	icon:SetPoint("LEFT", 3, 0)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	bar.icon = icon

	local title = over:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOPLEFT", iconSize + 8, -2)
	title:SetPoint("TOPRIGHT", -6, -2)
	title:SetJustifyH("CENTER")
	if title.SetWordWrap then title:SetWordWrap(false) end
	local detail = over:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	detail:SetPoint("BOTTOMLEFT", iconSize + 8, 4)
	detail:SetPoint("BOTTOMRIGHT", -6, 4)
	detail:SetJustifyH("CENTER")
	if detail.SetWordWrap then detail:SetWordWrap(false) end
	bar.detail = detail

	local highlight = bar:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
	highlight:SetPoint("TOPLEFT", 2, -2)
	highlight:SetPoint("BOTTOMRIGHT", -2, 2)
	highlight:SetBlendMode("ADD")
	highlight:SetVertexColor(1, 1, 1, 0.05)

	bar:SetScript("OnMouseDown", function()
		if bar.cf.state == "ready" or bar.cf.state == "paused" then over:SetPoint("TOPLEFT", fill, "TOPLEFT", 1, -1) end
	end)
	bar:SetScript("OnMouseUp", function() over:SetAllPoints(fill) end)
	bar:SetScript("OnEnter", CraftBarTooltip)
	bar:SetScript("OnLeave", GameTooltip_Hide)
	bar:HookScript("OnShow", function(self) RenderCraftBar(self) end)
	bar:HookScript("OnHide", function(self)
		self.cf.animating = false
		self:SetScript("OnUpdate", nil)
	end)

	bar.SetText = function(self, text)
		self.text = text
		title:SetText(text)
	end
	bar.GetText = function(self) return self.text end
	-- Called with what Craft Next would do; the bar adds the progress and the times.
	bar.Update = function(self, craft, count, blocking, open)
		self.cf.craft, self.cf.count, self.cf.blocking, self.cf.open = craft, count, blocking, open
		self:SetEnabled(craft ~= nil or open ~= nil)
		RenderCraftBar(self)
	end
	table.insert(craftBars, bar)
	return bar
end

-- Casts starting, finishing or stopping: every Craft Next bar on screen catches up at once.
function UI.UpdateCraftBars()
	for _, bar in ipairs(craftBars) do
		if bar:IsVisible() then RenderCraftBar(bar) end
	end
end

function CreateQueuePane()
	local window = CreatePane("queue", 142)
	window.build = BuildQueueList

	local clear = HeaderButton(window.frame, "Clear", 70, function()
		local count = #ns.db.queue
		if count == 0 then return end
		StaticPopup_Show("CFF_CLEAR_QUEUE", count == 1 and "remove the one entry from the queue?"
			or ("remove all %d entries from the queue?"):format(count))
	end)
	clear:SetPoint("TOPLEFT", 10, -PANE_ACTIONS_TOP)

	-- Buy It and Farm It side by side, the current mode lit, so the button shows where you are, not where you'd go.
	local modes = {}
	for index, mode in ipairs({
		{ farm = false, label = "Buy It", tip = "Plan to buy materials at the auction house and from vendors." },
		{ farm = true, label = "Farm It", tip = "Plan to gather materials yourself. Closes this window; the Next step bar "
			.. "at the top of the screen then says what to gather and where." },
	}) do
		local button = HeaderButton(window.frame, mode.label, 62, function()
			if (ns.db.ui.farmMode and true or false) ~= mode.farm then ns.ToggleFarmMode() end
		end)
		button:SetPoint("LEFT", index == 1 and clear or modes[1], "RIGHT", index == 1 and 12 or 0, 0)
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(mode.label)
			GameTooltip:AddLine(mode.tip, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
		button.mode = mode
		modes[index] = button
	end
	window.modeButtons = modes

	local removeLosing = HeaderButton(window.frame, "Remove losing", 124, function()
		local losing = 0
		for _, net in pairs(ns.totals.entries) do
			if net < 0 then losing = losing + 1 end
		end
		if losing > 0 then StaticPopup_Show("CFF_REMOVE_LOSING", ns.Plural(losing, "entry", "entries")) end
	end)
	-- In the footer beside the note about losing entries: the top row's right side belongs to the stale-price banner.
	removeLosing:SetPoint("BOTTOMRIGHT", -10, 55)
	removeLosing:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Remove losing entries")
		GameTooltip:AddLine("Removes the queue entries shaded red: at current prices they'd sell for less than "
			.. "their materials cost. Asks first.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	removeLosing:SetScript("OnLeave", GameTooltip_Hide)
	window.removeLosingButton = removeLosing

	local craftButton = CreateCraftBar(window.frame, 40)
	window.craftButton = craftButton
	craftButton:SetPoint("BOTTOMLEFT", 10, 10)
	craftButton:SetPoint("BOTTOMRIGHT", -10, 10)

	local status = window.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("BOTTOMLEFT", 12, 54)
	status:SetPoint("BOTTOMRIGHT", -12, 54)
	status:SetHeight(24)
	status:SetJustifyH("LEFT")
	status:SetJustifyV("BOTTOM")

	local detail = window.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	detail:SetPoint("BOTTOMLEFT", 12, 80)
	detail:SetPoint("BOTTOMRIGHT", -12, 80)
	detail:SetHeight(26)
	detail:SetJustifyH("LEFT")
	detail:SetJustifyV("BOTTOM")

	local total = window.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	window.totalText = total
	total:SetPoint("BOTTOMLEFT", 12, 110)
	total:SetPoint("BOTTOMRIGHT", -150, 110)
	total:SetJustifyH("LEFT")

	-- Quote margin, beside the total: the top row's right side belongs to the stale-price banner.
	local margin, marginLabel = NumberBox(window.frame, "Quote margin %", nil, ns.Queue.QuoteMargin,
		ns.Queue.SetQuoteMargin, "queue")
	window.marginBox = margin
	margin:ClearAllPoints()
	margin:SetPoint("BOTTOMRIGHT", -14, 108)
	marginLabel:ClearAllPoints()
	marginLabel:SetPoint("RIGHT", margin, "LEFT", -8, 0)
	margin:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Quote margin")
		GameTooltip:AddLine(("Added to the material cost when you press Quote. 0 to %d%%; press Enter to save.")
			:format(ns.Queue.QUOTE_MARGIN_MAX), 1, 1, 1, true)
		GameTooltip:Show()
	end)
	margin:SetScript("OnLeave", GameTooltip_Hide)

	window.clearButton = clear
	window.update = function()
		margin:Sync()
		clear:SetEnabled(#ns.db.queue > 0)
		local totals = ns.totals
		local farming = ns.db.ui.farmMode and true or false
		for _, button in ipairs(modes) do
			local on = button.mode.farm == farming
			button:SetText(on and ("|cffffffff" .. button.mode.label .. "|r") or button.mode.label)
			if on then button:LockHighlight() else button:UnlockHighlight() end
		end
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

		local craft, count, reason, blocking, open = ns.Queue.NextCraft()
		craftButton:Update(craft, count, blocking, open)
		if open then reason = nil end -- the button itself says it opens the profession

		local notes = {}
		if reason then table.insert(notes, reason) end
		local losing = 0
		for _, net in pairs(totals.entries) do
			if net < 0 then losing = losing + 1 end
		end
		removeLosing:SetShown(losing > 0)
		status:SetPoint("BOTTOMRIGHT", losing > 0 and -140 or -12, 54)
		removeLosing:SetText(("Remove losing (%d)"):format(losing))
		if losing > 0 then
			table.insert(notes, losing == 1 and "1 entry would now lose money (shaded red)."
				or (losing .. " entries would now lose money (shaded red)."))
		end
		if totals.excluded > 0 and (totals.counted > 0 or totals.bound > 0) then
			table.insert(notes, totals.excluded == 1 and "1 queued recipe has no price and isn't in the total."
				or (totals.excluded .. " queued recipes have no price and aren't in the total."))
		end
		if totals.bound > 0 and totals.counted > 0 then
			table.insert(notes, (totals.bound == 1 and "1 bind-on-pickup craft costs %s and isn't in the profit."
				or (totals.bound .. " bind-on-pickup crafts cost %s and aren't in the profit.")):format(ns.Money(totals.boundCost)))
		end
		local shopping = ns.Shopping.status
		if shopping.error then table.insert(notes, "List update failed. See /cff diag.") end
		if shopping.loading > 0 then table.insert(notes, ns.Plural(shopping.loading, "item name", "item names") .. " loading.") end
		if not ns.Stock.HasSyndicator() then table.insert(notes, "Syndicator not active: alts not counted.") end
		status:SetText(table.concat(notes, " "))
	end
end

-- The Next step bar: a small window at the top of the screen with the first step of the queue's to-do list. It
-- exists only while something is queued, opens by itself, and can be folded down to its title line, which still
-- names the step. Not a tab: it stays up while you play. In Farm It mode it's also the list of what to gather and
-- where, with a Buy It button to go back to buying.
local NEXT_WIDTH = 300
local NEXT_MAX_ROWS = 10
local NEXT_MAX_ROWS_FARMING = 16 -- every gathering group at once
local NEXT_BUTTON_ROOM = 42

local function CreateNextWindow()
	local frame = CreateFrame("Frame", "CFFNextStep", UIParent, "BackdropTemplate")
	local window = { key = "next", frame = frame, list = {}, offset = 0, rows = {}, mini = true, maxRows = NEXT_MAX_ROWS }
	windows.next = window
	MakeMovable(frame, "next")
	frame:SetFrameStrata("MEDIUM") -- under the main window and dialogs, as it's always there
	frame:SetSize(NEXT_WIDTH, MINI_TOP + 8)
	frame:SetBackdropColor(0.05, 0.05, 0.07, 0.85)

	local fold = HeaderButton(frame, "-", 22, function()
		ns.db.ui.nextMinimized = not ns.db.ui.nextMinimized or nil
		UI.Refresh("next")
	end)
	fold:SetHeight(18)
	fold:SetPoint("TOPRIGHT", -6, -5)
	fold:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(ns.db.ui.nextMinimized and "Show the step" or "Fold away")
		GameTooltip:AddLine("Folded, the title line still names the step. It goes away by itself when the queue is "
			.. "empty. Drag the window to move it.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	fold:SetScript("OnLeave", GameTooltip_Hide)
	window.foldButton = fold

	local buy = HeaderButton(frame, "Buy It", 54, function() ns.ToggleFarmMode() end)
	buy:SetHeight(18)
	buy:SetPoint("RIGHT", fold, "LEFT", -2, 0)
	buy:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Buy It")
		GameTooltip:AddLine("Back to buying materials instead of gathering them: opens the queue.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	buy:SetScript("OnLeave", GameTooltip_Hide)
	window.buyButton = buy

	local count = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	window.countText = count

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -8)
	title:SetPoint("RIGHT", count, "LEFT", -6, 0)
	title:SetJustifyH("LEFT")
	title:SetHeight(14)
	if title.SetWordWrap then title:SetWordWrap(false) end
	window.titleText = title

	CreateListArea(window, frame, 10, MINI_TOP, 6, MINI_ROW_HEIGHT)
	for _, row in ipairs(window.rows) do row.icon:SetSize(14, 14) end

	local craft = CreateCraftBar(frame, 38)
	craft:SetPoint("BOTTOMLEFT", 10, 8)
	craft:SetPoint("BOTTOMRIGHT", -10, 8)
	window.craftButton = craft

	-- The list area's bottom moves up when the Craft Next button is there.
	local function SetFooter(footer)
		window.container:SetPoint("BOTTOMRIGHT", -24, footer)
		window.slider:SetPoint("BOTTOMRIGHT", -10, footer)
	end

	window.build = function()
		local step, steps, rows = BuildNextStep()
		window.step, window.steps = step, steps
		local folded = ns.db.ui.nextMinimized
		local list = {}
		window.nextCraft, window.nextCount, window.blocking, window.open, window.crafting = nil, nil, nil, nil, false
		window.maxRows = ns.db.ui.farmMode and NEXT_MAX_ROWS_FARMING or NEXT_MAX_ROWS
		window.gatherGroups = 0
		if step and step.gather then
			window.gatherGroups = 1
			for _, row in ipairs(rows) do
				if row.kind == "header" then window.gatherGroups = window.gatherGroups + 1 end
			end
		end
		-- Farming, this is the only window up, and what's worth gathering depends on prices too.
		if ns.db.ui.farmMode and not folded and ns.Prices.IsStale() then
			table.insert(list, { kind = "warn", text = ScanAgeText() .. " Scan at the AH." })
		end
		if step and not folded then
			table.insert(list, { kind = "header", text = ShortStepTitle(step.text) })
			for _, row in ipairs(rows) do table.insert(list, row) end
			if step.crafting then
				local nextCraft, nextCount, reason, blocking, open = ns.Queue.NextCraft()
				window.nextCraft, window.nextCount, window.blocking, window.open = nextCraft, nextCount, blocking, open
				window.crafting = true
				if not nextCraft and reason and not open then table.insert(list, { kind = "note", text = reason }) end
			end
		end
		-- On a crafting step the button stays, saying what to finish while it can't craft.
		local button = window.crafting
		local footer = button and NEXT_BUTTON_ROOM + 6 or 6
		SetFooter(footer)
		window.container:SetShown(not folded)
		frame:SetHeight(folded and (MINI_TOP + 2)
			or (MINI_TOP + math.min(#list, window.maxRows) * MINI_ROW_HEIGHT + footer + 2))
		return list
	end

	window.update = function()
		local folded = ns.db.ui.nextMinimized
		local step = window.step
		fold:SetText(folded and "+" or "-")
		local farming = ns.db.ui.farmMode and true or false
		buy:SetShown(farming)
		count:ClearAllPoints()
		count:SetPoint("RIGHT", farming and buy or fold, "LEFT", -6, 0)
		if folded and step then
			local name = window.gatherGroups > 1 and "Gather materials" or ShortStepTitle(step.text)
			title:SetText("Next: " .. Color("ffffffff", name))
		else
			title:SetText(farming and "Next step  " .. Color(COLOR_MUTED, "Farm It") or "Next step")
		end
		count:SetText(window.steps > 1 and Color(COLOR_MUTED, ("1 of %d"):format(window.steps)) or "")
		if window.crafting and not folded then
			craft:Show()
			craft:Update(window.nextCraft, window.nextCount, window.blocking, window.open)
		else
			craft:Hide()
		end
	end

	frame:HookScript("OnShow", function() UI.Refresh("next") end)
end

-- Shown while anything is queued, gone the moment the queue is empty.
local inCombat = false

-- Out of the way in combat, dungeons, raids, battlegrounds and arenas: nothing to craft or gather there.
local function NextStepAllowed()
	if inCombat then return false end
	local inInstance = IsInInstance()
	return not inInstance
end

function UpdateNextStep()
	if not ns.db or #ns.db.queue == 0 or not NextStepAllowed() then
		if windows.next then windows.next.frame:Hide() end
		return
	end
	if not windows.next then CreateNextWindow() end
	local frame = windows.next.frame
	if frame:IsShown() then
		UI.Refresh("next")
		return
	end
	local saved = ns.db.ui.positions and ns.db.ui.positions.next
	frame:ClearAllPoints()
	if saved then
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
	else
		frame:SetPoint("TOP", UIParent, "TOP", 0, -12)
	end
	frame:Show()
end

function UI.ToggleNextStep()
	if #ns.db.queue == 0 then
		ns.Print("The queue is empty, so there's no next step.")
		return
	end
	if not NextStepAllowed() then
		ns.Print("The Next step bar is hidden in combat and in dungeons, raids and battlegrounds.")
		return
	end
	ns.db.ui.nextMinimized = not ns.db.ui.nextMinimized or nil
	UpdateNextStep()
	UI.Refresh("next")
end

-- Craft Next depends on which profession is open.
ns.On("TRADE_SKILL_CLOSE", function() UI.Refresh("next") end)
ns.On("PLAYER_REGEN_DISABLED", function()
	inCombat = true
	UpdateNextStep()
end)
ns.On("PLAYER_REGEN_ENABLED", function()
	inCombat = false
	UpdateNextStep()
end)
-- Logging in or reloading mid-fight, and entering or leaving an instance (zone changes refresh the queue already).
ns.On("PLAYER_ENTERING_WORLD", function()
	inCombat = InCombatLockdown() and true or false
	UpdateNextStep()
end)

-- A labelled number box in the restock footer. Saves on Enter or when it loses focus.

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

	local stack = NumberBox(window.frame, "Default goal: stackable", nil,
		function() return ns.db.restock.stackGoal end, function(v) ns.db.restock.stackGoal = v end)
	local single = NumberBox(window.frame, "single", stack,
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
		for _, data in ipairs(window.list) do
			if data.row then table.insert(rows, data.row) end
		end
		local added = ns.Restock.Apply(rows, selectedProfession.restock)
		ns.Print(("Restock: %s added to the queue."):format(ns.Plural(added, "item", "items")))
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

		local needed, toPost, items = 0, 0, 0
		for _, data in ipairs(self.list) do
			local row = data.row
			if row then
				items = items + 1
				if row.crafts > 0 then needed = needed + 1 end
				if row.goal > 0 and (row.onAH or 0) < row.goal then
					toPost = toPost + math.min(row.owned, row.goal - (row.onAH or 0))
				end
			end
		end

		if not ns.Stock.HasSyndicator() then
			apply:Disable()
			apply:SetText("Queue restock")
			status:SetText("Syndicator is needed to see your auctions. Without it this would over-craft.")
			return
		end
		apply:SetEnabled(needed > 0)
		apply:SetText(needed > 0 and ("Queue restock: %s"):format(ns.Plural(needed, "item", "items")) or "Fully stocked")
		local notes = { "AH counts update when you visit the auction house." }
		if toPost > 0 then
			table.insert(notes, 1, (toPost == 1 and "1 item you hold is" or (toPost .. " items you hold are"))
				.. " ready to post, from the auction house's Restocking tab.")
		end
		if items == 0 then notes = { "No profitable items yet. Open your professions and scan the AH." } end
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
		elseif key == "sales" then
			CreateSalesPane()
		else
			local frame = CreateFrame("Frame", nil, main.frame)
			frame:Hide()
			windows.changelog = { key = "changelog", frame = frame, update = ns.WhatsNew.BuildPane(frame, PANE_LIST_TOP) }
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

-- Size: one width for the window alone and one with the queue beside Restock, and one height for both. Dragging the
-- corner changes the one in use.
local function SizeLimits(beside)
	local minWidth = beside and BESIDE_MIN_WIDTH or MAIN_WIDTH
	local maxWidth = math.max(minWidth, math.floor(UIParent:GetWidth() or minWidth))
	local maxHeight = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, math.floor(UIParent:GetHeight() or MAX_HEIGHT)))
	return minWidth, maxWidth, maxHeight
end

local function SavedSize(beside)
	local ui = ns.db.ui
	local minWidth, maxWidth, maxHeight = SizeLimits(beside)
	local width
	if beside then width = ui.besideWidth or BESIDE_WIDTH else width = ui.width or MAIN_WIDTH end
	width = math.max(minWidth, math.min(width, maxWidth))
	-- Only a saved height is fitted to the screen; the default is left as it always was.
	local height = ui.height and math.max(MIN_HEIGHT, math.min(ui.height, maxHeight)) or WINDOW_HEIGHT
	return width, height
end

local function SetSizeLimits(beside)
	local frame = main.frame
	local minWidth, maxWidth, maxHeight = SizeLimits(beside)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(minWidth, MIN_HEIGHT, maxWidth, maxHeight)
	elseif frame.SetMinResize then
		frame:SetMinResize(minWidth, MIN_HEIGHT)
		frame:SetMaxResize(maxWidth, maxHeight)
	end
end

local function SaveSize()
	local width, height = main.frame:GetWidth(), main.frame:GetHeight()
	if not (width and height) then return end
	width, height = math.floor(width + 0.5), math.floor(height + 0.5)
	if QueueBeside() then ns.db.ui.besideWidth = width else ns.db.ui.width = width end
	ns.db.ui.height = height
end

-- Anchors the showing panes to the window: one pane fills it, or Restock and the queue share it.
local function PlacePanes()
	local beside = QueueBeside()
	local split = math.floor((main.frame:GetWidth() or 0) * RESTOCK_SHARE)
	main.divider:ClearAllPoints()
	main.divider:SetPoint("TOPLEFT", split, -MAIN_TOP)
	main.divider:SetPoint("BOTTOMLEFT", split, 6)
	main.divider:SetShown(beside)
	for key, pane in pairs(windows) do
		if pane.frame:GetParent() == main.frame and pane.frame:IsShown() then
			if not beside then
				PlacePane(pane, 0)
			elseif key == "restock" then
				PlacePane(pane, 0, split)
			else
				PlacePane(pane, split)
			end
		end
	end
end

-- Shows the selected tab's pane, with the queue beside Restock when asked for, and redraws what's showing.
local function Layout()
	local active, beside = ActiveTab(), QueueBeside()
	if amountPopup then amountPopup:Hide() end
	SetSizeLimits(beside)
	main.frame:SetSize(SavedSize(beside))
	PlaceMain()
	local showing = {}
	for _, tab in ipairs(MAIN_TABS) do
		local key = tab.key
		if key == active or (beside and key == "queue") then
			GetPane(key).frame:Show()
			table.insert(showing, key)
		elseif windows[key] then
			windows[key].frame:Hide()
		end
	end
	PlacePanes()
	for _, key in ipairs(showing) do UI.Refresh(key) end
	UpdateTabStrip()
end

local function CreateMain()
	local frame = CreateFrame("Frame", "CFFWindow", UIParent, "BackdropTemplate")
	main = { frame = frame, tabButtons = {} }
	UI.main = main
	MakeMovable(frame, "main")
	frame:SetSize(MAIN_WIDTH, WINDOW_HEIGHT)
	table.insert(UISpecialFrames, "CFFWindow") -- Escape closes it, like the game's own windows

	-- The full name is too long for one line beside the tabs, so it's the logo and the name on two lines. The tabs
	-- start wherever the name ends, so a wider font can't push it under them.
	local logo = frame:CreateTexture(nil, "ARTWORK")
	logo:SetSize(28, 28)
	logo:SetPoint("TOPLEFT", 8, -4)
	logo:SetTexture(LOGO_TEXTURE)
	main.logo = logo

	local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	titleText:SetPoint("LEFT", logo, "RIGHT", 5, 0)
	titleText:SetJustifyH("LEFT")
	titleText:SetText("Crafting and Farming\nForever")
	main.titleText = titleText

	for index, info in ipairs(MAIN_TABS) do
		local tab = CreateFrame("Button", nil, frame)
		tab:SetSize(MAIN_TAB_WIDTH, MAIN_TAB_HEIGHT)
		if index == 1 then
			tab:SetPoint("LEFT", titleText, "RIGHT", 10, 0)
			tab:SetPoint("TOP", frame, "TOP", 0, -7)
		else
			tab:SetPoint("TOPLEFT", main.tabButtons[index - 1], "TOPRIGHT", 2, 0)
		end
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
		tab.badge = tab:CreateTexture(nil, "OVERLAY")
		tab.badge:SetColorTexture(0.33, 0.87, 0.33, 1)
		tab.badge:SetSize(6, 6)
		tab.badge:SetPoint("TOPRIGHT", -4, -4)
		tab.badge:Hide()
		main.tabButtons[index] = tab
	end

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 0, 0)
	close:SetScript("OnClick", function() frame:Hide() end)

	local refresh = HeaderButton(frame, "Refresh", 70, function() ns.RefreshEverything() end)
	refresh:SetHeight(20)
	refresh:SetPoint("RIGHT", close, "LEFT", -2, 0)
	refresh:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Refresh")
		GameTooltip:AddLine("Re-reads your recipes, item data, prices from Auctionator and stock, then redraws "
			.. "everything. At the auction house it also re-reads your auctions.", 1, 1, 1, true)
		GameTooltip:AddLine("It doesn't scan the auction house. Scan with Auctionator, or with Scan now when prices "
			.. "are old.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	refresh:SetScript("OnLeave", GameTooltip_Hide)

	local rule = frame:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(0.5, 0.5, 0.5, 0.5)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 6, -MAIN_TOP + 1)
	rule:SetPoint("TOPRIGHT", -6, -MAIN_TOP + 1)

	main.divider = frame:CreateTexture(nil, "ARTWORK")
	main.divider:SetColorTexture(0.5, 0.5, 0.5, 0.5)
	main.divider:SetWidth(1)

	-- Drag the corner to resize; right-click it for the default size.
	frame:SetResizable(true)
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -3, 3)
	grip:SetFrameLevel((frame:GetFrameLevel() or 0) + 20) -- above the panes
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:RegisterForClicks("RightButtonUp")
	grip:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
	end)
	grip:SetScript("OnMouseUp", function(_, button)
		if button ~= "LeftButton" then return end
		frame:StopMovingOrSizing()
		SaveSize()
		SavePosition("main", frame)
		PlaceMain() -- sizing leaves the window anchored differently; back to the top left
	end)
	grip:SetScript("OnClick", function() UI.ResetSize() end)
	grip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Resize")
		GameTooltip:AddLine("Drag to resize the window. Right-click for the default size.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	grip:SetScript("OnLeave", GameTooltip_Hide)
	main.grip = grip
	frame:SetScript("OnSizeChanged", function() PlacePanes() end)

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

function UI.ResetSize()
	if QueueBeside() then ns.db.ui.besideWidth = nil else ns.db.ui.width = nil end
	ns.db.ui.height = nil
	if UI.IsOpen() then Layout() end
end

UI.SaveSize = function() SaveSize() end

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

-- The Next step bar stays up on its own, so this leaves it alone.
function UI.ToggleMain()
	if UI.IsOpen() then
		UI.Hide()
	else
		UI.Show(ActiveTab())
	end
end

-- Farm It closes the main window, leaving the Next step bar to follow while you gather; Buy It brings the queue back.
function UI.FarmModeChanged()
	if ns.db.ui.farmMode then
		UI.Hide()
	else
		UI.Show("queue")
	end
	UI.RefreshQueue()
end

ns.On("ZONE_CHANGED_NEW_AREA", function() UI.RefreshQueue() end)

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

	local form = page.SchematicForm
	if form then
		-- On the recipe's own pane, under the favourite star: clear of long names, which run left to right along the top.
		queueButton = CreateFrame("Button", "CFFQueueButton", form, "UIPanelButtonTemplate")
		queueButton:SetSize(64, 22)
		queueButton:SetPoint("TOPRIGHT", form, "TOPRIGHT", -12, -47)
		queueButton:SetText("Queue")
		UI.queueButton = queueButton
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
			GameTooltip:SetText("Add to Crafting and Farming Forever queue")
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

-- Once a session: at login, or when a profession opens, whichever comes first.
ns.On("PLAYER_LOGIN", function() C_Timer.After(10, NotifyStale) end)

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
function Advertise.DestinationLabel()
	return CurrentDestination().label
end

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
function Advertise.QuoteInWhisper(recipeID, crafts)
	local text = ns.Queue.QuoteText(recipeID, crafts)
	if not text then
		ns.Print("A material has no price yet, so there's nothing to quote. Scan the auction house first.")
		return
	end
	-- A customer gets this price, so say so every time, not once a session.
	if ns.Prices.IsStale() then
		ns.Print(Color(COLOR_WARN, UI.ScanAgeText() .. " This quote may be off: scan the auction house before you send it."))
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
	adBox = CreateFrame("Button", "CFFAdBox", UIParent, "UIPanelButtonTemplate")
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

	destinationButton = CreateFrame("Button", "CFFAdDestination", UIParent, "UIPanelButtonTemplate")
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
		button = CreateFrame("Button", "CFFAdvertiseButton" .. index, UIParent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
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

StaticPopupDialogs["CFF_CLEAR_QUEUE"] = {
	text = "Crafting and Farming Forever: %s",
	button1 = YES,
	button2 = NO,
	OnAccept = function() ns.Queue.Clear() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["CFF_REMOVE_LOSING"] = {
	text = "Crafting and Farming Forever: remove %s that would lose money at current prices?",
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		local removed = ns.Queue.RemoveLosing()
		ns.Print(("Removed %s that would lose money."):format(ns.Plural(removed, "entry", "entries")))
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["CFF_SCAN"] = {
	text = "Crafting and Farming Forever: %s Run a new auction house scan now?",
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
			StaticPopup_Show("CFF_SCAN", ScanAgeText())
		end
		-- Once per visit, the way to the list, when there's something on it.
		if next(ns.plan.buy) and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
			ns.Print(('Materials to buy: click the Shopping tab at the bottom of the auction house (Auctionator), '
				.. 'then the list "%s".'):format(ns.LIST_NAME))
		end
		UI.RefreshAll()
	end)
end)

ns.On("PLAYER_MONEY", UI.RefreshQueue)

ns.On("AUCTION_HOUSE_CLOSED", function()
	StaticPopup_Hide("CFF_SCAN")
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

SLASH_CFF1 = "/cff"
SLASH_CFF2 = "/craftfarm"
SlashCmdList.CFF = function(input)
	local command = (input or ""):lower():match("^%s*(%S*)")
	if command == "new" then command = "changelog" end
	if command == "queue" or command == "profit" or command == "restock" or command == "sales" or command == "changelog" then
		UI.Toggle(command)
	elseif command == "next" then
		UI.ToggleNextStep()
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
		ns.Print("/cff [profit | queue | restock | sales | changelog | next | advertise | refresh | clear | auto | diag]")
	end
end
