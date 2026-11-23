-- Crafting and Farming Forever :: Shopping
-- Keeps one Auctionator shopping list equal to what the plan still has to buy.
--
-- The list is edited in place. CreateShoppingList replaces the list and re-expands it in Auctionator's tab, which
-- would disturb a purchase in progress every time the bags change, so it is only used to create the list once.

local _, ns = ...

local Shopping = {}
ns.Shopping = Shopping

Shopping.status = { items = 0, loading = 0 }

local function Sanitize(name)
	return (name:gsub("[;^\"]", " "))
end

-- An exact-name Auctionator search, for a quantity or (nil) just to see the price. Used by the writs list too.
function Shopping.SearchString(name, quantity)
	return Auctionator.API.v1.ConvertToSearchString(ns.name, {
		searchString = Sanitize(name),
		isExact = true,
		categoryKey = "",
		quantity = quantity,
	})
end

-- The item name a search string was built from.
local function NameOf(searchString)
	return (searchString:match('^"([^"]*)"') or searchString:match("^([^;]*)") or ""):lower()
end

-- Search strings wanted right now, by lowercase name, plus the number of items whose names are still loading.
local function DesiredStrings()
	local byName, loading = {}, 0
	-- Materials only. The queued results used to be listed too, with no quantity, to refresh their sale prices, but
	-- that read as "buy what you're about to craft".
	for itemID, count in pairs(ns.plan.buy) do
		local name = ns.Items.Name(itemID)
		if name then
			-- Different item IDs can share a name, and an exact-name search finds them all, so add them up.
			local clean = Sanitize(name)
			local key = clean:lower()
			byName[key] = byName[key] or { name = clean, count = 0 }
			byName[key].count = byName[key].count + count
		elseif not ns.Items.IsMissing(itemID) then
			loading = loading + 1
		end
	end

	local wanted = {}
	for key, item in pairs(byName) do
		wanted[key] = Shopping.SearchString(item.name, item.count)
	end
	return wanted, loading
end

local function ListExists()
	return Auctionator.Shopping.ListManager:GetIndexForName(ns.LIST_NAME) ~= nil
end

local function Update()
	local api = Auctionator.API.v1
	local wanted, loading = DesiredStrings()
	Shopping.status.loading = loading
	local total = 0
	for _ in pairs(wanted) do total = total + 1 end
	Shopping.status.items = total

	if not ListExists() then
		-- Nothing to buy and no list yet: don't add an empty list to the user's Auctionator.
		if total == 0 then return end
		local strings = {}
		for _, searchString in pairs(wanted) do table.insert(strings, searchString) end
		table.sort(strings)
		api.CreateShoppingList(ns.name, ns.LIST_NAME, strings)
		return
	end

	for _, existing in ipairs(api.GetShoppingListItems(ns.name, ns.LIST_NAME)) do
		local key = NameOf(existing)
		local desired = wanted[key]
		if not desired then
			-- While a name is loading a row can't be told apart from that item, so removal waits for the next
			-- sync, which runs as soon as the name arrives.
			if loading == 0 then api.DeleteShoppingListItem(ns.name, ns.LIST_NAME, existing) end
		else
			if desired ~= existing then api.AlterShoppingListItem(ns.name, ns.LIST_NAME, existing, desired) end
			wanted[key] = nil
		end
	end

	local additions = {}
	for _, searchString in pairs(wanted) do table.insert(additions, searchString) end
	if #additions == 0 then return end
	table.sort(additions)
	local list = Auctionator.Shopping.ListManager:GetByName(ns.LIST_NAME)
	for _, searchString in ipairs(additions) do list:InsertItem(searchString) end
end

function Shopping.Sync()
	if not (Auctionator and Auctionator.Shopping and Auctionator.Shopping.ListManager) then return end
	local ok, err = pcall(Update)
	Shopping.status.error = not ok and tostring(err) or nil
	if not ok and not Shopping.reported then
		Shopping.reported = true
		ns.Say("chatWarnings", "Could not update the Auctionator list: " .. tostring(err))
	end
