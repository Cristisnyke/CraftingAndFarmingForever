-- Crafting and Farming Forever :: UI
-- One tabbed window anchored to the screen (Profit, Queue, Restock, Sales, Options, Changelog; the queue can sit beside
-- Restock; the Options tab's contents are in Options.lua), the small
-- Next step bar, the Queue button on the crafting page, the stale-price prompts and the slash command.

local _, ns = ...

local UI = {}
ns.UI = UI

local ROW_HEIGHT = 22
local ROW_GLOW = 0.16 -- how strongly a row lights up under the mouse
local ROW_COUNT = 48 -- enough for the tallest window
local MAIN_WIDTH = 797 -- default and narrowest width: eight tabs beside Refresh
local BESIDE_WIDTH = 1240 -- default width with the queue beside Restock
local BESIDE_MIN_WIDTH = 1180
local RESTOCK_SHARE = 0.45 -- Restock's share of the width with the queue beside it
local WINDOW_HEIGHT = 560
local MIN_HEIGHT, MAX_HEIGHT = 460, 1100
local MAIN_TOP = 36 -- title and tabs
local MAIN_TAB_WIDTH, MAIN_TAB_HEIGHT = 65, 26
local LOGO_TEXTURE = "Interface\\AddOns\\CraftingAndFarmingForever\\Media\\Logo"
local MAIN_TABS = {
	{ key = "profit", title = "Profit" },
	{ key = "queue", title = "Queue" },
	{ key = "restock", title = "Restock" },
	{ key = "sales", title = "Sales" },
	{ key = "writs", title = "Writs" },
	{ key = "crates", title = "Crates" },
	{ key = "options", title = "Options" },
	{ key = "changelog", title = "Changelog" },
}
local PANE_ACTIONS_TOP = 4
local PANE_LIST_TOP = 30
local SALES_TILE_TOP, SALES_TILE_HEIGHT = 32, 54 -- the summary boxes above the Sales list
local TAB_WIDTH = 112
local TAB_COUNT = 16
local MINI_ROW_HEIGHT = 15
local MINI_TOP = 26
local COLOR_PROFIT, COLOR_LOSS, COLOR_MUTED = "ff55dd55", "ffff6655", "ff999999"

-- One blue palette for every window, button and list, the same family as the Craft Next bar.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local THEME = {
	bg = { 0.04, 0.05, 0.075 },
	header = { 0.065, 0.095, 0.15 },
	border = { 0.16, 0.27, 0.44 },
	accent = { 0.27, 0.58, 1.00 },
	button = { 0.085, 0.14, 0.235 },
	buttonEdge = { 0.20, 0.34, 0.56 },
	primary = { 0.13, 0.36, 0.70 },
	primaryEdge = { 0.34, 0.60, 0.98 },
	field = { 0.02, 0.03, 0.05 },
}
UI.THEME = THEME

-- A dark fill with a one-pixel edge, drawn behind a button or a box.
local function FlatBox(frame, fill, edge, left, right)
	local border = frame:CreateTexture(nil, "BACKGROUND")
	border:SetPoint("TOPLEFT", left or 0, 0)
	border:SetPoint("BOTTOMRIGHT", right or 0, 0)
	border:SetColorTexture(edge[1], edge[2], edge[3], 1)
	local inside = frame:CreateTexture(nil, "BORDER")
	inside:SetPoint("TOPLEFT", border, "TOPLEFT", 1, -1)
	inside:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -1, 1)
	inside:SetColorTexture(fill[1], fill[2], fill[3], 1)
end
UI.FlatBox = FlatBox

-- The add-on's own button: flat, lights up under the mouse (and while LockHighlight marks it selected), dims when
-- disabled. primary is the brighter blue of a pane's main action.
local function FlatButton(parent, text, width, height, primary, name, template)
	local button = CreateFrame("Button", name, parent, template)
	button:SetSize(width, height)
	FlatBox(button, primary and THEME.primary or THEME.button, primary and THEME.primaryEdge or THEME.buttonEdge)
	button:SetHighlightTexture(WHITE, "ADD")
	local glow = button:GetHighlightTexture()
	if glow then glow:SetVertexColor(0.30, 0.55, 1, 0.30) end
	button:SetDisabledTexture(WHITE)
	local dim = button:GetDisabledTexture()
	if dim then dim:SetVertexColor(0.02, 0.03, 0.05, 0.6) end
	button:SetNormalFontObject("GameFontHighlightSmall")
	button:SetHighlightFontObject("GameFontHighlightSmall")
	button:SetDisabledFontObject("GameFontDisableSmall")
	button:SetPushedTextOffset(1, -1)
	button:SetText(text or "")
	return button
end
UI.FlatButton = FlatButton

-- The game's input box without its rounded border, on the theme's dark field. Left alone if the template's parts
-- aren't where they're expected.
local function SkinBox(box)
	if type(box.Left) ~= "table" or type(box.Middle) ~= "table" or type(box.Right) ~= "table" then return box end
	box.Left:SetAlpha(0)
	box.Middle:SetAlpha(0)
	box.Right:SetAlpha(0)
	FlatBox(box, THEME.field, THEME.buttonEdge, -5, 2)
	return box
end
UI.SkinBox = SkinBox

local function ThemeBackdrop(frame, alpha)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	frame:SetBackdropColor(THEME.bg[1], THEME.bg[2], THEME.bg[3], alpha or 0.97)
	frame:SetBackdropBorderColor(THEME.border[1], THEME.border[2], THEME.border[3], 1)
end
UI.ThemeBackdrop = ThemeBackdrop

local function Color(hex, text)
	return "|c" .. hex .. text .. "|r"
end
UI.Color = Color

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
local CreateWritsPane, CreateCratesPane
local UpdateNextStep
local profitCache
local profitSearch = "" -- the Profit search box's text, trimmed and lowercase
local scanNotified = false

---------------------------------------------------------------------------
-- Profit data
---------------------------------------------------------------------------

-- The redraw waits a moment, so a burst of price updates (searches at the auction house) redraws once.
local function RedrawProfit()
	UI.Refresh("profit")
	UI.Refresh("restock")
end

function ns.InvalidateProfit()
	profitCache = nil
	if ns.Sales then ns.Sales.ForgetCraftInfo() end
	ns.Debounce("profit", 0.1, RedrawProfit)
end

-- Every recipe known on any character that makes an item, most profitable first. Results that can't be sold on the
-- AH (bind on pickup) are flagged bound and have no sale or profit, only a cost; they follow the priced ones.
-- The Profit tab prices each recipe for the crafts its restock goal makes (the user's choice, 2026-11-19): buying
-- materials for five crafts can cost more per craft than one, once the cheapest listings run out. The goal without
-- your gold's limit, at least one craft.
local function ProfitBatch(recipe)
	local goal = ns.Restock.FullGoal(recipe.o)
	if not goal or goal <= 0 then return 1 end
	return math.max(1, math.ceil(goal / math.max(1, recipe.qmin or 1)))
end

-- What the Profit tab's numbers were worked out from, besides prices: listings read and restock goals.
local function ProfitKey()
	local restock = ns.db.restock
	local parts = { ns.Depth.version, restock.stackGoal, restock.singleGoal, ns.Restock.SmartLevel(), tostring(ns.Restock.SmartOn()) }
	for itemID, goal in pairs(restock.goals) do parts[#parts + 1] = itemID .. "=" .. goal end
	return table.concat(parts, ",")
end

local function ComputeProfit()
	local ctx = ns.NewContext()
	local results = {}
	local seen = {}
	for key, char in pairs(ns.db.chars) do
		-- Characters left out on the Options tab add no recipes.
		for recipeID in pairs(ns.CharExcluded(key) and {} or char.recipes) do
			if not seen[recipeID] then
				seen[recipeID] = true
				local recipe = ns.db.recipes[recipeID]
				-- CanSellOnAH is nil while loading: left out now, added by the refresh when the data arrives.
				local sellable = recipe and recipe.o and ns.Items.CanSellOnAH(recipe.o)
				if sellable ~= nil then
					local result = ns.Planner.Profit(ctx, recipeID, sellable and ProfitBatch(recipe) or nil)
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
	-- Recipes: by the skill needed, lowest first; names A to Z; source in a fixed order (trainer, vendor, quest, ...);
	-- the recipe's auction house price, cheapest first; profit per craft, highest first; fewest crafts to pay back first.
	recipes = { key = "recipeSort", asc = "recipeSortAsc", default = "chance",
		ascending = { name = true, chance = true, cost = true, profit = true, net = false, back = true } },
	-- Writs: names and hand-in zones A to Z, the writ's price lowest first, the gold kept highest first, gold per
	-- reputation lowest first.
	writs = { key = "writSort", asc = "writSortAsc", default = "profit", pane = "writs",
		ascending = { name = true, zone = true, chance = true, cost = false, profit = true } },
	-- Crates: names A to Z, the crate's price lowest first, the most Merchant's Favor first, gold per Favor lowest first.
	crates = { key = "crateSort", asc = "crateSortAsc", default = "profit", pane = "crates",
		ascending = { name = true, chance = true, cost = false, profit = true } },
}

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
	local pane = sort.pane or "profit"
	if windows[pane] then windows[pane].offset = 0 end
	UI.Refresh(pane)
end

function UI.ProfitSort() return UI.ListSort("profit") end

-- What a recipe sorts by. Nil (no price, no sales data, name still loading) always goes last.
local function SortValue(result, key)
	local name = ns.Items.Name(result.itemID)
	if key == "name" then return name and name:lower() end
	if key == "chance" then return not result.bound and name and ns.Sales.Chance(name) or nil end
	return result.net
end

-- Levelling mode: recipe colours as the game shows them, and what each colour means here.
local SKILL = {
	COLORS = { [0] = "ffff8040", [1] = "ffffff00", [2] = "ff40bf40", [3] = "ff808080" },
	CHANCE_TEXT = { [0] = "100%", [1] = "~50%", [2] = "~25%", [3] = "none" },
	NAMES = { [0] = "Orange", [1] = "Yellow", [2] = "Green", [3] = "Grey" },
	MEANING = { [0] = "a skill point every craft", [1] = "a skill point about every other craft",
		[2] = "a skill point now and then", [3] = "no more skill points" },
}

-- Tooltip line: how hard a craft is for the character making it (the profession window's colour).
-- A levelling cost: white, or green with + when selling what the craft makes earns more than it costs.
function SKILL.CostText(copper)
	if copper < 0 then return Color(COLOR_PROFIT, "+" .. ns.Money(-copper)) end
	return ns.Money(copper)
end

function SKILL.AddLine(recipeID, charKey)
	local difficulty, points = ns.Recipes.Difficulty(charKey, recipeID)
	if not SKILL.NAMES[difficulty] then
		GameTooltip:AddLine("Difficulty: unknown until " .. ns.CharLabel(charKey) .. " opens the profession.", 0.6, 0.6, 0.6, true)
		return
	end
	local meaning = SKILL.MEANING[difficulty]
	if difficulty < 3 and (points or 1) > 1 then meaning = meaning:gsub("a skill point", points .. " skill points") end
	GameTooltip:AddLine(Color(SKILL.COLORS[difficulty], SKILL.NAMES[difficulty]) .. ": " .. meaning, 1, 1, 1, true)
end

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
	-- What selling the results gets back: the vendor's price always, the auction house's when ticked.
	local rows = ns.Planner.SkillUpRows(ns.NewContext(), entries, { sellPrice = ns.Items.SellPrice,
		ahSellable = ns.db.ui.skillSellAH and ns.Items.CanSellOnAH or nil, ahShown = ns.Items.CanSellOnAH })
	-- The planner's order (cheapest per skill point) is the default and the tie-break.
	local key, ascending = UI.ListSort("skill")
	if key ~= "profit" or not ascending then
		local order, values = {}, {}
		for index, row in ipairs(rows) do
			local recipe = ns.db.recipes[row.recipeID]
			order[row] = index
			values[row] = key == "name" and recipe and recipe.n and recipe.n:lower()
				or key == "chance" and row.chance
				or key == "cost" and row.net
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

-- Recipes mode: every recipe of the professions looked at, against one character (default) or all of them.
-- COLORS by status: green can be learned now, white needs more skill, grey learned, dim nobody has the profession.
local RECIPE = {
	COLORS = { learn = "ff40bf40", skill = "ffffffff", learned = "ff808080", none = "ff999999" },
	SKILL_SHORT = "ffff6655", -- the skill needed, when it's more than the character has
	WHO = "ff99ccff",
	NAMES_ON_ROW = 2,
}

-- The Profit column: one craft's profit; BoP when what it makes binds; - for no item; ? while not known.
function RECIPE.ProfitText(item)
	if item.madeBound then return Color(COLOR_MUTED, "BoP") end
	if item.made == false then return Color(COLOR_MUTED, "-") end
	if not item.net then return Color(COLOR_MUTED, "?") end
	return Color(item.net >= 0 and COLOR_PROFIT or COLOR_LOSS, ns.Money(item.net))
end

-- The Pays back column: crafts until the recipe's auction house price is earned back.
function RECIPE.PaybackText(item)
	if item.payback == false then return Color(COLOR_LOSS, "never") end
	if not item.payback then return "" end
	return ns.Plural(item.payback, "craft", "crafts")
end

function RECIPE.Who()
	return ns.db.ui.recipeWho == "all" and "all" or "me"
end

-- Recipes this character has become able to learn since Recipes was last open: the Profit tab and the Recipes button
-- light up green with a dot, as the Changelog tab does for unread notes.
function RECIPE.NewCount()
	if not (ns.db and ns.RecipeBook) then return 0 end
	return ns.RecipeBook.NewCount(ns.CharKey())
end

local function BuildRecipeList()
	local who = RECIPE.Who()
	local me = ns.CharKey()
	-- Looking at the list is reading the news: the glow goes out.
	if ns.RecipeBook.MarkSeen(me) then UpdateTabStrip() end
	local rows, info = ns.RecipeBook.Rows({ professionID = selectedProfession.profit, who = who, me = me,
		showLearned = ns.db.ui.recipeLearned, search = profitSearch, hideBound = ns.db.ui.recipeHideBound })
	ns.RecipeBook.AddProfit(rows, ns.NewContext())
	local key, ascending = UI.ListSort("recipes")
	ns.RecipeBook.Sort(rows, key, ascending)
	local list = { recipes = true, info = info, who = who }
	if #rows == 0 then
		local text
		if profitSearch ~= "" then
			text = "No recipes match your search."
		elseif info.boundHidden > 0 then
			text = "Every recipe left here makes something that binds on pickup. Untick Hide BoP to list them."
		elseif info.learnedHidden > 0 then
			text = "Every recipe here is learned. Tick Show learned to list them."
		else
			text = "Open a profession on a character to record it, then its recipes show here."
		end
		table.insert(list, { kind = "note", text = text })
		return list
	end
	table.insert(list, { kind = "header", text = "Recipe", columns = "recipes" })
	table.insert(list, { kind = "tip", text = "Click any recipe for its Wowhead link: who sells it, what drops it." })
	for _, row in ipairs(rows) do table.insert(list, { kind = "recipe", row = row, who = who }) end
	return list
end

local function BuildProfitList()
	if ns.db.ui.profitMode == "skill" then return BuildSkillList() end
	if ns.db.ui.profitMode == "recipes" then return BuildRecipeList() end
	local cacheKey = ProfitKey()
	if not profitCache or profitCache.key ~= cacheKey then
		profitCache = ComputeProfit()
		profitCache.key = cacheKey
	end
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

-- charKey (optional): colour the name by how hard the craft is for that character, as the profession window does.
local function RecipeName(recipeID, charKey)
	local recipe = ns.db.recipes[recipeID]
	local name = recipe and recipe.n or ("Recipe " .. tostring(recipeID))
	local hex = charKey and SKILL.COLORS[ns.Recipes.Difficulty(charKey, recipeID)]
	return hex and Color(hex, name) or name
end

-- priceLabel and priceOf are for lists bought with gold: the price each row's quantity was costed at.
-- plan (optional): the plan these are bought for. What it pays for each item is the row's total, which is more than
-- price x count when buying that many goes past the cheapest listing (row.deep: worked out from the listings;
-- row.thin: units wanted beyond everything listed).
local function AddItemRows(list, title, items, priceLabel, priceOf, plan)
	local sorted = {}
	for itemID, count in pairs(items) do
		local price = priceOf and priceOf(itemID)
		table.insert(sorted, {
			kind = "item", itemID = itemID, count = count, priceLabel = priceLabel, price = price,
			total = plan and plan.paid[itemID] or (price and price * count),
			deep = plan and plan.deep[itemID] or nil, thin = plan and plan.thin[itemID] or nil,
		})
	end
	if #sorted == 0 then return end
	table.sort(sorted, function(a, b) return a.itemID < b.itemID end)
	if priceOf then
		local subtotal, allPriced = 0, true
		for _, row in ipairs(sorted) do
			if row.total then subtotal = subtotal + row.total else allPriced = false end
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

-- "a Blacksmith Hammer", "an Arclight Spanner".
local function WithArticle(name)
	return (name:match("^[AEIOUaeiou]") and "an " or "a ") .. name
end

-- Restock rows a camp station limits (row.camp, Planner.RestockStations; info = what it decided): why, in words.
function UI.RestockCampText(camp, info)
	local function Minutes(seconds) return math.max(1, math.ceil((seconds or 0) / 60)) end
	local station = WithArticle((camp.station:gsub("%+", " and ")))
	if camp.fit then
		if camp.placed then
			return ("Your %s stands %d more minutes: %d of %d crafts fit."):format(camp.station, Minutes(camp.window),
				camp.fit, camp.wanted)
		end
		return ("Needs %s, which stands %d minutes once placed: %d of %d crafts fit."):format(station,
			Minutes(camp.window), camp.fit, camp.wanted)
	end
	local cooldown = ns.CAMP.COOLDOWN_MINUTES
	if camp.cut == "other" then
		return ("Needs %s: only one camp station an hour (they share a %d minute cooldown), and %s pays more."):format(
			station, cooldown, WithArticle(info and info.station or "other station"))
	elseif camp.cut == "queued" then
		return ("Needs %s: your queue already uses %s, and only one camp station can be placed an hour."):format(
			station, WithArticle(info and info.queued or "another station"))
	elseif camp.cut == "cooldown" then
		return ("Needs %s: camp stations are on cooldown for %d more minutes."):format(station,
			Minutes(info and info.cooldown))
	elseif camp.cut == "two" then
		return ("Needs %s: only one camp station can be placed an hour."):format(station)
	elseif camp.cut == "none" then
		return ("Needs %s and you have none: none listed at the auction house and no character of yours makes one.")
			:format(station)
	end
	return ("Needs %s: placing one costs more than these crafts earn."):format(station)
end

-- The Restock tab's line about the camp station: which one the restock uses, and what it left out.
function UI.RestockCampNote(info)
	local left = info.cut > 0 and ns.Plural(info.cut, "item", "items") .. " needing another station left out" or nil
	if info.station then
		return ("Camp: one station an hour, so this restock uses %s%s%s."):format(
			info.placed and ("your " .. info.station) or WithArticle(info.station),
			info.placed and "" or (" (" .. ns.CAMP.STATION_MINUTES .. " minutes of crafting)"),
			left and ("; " .. left) or "")
	end
	if (info.cooldown or 0) > 0 then
		return ("Camp stations are on cooldown for %d more minutes: %s needing one left out."):format(
			math.max(1, math.ceil(info.cooldown / 60)), ns.Plural(info.cut, "item", "items"))
	end
	return ("No camp station pays for itself here: %s needing one left out."):format(ns.Plural(info.cut, "item", "items"))
end

-- Where to buy, under the auction house step and in chat when the auction house opens.
UI.SHOPPING_HOW = {
	"At the auction house, open the Shopping tab",
	"(Auctionator) and click the list",
	'"' .. ns.LIST_NAME .. '".',
}

-- The Queue tab is a to-do list in the order you'd work through it, numbered: (Farm It: gather first), fetch from
-- alts, the bank, the auction house and the mailbox beside it, vendors, (Farm It: smelt), sub-crafts, and only then the queued crafts themselves, so you reach the crafting station with
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
		local at = #list
		AddItemRows(list, Step() .. title, items, ...)
		-- A tool your crafts need, got here so it's in your bags at the crafting station.
		for i = at + 1, #list do
			local row = list[i]
			if row.kind == "item" and plan.tools and plan.tools[row.itemID] then row.tool = plan.tools[row.itemID] end
			if row.kind == "item" and plan.campItems and plan.campItems[row.itemID] then row.camp = plan.campItems[row.itemID] end
		end
	end

	-- Farming, gather first: what you pick up out there shrinks every errand after it, so you only go to town (alts,
	-- bank, auction house, mailbox, vendor) once, for what's still missing.
	if farming then AddGatherRows(list, plan, Step) end
	local names = {}
	for name in pairs(plan.fetch) do table.insert(names, name) end
	table.sort(names)
	for _, name in ipairs(names) do Section("Get from " .. name .. " (log in there and mail them over)", plan.fetch[name]) end
	-- Bags too full for the queue: what to put in the bank, on the same trip as what to take out of it.
	local room = plan.room
	local function BankSection(title, items)
		local at = #list + 1
		Section(title, items)
		if list[at] then list[at].bank = true end -- the Next step bar can do it at the bank
	end
	if room and next(room.bank) then
		BankSection("Make room: put these in your bank (your bags would fill up)", room.bank)
	end
	if room and room.short > 0 then
		if not (room.bank and next(room.bank)) then
			table.insert(list, { kind = "header", text = Step() .. "Make room in your bags" })
		end
		table.insert(list, { kind = "warn", text = ("Still %s short: sell, mail or bank something else."):format(
			ns.Plural(room.short, "bag slot", "bag slots")) })
	end
	BankSection("Take from your bank", plan.bank)
	local beforeBuy = #list
	-- While the listings of what's to buy are being read, the total can still move.
	local reading = ns.Depth.Status()
	Section("Buy at auction house: %s (" .. (reading and ("reading listings, %d to go"):format(reading)
		or "red: dearer since last scan, green: cheaper") .. ")", plan.buy, "max", ns.Prices.AH, plan)
	-- New players don't know where the list is: say it under the heading, short enough for the Next step bar.
	if #list > beforeBuy then
		list[beforeBuy + 1].ah = true -- jumped to on the Next step bar at the auction house
		for offset, text in ipairs(UI.SHOPPING_HOW) do
			table.insert(list, beforeBuy + 1 + offset, { kind = "tip", text = text })
		end
	end
	-- Right after the auction house, which always has a mailbox beside it; not before, as purchases land there one by
	-- one and collecting halfway through would send you away with things still to buy.
	local mailAt = #list + 1
	Section("Collect from your mailbox", plan.mail)
	if list[mailAt] then list[mailAt].collect = true end -- jumped to on the Next step bar at a mailbox
	local vendorAt = #list + 1
	Section("Buy from vendor: %s", plan.vendor, "at", ns.Prices.Vendor)
	if list[vendorAt] then list[vendorAt].vendor = true end -- the Next step bar can buy it at a merchant
	if farming then Section("Smelt with Mining", plan.smelt) end
	-- Tools you have nowhere: a step of their own before the crafting, gone once one is in your bags. Tools this
	-- add-on can't look for only get a reminder on the first crafting step, so they never hold up the steps.
	local toolReminders = {}
	local missingTools = {}
	for _, need in ipairs(plan.noTool or {}) do
		local recipe = ns.db.recipes[need.recipeID]
		local craft = recipe and recipe.n or "your queue"
		if need.unknown then
			table.insert(toolReminders, { kind = "warn", text = ("%s needs %s: have it in your bags."):format(craft, WithArticle(need.name)) })
		else
			table.insert(missingTools, { kind = "warn",
				text = ("%s needs %s and you have none: a trade supplier sells it."):format(craft, WithArticle(need.name)) })
		end
	end
	if #missingTools > 0 then
		table.insert(list, { kind = "header", text = Step() .. "Get your tools" })
		for _, row in ipairs(missingTools) do table.insert(list, row) end
	end
	local toolsAt = #list + 1
	-- Camp stations: one stands only a while once placed and the next can't go down for an hour, so everything else
	-- is crafted first (sub-crafts for the station's crafts too), then a step of its own places it and lists only
	-- the crafts made beside it. Getting the station and the kit is on the buying and crafting steps like any
	-- material. campOf[recipeID] = the station (index in plan.camp) an own craft needs; campFrom = where the first
	-- one comes in the plan, so crafts that have to wait for a station's (rare) are listed after it.
	local camp = plan.camp or {}
	local campOf, campFrom, campRows, afterCamp = {}, nil, {}, {}
	for s, station in ipairs(camp) do
		campRows[s] = {}
		for _, craft in ipairs(station.crafts) do campOf[craft.recipeID] = campOf[craft.recipeID] or s end
	end
	local position = {}
	for at, craft in ipairs(plan.crafts) do
		local key = ns.Planner.RunKey(craft.recipeID, craft.char)
		position[key] = position[key] or at
		if campOf[craft.recipeID] and not campFrom then campFrom = at end
	end
	-- Where a craft's row goes: its station's step, after the stations, or nil for where it is.
	local function CampPlace(recipeID, at)
		local s = campOf[recipeID]
		if s then return campRows[s] end
		if campFrom and at and at > campFrom then return afterCamp end
	end
	local campDone = false
	local function CampSteps()
		if campDone then return end
		campDone = true
		local fireSaid = false
		for s, station in ipairs(camp) do
			local craftNames, counted = {}, {}
			for _, craft in ipairs(station.crafts) do
				local recipe = ns.db.recipes[craft.recipeID]
				local name = recipe and recipe.n or "a craft"
				if not counted[name] then
					counted[name] = craft.count
					table.insert(craftNames, name)
				else
					counted[name] = counted[name] + craft.count
				end
			end
			for at, name in ipairs(craftNames) do craftNames[at] = name .. " x" .. counted[name] end
			local crafts = table.concat(craftNames, ", ")
			local window = station.window
			local why = window and window.why
			local function Minutes(seconds) return math.max(1, math.ceil((seconds or 0) / 60)) end
			-- A second station waits for the cooldown the first one starts.
			local later = s > 1 and why ~= "placed"
			local title
			if not station.itemID then
				title = ("Camp: %s (you have none)"):format(station.name)
			elseif station.placed then
				title = ("Camp: craft beside your %s (it stands %d more minutes)"):format(station.name,
					Minutes(window and window.seconds))
			elseif why == "cooldown" or later then
				title = ("Camp: %s, after the station cooldown"):format(station.name)
			else
				title = ("Camp: place %s and craft beside it"):format(WithArticle(station.name))
					.. (window and (" (it stands %d minutes)"):format(Minutes(window.seconds)) or "")
			end
			local columns
			for _, row in ipairs(campRows[s]) do
				if row.kind == "queue" then columns = "queue" end
			end
			table.insert(list, { kind = "header", crafting = true, columns = columns, text = Step() .. title })
			if not station.itemID then
				table.insert(list, { kind = "warn", text = ("%s needs %s and you have none: none listed at the "
					.. "auction house and no character of yours makes one."):format(crafts, WithArticle(station.name)) })
			elseif station.placed then
				table.insert(list, { kind = "tip", text = ("Camp: your %s is placed: craft %s beside it."):format(
					station.name, crafts) })
			elseif later then
				table.insert(list, { kind = "tip", text = ("Camp: after the cooldown, place %s (and a campfire if yours "
					.. "is out) and craft %s."):format(WithArticle(station.name), crafts) })
			elseif station.firePlaced then
				table.insert(list, { kind = "tip", text = ("Camp: your campfire is lit: place %s beside it and craft %s."):format(
					WithArticle(station.name), crafts) })
			elseif fireSaid then
				table.insert(list, { kind = "tip", text = ("Camp: then place %s at the same campfire and craft %s."):format(
					WithArticle(station.name), crafts) })
			else
				fireSaid = true
				table.insert(list, { kind = "tip", text = ("Camp: place %s, then %s, and craft %s beside it."):format(
					station.fire and WithArticle(ns.Items.Name(station.fire) or "Campfire Kit") or "a campfire",
					WithArticle(station.name), crafts) })
			end
			if s == 1 and #camp > 1 then
				local needed = {}
				for _, other in ipairs(camp) do needed[#needed + 1] = WithArticle(other.name) end
				table.insert(list, { kind = "warn", text = ("Only one camp station an hour: they share a %d minute "
					.. "cooldown, and your queue needs %s. Craft one station's crafts now, the next after the "
					.. "cooldown."):format(ns.CAMP.COOLDOWN_MINUTES, table.concat(needed, " and ")) })
			end
			if station.itemID and why == "cooldown" and not later then
				local cooldown = plan.campState and plan.campState.cooldown or 0
				table.insert(list, { kind = "warn", text = ("Camp stations are on cooldown for %d more minutes: "
					.. "these crafts wait. Do everything else first."):format(Minutes(cooldown)) })
			elseif station.itemID and window and window.fits < window.total then
				table.insert(list, { kind = "warn", text = ("Only %d of %d crafts fit in the %d minutes %s stands "
					.. "(about %s each): the rest wait for the %d minute cooldown."):format(window.fits, window.total,
					Minutes(window.seconds), station.placed and ("your " .. station.name) or WithArticle(station.name),
					ns.Planner.FormatDuration(window.need / math.max(1, window.total)), ns.CAMP.COOLDOWN_MINUTES) })
			end
			for _, row in ipairs(campRows[s]) do table.insert(list, row) end
		end
		if #afterCamp > 0 then
			table.insert(list, { kind = "header", crafting = true, text = Step() .. "Then craft (needs what the "
				.. "station made)" })
			for _, row in ipairs(afterCamp) do table.insert(list, row) end
		end
	end
	local autoHeader = false
	for at, craft in ipairs(plan.crafts) do
		if (craft.subCount or 0) > 0 then
			local row = { kind = "auto", craft = craft }
			local place = CampPlace(craft.recipeID, at)
			if place then
				table.insert(place, row)
			else
				if not autoHeader then
					autoHeader = true
					table.insert(list, { kind = "header", crafting = true,
						text = Step() .. (farming and "Sub-crafts (make these yourself)" or "Sub-crafts (cheaper than buying)") })
				end
				table.insert(list, row)
			end
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
		-- Bags short of room: your crafts in the plan's order (those freeing the most room first), and with a run, its
		-- share of each entry; the rest waits for the next run.
		local later = {}
		-- Crafts needing a camp station follow the plan's order too, which keeps each station's crafts together.
		if (room or #camp > 0) and #mine > 1 then
			for at, row in ipairs(mine) do row.at = at end
			table.sort(mine, function(a, b)
				local left = position[ns.Planner.RunKey(a.entry.recipeID, me)] or math.huge
				local right = position[ns.Planner.RunKey(b.entry.recipeID, me)] or math.huge
				if left ~= right then return left < right end
				return a.at < b.at
			end)
		end
		if plan.run then
			local left, kept = {}, {}
			for key, qty in pairs(plan.run.qty) do left[key] = qty end
			for _, row in ipairs(mine) do
				local key = ns.Planner.RunKey(row.entry.recipeID, me)
				row.run = math.min(row.entry.qty, left[key] or 0)
				left[key] = (left[key] or 0) - row.run
				table.insert(row.run > 0 and kept or later, row)
			end
			mine = kept
		end
		-- Station crafts go to their station's step, crafts waiting for them after it.
		if #camp > 0 then
			local before = {}
			for _, row in ipairs(mine) do
				local place = CampPlace(row.entry.recipeID, position[ns.Planner.RunKey(row.entry.recipeID, me)])
				table.insert(place or before, row)
			end
			mine = before
		end
		if #mine > 0 then
			local title = plan.run and ("Craft this run: %s (as many as your bags hold)"):format(
				ns.Plural(plan.run.crafts, "craft", "crafts")) or "Craft your queue"
			if #camp > 0 then title = title .. " (before the camp)" end
			table.insert(list, { kind = "header", text = NumberedStep() .. title, columns = "queue", crafting = true })
			for _, row in ipairs(mine) do table.insert(list, row) end
		end
		CampSteps()
		if #later > 0 then
			table.insert(list, { kind = "header", columns = "queue", text = Step() .. ("Next run: %s left (craft this "
				.. "run first, then the list starts over with room in your bags)"):format(
				ns.Plural(plan.run.later, "craft", "crafts")) })
			for _, row in ipairs(later) do table.insert(list, row) end
		end
		table.sort(order, function(a, b) return ns.CharLabel(a) < ns.CharLabel(b) end)
		for _, crafter in ipairs(order) do
			table.insert(list, { kind = "header", columns = "queue", elsewhere = crafter,
				text = Step() .. "Log in to " .. ns.CharLabel(crafter) .. " (their materials are bought and made there)" })
			for _, row in ipairs(others[crafter]) do table.insert(list, row) end
		end
	end
	CampSteps() -- with nothing queued by hand: a writ's or crate's crafts can need a station too
	-- Queued writs and crates come last: by then you hold the writ or crate and what it needs.
	if #ns.db.wanted > 0 then
		local ctx = ns.NewContext()
		local rows = {}
		for index, want in ipairs(ns.db.wanted) do
			local items, fill = ns.Queue.WantedItems(ctx, want)
			if items then
				local row = { kind = "want", index = index, entry = want, fill = fill }
				if want.kind == "writ" then
					row.cost = ns.Planner.Writ(ctx, ns.Writs.ByID(want.id)).total
				else
					local price = ns.Prices.AH(want.id)
					local unit = fill and ns.Planner.ItemCost(ctx, fill.item)
					row.cost = price and price > 0 and unit and price + unit * fill.count or nil
				end
				table.insert(rows, row)
			end
		end
		if #rows > 0 then
			table.insert(list, { kind = "header", text = (number > 0 and Step() or "") .. "Hand in writs, fill crates" })
			for _, row in ipairs(rows) do table.insert(list, row) end
		end
	end
	-- Bank alt mode, last: what you made goes to the bank alt, which sells it. Crafts in the bank come out first.
	-- Checked live too: Options redraws before the plan catches up with the mode or the name being cleared.
	local function MailSteps()
		local seller = ns.Seller.Active() and ns.Seller.Name()
		local send = not farming and seller and ns.plan.send
		if not send then return end
		BankSection("Take your crafts out of the bank (for " .. seller .. ")", send.bank)
		local all = {}
		for _, side in ipairs({ send.bags, send.bank }) do
			for itemID, units in pairs(side) do all[itemID] = (all[itemID] or 0) + units end
		end
		local at = #list + 1
		Section("Mail your crafts to " .. seller .. " (it sells them)", all)
		if list[at] then list[at].mail = true end
	end
	MailSteps()
	for at = toolsAt, #list do
		if list[at].crafting then
			for offset, row in ipairs(toolReminders) do table.insert(list, at + offset, row) end
			break
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

-- Where the player stands right now, for a step that can be done there: a merchant selling something the vendor step
-- buys, the open bank, mailbox or auction house.
local function StepIsHere(header)
	if header.vendor and ns.Vendor.IsOpen() and (ns.Vendor.Pending() ~= nil or ns.Vendor.Busy()) then return true end
	if header.bank and ns.Bank.IsOpen() then return true end
	if (header.mail or header.collect) and ns.Seller.IsOpen() then return true end
	if header.ah and UI.atAuctionHouse then return true end
	return false
end

-- The Next step bar: the first step of the Queue tab's to-do list, cut down to fit a small window. Every header in
-- that list is a step, except that the gathering groups (Mine, Pick herbs, ...) count as one: you gather whatever
-- you come across, so they're shown together, each under its own heading. A later step that can be done where the
-- player stands (StepIsHere) is shown instead of the first, so nobody walks off to the auction house while standing
-- at the vendor; once it's done, the bar goes back to the first step. Returns the step's header, how many steps
-- there are, its rows (items without prices, queue entries as plain crafts) and its number when it isn't the first.
local function BuildNextStep()
	local groups, lastGather = {}, false
	for _, data in ipairs(BuildQueueList()) do
		if data.kind == "header" then
			if data.gather and lastGather then
				table.insert(groups[#groups].rows, { kind = "header", text = ShortStepTitle(data.text) })
			else
				table.insert(groups, { header = data, rows = {} })
			end
			lastGather = data.gather or false
		elseif groups[1] then
			local rows = groups[#groups].rows
			if data.kind == "queue" then
				table.insert(rows, { kind = "next", recipeID = data.entry.recipeID, count = (data.run or 0) > 0 and data.run or data.entry.qty,
					char = data.entry.char })
			elseif data.kind == "want" then
				table.insert(rows, { kind = "item", itemID = data.entry.id, count = data.entry.qty })
			elseif data.kind == "item" then
				local copy = {}
				for key, value in pairs(data) do copy[key] = value end
				copy.priceLabel, copy.price, copy.total, copy.deep, copy.thin = nil, nil, nil, nil, nil
				table.insert(rows, copy)
			else
				table.insert(rows, data)
			end
		end
	end
	local pick = 1
	for index = 2, #groups do
		if StepIsHere(groups[index].header) and not StepIsHere(groups[1].header) then
			pick = index
			break
		end
	end
	local group = groups[pick]
	if not group then return nil, 0, {} end
	return group.header, #groups, group.rows, pick > 1 and pick or nil
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
	local rows, budget, camp = ns.Restock.Rows()
	UI.restockBudget, UI.restockCamp = budget, camp
	for _, row in ipairs(rows) do
		local recipe = ns.db.recipes[row.recipeID]
		if not selected or (recipe and recipe.p == selected) then
			table.insert(list, { kind = "restock", row = row })
		end
	end
	if #list > 0 then table.insert(list, 1, { kind = "header", text = "Item", columns = "restock" }) end
	return list
end

-- What a writ sorts by. Nil (no price yet, name still loading) always goes last.
local function WritSortValue(item, key)
	if key == "name" then
		local name
		if item.writ.item then name = ns.Items.Name(item.writ.item) else name = ns.Writs.Name(item.writ) end
		return name and name:lower()
	end
	if key == "zone" then return item.writ.zone and item.writ.zone:lower() end
	if key == "chance" then return item.writPrice end
	if key == "cost" then return item.net end
	return item.perRep
end

local function BuildWritsList()
	local rows = ns.Writs.Rows(ns.db.ui.writTier, not ns.db.ui.writAll)
	-- The zone filter: counts are of the writs the level and the box let through, before it.
	local counts, zones = {}, ns.db.ui.writZones
	for _, item in ipairs(rows) do
		local key = item.writ.zone or ns.Writs.NO_ZONE
		counts[key] = (counts[key] or 0) + 1
	end
	if windows.writs then windows.writs.zoneCounts = counts end
	if zones and next(zones) then
		local kept = {}
		for _, item in ipairs(rows) do
			if item.held > 0 or zones[item.writ.zone or ns.Writs.NO_ZONE] then kept[#kept + 1] = item end
		end
		rows = kept
	end
	local key, ascending = UI.ListSort("writs")
	for index, item in ipairs(rows) do item.order, item.sortValue = index, WritSortValue(item, key) end
	table.sort(rows, function(a, b)
		if (a.held > 0) ~= (b.held > 0) then return a.held > 0 end -- the ones you hold first
		local left, right = a.sortValue, b.sortValue
		if left ~= right then
			if left == nil or right == nil then return left ~= nil end
			if ascending then return left < right end
			return left > right
		end
		-- Within a zone, the cheapest reputation first.
		if key == "zone" and a.perRep ~= b.perRep then
			if a.perRep == nil or b.perRep == nil then return a.perRep ~= nil end
			return a.perRep < b.perRep
		end
		return a.order < b.order
	end)
	local list = {}
	for _, item in ipairs(rows) do table.insert(list, { kind = "writ", row = item, selected = item.queued > 0 }) end
	if #list > 0 then table.insert(list, 1, { kind = "header", text = "Item wanted", columns = "writs" }) end
	return list
end

-- What a crate sorts by. Nil (no price yet, name still loading) always goes last.
local function CrateSortValue(item, key)
	if key == "name" then
		local name = ns.Crates.Name(item.crate)
		return name and name:lower()
	end
	if key == "chance" then return item.cratePrice end
	if key == "cost" then return item.tokens end
	return item.perToken
end

local function BuildCratesList()
	local rows, best = ns.Crates.Rows(ns.db.ui.crateTier)
	local key, ascending = UI.ListSort("crates")
	for index, item in ipairs(rows) do item.order, item.sortValue = index, CrateSortValue(item, key) end
	table.sort(rows, function(a, b)
		if (a.held > 0) ~= (b.held > 0) then return a.held > 0 end -- the ones you hold first
		local left, right = a.sortValue, b.sortValue
		if left ~= right then
			if left == nil or right == nil then return left ~= nil end
			if ascending then return left < right end
			return left > right
		end
		return a.order < b.order
	end)
	local list = { best = best }
	for _, item in ipairs(rows) do table.insert(list, { kind = "crate", row = item, selected = item.queued > 0 }) end
	if #list > 0 then table.insert(list, 1, { kind = "header", text = "Crate", columns = "crates" }) end
	return list
end

local function BuildSalesList()
	local list = {}
	-- First the money that hasn't been collected: on its way, or already in a mailbox.
	local incoming = ns.Sales.Incoming()
	if #incoming > 0 then
		table.insert(list, { kind = "header", text = "Money on its way", columns = "incoming" })
		for _, entry in ipairs(incoming) do table.insert(list, { kind = "incoming", entry = entry }) end
	end
	local items = ns.Sales.AllItems(ns.db.ui.salesEverything)
	if #items > 0 then table.insert(list, { kind = "header", text = "Item (last 7 days)", columns = "sales" }) end
	for _, item in ipairs(items) do table.insert(list, { kind = "sales", item = item }) end
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
-- "14 hours", "2 days", for the time between restocks.
local function GapText(days)
	if days < 1.5 then return ns.Plural(math.max(1, math.floor(days * 24 + 0.5)), "hour", "hours") end
	return (("%.1f days"):format(days):gsub("%.0 ", " "))
end

-- Why a smart restock goal is what it is, in plain words. goal is what the row shows.
function UI.SmartGoalLines(smart, goal)
	local lines = {}
	local smartness = ns.Planner.SMART
	if smart.learning then
		lines[1] = ("Smart goal: too few sales yet, so the default (%d) is used."):format(smart.base)
	elseif smart.paused or smart.retry then
		lines[1] = ("Paused: lately its expired auctions lost %s in deposits and its sales earned %s."):format(
			ns.Money(smart.lost), ns.Money(math.max(0, smart.earned)))
		if smart.paused then
			lines[2] = ("It's tried again with one in %s. Set a goal of your own to keep stocking it."):format(
				ns.Plural(math.max(1, math.ceil(smart.retryIn)), "day", "days"))
		else
			lines[2] = "Time for another try: one is stocked. If it sells, the goal grows again; if it expires, "
				.. "the pause comes back for twice as long."
		end
	else
		local full = smart.full or goal or smart.base
		if smart.raised > 0 and full > smart.base then
			lines[1] = ("Smart goal: raised from the default (%d). On %s everything you listed sold, so more might have.")
				:format(smart.base, ns.Plural(smart.raised, "day", "days"))
		elseif full < smart.base then
			lines[1] = ("Smart goal: lowered from the default (%d), because too many came back unsold."):format(smart.base)
		else
			lines[1] = ("Smart goal: the default (%d) fits what sold."):format(smart.base)
		end
		local recent = smart.recentSold + smart.recentExpired
		if smart.recentExpired > 0 then
			lines[#lines + 1] = ("In the last %d days %d of %d came back unsold%s."):format(smartness.RECENT,
				smart.recentExpired, recent, smart.lowered > 0 and ", which lowers it" or ": few enough to leave it")
		end
		if smart.gapKnown then
			lines[#lines + 1] = ("It never rises past what sold between two restocks, and yours are about %s apart "
				.. "(long breaks count most)."):format(GapText(smart.gap))
		else
			lines[#lines + 1] = ("It never rises past what sold in one auction's length (%s), until a few of your "
				.. "restocks are on record."):format(GapText(smart.gap))
		end
		if smart.margin == nil then
			lines[#lines + 1] = "The deposit isn't known until you post one, so a usual profit is assumed."
		elseif smart.margin >= 0.85 then
			lines[#lines + 1] = "An unsold one only costs a small deposit next to its profit: bigger steps up, smaller steps down."
		elseif smart.margin <= 0.5 then
			lines[#lines + 1] = "The deposit is large next to its profit: smaller steps up, bigger steps down."
		end
		if math.abs(smart.level - smartness.LEVEL) > 0.001 then
			lines[#lines + 1] = ("Stock level %d%% (Options tab): %s."):format(smart.level * 100 + 0.5,
				smart.level < smartness.LEVEL and "more cautious" or "more aggressive")
		end
	end
	if smart.limited == "gold" then
		lines[#lines + 1] = ("Kept low: more would cost over %d%% of your gold to make."):format(
			smartness.GOLD_SHARE * 100)
	end
	if smart.pair then lines[#lines + 1] = "Daggers are stocked in pairs: buyers usually want two." end
	return lines
end

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
	GameTooltip:AddDoubleLine(" ", "profit / sales", 1, 1, 1, 0.6, 0.6, 0.6)
	local estimated = false
	for _, period in ipairs({ { "Last 7 days", 7 }, { "Last 30 days", 30 }, { "All time", nil } }) do
		local profit, rough, _, _, gold = ns.Sales.Profit(item, period[2])
		estimated = estimated or rough
		GameTooltip:AddDoubleLine(period[1], (rough and "~" or "") .. ns.Money(profit) .. " / " .. ns.Money(gold),
			1, 1, 1, 1, 1, 1)
	end
	GameTooltip:AddLine("Profit is the money you received, after the auction house cut, less what the sold items "
		.. "cost you: materials at the price you paid, gathered ones and ones you already had at the market price "
		.. "on the day you used them.", 0.6, 0.6, 0.6, true)
	if estimated then
		GameTooltip:AddLine("~ Part of it is an estimate: money still on its way, or items made before the add-on "
			.. "recorded costs, which count at today's cost to craft one.", 0.6, 0.6, 0.6, true)
	end
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

-- "167% of usual" for a price far from its usual one: orange when dear, green when cheap; nil otherwise.
local function UsualText(ratio)
	local NORMAL = ns.Planner.NORMAL
	if not ratio or (ratio < NORMAL.HIGH and ratio > NORMAL.LOW) then return nil end
	return Color(ratio >= NORMAL.HIGH and COLOR_WARN or COLOR_PROFIT, ("%d%% of usual"):format(math.floor(ratio * 100 + 0.5)))
end

-- Materials with their cost. An auction house price that's a day or more old says so, in orange: a recent scan can
-- still have missed an item that had no listings at the time. One far from its usual price says that too.
local function AddPartLines(parts)
	for _, part in ipairs(parts or {}) do
		local name = ns.Items.Name(part.itemID) or "Loading..."
		local label = (KIND_LABEL[part.kind] or "?") .. (part.deep and " avg" or "")
		local value = part.unit and (ns.Money(part.unit * part.qty) .. " (" .. label .. ")") or "no price"
		local age = part.kind == "ah" and ns.Prices.ItemAgeDays(part.itemID)
		if age and age > 0 then value = value .. Color(COLOR_WARN, (" %dd old"):format(age)) end
		local usual = part.kind == "ah" and UsualText(ns.Prices.OfNormal(part.itemID))
		if usual then value = value .. " " .. usual end
		GameTooltip:AddDoubleLine(part.qty .. " x " .. name, value, 0.85, 0.85, 0.85, 1, 1, 1)
	end
end

local function ShowSkillTooltip(row, item)
	StartItemTooltip(row, item.itemID, item.recipeID)
	AddPartLines(item.parts)
	GameTooltip:AddLine(" ")
	local hex = SKILL.COLORS[item.difficulty]
	GameTooltip:AddDoubleLine("Colour", Color(hex, SKILL.NAMES[item.difficulty]), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Chance of a skill point", Color(hex, SKILL.CHANCE_TEXT[item.difficulty]), 1, 1, 1, 1, 1, 1)
	if item.points > 1 then GameTooltip:AddDoubleLine("Skill points per craft", tostring(item.points), 1, 1, 1, 1, 1, 1) end
	GameTooltip:AddDoubleLine("Materials per craft", item.cost and ns.Money(item.cost) or "no price", 1, 1, 1, 1, 1, 1)
	-- Both resale prices, the one counted in white, the other grey with "not counted".
	local function ResaleLine(label, amount, counted)
		if not (amount and amount > 0) then return end
		if counted then
			GameTooltip:AddDoubleLine(label, "- " .. ns.Money(amount), 1, 1, 1, 1, 1, 1)
		else
			GameTooltip:AddDoubleLine(label .. " (not counted)", ns.Money(amount), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
		end
	end
	ResaleLine("A vendor pays", item.vendorBack, item.backKind == "vendor")
	ResaleLine("Sells on the AH for (after the cut)", item.ahBack, item.backKind == "ah")
	if item.back and item.back > 0 then
		GameTooltip:AddDoubleLine(item.net and item.net < 0 and "Earned per craft" or "Cost per craft",
			item.net and SKILL.CostText(item.net) or "no price", 1, 1, 1, 1, 1, 1)
	end
	GameTooltip:AddDoubleLine(item.perPoint and item.perPoint < 0 and "Expected gold per skill point"
		or "Expected cost per skill point", item.perPoint and SKILL.CostText(item.perPoint) or "no price", 1, 1, 1, 1, 1, 1)
	if not ns.db.ui.skillSellAH then
		GameTooltip:AddLine("Counts what a vendor pays for what it makes. Tick Selling on the AH to count the auction "
			.. "house price instead when it's more.", 0.6, 0.6, 0.6, true)
	elseif item.backKind == "ah" then
		GameTooltip:AddLine("Counts the auction house price: levelling makes many of one thing, and the auction house "
			.. "may not take them all at that price.", 0.6, 0.6, 0.6, true)
	end
	GameTooltip:AddLine("Orange always gives a skill point. Yellow and green are estimates: yellow about half the time, "
		.. "green less often, and both get less likely as your skill rises.", 0.6, 0.6, 0.6, true)
	GameTooltip:AddLine("Click to open the recipe. + queues one, Shift + queues ten, right-click + to type an amount.",
		0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

-- Tooltip lines: materials, what it sells for, profit, and when the recipe pays for itself.
function RECIPE.AddProfitLines(item)
	local result = item.result
	if item.madeBound or item.made == false or not result then
		if item.made and not item.madeBound and not result then
			GameTooltip:AddLine("Profit not known yet: what it makes is still loading.", 0.6, 0.6, 0.6, true)
		elseif item.made == nil then
			GameTooltip:AddLine("Profit not known yet: open this profession once on any character to read its materials.",
				0.6, 0.6, 0.6, true)
		end
		return
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("If you learn it", 1, 0.82, 0)
	AddPartLines(result.parts)
	GameTooltip:AddDoubleLine("Materials per craft", result.cost and ns.Money(result.cost) or "no price", 1, 1, 1, 1, 1, 1)
	if result.saleUnit then
		GameTooltip:AddDoubleLine("Sells for (after the 5% cut)", ns.Money(result.saleUnit * result.yield * (1 - ns.AH_CUT)),
			1, 1, 1, 1, 1, 1)
	else
		GameTooltip:AddLine("What it makes has no auction house price yet.", 0.6, 0.6, 0.6, true)
	end
	if item.net then
		GameTooltip:AddDoubleLine("Profit per craft", Color(item.net >= 0 and COLOR_PROFIT or COLOR_LOSS, ns.Money(item.net)),
			1, 1, 1, 1, 1, 1)
	end
	if item.payback then
		GameTooltip:AddDoubleLine("Pays for the recipe after", ns.Plural(item.payback, "craft", "crafts"), 1, 1, 1, 1, 1, 1)
	elseif item.payback == false then
		GameTooltip:AddLine("A craft makes no profit, so the recipe never pays for itself.", 1, 0.4, 0.3, true)
	end
end

-- Tooltip lines: every character with the recipe's profession and where they stand with it, this character first.
function RECIPE.AddCharacterLines(recipeID, professionName)
	local Book = ns.RecipeBook
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(("Your characters with %s"):format(professionName), 1, 0.82, 0)
	local me, keys = ns.CharKey(), {}
	for key in pairs(ns.db.chars) do
		if not ns.CharExcluded(key) then table.insert(keys, key) end -- left out on the Options tab
	end
	table.sort(keys, function(a, b)
		if (a == me) ~= (b == me) then return a == me end
		return ns.CharLabel(a) < ns.CharLabel(b)
	end)
	local any = false
	for _, key in ipairs(keys) do
		local status, need, have = Book.Status(key, recipeID)
		if status ~= "none" then
			any = true
			local text, hex
			if status == "learned" then
				text, hex = "learned", COLOR_MUTED
			elseif status == "skill" then
				text, hex = ("needs %d, has %d"):format(need, have), COLOR_WARN
			elseif have then
				text, hex = ("can learn it now (%d)"):format(have), RECIPE.COLORS.learn
			else
				text, hex = ("can learn it (skill not read: open %s on it)"):format(professionName), RECIPE.COLORS.learn
			end
			GameTooltip:AddDoubleLine(ns.CharLabel(key) .. (key == me and " (you)" or ""), Color(hex, text),
				1, 1, 1, 1, 1, 1)
		end
	end
	if not any then GameTooltip:AddLine(("None of your characters has %s."):format(professionName), 0.6, 0.6, 0.6, true) end
end

-- Where a recipe comes from, then every character with its profession and whether they know it. Names the client
-- hasn't loaded yet are asked for; the tooltip is drawn once more a moment later to show them.
function RECIPE.ShowTooltip(row, item)
	local Book = ns.RecipeBook
	local recipeID = item.recipeID
	local data = Book.Data(recipeID)
	local missing = false
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	if data and data.i then
		GameTooltip:SetItemByID(data.i)
	elseif GameTooltip.SetSpellByID then
		GameTooltip:SetSpellByID(recipeID)
	else
		GameTooltip:SetText(item.name or "Recipe")
	end
	GameTooltip:AddLine(" ")
	local professionID = Book.Profession(recipeID)
	local professionName = professionID and ns.Recipes.ProfessionName(professionID) or "its profession"
	if item.skill then GameTooltip:AddLine(("Needs %s %d to learn"):format(professionName, item.skill), 1, 0.82, 0) end
	-- What it makes, and whether that sells.
	local sellable, output = Book.Sellable(recipeID)
	if output then
		local madeName = ns.Items.Name(output)
		missing = madeName == nil
		local price = sellable and ns.Prices.AH(output)
		local right = sellable == false and Color(COLOR_WARN, "binds on pickup")
			or price and ("sells for " .. ns.Money(price)) or ""
		GameTooltip:AddDoubleLine("Makes " .. (madeName or "..."), right, 1, 1, 1, 1, 1, 1)
	elseif output == false then
		GameTooltip:AddLine("Makes no item, so nothing to sell.", 1, 0.6, 0.2, true)
	end
	RECIPE.AddProfitLines(item)
	GameTooltip:AddLine("Where to get it", 1, 0.82, 0)
	local lines, sourceMissing = Book.SourceLines(recipeID, ns.CharKey())
	missing = missing or sourceMissing
	for _, line in ipairs(lines) do
		GameTooltip:AddLine(line.text, 1, 1, 1, true)
		if line.detail then GameTooltip:AddLine("   " .. line.detail, 0.75, 0.75, 0.75, true) end
		if line.note then GameTooltip:AddLine("   " .. line.note, 0.6, 0.6, 0.6, true) end
	end
	if item.bound then
		GameTooltip:AddLine("Binds on pickup: it can't be bought on the auction house.", 1, 0.6, 0.2, true)
	elseif data and data.i then
		if item.price then
			GameTooltip:AddDoubleLine("On the auction house", ns.Money(item.price), 1, 1, 1, 1, 1, 1)
		else
			GameTooltip:AddLine("Can be traded, but no auction house price seen yet.", 0.6, 0.6, 0.6, true)
		end
	end

	RECIPE.AddCharacterLines(recipeID, professionName)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("<Click for the Wowhead link>", 0.4, 0.8, 1)
	if data and data.i then GameTooltip:AddLine("Shift-click to link the recipe in chat.", 0.6, 0.6, 0.6, true) end
	GameTooltip:Show()
	-- Once per recipe, so a name that never loads doesn't redraw it forever.
	if missing and row.live.recipeRetry ~= recipeID then
		row.live.recipeRetry = recipeID
		C_Timer.After(0.5, function()
			if row.data and row.data.row == item and GameTooltip:IsOwned(row) then RECIPE.ShowTooltip(row, item) end
		end)
	end
end

local function ShowProfitTooltip(row, result)
	StartItemTooltip(row, result.itemID, result.recipeID)
	AddPartLines(result.parts)
	GameTooltip:AddLine(" ")
	local batch = result.batch and result.batch > 1 and result.batch
	GameTooltip:AddDoubleLine(batch and "Cost per craft" or "Cost", result.cost and ns.Money(result.cost) or "no price",
		1, 1, 1, 1, 1, 1)
	if batch then
		GameTooltip:AddLine(("Priced for %d crafts, what your restock goal makes: materials bought down the listings "
			.. "cost more once the cheapest run out."):format(batch), 0.6, 0.8, 1, true)
		if result.oneCost and result.cost and result.oneCost < result.cost - 0.5 then
			GameTooltip:AddDoubleLine("One craft", ns.Money(result.oneCost), 0.85, 0.85, 0.85, 1, 1, 1)
		end
	end
	if result.unread and #result.unread > 0 and result.cost then
		local names = {}
		for _, itemID in ipairs(result.unread) do names[#names + 1] = ns.Items.Name(itemID) or "Loading..." end
		GameTooltip:AddLine(("Listings not read for %s: counted at the cheapest listing. They're read at the auction "
			.. "house once your queue buys them."):format(table.concat(names, ", ")), 1, 0.6, 0.2, true)
	end
	if result.bound then
		GameTooltip:AddLine("Bind on pickup: can't be sold on the auction house.", 1, 0.6, 0.2, true)
	else
		local sale = result.saleUnit and (ns.Money(result.saleUnit * result.yield)) or "no price"
		local lowered = result.atNormal
		GameTooltip:AddDoubleLine(lowered and "Counted as selling for" or "Sells for", sale, 1, 1, 1, 1, 1, 1)
		if lowered then
			GameTooltip:AddDoubleLine("Listed on the AH for", ns.Money(result.listedUnit * result.yield), 1, 0.6, 0.2, 1, 0.6, 0.2)
		end
		if result.normalUnit then
			GameTooltip:AddDoubleLine(("Usual price (last %d days)"):format(ns.Planner.NORMAL.DAYS), ns.Money(result.normalUnit * result.yield)
				.. (" (now %d%%)"):format(math.floor(result.ofNormal * 100 + 0.5)), 1, 1, 1, 1, 1, 1)
		end
		if result.spiked and not result.capped then
			GameTooltip:AddLine("Price spike: profit counts the usual price, since the spike may be over before yours "
				.. "sell. Materials count at what they cost now.", 1, 0.6, 0.2, true)
		elseif result.atNormal and not result.capped then
			GameTooltip:AddLine("Listed a little above its usual price: profit counts the usual price.", 0.6, 0.6, 0.6, true)
		end
		if result.capped then
			GameTooltip:AddLine(("Check this price: it's more than %d%% of the material cost. Profit counts today's "
				.. "listing, but it's often one odd listing that won't sell. Search the item at the auction house "
				.. "before crafting it. Change the limit in Options."):format(ns.Queue.PriceCapPercent()), 1, 0.6, 0.2, true)
		end
		if result.postage then
			GameTooltip:AddDoubleLine("Postage to " .. (ns.Seller.Name() or "your bank alt"), ns.Money(result.postage),
				1, 1, 1, 1, 1, 1)
		end
		if result.net then
			GameTooltip:AddDoubleLine(result.postage and "Profit after AH cut and postage" or "Profit after 5% AH cut",
				ns.Money(result.net), 1, 1, 1, 1, 1, 1)
			if result.todayNet then
				GameTooltip:AddDoubleLine("Profit at today's price", ns.Money(result.todayNet), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
			end
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

local function ShowWritTooltip(row, item)
	local writ = item.writ
	if writ.item then
		StartItemTooltip(row, writ.item)
	else
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetText(ns.Writs.Name(writ) or "Craftsman's Writ")
	end
	GameTooltip:AddLine("Craftsman's Writ, " .. ns.Writs.TIERS[writ.tier], 1, 0.82, 0)
	GameTooltip:AddDoubleLine(item.haveWrit and "Writ (you have it)" or "Writ at the auction house",
		item.writPrice and ns.Money(item.writPrice) or "no price", 1, 1, 1, 1, 1, 1)
	local how = "Item"
	if item.haveItem then
		how = "Item (you have it)"
	elseif item.kind == "craft" then
		how = "Item, crafted by " .. ns.CharLabel(ns.Recipes.Crafter(item.recipeID))
	elseif item.kind == "ah" then
		how = "Item, bought at the auction house"
	elseif item.kind == "vendor" then
		how = "Item, bought from a vendor"
	end
	if writ.count > 1 then how = how .. " x" .. writ.count end
	GameTooltip:AddDoubleLine(how, item.itemCost and ns.Money(item.itemCost) or "no price", 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Coin pouch (average)", "~" .. ns.Money(item.reward), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Reputation", tostring(item.rep), 1, 1, 1, 1, 1, 1)
	if item.net then
		if item.net < 0 then
			GameTooltip:AddDoubleLine("You lose", ns.Money(-item.net), 1, 0.4, 0.33, 1, 0.4, 0.33)
		else
			GameTooltip:AddDoubleLine("You earn", ns.Money(item.net), 0.33, 0.87, 0.33, 0.33, 0.87, 0.33)
		end
	end
	if writ.zone then
		GameTooltip:AddLine("Hand in: " .. writ.zone .. (writ.zoneGuess and " (a guess from other writs, not confirmed)" or ""),
			0.6, 0.8, 1, true)
	else
		GameTooltip:AddLine("Hand in: not known yet. The writ's quest marks it on your map.", 0.6, 0.8, 1, true)
	end
	if item.done then GameTooltip:AddLine("Handed in today on this character.", 0.33, 0.87, 0.33) end
	GameTooltip:AddLine("Each writ can be handed in once a day. The pouch's amount is an average players reported, "
		.. "so the gold is rough.", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

-- "20 Iron Ore", for a crate's bundle.
-- Writs and crates you hold: the row is tinted gold and starts with how many you have.
local Held = {}
function Held.Mark(row, held)
	if held > 0 then row.tint:SetColorTexture(1, 0.82, 0, 0.20) end
	row.tint:SetShown(held > 0)
end
function Held.Text(held)
	return held > 0 and Color("ffffd100", ("You have %d: "):format(held)) or ""
end
-- The names of what you hold, one per line, for the tab's tooltip.
function Held.Names(key)
	local names = {}
	local list = key == "writs" and ns.Writs.list or ns.Crates.list
	for _, entry in ipairs(list) do
		local count = key == "writs" and ns.Writs.HeldCount(entry) or ns.Crates.HeldCount(entry)
		if count > 0 then
			local name = key == "writs" and (entry.item and ns.Items.Name(entry.item) or ns.Writs.Name(entry))
				or ns.Crates.Name(entry)
			names[#names + 1] = ("%s x%d"):format(name or "Loading...", count)
		end
	end
	return names
end

local function BundleText(fill)
	return ("%d %s"):format(fill.count, ns.Items.Name(fill.item) or "...")
end

local function ShowCrateTooltip(row, item)
	local crate = item.crate
	StartItemTooltip(row, crate.id)
	GameTooltip:AddLine("Waylaid Crate, " .. ns.Crates.TIERS[crate.tier], 1, 0.82, 0)
	GameTooltip:AddDoubleLine(item.haveCrate and "Crate (you have it)" or "Crate at the auction house",
		item.cratePrice and ns.Money(item.cratePrice) or "no price", 1, 1, 1, 1, 1, 1)
	GameTooltip:AddLine("Fill it with any one of:", 0.6, 0.8, 1)
	for _, fill in ipairs(item.bundles) do
		local how = BundleText(fill)
		if fill.kind == "craft" then how = how .. ", crafted by " .. ns.CharLabel(ns.Recipes.Crafter(fill.recipeID)) end
		if fill == item.best then
			GameTooltip:AddDoubleLine(how .. " (cheapest)", ns.Money(fill.cost), 0.33, 0.87, 0.33, 0.33, 0.87, 0.33)
		else
			GameTooltip:AddDoubleLine(how, fill.cost and ns.Money(fill.cost) or "no price", 1, 1, 1, 1, 1, 1)
		end
	end
	local guess = item.rough and "~" or ""
	GameTooltip:AddDoubleLine("Merchant's Favor", guess .. item.tokens, 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine("Coin with it", guess .. ns.Money(item.reward), 1, 1, 1, 1, 1, 1)
	if item.perToken then
		GameTooltip:AddDoubleLine("Each Merchant's Favor costs", item.perToken > 0 and ns.Money(item.perToken) or "nothing",
			1, 0.82, 0, 1, 0.82, 0)
	end
	if item.cheapest then GameTooltip:AddLine("The cheapest Merchant's Favor at today's prices.", 0.33, 0.87, 0.33) end
	if item.rough then
		GameTooltip:AddLine("Nobody has reported what an Artisan crate pays yet: this follows the other levels.",
			0.6, 0.6, 0.6, true)
	end
	GameTooltip:Show()
end

local COLUMN_TIPS = {
	crates = {
		"Crate: the crate's price at the auction house. Green when you hold it.",
		"Fill: its cheapest bundle of materials. Blue means one of your characters crafts it. Hover a row to see "
			.. "every bundle.",
		"Favor: the Merchant's Favor the filled crate pays.",
		"Per Favor: the crate and its fill, less the coin it pays, for each Merchant's Favor. The list starts with "
			.. "the cheapest.",
		"Click Crate, Price, Favor or Per Favor to sort by it; click again to reverse.",
	},
	writs = {
		"Writ: the writ's price at the auction house. Green when you hold it.",
		"Item: the item it wants, by the cheapest way. Blue means one of your characters crafts it.",
		"Net: the coin pouch (an average) less the writ and the item. Red is gold you lose.",
		"Per rep: gold lost for each reputation point. The list starts with the cheapest reputation.",
		"Zone: where the writ is handed in. Sorted by it, the writs of one zone come together, so one trip does them "
			.. "all (cheapest first within a zone). A ? is a guess from the other writs; unknown zones come last.",
		"Click Item wanted, Zone, Writ, Net or Per rep to sort by it; click again to reverse.",
	},
	profit = {
		"Sells: the chance one sells within 24 hours, from your sales history. Grey with ~ is a rough guess from under "
			.. "5 units; orange is under 50%, red under 20%.",
		"Profit: for one craft, after the 5% auction house cut, with materials by the cheapest path.",
		"Click Recipe, Sells or Profit to sort by it; click again to reverse.",
	},
	recipes = {
		"Green: can be learned now. White: needs more skill. Grey: learned. Blue names: the characters still "
			.. "missing it (All characters).",
		"Skill: the skill needed to learn it, red when it's more than you have.",
		"Source: where it comes from, the first of several (+1 means one more kind). * means during a holiday.",
		"AH price: the recipe on the auction house. BoP binds on pickup, so it can't be bought.",
		"Profit: what one craft earns after the 5% auction house cut, as on the Profit tab. BoP: what it makes binds "
			.. "on pickup. ? : its materials aren't known yet (open the profession once on any character).",
		"Pays back: how many crafts' profit pays for the recipe at its auction house price. Never: a craft makes no "
			.. "profit. Blank for learned recipes and recipes with no auction house price.",
		"Hover a recipe for where to find it and who knows it. Click a heading to sort by it; click again to reverse.",
	},
	skill = {
		"Recipes are coloured as in the profession window. Grey ones can't give skill and aren't listed.",
		"Chance: of a skill point per craft. Orange always; yellow about half the time and green less often "
			.. "(estimates).",
		"Craft: materials for one craft at market prices, by the cheapest path, less what selling what it makes gets "
			.. "back: a vendor's price, or the auction house's (after its cut) with Selling on the AH ticked. Green + "
			.. "means the craft earns gold.",
		"Per point: what a skill point is expected to cost with that recipe, green + when it earns. The list starts "
			.. "cheapest first.",
		"Click Recipe, Chance, Craft or Per point to sort by it; click again to reverse.",
	},
	restock = {
		"Profit: what one craft earns after the 5% auction house cut, minus its materials (the row tooltip has the "
			.. "details).",
		"Sells: the chance one sells within 24 hours, from your sales history.",
		"AH: how many you have on the auction house, across your characters. Updates when you visit the auction house.",
		"Have: how many your characters hold in bags, banks and mail.",
		"Craft: how many crafts Queue restock would add. 5q: already on your queue. Grey 'skip' means the goal is 0.",
		"X: skip the item until you /reload or log out, keeping its goal. Click again to restock it.",
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
	elseif data.kind == "recipe" then
		RECIPE.ShowTooltip(row, data.row)
	elseif data.kind == "writ" then
		ShowWritTooltip(row, data.row)
	elseif data.kind == "crate" then
		ShowCrateTooltip(row, data.row)
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
		if data.camp then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(data.camp == "Campfire" and "For your camp: a camp station is placed beside a campfire."
				or ("A camp station: some of your crafts need %s placed nearby. Placing it uses it up; it needs a "
				.. "campfire nearby, stands %d minutes, and every camp station shares a %d minute cooldown."):format(
				WithArticle(data.camp), ns.CAMP.STATION_MINUTES, ns.CAMP.COOLDOWN_MINUTES), 1, 1, 1, true)
		end
		if data.tool then
			local recipe = ns.db.recipes[data.tool.recipeID]
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(("A tool: %s won't start without %s in your bags. It isn't used up."):format(
				recipe and recipe.n or "your queue", WithArticle(data.tool.name)), 1, 1, 1, true)
		end
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
				if data.deep and data.total then
					GameTooltip:AddDoubleLine(("Buying %d costs"):format(data.count), ns.Money(data.total), 1, 1, 1, 1, 1, 1)
					GameTooltip:AddDoubleLine("On average, each", ns.Money(data.total / data.count), 1, 1, 1, 1, 1, 1)
					local seen = ns.Depth.Age(data.itemID)
					GameTooltip:AddLine(("From the listings at the auction house%s: the cheapest one only covers so "
						.. "many, the rest cost more."):format(seen and (", read " .. UI.AgoText(seen)) or ""),
						0.6, 0.6, 0.6, true)
					if data.thin then
						GameTooltip:AddLine(data.thin >= data.count and "None are listed right now, so this goes by the "
							.. "last scan's price." or ("Only %d are listed. The other %d count at the dearest listing.")
							:format(data.count - data.thin, data.thin), 1, 0.6, 0.2, true)
					end
				elseif data.total then
					GameTooltip:AddLine("Its listings haven't been read yet, so the total counts every one at the "
						.. "cheapest listing. They're read at the auction house.", 0.6, 0.6, 0.6, true)
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
		local smart = ns.Restock.SmartInfo(item.itemID)
		GameTooltip:AddDoubleLine(ns.Restock.IsCustom(item.itemID) and "Goal (your own)"
			or smart and "Goal (smart)" or "Goal (default)", tostring(item.goal), 1, 1, 1, 1, 1, 1)
		if item.batch then
			GameTooltip:AddLine(("Needs a camp station, so it's made in batches: once stock falls under %d, it's "
				.. "crafted up to %d (%dx the goal, see Options), so one station pays for itself. What isn't posted "
				.. "waits in your bags."):format(item.goal, item.batch, ns.Restock.StationBatch()), 0.45, 0.75, 1, true)
		end
		if item.queued then
			GameTooltip:AddDoubleLine("Crafts already queued", tostring(item.queued), 0.45, 0.75, 1, 0.45, 0.75, 1)
		end
		GameTooltip:AddDoubleLine(item.queued and "More crafts needed" or "Crafts needed",
			tostring(item.dear or (item.camp and item.camp.wanted) or item.wanted or item.crafts), 1, 1, 1, 1, 1, 1)
		if item.camp then
			GameTooltip:AddLine(UI.RestockCampText(item.camp, UI.restockCamp), 1, 0.6, 0.2, true)
		end
		if item.dear then
			local kept = item.wanted or item.crafts
			GameTooltip:AddLine((kept > 0 and ("Only %d more are worth making: "):format(kept)
				or "Not worth making more now: ")
				.. "the restock was cut at the auction house, where the cheap materials ran out and with the dearer "
				.. "ones a craft earned less than your minimum profit. Offered again within the hour.", 1, 0.6, 0.2, true)
		end
		if item.trim then
			GameTooltip:AddLine(("%d of the queued crafts aren't needed any more: you have more in stock now. "
				.. "Update restock takes them off the queue."):format(item.trim), 1, 0.6, 0.2, true)
		elseif item.queued then
			GameTooltip:AddLine("Queued restocks stay as they are while you shop and craft, whatever your gold "
				.. "and the prices do meanwhile.", 0.6, 0.6, 0.6, true)
		end
		if item.cooldownWanted then
			local left = item.cooldown or 0
			GameTooltip:AddLine(left > 0
				and ("On cooldown for %s: ready in %dh %02dm. Restock asks for it again then, one craft per "
					.. "cooldown."):format(ns.CharLabel(ns.Recipes.Crafter(item.recipeID)), math.floor(left / 3600),
					math.floor(left / 60) % 60)
				or ("Has a cooldown: one craft now, the rest (%d wanted) after it."):format(item.cooldownWanted),
				1, 0.6, 0.2, true)
		end
		if item.wanted then
			GameTooltip:AddLine(item.crafts > 0
				and ("Your gold covers %d of them: other items earn more for their materials."):format(item.crafts)
				or "Left out for now: your gold goes to items that earn more for their materials.", 1, 0.6, 0.2, true)
		end
		if smart then
			for _, line in ipairs(UI.SmartGoalLines(smart, item.goal)) do GameTooltip:AddLine(line, 0.45, 0.75, 1, true) end
		end
		AddSalesLines(ns.Items.Name(item.itemID))
		GameTooltip:AddLine("+ and - change this item's goal (Shift for 10). A goal of 0 skips the item.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	elseif data.kind == "post" then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(data.row.itemID)
		if data.row.unitProfit then
			GameTooltip:AddLine(" ")
			GameTooltip:AddDoubleLine("Profit each", ns.Money(data.row.unitProfit), 1, 1, 1, 1, 1, 1)
			GameTooltip:AddLine("At the last scanned AH price after the 5% cut, minus what one costs to craft. Click it "
				.. "for the profit at the live price.", 0.6, 0.6, 0.6, true)
		end
		AddSalesLines(ns.Items.Name(data.row.itemID))
		GameTooltip:Show()
	elseif data.kind == "incoming" then
		local entry = data.entry
		if entry.itemID then
			StartItemTooltip(row, entry.itemID)
		else
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:SetText(entry.name)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddDoubleLine("Sold", date("%H:%M", entry.at), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("Money arrives", date("%H:%M", entry.due), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine("Mailbox of", ns.CharLabel(entry.char), 1, 1, 1, 1, 1, 1)
		if entry.rough or not entry.amount then
			GameTooltip:AddLine("The game only says which item sold, so this amount is an estimate: one unit at the "
				.. "price you posted it for, or the market price. The mail has the real amount.", 0.6, 0.6, 0.6, true)
		end
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
	elseif data.kind == "want" then
		StartItemTooltip(row, data.entry.id)
		GameTooltip:AddLine(data.entry.kind == "writ" and "Queued from the Writs tab." or "Queued from the Crates tab.", 0.6, 0.8, 1)
		GameTooltip:AddLine("The steps above get it and what it needs. It comes off the queue when you "
			.. (data.entry.kind == "writ" and "hand it in." or "fill it."), 1, 1, 1, true)
		GameTooltip:Show()
	elseif data.kind == "queue" then
		local queuedRecipe = ns.db.recipes[data.entry.recipeID]
		StartItemTooltip(row, queuedRecipe and queuedRecipe.o, data.entry.recipeID)
		local crafter = ns.Recipes.Crafter(data.entry.recipeID, data.entry.char)
		GameTooltip:AddLine("Crafted by " .. ns.CharLabel(crafter), 0.6, 0.8, 1)
		SKILL.AddLine(data.entry.recipeID, crafter)
		if data.run then
			GameTooltip:AddLine(data.run > 0 and ("Your bags don't hold the materials for the whole queue: %d of these "
				.. "in this run, the rest in the next."):format(data.run)
				or "Your bags don't hold the materials for the whole queue: this waits for the next run.", 0.6, 0.8, 1, true)
		end
		if ns.totals.boundEntries[data.index] then
			GameTooltip:AddLine("Bind on pickup: can't be sold, so it isn't in the total profit.", 1, 0.6, 0.2, true)
		elseif queuedRecipe and queuedRecipe.o then
			local old, new = ns.Prices.Change(queuedRecipe.o)
			if old then
				GameTooltip:AddDoubleLine("Sale price before this scan", ns.Money(old), 1, 1, 1, 1, 1, 1)
				GameTooltip:AddDoubleLine("Sale price now", ns.Money(new), 1, 1, 1, 1, 1, 1)
			end
			if ns.totals.capped and ns.totals.capped[data.index] then
				GameTooltip:AddLine(("Check the price: it's listed at more than %d%% of the material cost. Profit "
					.. "counts today's listing; search it at the auction house before crafting."):format(ns.Queue.PriceCapPercent()),
					1, 0.6, 0.2, true)
			elseif ns.totals.spiked and ns.totals.spiked[data.index] then
				GameTooltip:AddLine(("Price spike: listed at %d%% of its usual price, so the profit counts the usual "
					.. "price. The spike may be over before these sell."):format(math.floor(ns.totals.spiked[data.index] * 100 + 0.5)),
					1, 0.6, 0.2, true)
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
		local crafter = ns.Recipes.Crafter(data.recipeID, data.char)
		GameTooltip:AddLine("Crafted by " .. ns.CharLabel(crafter), 0.6, 0.8, 1)
		SKILL.AddLine(data.recipeID, crafter)
		GameTooltip:Show()
	elseif data.kind == "auto" then
		local recipe = ns.db.recipes[data.craft.recipeID]
		StartItemTooltip(row, recipe and recipe.o, data.craft.recipeID)
		GameTooltip:AddLine(("Sub-craft: %d needed by the queue, made by %s."):format(data.craft.subCount,
			ns.CharLabel(data.craft.char)), 0.6, 0.8, 1, true)
		SKILL.AddLine(data.craft.recipeID, data.craft.char)
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
	elseif data and data.kind == "recipe" then
		local recipeID = data.row.recipeID
		local recipeData = ns.RecipeBook.Data(recipeID)
		if IsModifiedClick and IsModifiedClick("CHATLINK") then
			local link = recipeData and recipeData.i and select(2, C_Item.GetItemInfo(recipeData.i))
			if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
		else
			RECIPE.ShowWowhead(recipeID, recipeData and recipeData.i)
		end
	elseif data and (data.kind == "profit" or data.kind == "skill") then
		local recipeID = data.kind == "profit" and data.result.recipeID or data.row.recipeID
		if ns.Recipes.Knows(ns.CharKey(), recipeID) and ns.Recipes.OpenRecipes()[recipeID] then
			C_TradeSkillUI.OpenRecipe(recipeID)
		end
	end
end

local function SmallButton(parent, text, onClick)
	local button = FlatButton(parent, text, 20, 18)
	button:SetScript("OnClick", onClick)
	return button
end

-- Column widths in the lists.
local COLUMN = {
	QUEUE = 80,
	PROFIT = 110, -- fits "cost 12g 34s 56c" for bind-on-pickup crafts
	CHANCE = 44,
	RESTOCK = 38,
	WRIT = 76,
	RESTOCK_PROFIT = 76, -- Restock: profit per craft
	RECIPE_MONEY = 72, -- Recipes mode: AH price and Profit
	PAYBACK = 62,
}

-- Tooltips for + and -, by the kind of row they're on: title, then the help line.
local PLUS_TIPS = {
	profit = { "Queue one craft", "Shift: ten. Right-click or Ctrl-click: type an amount." },
	skill = { "Queue one craft", "Shift: ten. Right-click or Ctrl-click: type an amount." },
	queue = { "Add one craft", "Shift: ten. Or type the amount in the box." },
	restock = { "Raise the goal by one", "Shift: ten. Or type the goal in the box." },
	writ = { "Queue this writ", "The queue's shopping list gets the writ and the item it wants, or the item's materials "
		.. "when crafting it yourself is cheaper. Take it off again on the Queue tab." },
	crate = { "Queue one crate", "Shift: five. The queue's shopping list gets the crate and its cheapest bundle of "
		.. "materials. Take it off again on the Queue tab." },
	want = { "Add one", "Shift: five. Or type the amount in the box." },
}
local MINUS_TIPS = {
	queue = { "Remove one craft", "Shift: ten, down to one. At one, - removes the entry." },
	want = { "Remove one", "At one, - removes the entry." },
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
	if data and (data.kind == "queue" or data.kind == "want") then return { entry = data.entry, want = data.kind == "want" } end
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
		for index, entry in ipairs(target.want and ns.db.wanted or ns.db.queue) do
			if entry == target.entry then
				if target.want then ns.Queue.SetWanted(index, value) else ns.Queue.Set(index, value) end
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
	row.profit:SetWidth(COLUMN.PROFIT)
	return { { row.plus, 2 }, { row.profit, 6 }, { row.chance, 6 } }
end

-- The Recipes columns, right to left: Pays back, Profit, AH price, Source, Skill. The rightmost lines up with the
-- other modes' (where they have the + button).
function RECIPE.Controls(row)
	row.profit:SetWidth(COLUMN.PAYBACK)
	row.colAH:SetWidth(COLUMN.RECIPE_MONEY)
	row.colHave:SetWidth(COLUMN.RECIPE_MONEY)
	row.cost:SetWidth(COLUMN.QUEUE)
	return { { row.profit, 26 }, { row.colAH, 6 }, { row.colHave, 6 }, { row.cost, 6 }, { row.chance, 6 } }
end

local function SkillControls(row)
	row.profit:SetWidth(COLUMN.QUEUE)
	return { { row.plus, 2 }, { row.profit, 6 }, { row.cost, 6 }, { row.chance, 6 } }
end

-- The Stock level slider and the flashes on restock rows when their numbers change. seen = what each restock row last
-- showed, by item; emptied when the tab closes. sliders = the slider on the Restock tab and the one in Options.
local Live = {
	LEVEL_BOTTOM = 98, -- the slider's row in the Restock footer
	REDRAW_DELAY = 0.03, -- one redraw per frame or so while dragging
	FLASHES = 2,
	FLASH_ALPHA = 0.45,
	UP = { 0.25, 0.9, 0.35 },
	DOWN = { 1, 0.3, 0.25 },
	CHANGED = { 1, 0.82, 0.2 }, -- a plan check changed this row
	PLAN_NEWS = 10, -- seconds a changed row still pulses when it's first drawn (on opening the Queue tab)
	NOTE_SECONDS = 6,
	HELD_TEXT = "Plan checked: still the cheapest way",
	CHANGED_TEXT = "Plan updated for the new prices: %d change%s",
	seen = {},
	sliders = {},
	verdicts = {}, -- frame -> its plan check note and glow (the stub test's frames answer every unset field)
}

local function RestockControls(row)
	row.profit:SetWidth(COLUMN.RESTOCK_PROFIT)
	return {
		{ row.remove, 2 }, { row.plus, 6 }, { row.amount, 6 }, { row.minus, 8 }, { row.reset, 4 },
		{ row.colCraft, 4 }, { row.colHave, 6 }, { row.colAH, 6 }, { row.chance, 6 }, { row.profit, 6 },
	}
end

local function SalesControls(row)
	row.profit:SetWidth(COLUMN.QUEUE)
	return { { row.profit, 6 }, { row.cost, 6 }, { row.colAH, 6 }, { row.colHave, 6 }, { row.chance, 6 } }
end


local function WritControls(row)
	for _, region in ipairs({ row.profit, row.cost, row.colHave, row.colAH }) do region:SetWidth(COLUMN.WRIT) end
	return { { row.plus, 2 }, { row.profit, 6 }, { row.cost, 6 }, { row.colHave, 6 }, { row.colAH, 6 } }
end

local function IncomingControls(row)
	return { { row.cost, 6 }, { row.profit, 6 } }
end

local function QueueControls(row)
	row.profit:SetWidth(COLUMN.QUEUE)
	return {
		{ row.remove, 4 }, { row.quote, 8 }, { row.plus, 6 }, { row.amount, 6 }, { row.minus, 8 },
		{ row.profit, 8 }, { row.cost, 4 },
	}
end

-- A queued writ or crate: the queue row's controls without the quote and the profit.
local function WantControls(row)
	return { { row.remove, 4 }, { row.plus, 30 }, { row.amount, 6 }, { row.minus, 8 }, { row.cost, 8 } }
end

-- Right-click or Ctrl-click on a Profit row's +: a small box to type how many crafts to queue.
local amountPopup
local function AskQueueAmount(owner, recipeID)
	if not amountPopup then
		local frame = CreateFrame("Frame", "CFFAmountPopup", main.frame, "BackdropTemplate")
		frame:SetSize(220, 60)
		frame:SetFrameStrata("DIALOG")
		ThemeBackdrop(frame)
		frame:EnableMouse(true)

		frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		frame.title:SetPoint("TOPLEFT", 10, -9)
		frame.title:SetPoint("TOPRIGHT", -10, -9)
		frame.title:SetJustifyH("LEFT")
		frame.title:SetWordWrap(false)

		local box = SkinBox(CreateFrame("EditBox", nil, frame, "InputBoxTemplate"))
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
		local queue = FlatButton(frame, "Queue", 64, 22, true)
		queue:SetPoint("LEFT", box, "RIGHT", 8, 0)
		queue:SetScript("OnClick", Accept)
		local cancel = FlatButton(frame, CANCEL or "Cancel", 64, 22)
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

local function CreateRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_HEIGHT)
	row:SetHighlightTexture(WHITE, "ADD")
	local rowGlow = row:GetHighlightTexture()
	if rowGlow then rowGlow:SetVertexColor(0.30, 0.55, 1, ROW_GLOW) end
	row:SetScript("OnEnter", RowOnEnter)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnClick", RowOnClick)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(18, 18)
	row.icon:SetPoint("LEFT", 2, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- without the icon's own rounded border

	-- Behind a section heading: a faint blue band with a bright mark at its left end.
	row.band = row:CreateTexture(nil, "BACKGROUND")
	row.band:SetAllPoints()
	row.band:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.10)
	row.band:Hide()
	row.bandMark = row:CreateTexture(nil, "BORDER")
	row.bandMark:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.9)
	row.bandMark:SetWidth(2)
	row.bandMark:SetPoint("TOPLEFT")
	row.bandMark:SetPoint("BOTTOMLEFT")
	row.bandMark:Hide()

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
		elseif data.kind == "writ" then
			ns.Queue.Want("writ", data.row.writ.id, 1)
		elseif data.kind == "crate" then
			ns.Queue.Want("crate", data.row.crate.id, IsShiftKeyDown() and 5 or 1)
		elseif data.kind == "want" then
			ns.Queue.ChangeWanted(data.index, IsShiftKeyDown() and 5 or 1)
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
		elseif data.kind == "want" then
			ns.Queue.ChangeWanted(data.index, -1)
		elseif data.kind == "restock" then
			ns.Restock.SetGoal(data.row.itemID, data.row.goal - (IsShiftKeyDown() and 10 or 1))
			UI.Refresh("restock")
		end
	end)
	row.minus:SetScript("OnEnter", function(self) ButtonTip(self, MINUS_TIPS) end)
	row.minus:SetScript("OnLeave", GameTooltip_Hide)

	-- The amount between - and +: queued crafts, or a restock goal. Saved on Enter or when it loses focus.
	local amount = SkinBox(CreateFrame("EditBox", nil, row, "InputBoxTemplate"))
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
		if data and data.kind == "want" then ns.Queue.SetWanted(data.index, 0) end
		if data and data.kind == "restock" then
			ns.Restock.SetSkipped(data.row.itemID, not ns.Restock.Skipped(data.row.itemID))
			UI.Refresh("restock")
		end
	end)
	row.remove:SetScript("OnEnter", function(self)
		local data = self:GetParent().data
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if data and data.kind == "restock" then
			local skipping = ns.Restock.Skipped(data.row.itemID)
			GameTooltip:SetText(skipping and "Restock it again" or "Skip for now")
			GameTooltip:AddLine(skipping and "Skipped until you /reload or log out. Click to restock it again."
				or "Leaves it out of Queue restock until you /reload or log out, without changing its goal. "
				.. "Restock crafts of it already on the queue come off when you queue the restock.", 1, 1, 1, true)
		else
			GameTooltip:SetText("Remove from the queue")
		end
		GameTooltip:Show()
	end)
	row.remove:SetScript("OnLeave", GameTooltip_Hide)

	-- Behind a queue entry that would lose money.
	row.tint = row:CreateTexture(nil, "BACKGROUND")
	row.tint:SetAllPoints()
	row.tint:SetColorTexture(0.8, 0.1, 0.1, 0.18)
	row.tint:Hide()

	-- A restock row's numbers flash green when its goal or crafts go up, red when they go down (Stock level slider,
	-- gold, sales). Over the right-hand columns only; placed in SetRow, since those move.
	row.flash = row:CreateTexture(nil, "BORDER")
	row.flash:SetTexture(WHITE)
	row.flash:SetPoint("TOP", row, "TOP", 0, 0)
	row.flash:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
	row.flash:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.flash:SetAlpha(0)
	row.live = {} -- anim, item (the stub test's frames answer every unset field, so not on the row itself)
	local flash = row.flash.CreateAnimationGroup and row.flash:CreateAnimationGroup()
	if flash then
		flash:SetLooping("NONE")
		for i = 1, Live.FLASHES do
			local up = flash:CreateAnimation("Alpha")
			up:SetFromAlpha(0)
			up:SetToAlpha(Live.FLASH_ALPHA)
			up:SetDuration(0.12)
			up:SetOrder(i * 2 - 1)
			local down = flash:CreateAnimation("Alpha")
			down:SetFromAlpha(Live.FLASH_ALPHA)
			down:SetToAlpha(0)
			down:SetDuration(0.38)
			down:SetOrder(i * 2)
			if down.SetSmoothing then down:SetSmoothing("OUT") end
		end
		flash:SetScript("OnFinished", function() row.flash:SetAlpha(0) end)
		row.live.anim = flash
	end

	-- Columns: the queue's materials and profit for the whole entry, the Profit tab's sell chance and profit.
	for _, key in ipairs({ "cost", "profit", "chance" }) do
		row[key] = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row[key]:SetWidth(key == "chance" and COLUMN.CHANCE or COLUMN.QUEUE)
		row[key]:SetJustifyH("RIGHT")
		row[key]:SetWordWrap(false)
	end

	-- Restock's columns: on the AH, held, crafts to queue.
	for _, key in ipairs({ "colAH", "colHave", "colCraft" }) do
		row[key] = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row[key]:SetWidth(COLUMN.RESTOCK)
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
		GameTooltip:AddLine(("This item has its own goal. Click to go back to the %s%s."):format(
			ns.Restock.SmartOn() and "smart goal" or "default", default and (" (" .. default .. ")") or ""), 1, 1, 1, true)
		GameTooltip:Show()
	end)
	row.reset:SetScript("OnLeave", GameTooltip_Hide)

	-- The Profit headings are buttons, styled like the column headers of the game's own lists: a shaded box that lights
	-- up under the mouse, and an arrow on every one (bright on the sorted column, faint on the others).
	row.sortHeadings = {}
	for _, key in ipairs({ "name", "zone", "chance", "cost", "profit", "net", "back" }) do
		local heading = CreateFrame("Button", nil, row)
		heading:SetHeight(ROW_HEIGHT - 4)
		heading.key = key
		local bg = heading:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(THEME.button[1], THEME.button[2], THEME.button[3], 1)
		local glow = heading:CreateTexture(nil, "HIGHLIGHT")
		glow:SetAllPoints()
		glow:SetColorTexture(0.30, 0.55, 1, 0.25)
		heading.edge = heading:CreateTexture(nil, "ARTWORK")
		heading.edge:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
		heading.edge:SetHeight(1)
		heading.edge:SetPoint("BOTTOMLEFT")
		heading.edge:SetPoint("BOTTOMRIGHT")
		heading.arrow = heading:CreateTexture(nil, "OVERLAY")
		heading.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
		heading.arrow:SetSize(9, 10)
		heading.label = heading:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		if key == "name" or key == "zone" then
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
			.. ("The margin is %d%%; change it on the Options tab. You press Enter to send it."):format(ns.Queue.QuoteMargin()),
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

function Live.StopFlash(row)
	if row.live.anim then row.live.anim:Stop() end
	row.flash:SetAlpha(0)
	row.live.item = nil
end

-- Compares a restock row with what was last shown for its item and flashes the change: green for more (goal, or crafts
-- when the goal stayed), red for fewer.
function Live.Flash(row, item)
	local seen = Live.seen[item.itemID]
	Live.seen[item.itemID] = { goal = item.goal, crafts = item.crafts }
	if not seen then return end
	local change = item.goal - seen.goal
	if change == 0 then change = item.crafts - seen.crafts end
	if change == 0 then return end
	local color = change > 0 and Live.UP or Live.DOWN
	row.flash:SetVertexColor(color[1], color[2], color[3])
	row.flash:SetPoint("LEFT", row.colCraft, "LEFT", -4, 0)
	row.live.item = item.itemID
	if row.live.anim then
		row.live.anim:Stop()
		row.live.anim:Play()
	end
end

-- Plan check (ns.PlanCheck): the key a Queue row has in a plan's shape, nil for rows a price can't change.
function Live.PlanKey(data)
	if data.kind == "item" and data.itemID then return "i" .. data.itemID end
	if data.kind == "auto" and data.craft then return "r" .. data.craft.recipeID end
	return nil
end

-- A row whose buying or sub-crafting the last plan check changed pulses, once, while that's news.
function Live.PlanPulse(row, key)
	local result = ns.PlanCheck and ns.PlanCheck.result
	if not (result and result.changed[key]) or GetTime() - result.at > Live.PLAN_NEWS then return end
	if result.pulsed[row] == key then return end
	result.pulsed[row] = key
	local color = Live.CHANGED
	row.flash:SetVertexColor(color[1], color[2], color[3])
	row.flash:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.live.item = key
	if row.live.anim then
		row.live.anim:Stop()
		row.live.anim:Play()
	end
end

-- The verdict on a window: a note on it for a few seconds, and a green pulse round it when the plan held.
-- above = put the note above the window (the small Next step bar) instead of inside its top.
function Live.Verdict(frame, held, text, above)
	local verdict = Live.verdicts[frame]
	if not verdict then
		verdict = {}
		local glow = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		glow:SetAllPoints()
		glow:SetFrameLevel((frame:GetFrameLevel() or 0) + 40)
		glow:EnableMouse(false)
		glow:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 3 })
		glow:SetBackdropColor(Live.UP[1], Live.UP[2], Live.UP[3], 0.12)
		glow:SetBackdropBorderColor(Live.UP[1], Live.UP[2], Live.UP[3], 1)
		glow:SetAlpha(0)
		glow:Hide()
		local anim = glow.CreateAnimationGroup and glow:CreateAnimationGroup()
		if anim then
			for i = 1, Live.FLASHES do
				local up = anim:CreateAnimation("Alpha")
				up:SetFromAlpha(0)
				up:SetToAlpha(1)
				up:SetDuration(0.15)
				up:SetOrder(i * 2 - 1)
				local down = anim:CreateAnimation("Alpha")
				down:SetFromAlpha(1)
				down:SetToAlpha(0)
				down:SetDuration(0.45)
				down:SetOrder(i * 2)
			end
			anim:SetScript("OnFinished", function()
				glow:SetAlpha(0)
				glow:Hide()
			end)
		end
		verdict.glow, verdict.anim = glow, anim

		local note = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		note:SetFrameLevel((frame:GetFrameLevel() or 0) + 41)
		note:EnableMouse(false)
		ThemeBackdrop(note, 0.95)
		note:SetHeight(26)
		if above then
			note:SetPoint("BOTTOM", frame, "TOP", 0, 4)
		else
			note:SetPoint("TOP", frame, "TOP", 0, -40)
		end
		local label = note:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("CENTER")
		note.label = label
		note:Hide()
		verdict.note = note
		Live.verdicts[frame] = verdict
	end

	local color = held and Live.UP or Live.CHANGED
	verdict.note.label:SetText(text)
	verdict.note.label:SetTextColor(color[1], color[2], color[3])
	verdict.note:SetBackdropBorderColor(color[1], color[2], color[3], 1)
	verdict.note:SetWidth(math.max(160, (verdict.note.label:GetStringWidth() or 0) + 28))
	verdict.note:Show()
	verdict.shownAt = GetTime()
	local shownAt = verdict.shownAt
	C_Timer.After(Live.NOTE_SECONDS, function()
		if verdict.shownAt == shownAt then verdict.note:Hide() end
	end)
	if held then
		verdict.glow:Show()
		if verdict.anim then
			verdict.anim:Stop()
			verdict.anim:Play()
		end
	end
end

-- A plan check ended (ns.PlanCheck.AfterBuild): say so on whichever windows are up, in chat when none is, and redraw
-- so the changed rows pulse.
function UI.PlanChecked(result)
	local held = result.count == 0
	local text = held and Live.HELD_TEXT
		or Live.CHANGED_TEXT:format(result.count, result.count == 1 and "" or "s")
	local shown = false
	if main and main.frame:IsShown() then
		Live.Verdict(main.frame, held, text)
		shown = true
	end
	if windows.next and windows.next.frame:IsShown() then
		Live.Verdict(windows.next.frame, held, text, true)
		shown = true
	end
	if not shown then ns.Say("chatPlan", text) end
	UI.lastVerdict = text
	UI.RefreshQueue()
end

local function SetRow(row, data)
	row.data = data
	row.plus:Hide()
	row.minus:Hide()
	row.remove:Hide()
	row.remove:SetAlpha(1)
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
	if rowGlow then rowGlow:SetAlpha(sortable and 0 or ROW_GLOW) end
	local banded = data.kind == "header" and not sortable
	row.band:SetShown(banded)
	row.bandMark:SetShown(banded)
	row.tint:Hide()
	-- A flash belongs to its item: a reused row mustn't carry it to another.
	local planKey = Live.PlanKey(data)
	if row.live.item and not ((data.kind == "restock" and data.row.itemID == row.live.item)
		or (planKey and planKey == row.live.item)) then
		Live.StopFlash(row)
	end
	if planKey then Live.PlanPulse(row, planKey) end
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
			-- Sortable headings: Profit has Recipe, Sells, Profit; Skill up has Recipe, Chance, Craft, Per point; Writs
			-- has Item wanted, Writ, Net, Per rep, and a plain Item heading between.
			local mode = data.columns
			local columns
			if mode == "profit" then
				PlaceRight(row, ProfitControls(row), false)
				columns = { chance = { row.chance, "Sells" }, profit = { row.profit, "Profit" } }
			elseif mode == "writs" then
				PlaceRight(row, WritControls(row), false)
				columns = { chance = { row.colAH, "Writ" }, cost = { row.cost, "Net" }, profit = { row.profit, "Per rep" } }
				row.colHave:SetText(Color("ffffd100", "Item"))
				row.colHave:Show()
			elseif mode == "recipes" then
				PlaceRight(row, RECIPE.Controls(row), false)
				columns = { chance = { row.chance, "Skill" }, cost = { row.cost, "Source" }, profit = { row.colHave, "AH price" },
					net = { row.colAH, "Profit" }, back = { row.profit, "Pays back" } }
			elseif mode == "crates" then
				PlaceRight(row, WritControls(row), false)
				columns = { chance = { row.colAH, "Price" }, cost = { row.cost, "Favor" }, profit = { row.profit, "Per Favor" } }
				row.colHave:SetText(Color("ffffd100", "Fill"))
				row.colHave:Show()
			else
				PlaceRight(row, SkillControls(row), false)
				columns = { chance = { row.chance, "Chance" }, cost = { row.cost, "Craft" }, profit = { row.profit, "Per point" } }
			end
			row.left:SetText("")
			local sortKey, ascending = UI.ListSort(mode)
			local headings = row.sortHeadings
			headings.name.label:SetText(data.text)
			headings.name:ClearAllPoints()
			headings.name:SetPoint("LEFT", row, "LEFT", 0, 0)
			headings.name:SetWidth((headings.name.label:GetStringWidth() or 40) + 26)
			-- Writs also sort by where they're handed in: a heading right after the name's.
			local zone = mode == "writs"
			if zone then
				headings.zone.label:SetText("Zone")
				headings.zone:ClearAllPoints()
				headings.zone:SetPoint("LEFT", headings.name, "RIGHT", 4, 0)
				headings.zone:SetWidth((headings.zone.label:GetStringWidth() or 30) + 26)
			end
			for key, column in pairs(columns) do
				headings[key].label:SetText(column[2])
				headings[key]:ClearAllPoints()
				headings[key]:SetPoint("LEFT", column[1], "LEFT", -2, 0)
				headings[key]:SetPoint("RIGHT", column[1], "RIGHT", 2, 0)
			end
			for key, heading in pairs(headings) do
				if key == "name" or columns[key] or (key == "zone" and zone) then
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
			row.profit:SetText(Color("ffffd100", "Profit"))
			row.amountLabel:SetText("Goal")
			for _, region in ipairs({ row.chance, row.colAH, row.colHave, row.colCraft, row.profit, row.amountLabel }) do
				region:Show()
			end
		elseif data.columns == "incoming" then
			PlaceRight(row, IncomingControls(row), true)
			row.profit:SetText(Color("ffffd100", "Amount"))
			row.cost:SetText(Color("ffffd100", "Arrives in"))
		elseif data.columns == "sales" then
			PlaceRight(row, SalesControls(row), true)
			row.chance:SetText(Color("ffffd100", "Sells"))
			row.colHave:SetText(Color("ffffd100", "Sold"))
			row.colAH:SetText(Color("ffffd100", "Exp."))
			row.cost:SetText(Color("ffffd100", "Sales"))
			row.profit:SetText(Color("ffffd100", "Profit"))
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
		local spike = not result.capped and result.spiked and UsualText(result.ofNormal)
		row.left:SetText(ItemLabel(result.itemID) .. (result.capped and Color(COLOR_WARN, "  check price") or "")
			.. (spike and ("  " .. spike) or ""))
		PlaceRight(row, ProfitControls(row), true)
		if result.bound then
			row.profit:SetText(result.cost and (Color(COLOR_MUTED, "cost ") .. ns.Money(result.cost)) or Color(COLOR_MUTED, "no price"))
		elseif result.net then
			row.chance:SetText(ChanceText(ns.Items.Name(result.itemID)))
			row.profit:SetText(((result.capped or spike) and Color(COLOR_WARN, "! ") or "")
				.. Color(result.net >= 0 and COLOR_PROFIT or COLOR_LOSS, ns.Money(result.net)))
		else
			row.profit:SetText(Color(COLOR_MUTED, "no data"))
		end
	elseif data.kind == "recipe" then
		local item = data.row
		row.icon:SetTexture(ns.RecipeBook.Icon(item.recipeID))
		local text = Color(RECIPE.COLORS[item.status] or "ffffffff", item.name or "Loading...")
		if item.status == "learned" then text = text .. Color(COLOR_MUTED, "  learned") end
		if item.status == "learn" and ns.RecipeBook.fresh[item.recipeID] then text = text .. Color(RECIPE.COLORS.learn, "  new") end
		if data.who == "all" then
			local names = {}
			for _, char in ipairs(item.chars) do
				if char.status == "learn" or char.status == "skill" then table.insert(names, ns.CharLabel(char.key)) end
			end
			if #names > RECIPE.NAMES_ON_ROW then
				local more = #names - RECIPE.NAMES_ON_ROW
				for i = #names, RECIPE.NAMES_ON_ROW + 1, -1 do names[i] = nil end
				names[#names + 1] = "+" .. more
			end
			if #names > 0 then text = text .. "  " .. Color(RECIPE.WHO, table.concat(names, ", ")) end
		end
		row.left:SetText(text)
		PlaceRight(row, RECIPE.Controls(row), true)
		row.chance:SetText(item.skill and Color(item.status == "skill" and RECIPE.SKILL_SHORT or "ffffffff",
			tostring(item.skill)) or Color(COLOR_MUTED, "?"))
		row.cost:SetText(item.source)
		if item.bound then
			row.colHave:SetText(Color(COLOR_MUTED, "BoP"))
		else
			row.colHave:SetText(item.price and ns.Money(item.price) or "")
		end
		row.colAH:SetText(RECIPE.ProfitText(item))
		row.profit:SetText(RECIPE.PaybackText(item))
	elseif data.kind == "skill" then
		local item = data.row
		local recipe = ns.db.recipes[item.recipeID]
		local spellIcon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(item.recipeID))
			or (GetSpellTexture and GetSpellTexture(item.recipeID))
		row.icon:SetTexture(item.itemID and ns.Items.Icon(item.itemID) or spellIcon or 134400)
		local hex = SKILL.COLORS[item.difficulty]
		row.left:SetText(Color(hex, recipe and recipe.n or "?")
			.. (item.points > 1 and Color(COLOR_MUTED, (" +%d per craft"):format(item.points)) or ""))
		PlaceRight(row, SkillControls(row), true)
		row.chance:SetText(Color(hex, SKILL.CHANCE_TEXT[item.difficulty]))
		row.cost:SetText(item.net and SKILL.CostText(item.net) or Color(COLOR_MUTED, "no price"))
		row.profit:SetText(item.perPoint and SKILL.CostText(item.perPoint) or Color(COLOR_MUTED, "?"))
	elseif data.kind == "queue" then
		local entry = data.entry
		local recipe = ns.db.recipes[entry.recipeID]
		row.icon:SetTexture(recipe and recipe.o and ns.Items.Icon(recipe.o) or 134400)
		local net = ns.totals.entries[data.index]
		local capped = ns.totals.capped and ns.totals.capped[data.index]
		local spike = ns.totals.spiked and UsualText(ns.totals.spiked[data.index])
		local boundCost = ns.totals.boundEntries[data.index]
		local change = not boundCost and recipe and recipe.o and PriceChangeText(recipe.o, false)
		-- Who crafts it, when that isn't the character you're on.
		local crafter = ns.Recipes.Crafter(entry.recipeID, entry.char)
		local onAlt = crafter ~= ns.CharKey() and Color("ff99ccff", "  " .. ns.CharLabel(crafter)) or ""
		row.left:SetText(RecipeName(entry.recipeID, crafter) .. onAlt
			.. (entry.restock and Color(COLOR_MUTED, " restock") or "")
			.. (data.run and data.run > 0 and data.run < entry.qty and Color("ff99ccff", ("  this run: %d"):format(data.run)) or "")
			.. (capped and Color(COLOR_WARN, "  check price") or "")
			.. (spike and ("  " .. spike) or "")
			.. (change and ("   " .. Color(COLOR_MUTED, "sells ") .. change) or ""))
		PlaceRight(row, QueueControls(row), true)
		ShowAmount(row, data, entry.qty)
		-- Both columns are for the whole entry, every queued craft.
		local cost = boundCost or (data.matCost and data.matCost * entry.qty)
		row.cost:SetText(cost and ns.Money(cost) or Color(COLOR_MUTED, "?"))
		row.tint:SetColorTexture(0.8, 0.1, 0.1, 0.18)
		row.tint:SetShown(net ~= nil and net < 0 and not boundCost)
		row.profit:SetText(boundCost and Color(COLOR_MUTED, "can't sell")
			or net and (((capped or spike) and Color(COLOR_WARN, "! ") or "") .. Color(net >= 0 and COLOR_PROFIT or COLOR_LOSS, ns.Money(net)))
			or Color(COLOR_MUTED, "no price"))
	elseif data.kind == "want" then
		local want = data.entry
		row.icon:SetTexture(ns.Items.Icon(want.id) or 134400)
		local note
		if want.kind == "writ" then
			local writ = ns.Writs.ByID(want.id)
			note = writ.item and ("with " .. (ns.Items.Name(writ.item) or "...") .. (writ.count > 1 and " x" .. writ.count or ""))
		elseif data.fill then
			note = "fill with " .. BundleText(data.fill)
		end
		row.left:SetText(ItemLabel(want.id) .. (note and Color(COLOR_MUTED, "  " .. note) or ""))
		PlaceRight(row, WantControls(row), true)
		ShowAmount(row, data, want.qty)
		row.cost:SetText(data.cost and ns.Money(data.cost * want.qty) or Color(COLOR_MUTED, "?"))
	elseif data.kind == "restock" then
		local item = data.row
		row.icon:SetTexture(ns.Items.Icon(item.itemID))
		row.left:SetText(ItemLabel(item.itemID))
		PlaceRight(row, RestockControls(row), true)
		ShowAmount(row, data, item.goal)
		-- Grey: follows the default. White, with the reset arrow: the player's own goal for this item.
		local custom = ns.Restock.IsCustom(item.itemID)
		row.reset:SetShown(custom)
		-- Blue: a smart goal that differs from the default.
		local smart = not custom and ns.Restock.SmartInfo(item.itemID)
		if custom then
			row.amount:SetTextColor(1, 1, 1)
		elseif smart and item.goal ~= smart.base then
			row.amount:SetTextColor(0.45, 0.75, 1)
		else
			row.amount:SetTextColor(0.6, 0.6, 0.6)
		end
		row.chance:SetText(ChanceText(ns.Items.Name(item.itemID)))
		row.profit:SetText(item.net and Color(item.net >= 0 and COLOR_PROFIT or COLOR_LOSS, ns.Money(item.net))
			or Color(COLOR_MUTED, "-"))
		row.colAH:SetText(item.onAH and tostring(item.onAH) or Color(COLOR_MUTED, "?"))
		row.colHave:SetText(tostring(item.owned))
		local skipping = ns.Restock.Skipped(item.itemID)
		row.remove:SetAlpha(skipping and 1 or 0.5)
		if skipping then
			row.left:SetText(Color(COLOR_MUTED, ns.Items.Name(item.itemID) or "?"))
			row.colCraft:SetText(Color("ffffb040", "skipped"))
		elseif item.goal == 0 then
			row.colCraft:SetText(smart and smart.paused and Color("ffffb040", "paused") or Color(COLOR_MUTED, "skip"))
		elseif item.cooldown then
			-- The recipe is on cooldown for its crafter (a transmute).
			row.colCraft:SetText(Color("ffffb040", "cooldown"))
		elseif item.wanted or item.dear or item.camp or item.cooldownWanted then
			-- Cut to what your gold covers, to what's still worth making at what the materials really cost, to
			-- the one camp station an hour and its window, or to one craft per cooldown: crafts of wanted.
			row.colCraft:SetText(Color(item.crafts > 0 and "ffffb040" or COLOR_LOSS, tostring(item.crafts))
				.. Color(COLOR_MUTED, "/" .. (item.dear or (item.camp and item.camp.wanted) or item.wanted
				or item.cooldownWanted)))
		elseif item.trim then
			-- More queued than the stock still needs.
			row.colCraft:SetText(Color(COLOR_LOSS, "-" .. item.trim))
		elseif item.crafts > 0 then
			row.colCraft:SetText(Color("ffffb040", (item.queued and "+" or "") .. item.crafts))
		elseif item.queued then
			-- Already on the queue from an earlier restock.
			row.colCraft:SetText(Color("ff73bfff", item.queued .. "q"))
		else
			row.colCraft:SetText(Color(COLOR_PROFIT, "0"))
		end
		Live.Flash(row, item)
	elseif data.kind == "incoming" then
		local entry = data.entry
		row.icon:SetTexture(entry.itemID and ns.Items.Icon(entry.itemID) or 134400)
		local label = entry.itemID and ItemLabel(entry.itemID) or entry.name
		if entry.char ~= ns.CharKey() then label = label .. Color(COLOR_MUTED, "  " .. ns.CharLabel(entry.char)) end
		row.left:SetText(label)
		PlaceRight(row, IncomingControls(row), true)
		row.profit:SetText(entry.amount and ((entry.rough and Color(COLOR_MUTED, "~") or "") .. ns.Money(entry.amount))
			or Color(COLOR_MUTED, "?"))
		local wait = entry.due - time()
		row.cost:SetText(wait > 0 and ns.Sales.WaitText(wait) or Color(COLOR_PROFIT, "in mailbox"))
	elseif data.kind == "sales" then
		local item = data.item
		if item.itemID then
			row.icon:SetTexture(ns.Items.Icon(item.itemID))
			row.left:SetText(ItemLabel(item.itemID))
		else
			row.icon:SetTexture(134400) -- sold mail names the item but has no ID: the question mark, not a gap
			row.left:SetText(item.name)
		end
		local profit, rough, sold, expired, gold = ns.Sales.Profit(item, 7)
		PlaceRight(row, SalesControls(row), true)
		row.chance:SetText(ChanceText(item.name))
		row.colHave:SetText(tostring(sold))
		row.colAH:SetText(expired > 0 and Color(COLOR_LOSS, tostring(expired)) or Color(COLOR_MUTED, "0"))
		row.cost:SetText(sold > 0 and ns.Money(gold) or Color(COLOR_MUTED, "-"))
		row.profit:SetText(sold > 0 and ((rough and Color(COLOR_MUTED, "~") or "")
			.. Color(profit < 0 and COLOR_LOSS or COLOR_PROFIT, ns.Money(profit))) or Color(COLOR_MUTED, "-"))
	elseif data.kind == "writ" then
		local item, writ = data.row, data.row.writ
		row.icon:SetTexture(writ.item and ns.Items.Icon(writ.item) or 134400)
		local label = writ.item and ItemLabel(writ.item) or ns.Writs.Name(writ) or Color(COLOR_MUTED, "Loading...")
		if writ.count > 1 then label = label .. " x" .. writ.count end
		local where = ns.Writs.TIERS[writ.tier]
		if writ.zone then where = where .. ", " .. writ.zone .. (writ.zoneGuess and "?" or "") end
		Held.Mark(row, item.held)
		row.left:SetText(Held.Text(item.held) .. label .. "  " .. (item.done and Color(COLOR_PROFIT, "done today") or Color(COLOR_MUTED, where))
			.. (item.queued > 0 and Color("ff7fb8ff", "  queued") or ""))
		PlaceRight(row, WritControls(row), true)
		row.colAH:SetText(item.writPrice and Color(item.haveWrit and COLOR_PROFIT or "ffffffff", ns.Money(item.writPrice))
			or Color(item.haveWrit and COLOR_PROFIT or COLOR_MUTED, item.haveWrit and "have" or "no price"))
		row.colHave:SetText(item.itemCost
			and Color(item.haveItem and COLOR_PROFIT or item.kind == "craft" and "ff7fb8ff" or "ffffffff", ns.Money(item.itemCost))
			or Color(item.haveItem and COLOR_PROFIT or COLOR_MUTED, item.haveItem and "have" or "no price"))
		row.cost:SetText(item.net and Color(item.net < 0 and COLOR_LOSS or COLOR_PROFIT, ns.Money(item.net))
			or Color(COLOR_MUTED, "-"))
		row.profit:SetText(item.perRep and (item.perRep > 0 and ns.Money(item.perRep) or Color(COLOR_PROFIT, "free"))
			or Color(COLOR_MUTED, "-"))
	elseif data.kind == "crate" then
		local item, crate = data.row, data.row.crate
		row.icon:SetTexture(ns.Items.Icon(crate.id) or 134400)
		local label = ns.Crates.Name(crate) or Color(COLOR_MUTED, "Loading...")
		local note = item.best and BundleText(item.best) or ns.Crates.TIERS[crate.tier]
		Held.Mark(row, item.held)
		row.left:SetText(Held.Text(item.held) .. label .. "  " .. (item.cheapest and Color(COLOR_PROFIT, "best buy: " .. note) or Color(COLOR_MUTED, note))
			.. (item.queued > 0 and Color("ff7fb8ff", "  queued x" .. item.queued) or ""))
		PlaceRight(row, WritControls(row), true)
		row.colAH:SetText(item.cratePrice and Color(item.haveCrate and COLOR_PROFIT or "ffffffff", ns.Money(item.cratePrice))
			or Color(item.haveCrate and COLOR_PROFIT or COLOR_MUTED, item.haveCrate and "have" or "no price"))
		row.colHave:SetText(item.fillCost
			and Color(item.haveFill and COLOR_PROFIT or item.best.kind == "craft" and "ff7fb8ff" or "ffffffff", ns.Money(item.fillCost))
			or Color(COLOR_MUTED, "no price"))
		row.cost:SetText((item.rough and Color(COLOR_MUTED, "~") or "") .. item.tokens)
		row.profit:SetText(item.perToken and (item.perToken > 0 and ns.Money(item.perToken) or Color(COLOR_PROFIT, "free"))
			or Color(COLOR_MUTED, "-"))
	elseif data.kind == "post" then
		local item = data.row
		row.icon:SetTexture(ns.Items.Icon(item.itemID))
		row.left:SetText(ItemLabel(item.itemID))
		local held = ("%d in bags, AH %s/%d"):format(item.inBags, item.onAH and tostring(item.onAH) or "?", item.goal)
		if item.unitProfit then
			held = Color(item.unitProfit >= 0 and COLOR_PROFIT or COLOR_LOSS, (item.unitProfit >= 0 and "+" or "")
				.. ns.Money(item.unitProfit) .. " each") .. "   " .. held
		end
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
		local text = RecipeName(data.craft.recipeID, data.craft.char) .. " x" .. data.craft.subCount
		if data.craft.count > data.craft.subCount then
			text = text .. Color(COLOR_MUTED, (" (+%d queued)"):format(data.craft.count - data.craft.subCount))
		end
		row.left:SetText(text)
		row.right:SetText(Color(COLOR_MUTED, ns.CharLabel(data.craft.char)))
	elseif data.kind == "next" then
		local recipe = ns.db.recipes[data.recipeID]
		row.icon:SetTexture(recipe and recipe.o and ns.Items.Icon(recipe.o) or 134400)
		local crafter = ns.Recipes.Crafter(data.recipeID, data.char)
		row.left:SetText(RecipeName(data.recipeID, crafter))
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
		row.left:SetText(ItemLabel(data.itemID) .. (data.tool and Color(COLOR_MUTED, " (tool)") or "")
			.. (data.camp and Color(COLOR_MUTED, " (camp)") or ""))
		if data.priceLabel then
			-- Bought down the listings: what they average, as the cheapest one doesn't cover them all.
			local average = data.deep and data.total and (not data.price or data.total > data.price * data.count)
				and ("avg " .. ns.Money(data.total / data.count))
			local price = average or data.priceLabel == "max" and PriceChangeText(data.itemID, true)
				or (data.price and (data.priceLabel .. " " .. ns.Money(data.price)))
				or Color(COLOR_LOSS, "no price")
			local total = data.total and (", total " .. ns.Money(data.total)) or ""
			local thin = data.thin and Color(COLOR_WARN, data.thin >= data.count and ", none listed"
				or (", %d listed"):format(data.count - data.thin)) or ""
			row.right:SetText("x" .. data.count .. ", " .. price .. total .. thin)
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

-- A list's scroll position, the rows it shows at once and how far it scrolls; and moving it (Lock.lua follows the
-- item being read with these).
function UI.ListView(window)
	local visible = math.min(ROW_COUNT, math.floor(window.container:GetHeight() / ROW_HEIGHT))
	return window.offset, visible, math.max(0, #window.list - visible)
end

function UI.SetListOffset(window, offset)
	window.offset = math.max(0, offset)
	RenderRows(window)
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
		if tab.key == "queue" and ns.Queue.Count() > 0 then title = ("%s (%d)"):format(title, ns.Queue.Count()) end
		-- Notes for this version not opened yet: the tab is green with a dot, nothing pops up.
		local unseen = (tab.key == "changelog" and ns.WhatsNew and ns.WhatsNew.HasUnseen())
			or (tab.key == "profit" and RECIPE.NewCount() > 0)
		tab.label:SetText(Color(selected and "ffffffff" or (unseen and "ff55dd55" or "ffb8b8b8"), title))
		tab.badge:SetShown(unseen and true or false)
		-- Writs or crates in your possession: the tab shows how many, in gold, and pulses until you look.
		local held = (tab.key == "writs" and ns.Writs.Held()) or (tab.key == "crates" and ns.Crates.Held()) or 0
		tab.held = held
		if held > 0 then
			tab.label:SetText(Color(selected and "ffffffff" or "ffffd100", title)
				.. Color("ffffd100", (" (%d)"):format(held)))
		end
		if tab.key == "writs" or tab.key == "crates" then
			tab.flair:SetShown(held > 0)
			if tab.flairAnim then
				if held > 0 and not selected then
					if not tab.flairAnim:IsPlaying() then tab.flairAnim:Play() end
				elseif tab.flairAnim:IsPlaying() then
					tab.flairAnim:Stop()
				end
			end
		end
		local shade = selected and THEME.primary or THEME.button
		tab.bg:SetColorTexture(shade[1], shade[2], shade[3], selected and 0.55 or 0.6)
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
	UI.Refresh("writs")
	UI.Refresh("crates")
	UI.Refresh("options")
	UI.Refresh("posting")
	UpdateTabStrip()
end

function UI.RefreshTabs()
	UpdateTabStrip()
end

-- Queue, bags or bank changed: everything that counts stock needs redrawing.
-- For Data.lua: a recipe's colour changed.
function UI.UpdateNextStep() UpdateNextStep() end

function UI.RefreshQueue()
	UI.Refresh("queue")
	UI.Refresh("restock")
	UI.Refresh("posting")
	UI.Refresh("writs") -- their rows say what's queued
	UI.Refresh("crates")
	UpdateTabStrip()
	UpdateNextStep()
	ns.Vendor.Sync() -- the button under the merchant window follows the plan
end

local function SavePosition(key, frame)
	local left, top = frame:GetLeft(), frame:GetTop()
	if not (left and top) then return end
	ns.db.ui.positions = ns.db.ui.positions or {}
	ns.db.ui.positions[key] = { x = left, y = top }
end

local function HeaderButton(frame, text, width, onClick, primary)
	local button = FlatButton(frame, text, width, 22, primary)
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
	ThemeBackdrop(frame)
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
		if i % 2 == 0 then
			local stripe = row:CreateTexture(nil, "BACKGROUND", nil, -8)
			stripe:SetAllPoints()
			stripe:SetColorTexture(1, 1, 1, 0.025)
		end
		row:Hide()
		window.rows[i] = row
	end

	local slider = CreateFrame("Slider", nil, parent)
	slider:SetPoint("TOPRIGHT", -10, -top)
	slider:SetPoint("BOTTOMRIGHT", -10, footer)
	slider:SetWidth(8)
	local track = slider:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	track:SetColorTexture(1, 1, 1, 0.04)
	slider:SetOrientation("VERTICAL")
	slider:SetValueStep(1)
	slider:SetObeyStepOnDrag(true)
	local thumb = slider:CreateTexture(nil, "OVERLAY")
	thumb:SetColorTexture(THEME.buttonEdge[1], THEME.buttonEdge[2], THEME.buttonEdge[3], 1)
	thumb:SetSize(8, 36)
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
local function CreatePane(key, footerHeight, withTabs, listTop)
	local frame = CreateFrame("Frame", nil, main.frame)
	frame:Hide()
	local window = { key = key, frame = frame, list = {}, offset = 0, rows = {} }
	windows[key] = window
	CreateListArea(window, frame, withTabs and (10 + TAB_WIDTH) or 10, listTop or PANE_LIST_TOP, footerHeight, ROW_HEIGHT)

	if withTabs then
		window.tabs = {}
		for i = 1, TAB_COUNT do
			local tab = FlatButton(frame, "", TAB_WIDTH - 6, 24)
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
		{ key = "recipes", label = "Recipes", tip = "Every recipe in the game you haven't learned yet, by the skill it "
			.. "needs: hover one to see where it comes from and which of your characters has it. Bottom left switches "
			.. "between this character and all of them." },
	}) do
		local button = HeaderButton(window.frame, mode.label, 70, function()
			ns.db.ui.profitMode = mode.key
			window.offset = 0
			UI.Refresh("profit")
		end)
		if index == 1 then
			button:SetPoint("TOPLEFT", 10, -PANE_ACTIONS_TOP)
		else
			button:SetPoint("LEFT", modes[index - 1], "RIGHT", 0, 0)
		end
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(mode.label)
			GameTooltip:AddLine(mode.tip, 1, 1, 1, true)
			local new = mode.key == "recipes" and RECIPE.NewCount() or 0
			if new > 0 then
				GameTooltip:AddLine(("%s you can learn since you last looked."):format(ns.Plural(new, "new recipe", "new recipes")),
					0.33, 0.87, 0.33, true)
			end
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", GameTooltip_Hide)
		button.mode = mode
		-- Kept on the mode, not the button: a field a button doesn't have must read as nil.
		if mode.key == "recipes" then
			mode.badge = button:CreateTexture(nil, "OVERLAY")
			mode.badge:SetColorTexture(0.33, 0.87, 0.33, 1)
			mode.badge:SetSize(6, 6)
			mode.badge:SetPoint("TOPRIGHT", -3, -3)
			mode.badge:Hide()
		end
		modes[index] = button
	end
	window.modeButtons = modes

	local hideUnprofitable = CreateFrame("CheckButton", nil, window.frame, "UICheckButtonTemplate")
	hideUnprofitable:SetSize(24, 24)
	hideUnprofitable:SetPoint("LEFT", modes[#modes], "RIGHT", 10, 0)
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

	-- Skill up mode: what the crafts sell for counts at the auction house price, not only the vendor's.
	local sellAH = CreateFrame("CheckButton", nil, window.frame, "UICheckButtonTemplate")
	sellAH:SetSize(24, 24)
	sellAH:SetPoint("LEFT", modes[#modes], "RIGHT", 10, 0)
	sellAH:SetHitRectInsets(0, -100, 0, 0)
	local sellLabel = sellAH:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sellLabel:SetPoint("LEFT", sellAH, "RIGHT", 2, 1)
	sellLabel:SetText("Selling on the AH")
	sellAH:SetScript("OnClick", function(self)
		ns.db.ui.skillSellAH = self:GetChecked() and true or false
		window.offset = 0
		UI.Refresh("profit")
	end)
	sellAH:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Selling on the AH")
		GameTooltip:AddLine("What you level with costs its materials less what selling the results gets back. "
			.. "Unticked, that's what a vendor pays. Ticked, the auction house price after its 5% cut counts too, "
			.. "when it's more.", 1, 1, 1, true)
		GameTooltip:AddLine("Levelling makes many of one thing: the auction house may not take them all at that price.",
			0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	sellAH:SetScript("OnLeave", GameTooltip_Hide)
	window.sellAH = sellAH

	-- Recipes mode: learned recipes are left out unless this is ticked.
	local showLearned = CreateFrame("CheckButton", nil, window.frame, "UICheckButtonTemplate")
	showLearned:SetSize(24, 24)
	showLearned:SetPoint("LEFT", modes[#modes], "RIGHT", 10, 0)
	showLearned:SetHitRectInsets(0, -80, 0, 0)
	local learnedLabel = showLearned:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	learnedLabel:SetPoint("LEFT", showLearned, "RIGHT", 2, 1)
	learnedLabel:SetText("Show learned")
	showLearned:SetScript("OnClick", function(self)
		ns.db.ui.recipeLearned = self:GetChecked() and true or false
		window.offset = 0
		UI.Refresh("profit")
	end)
	window.showLearned = showLearned

	-- Recipes mode: only recipes whose craft can go on the auction house.
	local hideBound = CreateFrame("CheckButton", nil, window.frame, "UICheckButtonTemplate")
	hideBound:SetSize(24, 24)
	hideBound:SetPoint("LEFT", learnedLabel, "RIGHT", 10, -1)
	hideBound:SetHitRectInsets(0, -50, 0, 0)
	local boundLabel = hideBound:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	boundLabel:SetPoint("LEFT", hideBound, "RIGHT", 2, 1)
	boundLabel:SetText("Hide BoP")
	hideBound:SetScript("OnClick", function(self)
		ns.db.ui.recipeHideBound = self:GetChecked() and true or false
		window.offset = 0
		UI.Refresh("profit")
	end)
	hideBound:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Hide BoP")
		GameTooltip:AddLine("Lists only recipes whose craft you can post on the auction house: those that make "
			.. "something binding on pickup, or no item at all (most enchants), are left out. What an unlearned "
			.. "recipe makes is read when its profession window is open; until then it stays listed.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	hideBound:SetScript("OnLeave", GameTooltip_Hide)
	window.hideBound = hideBound

	-- Recipes mode: whose recipes, in the Advertise button's place (advertising has nothing to do with this list).
	local whoButton = HeaderButton(window.frame, "This character", TAB_WIDTH - 6, function()
		ns.db.ui.recipeWho = RECIPE.Who() == "all" and "me" or "all"
		window.offset = 0
		UI.Refresh("profit")
	end)
	whoButton:SetPoint("BOTTOMLEFT", 10, 7)
	whoButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(RECIPE.Who() == "all" and "All characters" or "This character")
		GameTooltip:AddLine(("Click to switch between %s's recipes and those of all your characters. All characters "
			.. "lists a recipe while any character with its profession is missing it, and names who."):format(
			ns.CharLabel(ns.CharKey())), 1, 1, 1, true)
		GameTooltip:Show()
	end)
	whoButton:SetScript("OnLeave", GameTooltip_Hide)
	window.whoButton = whoButton

	local search = SkinBox(CreateFrame("EditBox", nil, window.frame, "InputBoxTemplate"))
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
		local mode = ns.db.ui.profitMode
		if mode ~= "skill" and mode ~= "recipes" then mode = "profit" end
		local recipeMode = mode == "recipes"
		advertise:SetShown(ns.Advertise.Enabled() and not recipeMode)
		advertise:SetEnabled(ns.Advertise.Reason(UI.AdvertisedProfession()) == nil)
		whoButton:SetShown(recipeMode)
		whoButton:SetText(RECIPE.Who() == "all" and "All characters" or "This character")
		local new = RECIPE.NewCount() > 0
		for _, button in ipairs(modes) do
			local on = button.mode.key == mode
			local badge = button.mode.badge
			local lit = new and badge ~= nil and not on
			button:SetText(on and ("|cffffffff" .. button.mode.label .. "|r")
				or lit and Color("ff55dd55", button.mode.label) or button.mode.label)
			if on then button:LockHighlight() else button:UnlockHighlight() end
			if badge then badge:SetShown(lit) end
		end
		hideUnprofitable:SetShown(mode == "profit")
		hideUnprofitable:SetChecked(ns.db.ui.hideUnprofitable and true or false)
		sellAH:SetShown(mode == "skill")
		sellAH:SetChecked(ns.db.ui.skillSellAH and true or false)
		showLearned:SetShown(recipeMode)
		showLearned:SetChecked(ns.db.ui.recipeLearned and true or false)
		hideBound:SetShown(recipeMode)
		hideBound:SetChecked(ns.db.ui.recipeHideBound and true or false)
		if self.list.recipes then
			local info = self.list.info
			local shown = 0
			for _, entry in ipairs(self.list) do
				if entry.kind == "recipe" then shown = shown + 1 end
			end
			local whose = self.list.who == "all" and "your characters" or ns.CharLabel(ns.CharKey())
			local parts = { ("%s %s for %s."):format(ns.Plural(shown, "recipe", "recipes"),
				ns.db.ui.recipeLearned and "listed" or "to find", whose) }
			if info.noProfession then
				parts[1] = Color(COLOR_WARN, ("%s doesn't have %s: click This character (bottom left) for who needs these.")
					:format(ns.CharLabel(ns.CharKey()), ns.Recipes.ProfessionName(selectedProfession.profit) or "it"))
			end
			if info.learnNow > 0 then
				table.insert(parts, Color(RECIPE.COLORS.learn, ("%d can be learned now."):format(info.learnNow)))
			end
			if info.learnedHidden > 0 then
				table.insert(parts, Color(COLOR_MUTED, ("%d learned hidden."):format(info.learnedHidden)))
			end
			if info.boundHidden > 0 then
				table.insert(parts, Color(COLOR_MUTED, ("%d bind on pickup hidden."):format(info.boundHidden)))
			end
			if info.unchecked > 0 then
				table.insert(parts, Color(COLOR_MUTED, ("%d not checked yet (open the profession)."):format(info.unchecked)))
			end
			if info.notInGame > 0 then
				table.insert(parts, Color(COLOR_MUTED, ("%d not in this game left out."):format(info.notInGame)))
			end
			status:SetText(table.concat(parts, " "))
			return
		end
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

-- "just now", "12 min ago", "3 h ago".
function UI.AgoText(seconds)
	if seconds < 90 then return "just now" end
	if seconds < 5400 then return ("%d min ago"):format(math.floor(seconds / 60 + 0.5)) end
	return ("%d h ago"):format(math.floor(seconds / 3600 + 0.5))
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
	local box = SkinBox(CreateFrame("EditBox", nil, parent, "InputBoxTemplate"))
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

-- The Stock level slider (smart goals, cautious to aggressive). One on the Restock tab, one in Options; moving either
-- moves the other and redraws the restock straight away, so its goals change under your mouse.

function Live.LevelWord(percent)
	return percent < 50 and "cautious" or percent > 50 and "aggressive" or "balanced"
end

function UI.StockLevelSlider(parent, width)
	local level = CreateFrame("Slider", nil, parent)
	level:SetSize(width, 14)
	level:SetOrientation("HORIZONTAL")
	level:SetHitRectInsets(0, 0, -4, -4)
	local track = level:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(4)
	track:SetColorTexture(1, 1, 1, 0.12)
	local thumb = level:CreateTexture(nil, "OVERLAY")
	local edge = THEME.buttonEdge
	thumb:SetColorTexture(edge[1], edge[2], edge[3], 1)
	thumb:SetSize(10, 14)
	level:SetThumbTexture(thumb)
	local smart = ns.Planner.SMART
	level:SetMinMaxValues(smart.LEVEL_MIN * 100, smart.LEVEL_MAX * 100)
	level:SetValueStep(10)
	level:SetObeyStepOnDrag(true)
	level.text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	level.text:SetPoint("LEFT", level, "RIGHT", 10, 0)
	level.ShowLevel = function(self)
		local percent = ns.Restock.SmartLevel()
		if not ns.Restock.SmartOn() then
			self.text:SetText(Color(COLOR_MUTED, ("%d%%  smart goals are off"):format(percent)))
			return
		end
		self.text:SetText(("%d%%  %s"):format(percent, Color(COLOR_MUTED, Live.LevelWord(percent))))
	end
	level:SetScript("OnValueChanged", function(self, value)
		if self.syncing then return end
		local before = ns.Restock.SmartLevel()
		ns.Restock.SetSmartLevel(value)
		for _, other in ipairs(Live.sliders) do
			if other ~= self then other:Sync() end
		end
		self:ShowLevel()
		if ns.Restock.SmartLevel() == before then return end
		ns.Debounce("smartLevel", Live.REDRAW_DELAY, function()
			UI.Refresh("restock")
			UI.Refresh("posting")
		end)
	end)
	level.Sync = function(self)
		self.syncing = true
		self:SetValue(ns.Restock.SmartLevel())
		self.syncing = false
		local on = ns.Restock.SmartOn()
		if on then self:Enable() else self:Disable() end
		self:SetAlpha(on and 1 or 0.4)
		self:ShowLevel()
	end
	level:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Stock level")
		GameTooltip:AddLine("How eagerly smart goals stock up. A goal rises a step each day everything you listed "
			.. "sold, and drops when auctions expire. At 50% it can rise to what sold between two of your restocks; "
			.. "at 100% to twice that, in bigger steps. Lower is safer for your gold and drops faster on expiries.",
			1, 1, 1, true)
		if not ns.Restock.SmartOn() then
			GameTooltip:AddLine("Smart restock goals are off (Options), so this does nothing.", 1, 0.6, 0.2, true)
		else
			GameTooltip:AddLine("Restock goals that change flash green (more) or red (fewer).", 0.6, 0.6, 0.6, true)
		end
		GameTooltip:Show()
	end)
	level:SetScript("OnLeave", GameTooltip_Hide)
	table.insert(Live.sliders, level)
	UI.stockLevelSliders = Live.sliders
	return level
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

-- The Craft Next bar: the Craft Next button and a progress bar in one. Idle it glows and says what Craft Next makes
-- and how long that takes; while you craft it fills through the crafts of that recipe (7 of 20), with the time left
-- on them and on all your crafts, and a thin light line under it fills through all crafts.
-- One blue palette on the main window's dark background, solid colours only: a status bar's texture takes its colour
-- from SetStatusBarColor, and the earlier gradient attempt (SetVertexColor(1, 1, 1) after SetGradient) left it white.
local CRAFT_BAR = {
	TRACK = { 0.05, 0.05, 0.07 },
	-- The all-crafts line: pale ice blue on a near-black blue track, so it stands out against the fill above it.
	ALL_COLOR = { 0.62, 0.88, 1.00 },
	ALL_TRACK = { 0.02, 0.04, 0.08 },
}
CRAFT_BAR.STYLES = {
	--            fill                  border
	ready    = { { 0.13, 0.36, 0.70 }, { 0.28, 0.56, 0.95 } },
	crafting = { { 0.18, 0.48, 0.90 }, { 0.38, 0.68, 1.00 } },
	paused   = { { 0.10, 0.24, 0.46 }, { 0.20, 0.38, 0.65 } },
	blocked  = { { 0.11, 0.12, 0.16 }, { 0.20, 0.22, 0.28 } },
}
local craftBars = {}
UI.craftBars = craftBars -- for CraftFx.lua's effects


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
	local style = CRAFT_BAR.STYLES[state]
	if bar.cf.paintedState ~= state then
		bar.cf.paintedState = state
		bar.fill:SetStatusBarColor(style[1][1], style[1][2], style[1][3])
		bar:SetBackdropBorderColor(style[2][1], style[2][2], style[2][3], 1)
		bar.glow:SetVertexColor(style[2][1], style[2][2], style[2][3])
		if bar.cf.pulse then
			if state == "ready" then bar.cf.pulse:Play() else bar.cf.pulse:Stop() end
		end
		bar.glow:SetShown(state == "ready")
		bar.fill:SetAlpha(1)
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
	GameTooltip:AddLine("The fill is the recipe you're crafting, the light line under it all your crafts. Times "
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
	bar:SetBackdropColor(CRAFT_BAR.TRACK[1], CRAFT_BAR.TRACK[2], CRAFT_BAR.TRACK[3], 0.97)
	bar:RegisterForClicks("LeftButtonUp")
	bar:SetScript("OnClick", function(self)
		if self.cf.state == "ready" or self.cf.state == "paused" then ns.Queue.CraftNext() end
	end)

	local fill = CreateFrame("StatusBar", nil, bar)
	fill:SetPoint("TOPLEFT", 2, -2)
	fill:SetPoint("BOTTOMRIGHT", -2, 2)
	fill:SetStatusBarTexture(WHITE)
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
	allTrack:SetVertexColor(CRAFT_BAR.ALL_TRACK[1], CRAFT_BAR.ALL_TRACK[2], CRAFT_BAR.ALL_TRACK[3], 0.9)
	allStrip:SetStatusBarColor(CRAFT_BAR.ALL_COLOR[1], CRAFT_BAR.ALL_COLOR[2], CRAFT_BAR.ALL_COLOR[3])
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
		local count = ns.Queue.Count()
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
	total:SetPoint("BOTTOMRIGHT", -12, 110)
	total:SetJustifyH("LEFT")

	window.clearButton = clear
	window.update = function()
		clear:SetEnabled(ns.Queue.Count() > 0)
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
local NEXT = {
	WIDTH = 300,
	MAX_ROWS = 10,
	MAX_ROWS_FARMING = 16, -- every gathering group at once
	BUTTON_ROOM = 42,
	BANK_BUTTON_ROOM = 30,
}

local function CreateNextWindow()
	local frame = CreateFrame("Frame", "CFFNextStep", UIParent, "BackdropTemplate")
	local window = { key = "next", frame = frame, list = {}, offset = 0, rows = {}, mini = true, maxRows = NEXT.MAX_ROWS }
	windows.next = window
	MakeMovable(frame, "next")
	frame:SetFrameStrata("MEDIUM") -- under the main window and dialogs, as it's always there
	frame:SetSize(NEXT.WIDTH, MINI_TOP + 8)
	ThemeBackdrop(frame, 0.88)

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

	-- On a bank step: moves it all for you while the bank is open.
	local bank = FlatButton(frame, "", 10, 24, true)
	bank:SetPoint("BOTTOMLEFT", 10, 8)
	bank:SetPoint("BOTTOMRIGHT", -10, 8)
	bank:SetScript("OnClick", function()
		local ok, why = ns.Bank.Run()
		if not ok and why then ns.Say("chatWarnings", why) end
	end)
	bank:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Do the bank step")
		GameTooltip:AddLine("With your bank open, puts away what this step says to make room with, then takes out "
			.. "what the queue needs from the bank. One stack at a time; it stops if the bank closes or a fight starts.",
			1, 1, 1, true)
		GameTooltip:Show()
	end)
	bank:SetScript("OnLeave", GameTooltip_Hide)
	bank.Sync = function(self)
		local moved, total = ns.Bank.Progress()
		if moved then
			self:SetText(("Moving... %d / %d"):format(moved, total))
			self:Disable()
		elseif ns.Bank.IsOpen() then
			local pending = ns.Bank.Pending()
			local away, take = 0, 0
			for _, units in pairs(pending and pending.deposit or {}) do away = away + units end
			for _, units in pairs(pending and pending.take or {}) do take = take + units end
			local parts = {}
			if away > 0 then table.insert(parts, "put away " .. away) end
			if take > 0 then table.insert(parts, "take out " .. take) end
			self:SetText(#parts > 0 and ("Bank it: " .. table.concat(parts, ", ")) or "Nothing to move")
			self:SetEnabled(#parts > 0)
		else
			self:SetText("Open your bank and this does it for you")
			self:Disable()
		end
	end
	window.bankButton = bank
	UI.SyncBankButton = function()
		if window.banking and frame:IsShown() then bank:Sync() end
	end

	-- On the vendor step, or at any merchant that sells something the plan buys from vendors: buys it for you.
	local vendor = FlatButton(frame, "", 10, 24, true)
	vendor:SetPoint("BOTTOMLEFT", 10, 8)
	vendor:SetPoint("BOTTOMRIGHT", -10, 8)
	vendor:SetScript("OnClick", function()
		local ok, why = ns.Vendor.Run()
		if not ok and why then ns.Say("chatWarnings", why) end
	end)
	vendor:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Do the vendor step")
		ns.Vendor.AddTooltipLines(GameTooltip)
		GameTooltip:Show()
	end)
	vendor:SetScript("OnLeave", GameTooltip_Hide)
	vendor.Sync = function(self)
		local text, enabled = ns.Vendor.ButtonText()
		self:SetText(text)
		self:SetEnabled(enabled)
	end
	window.vendorButton = vendor

	-- Bank alt mode's mail step: at a mailbox, sends the crafts to the bank alt.
	local mail = FlatButton(frame, "", 10, 24, true)
	mail:SetPoint("BOTTOMLEFT", 10, 8)
	mail:SetPoint("BOTTOMRIGHT", -10, 8)
	mail:SetScript("OnClick", function()
		local ok, why = ns.Seller.Run(false)
		if not ok and why then ns.Say("chatWarnings", why) end
	end)
	mail:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Do the mail step")
		ns.Seller.AddTooltipLines(GameTooltip)
		GameTooltip:Show()
	end)
	mail:SetScript("OnLeave", GameTooltip_Hide)
	mail.Sync = function(self)
		local text, enabled = ns.Seller.ButtonText()
		self:SetText(text)
		self:SetEnabled(enabled)
	end
	window.mailButton = mail
	UI.SyncMailButton = function()
		if window.mailing and frame:IsShown() then mail:Sync() end
	end
	UI.SyncVendorButton = function()
		if not frame:IsShown() then return end
		-- A merchant opening or the last purchase landing can add or remove the button: lay the bar out again.
		local wanted = not window.crafting and (window.vendorStep or ns.Vendor.Pending() ~= nil or ns.Vendor.Busy())
		if wanted ~= window.vendoring then return UI.Refresh("next") end
		if window.vendoring then vendor:Sync() end
	end

	-- The list area's bottom moves up when the Craft Next button is there.
	local function SetFooter(footer)
		window.container:SetPoint("BOTTOMRIGHT", -24, footer)
		window.slider:SetPoint("BOTTOMRIGHT", -10, footer)
	end

	window.build = function()
		local step, steps, rows, here = BuildNextStep()
		window.step, window.steps, window.here = step, steps, here
		local folded = ns.db.ui.nextMinimized
		local list = {}
		window.nextCraft, window.nextCount, window.blocking, window.open, window.crafting = nil, nil, nil, nil, false
		window.banking, window.vendoring, window.vendorStep, window.mailing = false, false, false, false
		window.maxRows = ns.db.ui.farmMode and NEXT.MAX_ROWS_FARMING or NEXT.MAX_ROWS
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
			window.banking = step.bank or false
			window.vendorStep = step.vendor or false
			window.mailing = step.mail or false
		end
		-- At a merchant that sells what the plan buys from vendors, its button shows whatever the step.
		window.vendoring = not folded and not window.crafting
			and (window.vendorStep or ns.Vendor.Pending() ~= nil or ns.Vendor.Busy())
		if window.vendoring then window.banking, window.mailing = false, false end
		-- On a crafting step the button stays, saying what to finish while it can't craft.
		local button = window.crafting
		local footer = button and NEXT.BUTTON_ROOM + 6
			or (window.banking or window.vendoring or window.mailing) and NEXT.BANK_BUTTON_ROOM + 6 or 6
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
		-- A step jumped to because you're standing where it's done: say so, the order comes back after it.
		if window.here then
			count:SetText(Color("ff66ccff", ("Here: %d of %d"):format(window.here, window.steps)))
		else
			count:SetText(window.steps > 1 and Color(COLOR_MUTED, ("1 of %d"):format(window.steps)) or "")
		end
		if window.crafting and not folded then
			craft:Show()
			craft:Update(window.nextCraft, window.nextCount, window.blocking, window.open)
		else
			craft:Hide()
		end
		bank:SetShown(window.banking and not folded)
		if window.banking and not folded then bank:Sync() end
		vendor:SetShown(window.vendoring)
		if window.vendoring then vendor:Sync() end
		mail:SetShown(window.mailing and not folded)
		if window.mailing and not folded then mail:Sync() end
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
	-- Bank alt mode keeps it up while there are crafts to mail (a step Farm It doesn't have).
	local mailing = ns.db and ns.plan.send and not ns.db.ui.farmMode
	if not ns.db or (ns.Queue.Count() == 0 and not mailing) or not NextStepAllowed() or not ns.Option("nextStep") then
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
	if not ns.Option("nextStep") then
		ns.Say("chatWarnings", "The Next step bar is turned off. Turn it on in the Options tab.")
		return
	end
	if ns.Queue.Count() == 0 then
		ns.Say("chatWarnings", "The queue is empty, so there's no next step.")
		return
	end
	if not NextStepAllowed() then
		ns.Say("chatWarnings", "The Next step bar is hidden in combat and in dungeons, raids and battlegrounds.")
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
	local window = CreatePane("restock", 120, true)
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

	-- Smart goals' stock level, right here: the goals above follow it as it moves.
	local levelLabel = window.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	levelLabel:SetPoint("BOTTOMLEFT", 12, Live.LEVEL_BOTTOM)
	levelLabel:SetText("Stock level")
	local level = UI.StockLevelSlider(window.frame, 180)
	level:SetPoint("LEFT", levelLabel, "RIGHT", 10, 0)

	-- Beside it, how long the restock takes to craft: moves with the slider.
	local timer = CreateFrame("Frame", nil, window.frame)
	timer:SetSize(150, 16)
	timer:SetPoint("BOTTOMRIGHT", -12, Live.LEVEL_BOTTOM - 1)
	timer.text = timer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	timer.text:SetPoint("RIGHT")
	timer.text:SetJustifyH("RIGHT")
	timer.icon = timer:CreateTexture(nil, "OVERLAY")
	timer.icon:SetSize(14, 14)
	timer.icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
	timer.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	timer.icon:SetPoint("RIGHT", timer.text, "LEFT", -4, 0)
	timer:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Crafting time")
		GameTooltip:AddLine("About how long this restock takes to craft: the crafts above, new and already on your "
			.. "queue, plus the sub-crafts their materials need (bars, cloth), at each recipe's cast time and the pause "
			.. "between casts. Shopping and walking aren't counted.", 1, 1, 1, true)
		if (self.direct or 0) > 0 then
			GameTooltip:AddDoubleLine("Restock crafts", tostring(self.direct), 1, 0.82, 0, 1, 1, 1)
			if self.count > self.direct then
				GameTooltip:AddDoubleLine("Sub-crafts", tostring(self.count - self.direct), 1, 0.82, 0, 1, 1, 1)
			end
		end
		GameTooltip:AddLine("Cast times are learned as you craft; until then the spell's own time is used.",
			0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	timer:SetScript("OnLeave", GameTooltip_Hide)
	timer.Update = function(self, rows)
		local seconds, direct, count = ns.Restock.CraftTime(rows)
		self.direct, self.count = direct, count
		self.text:SetText(direct > 0
			and (Color(COLOR_MUTED, "Crafting time ") .. ns.Planner.FormatDuration(seconds))
			or Color(COLOR_MUTED, "Nothing to craft"))
		self.icon:SetDesaturated(direct == 0)
	end
	-- A fresh look at the tab doesn't flash: only changes seen while it's open do.
	window.frame:HookScript("OnHide", function() wipe(Live.seen) end)

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
		local changed = ns.Restock.Apply(rows)
		ns.Say("chatDone", ("Restock: %s updated on the queue."):format(ns.Plural(changed, "item", "items")))
		UI.Show("queue")
	end, true)
	apply:SetHeight(26)
	apply:ClearAllPoints()
	apply:SetPoint("BOTTOMLEFT", 10, 10)
	apply:SetPoint("BOTTOMRIGHT", -10, 10)

	window.update = function(self)
		showQueue:SetText(ns.db.ui.queueBeside and "Hide Queue" or "Show Queue")
		level:Sync()
		stack:Sync()
		single:Sync()
		minProfit:Sync()

		local needed, toPost, items, queued, trims = 0, 0, 0, 0, 0
		local shown = {}
		for _, data in ipairs(self.list) do
			local row = data.row
			if row then
				shown[#shown + 1] = row
				items = items + 1
				if row.crafts > 0 or row.trim then needed = needed + 1 end
				if row.trim then trims = trims + 1 end
				if row.queued then queued = queued + 1 end
				if row.goal > 0 and (row.onAH or 0) < row.goal then
					toPost = toPost + math.min(row.owned, row.goal - (row.onAH or 0))
				end
			end
		end

		timer:Update(shown)

		if not ns.Stock.HasSyndicator() then
			apply:Disable()
			apply:SetText("Queue restock")
			status:SetText("Syndicator is needed to see your auctions. Without it this would over-craft.")
			return
		end
		local budget = UI.restockBudget
		local short = budget and budget.short
		apply:SetEnabled(needed > 0)
		apply:SetText(needed > 0 and ((trims == needed and "Update restock: %s" or short and "Queue partial restock: %s"
				or queued > 0 and "Add to restock: %s" or "Queue restock: %s"):format(ns.Plural(needed, "item", "items")))
			or queued > 0 and ("Restock is on your queue: %s"):format(ns.Plural(queued, "item", "items"))
			or short and "Not enough gold to restock" or "Fully stocked")
		local notes = { "AH counts update when you visit the auction house." }
		if queued > 0 then
			notes[1] = "A queued restock stays as it is while you shop and craft. " .. notes[1]
		end
		if short then
			local deposit = (budget.deposit or 0) > 0
			notes = { Color("ffffb040", ("Not enough gold for a full restock: its materials cost %s%s and you have %s%s. "
				.. "This is a partial restock, %s of materials%s, picked for the most profit."):format(
				ns.Money(budget.full),
				(budget.fullDeposit or 0) > 0 and (" plus " .. ns.Money(budget.fullDeposit) .. " in deposits to post it") or "",
				ns.Money(budget.gold),
				budget.queued > 0 and (", " .. ns.Money(budget.queued) .. " of it for your queue") or "",
				ns.Money(budget.cost),
				(deposit and (" with " .. ns.Money(budget.deposit) .. " kept for posting") or "")
					.. ((budget.keep or 0) > 0 and ((deposit and " and " or " with ") .. ns.Money(budget.keep)
						.. " left alone") or ""))) }
		end
		if UI.restockCamp and (UI.restockCamp.station or UI.restockCamp.cut > 0) then
			table.insert(notes, UI.RestockCampNote(UI.restockCamp))
		end
		-- Crafts are picked at the cheapest listing; the queued restock is checked against every listing later.
		local reading = ns.Depth.Status()
		if reading then
			table.insert(notes, ("Reading listings for your queue (%d to go): the queued restock can still be cut.")
				:format(reading))
		elseif needed > 0 and ns.Option("depthCheck") then
			table.insert(notes, "Picked at the cheapest listings. Once queued, the auction house reads what buying "
				.. "them really costs and cuts crafts that no longer earn your minimum profit.")
		end
		if toPost > 0 then
			table.insert(notes, 1, (toPost == 1 and "1 item you hold is" or (toPost .. " items you hold are"))
				.. " ready to post, from the auction house's Restocking tab.")
		end
		if items == 0 then notes = { "No profitable items yet. Open your professions and scan the AH." } end
		status:SetText(table.concat(notes, " "))
	end
end

-- A summary box on the Sales tab: a small label, a large figure and a line of detail.
local function StatTile(parent, labelText, bright)
	local tile = CreateFrame("Frame", nil, parent)
	tile:SetHeight(SALES_TILE_HEIGHT)
	FlatBox(tile, THEME.header, bright and THEME.primaryEdge or THEME.border)
	tile.label = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tile.label:SetPoint("TOPLEFT", 8, -6)
	tile.label:SetText(Color(bright and "ff7fb8ff" or COLOR_MUTED, labelText))
	tile.value = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	tile.value:SetPoint("TOPLEFT", 8, -19)
	tile.detail = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tile.detail:SetPoint("BOTTOMLEFT", 8, 6)
	tile.detail:SetPoint("BOTTOMRIGHT", -6, 6)
	tile.detail:SetJustifyH("LEFT")
	tile.detail:SetWordWrap(false)
	return tile
end

function CreateSalesPane()
	local window = CreatePane("sales", 28, false, SALES_TILE_TOP + SALES_TILE_HEIGHT + 8)
	window.build = BuildSalesList

	-- Money on its way first, then what the sales earned.
	local tiles = {
		StatTile(window.frame, "ON ITS WAY", true),
		StatTile(window.frame, "PROFIT TODAY"),
		StatTile(window.frame, "PROFIT, 7 DAYS"),
		StatTile(window.frame, "PROFIT, 30 DAYS"),
	}
	window.tiles = tiles

	-- Off: only what your characters craft. On: every auction, such as spare materials and drops.
	local everything = CreateFrame("CheckButton", nil, window.frame, "UICheckButtonTemplate")
	everything:SetSize(24, 24)
	everything:SetPoint("TOPLEFT", 8, -PANE_ACTIONS_TOP)
	everything:SetHitRectInsets(0, -190, 0, 0) -- the label is clickable too
	local everythingLabel = everything:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	everythingLabel:SetPoint("LEFT", everything, "RIGHT", 2, 1)
	everythingLabel:SetText("Show everything I sell, not only my crafts")
	everything:SetScript("OnClick", function(self)
		ns.db.ui.salesEverything = self:GetChecked() and true or false
		window.offset = 0
		UI.Refresh("sales")
	end)
	window.everything = everything

	-- Asks first: the profit so far can't be brought back.
	local reset = HeaderButton(window.frame, "Reset profit", 96, function() StaticPopup_Show("CFF_RESET_PROFIT") end)
	reset:SetPoint("TOPRIGHT", -12, -PANE_ACTIONS_TOP)
	reset:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Reset profit")
		GameTooltip:AddLine("Starts profit again from zero, from now. Sales so far leave the profit and this list, but "
			.. "still count for the chance to sell. You're asked to confirm.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	reset:SetScript("OnLeave", function() GameTooltip:Hide() end)
	window.reset = reset
	local function PlaceTiles()
		local width = window.frame:GetWidth()
		if type(width) ~= "number" or width <= 0 then width = MAIN_WIDTH end
		local gap = 6
		local each = (width - 20 - gap * (#tiles - 1)) / #tiles
		for index, tile in ipairs(tiles) do
			tile:ClearAllPoints()
			tile:SetPoint("TOPLEFT", 10 + (index - 1) * (each + gap), -SALES_TILE_TOP)
			tile:SetWidth(each)
		end
	end
	window.frame:SetScript("OnSizeChanged", PlaceTiles)

	local hint = window.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("BOTTOMLEFT", 12, 9)
	hint:SetPoint("BOTTOMRIGHT", -24, 9)
	hint:SetJustifyH("LEFT")
	hint:SetWordWrap(false)

	-- The waits count down while the tab is open.
	local sinceRefresh = 0
	window.frame:SetScript("OnUpdate", function(_, elapsed)
		sinceRefresh = sinceRefresh + (elapsed or 0)
		if sinceRefresh >= 20 then
			sinceRefresh = 0
			UI.Refresh("sales")
		end
	end)

	window.update = function()
		PlaceTiles()
		local incoming, onItsWay, waiting, nextDue, rough = ns.Sales.Incoming()
		local about = rough and "~" or ""
		local way = tiles[1]
		if #incoming == 0 then
			way.value:SetText(Color(COLOR_MUTED, "nothing"))
			way.detail:SetText(Color(COLOR_MUTED, "no sales waiting to pay out"))
		else
			way.value:SetText(about .. ns.Money(onItsWay + waiting))
			if nextDue then
				way.detail:SetText(("next in %s%s"):format(ns.Sales.WaitText(nextDue - time()),
					waiting > 0 and Color(COLOR_PROFIT, ", " .. ns.Money(waiting) .. " in mailbox") or ""))
			else
				way.detail:SetText(Color(COLOR_PROFIT, "all waiting in the mailbox"))
			end
		end
		local showAll = ns.db.ui.salesEverything and true or false
		everything:SetChecked(showAll)
		for index, days in ipairs({ 1, 7, 30 }) do
			local sold, _, gold, profit, estimated = ns.Sales.Totals(days, showAll)
			local tile = tiles[index + 1]
			tile.value:SetText((estimated and "~" or "") .. (profit < 0 and Color(COLOR_LOSS, ns.Money(profit)) or ns.Money(profit)))
			tile.detail:SetText(Color(COLOR_MUTED, ("%s in sales, %d sold"):format(ns.Money(gold), sold)))
		end
		local soldEver, expiredEver = ns.Sales.Totals(nil, true)
		if soldEver + expiredEver == 0 and #incoming == 0 then
			hint:SetText("Nothing yet. Profit is counted from this version on; sales are read from your mailbox on each character.")
		elseif not showAll and #ns.Sales.AllItems(false) == 0 then
			hint:SetText("None of your crafts has sold or expired yet. Tick the box above to see your other auctions.")
		else
			hint:SetText(Color(COLOR_MUTED, "Profit = sale after the AH cut, less what the materials cost you. ~ marks an estimate."))
		end
	end
end

-- Craftsman's Writs: every writ with what it costs to hand in, cheapest reputation first.
function CreateWritsPane()
	local window = CreatePane("writs", 30)
	window.build = BuildWritsList

	-- All, then one button per level.
	window.tierButtons = {}
	for index = 0, #ns.Writs.TIERS do
		local tier = index > 0 and index or nil
		local button = HeaderButton(window.frame, tier and ns.Writs.TIERS[tier] or "All", tier and 84 or 44, function()
			ns.db.ui.writTier = tier
			window.offset = 0
			UI.Refresh("writs")
		end)
		if index == 0 then
			button:SetPoint("TOPLEFT", 10, -PANE_ACTIONS_TOP)
		else
			button:SetPoint("LEFT", window.tierButtons[index], "RIGHT", 4, 0)
		end
		button.tier = tier
		window.tierButtons[index + 1] = button
	end

	-- Zone filter: a button that opens a list of the zones writs are handed in, with how many each has. Clicking zones
	-- ticks them on and off (any number, kept in db.ui.writZones); All zones clears them.
	local zoneButton = HeaderButton(window.frame, "Filter by zone", 170, nil)
	zoneButton:SetPoint("LEFT", window.tierButtons[#window.tierButtons], "RIGHT", 12, 0)
	local zoneMenu = CreateFrame("Frame", nil, zoneButton, "BackdropTemplate")
	zoneMenu:SetFrameStrata("DIALOG")
	zoneMenu:SetPoint("TOPLEFT", zoneButton, "BOTTOMLEFT", 0, -2)
	FlatBox(zoneMenu, THEME.header, THEME.border)
	zoneMenu:Hide()
	zoneMenu.options = {}
	window.zoneButton, window.zoneMenu = zoneButton, zoneMenu
	local ZONE_ROWS, ZONE_WIDTH, ZONE_HEIGHT = 14, 160, 18
	local function PickZone(zone)
		if zone then
			local zones = ns.db.ui.writZones or {}
			zones[zone] = not zones[zone] or nil
			ns.db.ui.writZones = next(zones) and zones or nil
		else
			ns.db.ui.writZones = nil
		end
		window.offset = 0
		UI.Refresh("writs")
	end
	zoneMenu.Fill = function(self)
		local counts = window.zoneCounts or {}
		local zones = {}
		for _, writ in ipairs(ns.Writs.list) do
			local key = writ.zone or ns.Writs.NO_ZONE
			if not zones[key] then zones[key] = true; zones[#zones + 1] = key end
		end
		table.sort(zones, function(a, b)
			if (a == ns.Writs.NO_ZONE) ~= (b == ns.Writs.NO_ZONE) then return b == ns.Writs.NO_ZONE end
			return a < b
		end)
		table.insert(zones, 1, false)
		for index, zone in ipairs(zones) do
			local option = self.options[index]
			if not option then
				option = FlatButton(self, "-", ZONE_WIDTH, ZONE_HEIGHT)
				local text = option:GetFontString()
				if text then
					text:ClearAllPoints()
					text:SetPoint("LEFT", 6, 0)
					text:SetPoint("RIGHT", -4, 0)
					text:SetJustifyH("LEFT")
				end
				local column, line = math.floor((index - 1) / ZONE_ROWS), (index - 1) % ZONE_ROWS
				option:SetPoint("TOPLEFT", 4 + column * (ZONE_WIDTH + 2), -4 - line * ZONE_HEIGHT)
				option:SetScript("OnClick", function(button) PickZone(button.zone or nil) end)
				option.check = option:CreateTexture(nil, "OVERLAY")
				option.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
				option.check:SetSize(16, 16)
				option.check:SetPoint("RIGHT", -2, 0)
				self.options[index] = option
			end
			option.zone = zone
			local count = zone and (counts[zone] or 0)
			local label = zone == false and "All zones" or zone == ns.Writs.NO_ZONE and "Zone not known" or zone
			option:SetText(zone and (count > 0 and (label .. Color(COLOR_MUTED, "  " .. count))
				or Color(COLOR_MUTED, label .. "  0")) or label)
			local picked = ns.db.ui.writZones
			local on
			if zone then on = picked and picked[zone] or false else on = not picked end
			if on then option:LockHighlight() else option:UnlockHighlight() end
			option.check:SetShown(on and zone and true or false)
			option:Show()
		end
		local columns = math.ceil(#zones / ZONE_ROWS)
		self:SetSize(8 + columns * (ZONE_WIDTH + 2) - 2, 8 + math.min(#zones, ZONE_ROWS) * ZONE_HEIGHT)
	end
	zoneButton:SetScript("OnClick", function()
		if zoneMenu:IsShown() then zoneMenu:Hide() return end
		zoneMenu:Fill()
		zoneMenu:Show()
	end)
	zoneButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Hand-in zone")
		GameTooltip:AddLine("Show only the writs handed in where you're going: click zones to tick them, as many as you "
			.. "like, and All zones to clear them. The number beside each zone is how many writs it has at the level "
			.. "picked. Zones marked ? in the list are guesses from the other writs.", 1, 1, 1, true)
		local names = ns.Writs.ZoneNames(ns.db.ui.writZones)
		if #names > 0 then GameTooltip:AddLine("Showing: " .. table.concat(names, ", "), 1, 0.82, 0, true) end
		GameTooltip:Show()
	end)
	zoneButton:SetScript("OnLeave", GameTooltip_Hide)
	window.frame:HookScript("OnHide", function() zoneMenu:Hide() end)

	-- Off: only writs whose item one of your characters can craft. On: every writ.
	local everything = CreateFrame("CheckButton", nil, window.frame, "UICheckButtonTemplate")
	everything:SetSize(24, 24)
	everything:SetPoint("BOTTOMLEFT", 8, 3)
	everything:SetHitRectInsets(0, -200, 0, 0) -- the label is clickable too
	local everythingLabel = everything:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	everythingLabel:SetPoint("LEFT", everything, "RIGHT", 2, 1)
	everythingLabel:SetText("Show all writs, not only what I can craft")
	everything:SetScript("OnClick", function(self)
		ns.db.ui.writAll = self:GetChecked() and true or false
		window.offset = 0
		UI.Refresh("writs")
	end)
	window.everything = everything

	local hint = window.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("BOTTOMLEFT", 270, 9)
	hint:SetPoint("BOTTOMRIGHT", -24, 9)
	hint:SetJustifyH("RIGHT")
	hint:SetWordWrap(false)
	window.hint = hint

	window.update = function()
		local tier = ns.db.ui.writTier
		for _, button in ipairs(window.tierButtons) do
			if button.tier == tier then button:LockHighlight() else button:UnlockHighlight() end
		end
		everything:SetChecked(ns.db.ui.writAll and true or false)
		local names = ns.Writs.ZoneNames(ns.db.ui.writZones)
		local zone = #names > 0
		zoneButton:SetText(#names == 1 and ("Zone: " .. names[1]) or zone and ("Zones: " .. #names .. " picked")
			or "Filter by zone")
		if zone then zoneButton:LockHighlight() else zoneButton:UnlockHighlight() end
		if zoneMenu:IsShown() then zoneMenu:Fill() end
		local priced, shown = 0, 0
		for _, data in ipairs(window.list) do
			if data.row then
				shown = shown + 1
				if data.row.writPrice then priced = priced + 1 end
			end
		end
		if shown == 0 and zone then
			hint:SetText("No writs here in the zones picked. Pick other zones or All zones.")
		elseif shown == 0 then
			hint:SetText("None of your characters can craft a writ's item here. Tick the box to see every writ.")
		elseif priced == 0 then
			hint:SetText(Color(COLOR_WARN, "No writ prices yet: run a full scan at the auction house."))
		else
			hint:SetText(Color(COLOR_MUTED, ("%d of %d writs have a price. + queues a writ and what it needs."):format(priced, shown)))
		end
	end
end

-- Waylaid Crates: every crate with what it costs to fill, cheapest Merchant's Favor first.
function CreateCratesPane()
	local window = CreatePane("crates", 30)
	window.build = BuildCratesList

	-- All, then one button per level.
	window.tierButtons = {}
	for index = 0, #ns.Crates.TIERS do
		local tier = index > 0 and index or nil
		local button = HeaderButton(window.frame, tier and ns.Crates.TIERS[tier] or "All", tier and 84 or 44, function()
			ns.db.ui.crateTier = tier
			window.offset = 0
			UI.Refresh("crates")
		end)
		if index == 0 then
			button:SetPoint("TOPLEFT", 10, -PANE_ACTIONS_TOP)
		else
			button:SetPoint("LEFT", window.tierButtons[index], "RIGHT", 4, 0)
		end
		button.tier = tier
		window.tierButtons[index + 1] = button
	end

	local hint = window.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("BOTTOMLEFT", 12, 9)
	hint:SetPoint("BOTTOMRIGHT", -24, 9)
	hint:SetJustifyH("LEFT")
	hint:SetWordWrap(false)
	window.hint = hint

	window.update = function()
		local tier = ns.db.ui.crateTier
		for _, button in ipairs(window.tierButtons) do
			if button.tier == tier then button:LockHighlight() else button:UnlockHighlight() end
		end
		local best = window.list.best
		if best then
			hint:SetText(("Best buy: %s with %s, %s for each Merchant's Favor."):format(
				Color(COLOR_PROFIT, ns.Crates.Name(best.crate) or "..."), BundleText(best.best),
				best.perToken > 0 and ns.Money(best.perToken) or "nothing") .. Color(COLOR_MUTED, "  + queues a crate."))
		else
			hint:SetText(Color(COLOR_WARN, "No crate prices yet: run a full scan at the auction house."))
		end
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
		elseif key == "writs" then
			CreateWritsPane()
		elseif key == "crates" then
			CreateCratesPane()
		elseif key == "options" then
			local frame = CreateFrame("Frame", nil, main.frame)
			frame:Hide()
			windows.options = { key = "options", frame = frame, update = ns.Options.Build(frame, PANE_LIST_TOP) }
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
		tab:SetHighlightTexture(WHITE, "ADD")
		local tabGlow = tab:GetHighlightTexture()
		if tabGlow then tabGlow:SetVertexColor(0.30, 0.55, 1, 0.22) end
		tab:SetScript("OnClick", function() UI.Select(info.key) end)
		tab.key, tab.title = info.key, info.title
		tab.bg = tab:CreateTexture(nil, "BACKGROUND")
		tab.bg:SetAllPoints()
		tab.accent = tab:CreateTexture(nil, "ARTWORK")
		tab.accent:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 1)
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
		if info.key == "writs" or info.key == "crates" then
			-- Gold glow and top edge while you hold some (UpdateTabStrip).
			local flair = tab:CreateTexture(nil, "ARTWORK")
			flair:SetAllPoints()
			flair:SetColorTexture(1, 0.82, 0, 0.18)
			flair:Hide()
			local edge = tab:CreateTexture(nil, "OVERLAY")
			edge:SetColorTexture(1, 0.82, 0, 1)
			edge:SetHeight(2)
			edge:SetPoint("TOPLEFT")
			edge:SetPoint("TOPRIGHT")
			edge:Hide()
			flair:HookScript("OnShow", function() edge:Show() end)
			flair:HookScript("OnHide", function() edge:Hide() end)
			local anim = flair.CreateAnimationGroup and flair:CreateAnimationGroup()
			if anim then
				local pulse = anim:CreateAnimation("Alpha")
				pulse:SetFromAlpha(1)
				pulse:SetToAlpha(0.25)
				pulse:SetDuration(0.9)
				anim:SetLooping("BOUNCE")
				anim:SetScript("OnStop", function() flair:SetAlpha(1) end)
			end
			tab.flair, tab.flairAnim = flair, anim or false
			tab:SetScript("OnEnter", function(self)
				if (self.held or 0) == 0 then return end
				GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
				GameTooltip:SetText(("You have %d %s (bags and bank):"):format(self.held,
					info.key == "writs" and (self.held == 1 and "writ" or "writs") or (self.held == 1 and "crate" or "crates")))
				for _, name in ipairs(Held.Names(info.key)) do GameTooltip:AddLine(name, 1, 0.82, 0) end
				GameTooltip:Show()
			end)
			tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end
		main.tabButtons[index] = tab
	end

	-- The strip behind the title and tabs.
	local strip = frame:CreateTexture(nil, "BORDER")
	strip:SetPoint("TOPLEFT", 1, -1)
	strip:SetPoint("TOPRIGHT", -1, -1)
	strip:SetHeight(MAIN_TOP - 2)
	strip:SetColorTexture(THEME.header[1], THEME.header[2], THEME.header[3], 1)

	local close = FlatButton(frame, "X", 20, 20)
	close:SetPoint("TOPRIGHT", -8, -8)
	close:SetScript("OnClick", function() frame:Hide() end)

	local refresh = HeaderButton(frame, "Refresh", 70, function() ns.RefreshEverything() end)
	refresh:SetHeight(20)
	refresh:SetPoint("RIGHT", close, "LEFT", -2, 0)
	refresh:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Refresh")
		GameTooltip:AddLine("Re-reads your recipes, item data, prices from Auctionator and stock, then redraws "
			.. "everything.", 1, 1, 1, true)
		GameTooltip:AddLine("At the auction house it also re-reads your auctions and looks up every listing of the "
			.. "materials your queue buys again, so the costs are as of now.", 1, 1, 1, true)
		GameTooltip:AddLine("It isn't a price scan: sale prices come from Auctionator's scan (Scan now when prices "
			.. "are old).", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	refresh:SetScript("OnLeave", GameTooltip_Hide)

	local rule = frame:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.7)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 1, -MAIN_TOP + 1)
	rule:SetPoint("TOPRIGHT", -1, -MAIN_TOP + 1)

	main.divider = frame:CreateTexture(nil, "ARTWORK")
	main.divider:SetColorTexture(THEME.border[1], THEME.border[2], THEME.border[3], 1)
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
	main.scanButton = HeaderButton(banner, "Scan now", 80, function() ns.Prices.StartScan() end, true)
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
		-- With the bar turned off the Queue tab is the gathering list, so it stays.
		if ns.Option("nextStep") then UI.Hide() end
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
		queueButton = FlatButton(form, "Queue", 64, 22, true, "CFFQueueButton")
		queueButton:SetPoint("TOPRIGHT", form, "TOPRIGHT", -12, -47)
		queueButton:SetText("Queue")
		UI.queueButton = queueButton
		queueButton:SetScript("OnClick", function()
			local info = SelectedRecipe()
			if not info or not info.recipeID then
				ns.Say("chatWarnings", "Select a recipe first.")
			elseif not info.learned then
				ns.Say("chatWarnings", "You have not learned that recipe.")
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
	if scanNotified or not ns.Prices.IsStale() or not ns.Option("chatTips") then return end
	scanNotified = true
	ns.Say("chatTips", ScanAgeText() .. " Scan at the auction house for accurate profit.")
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
-- Scan prompt
---------------------------------------------------------------------------

-- Add-ons can't open a browser or write the clipboard, so the link goes in a box, selected, ready for Ctrl+C.
-- The recipe item's page says where to get it; recipes without one (trainer ones) get the spell page.
StaticPopupDialogs["CFF_WOWHEAD"] = {
	text = "Wowhead link for %s\nPress Ctrl+C to copy it.",
	button1 = "Close",
	hasEditBox = true,
	editBoxWidth = 320,
	OnShow = function(self, url)
		local box = self.editBox or self.EditBox
		box:SetText(url)
		box:HighlightText()
		box:SetFocus()
	end,
	EditBoxOnTextChanged = function(box, url)
		-- Keep the link as it was if a key gets typed into the box.
		if box:GetText() ~= url then
			box:SetText(url)
			box:HighlightText()
		end
	end,
	EditBoxOnEnterPressed = function(box) box:GetParent():Hide() end,
	EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

function RECIPE.ShowWowhead(recipeID, itemID)
	local url = itemID and ("https://www.wowhead.com/forever/item=" .. itemID)
		or ("https://www.wowhead.com/forever/spell=" .. recipeID)
	StaticPopup_Show("CFF_WOWHEAD", ns.RecipeBook.Name(recipeID) or "this recipe", nil, url)
end

StaticPopupDialogs["CFF_CLEAR_QUEUE"] = {
	text = "Crafting and Farming Forever: %s",
	button1 = YES,
	button2 = NO,
	OnAccept = function() ns.Queue.Clear() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["CFF_RESET_PROFIT"] = {
	text = "Crafting and Farming Forever: reset your sales profit to zero and start counting again from now? "
		.. "This can't be undone.",
	button1 = "Reset profit",
	button2 = CANCEL,
	OnAccept = function()
		ns.Sales.ResetProfit()
		ns.Say("chatDone", "Sales profit reset. It counts again from now.")
	end,
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
		ns.Say("chatDone", ("Removed %s that would lose money."):format(ns.Plural(removed, "entry", "entries")))
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
	UI.atAuctionHouse = true
	UI.Refresh("next")
	-- Auctionator creates its scan frames as the auction house opens, so wait for them.
	C_Timer.After(1.5, function()
		if ns.Option("scanPopup") and ns.Prices.IsStale() and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
			StaticPopup_Show("CFF_SCAN", ScanAgeText())
		end
		-- Once per visit, the way to the list, when there's something on it.
		if ns.Option("chatTips") and next(ns.plan.buy) and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
			ns.Say("chatTips", ('Materials to buy: click the Shopping tab at the bottom of the auction house (Auctionator), '
				.. 'then the list "%s".'):format(ns.LIST_NAME))
		end
		UI.RefreshAll()
	end)
end)

-- Gold changes come in bursts (each AH purchase, each mail's gold, selling junk), and every redraw of the Restock
-- tab may re-plan a partial restock against the gold carried, so draw once after the burst.
UI.MONEY_REFRESH_DELAY = 0.3
ns.On("PLAYER_MONEY", function()
	ns.Debounce("money", UI.MONEY_REFRESH_DELAY, function() UI.RefreshQueue() end)
end)

ns.On("AUCTION_HOUSE_CLOSED", function()
	UI.atAuctionHouse = false
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
	local send = ns.plan.send
	Add(("bank alt: %s, name %s, this one %s, to send %d, sends %s"):format(
		ns.db.ui.bankAltMode and "on" or "off", ns.Seller.Name() or "none",
		ns.Seller.IsMe() and "is the bank alt" or "crafts", send and send.units or 0,
		ns.db.ui.noAutoMail and "on a click" or "by itself"))
	Add("to buy: " .. CountKeys(ns.plan.buy) .. ", vendor: " .. CountKeys(ns.plan.vendor))
	Add("listings: " .. ns.Depth.Diag())
	if ns.Lock then Add("screen lock: " .. ns.Lock.Diag()) end -- a new file: not there after a /reload alone
	local status = ns.Shopping.status
	local soldTotal, expiredTotal = 0, 0
	for _, item in pairs(ns.db.sales.items) do
		soldTotal, expiredTotal = soldTotal + item.sold, expiredTotal + item.expired
	end
	Add(("sales recorded: %d sold, %d expired; open posts tracked: %d"):format(soldTotal, expiredTotal, #ns.db.sales.lots))
	Add(("list '%s': %d items, %d loading, error: %s"):format(ns.LIST_NAME, status.items, status.loading, tostring(status.error)))
	local rs = ns.Shopping.recipeStatus
	Add(("recipe lists: %d professions, %d items, %d loading, error: %s"):format(rs.lists, rs.items, rs.loading, tostring(rs.error)))
	Add(("queue profit: %s from %d entries, %d without a price, %d bind on pickup"):format(ns.Money(ns.totals.net), ns.totals.counted, ns.totals.excluded, ns.totals.bound))
	local openKey = ns.Recipes.OpenProfession()
	Add("open profession: " .. tostring(openKey) .. ", recipes in window: " .. CountKeys(ns.Recipes.OpenRecipes()))
	Add("Queue button on crafting page: " .. tostring(queueButton ~= nil))
	Add(("auction durations: %dh, %dh, %dh; client text: %s"):format(ns.Sales.DurationHours(1), ns.Sales.DurationHours(2),
		ns.Sales.DurationHours(3), tostring(_G.AUCTION_DURATION_ONE)))
	Add("Restocking tab created: " .. tostring(windows.posting ~= nil))
	Add("profession link API: " .. tostring(C_TradeSkillUI.GetTradeSkillListLink ~= nil)
		.. ", posting to: " .. tostring(ns.db.ui.adDestination or "TRADE"))
	local off = {}
	for _, key in ipairs({ "autoOpen", "nextStep", "scanPopup", "chatTips", "chatSales", "chatPlan", "chatDone", "chatWarnings", "adEnabled", "priceCap", "smartRestock", "bagSpace", "depthCheck", "recipeLists" }) do
		if not ns.Option(key) then table.insert(off, key) end
	end
	Add("options off: " .. (#off > 0 and table.concat(off, ", ") or "none") .. "; own ad text: "
		.. tostring(ns.db.ui.adText ~= nil) .. ", own quote text: " .. tostring(ns.db.ui.quoteText ~= nil))
	Add(("price check: above %d%%"):format(ns.Queue.PriceCapPercent()))
	ns.db.lastDiag = lines
end

SLASH_CFF1 = "/cff"
SLASH_CFF2 = "/craftfarm"
SlashCmdList.CFF = function(input)
	local command = (input or ""):lower():match("^%s*(%S*)")
	if command == "new" then command = "changelog" end
	if command == "config" or command == "settings" then command = "options" end
	if command == "writ" then command = "writs" end
	if command == "crate" then command = "crates" end
	if command == "queue" or command == "profit" or command == "restock" or command == "sales" or command == "options"
		or command == "writs" or command == "crates"
		or command == "changelog" then
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
		ns.Say("chatDone", "Open with the profession window: " .. tostring(ns.db.ui.autoOpen))
		ns.Options.Sync()
	elseif command == "minimap" then
		ns.MinimapButton.Toggle()
	elseif command == "diag" then
		Diagnostics()
	elseif command == "" then
		UI.ToggleMain()
	else
		ns.Print("/cff [profit | queue | restock | sales | writs | crates | options | changelog | next | minimap | advertise | refresh | clear | auto | diag]")
	end
end