end

---------------------------------------------------------------------------
-- Recipes to learn: a second list with the recipe items (patterns, plans, formulas...) the logged-in character can
-- learn right now, lowest skill first. Only recipes that come as an item which isn't bound; trainer recipes have
-- nothing to buy.
---------------------------------------------------------------------------

Shopping.recipeStatus = { items = 0, loading = 0 }

-- Search strings in order, plus how many names are still loading.
function Shopping.RecipeStrings(charKey)
	local Book = ns.RecipeBook
	local rows, loading = {}, 0
	for recipeID in pairs(Book.Learnable(charKey)) do
		local data = ns.RecipeData[recipeID]
		local _, bound = Book.Price(recipeID)
		if data and data.i and not bound then
			local name = ns.Items.Name(data.i)
			if name then
				table.insert(rows, { skill = data.s or 0, name = Sanitize(name) })
			elseif not ns.Items.IsMissing(data.i) then
				loading = loading + 1
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.skill ~= b.skill then return a.skill < b.skill end
		return a.name < b.name
	end)
	local strings, have = {}, {}
	for _, row in ipairs(rows) do
		-- Two recipes can share an item name; an exact-name search finds both.
		local key = row.name:lower()
		if not have[key] then
			have[key] = true
			table.insert(strings, Shopping.SearchString(row.name))
		end
	end
	return strings, loading
end

-- True when old minus some entries is exactly new (same order): then rows can be deleted in place.
local function OnlyRemoved(old, new)
	local j = 1
	for _, s in ipairs(old) do
		if s == new[j] then j = j + 1 end
	end
	return j == #new + 1
end

local function UpdateRecipes()
	local api = Auctionator.API.v1
	local manager = Auctionator.Shopping.ListManager
	local wanted, loading = Shopping.RecipeStrings(ns.CharKey())
	Shopping.recipeStatus.loading = loading
	Shopping.recipeStatus.items = #wanted
	-- Wait for every name, so the order is right in one go.
	if loading > 0 then return end
	if manager:GetIndexForName(ns.RECIPE_LIST_NAME) == nil then
		if #wanted > 0 then api.CreateShoppingList(ns.name, ns.RECIPE_LIST_NAME, wanted) end
		return
	end
	local existing = api.GetShoppingListItems(ns.name, ns.RECIPE_LIST_NAME)
	local same = #existing == #wanted
	for i = 1, #wanted do
		if existing[i] ~= wanted[i] then same = false break end
	end
	if same then return end
	if OnlyRemoved(existing, wanted) then
		-- A recipe learned (often one just bought): delete its row, so a search in progress isn't disturbed.
		local keep = {}
		for _, s in ipairs(wanted) do keep[s] = true end
		for _, s in ipairs(existing) do
			if not keep[s] then api.DeleteShoppingListItem(ns.name, ns.RECIPE_LIST_NAME, s) end
		end
		return
	end
	-- New ones (a skill-up, another character): rewrite the list in skill order.
	api.CreateShoppingList(ns.name, ns.RECIPE_LIST_NAME, wanted)
end

function Shopping.SyncRecipes()
	if not (ns.RecipeBook and Auctionator and Auctionator.API and Auctionator.Shopping
		and Auctionator.Shopping.ListManager) then return end
	local ok, err = pcall(UpdateRecipes)
	Shopping.recipeStatus.error = not ok and tostring(err) or nil
end

local function RequestRecipes()
	ns.Debounce("recipeList", 1, Shopping.SyncRecipes)
end
ns.WhenDataReady(RequestRecipes)
ns.On("AUCTION_HOUSE_SHOW", RequestRecipes)
ns.On("NEW_RECIPE_LEARNED", RequestRecipes)
ns.On("SKILL_LINES_CHANGED", RequestRecipes)
ns.On("TRADE_SKILL_LIST_UPDATE", RequestRecipes)
ns.On("GET_ITEM_INFO_RECEIVED", function()
	if Shopping.recipeStatus.loading > 0 then RequestRecipes() end
end)
