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

-- The item name a search string was built from.
local function NameOf(searchString)
	return (searchString:match('^"([^"]*)"') or searchString:match("^([^;]*)") or ""):lower()
end

-- Search strings wanted right now, by lowercase name, plus the number of items whose names are still loading.
local function DesiredStrings()
	local api = Auctionator.API.v1
	local byName, loading = {}, 0
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
	-- What the queue will make goes on the list too, with no quantity to buy, so scanning the list also refreshes
	-- the sale prices the profit depends on. Bind-on-pickup results have no sale price to refresh.
	for _, entry in ipairs(ns.db.queue) do
		local recipe = ns.db.recipes[entry.recipeID]
		if recipe and recipe.o and ns.Items.CanSellOnAH(recipe.o) ~= false then
			local name = ns.Items.Name(recipe.o)
			if name then
				local clean = Sanitize(name)
				local key = clean:lower()
				byName[key] = byName[key] or { name = clean, count = 0 }
			elseif not ns.Items.IsMissing(recipe.o) then
				loading = loading + 1
			end
		end
	end

	local wanted = {}
	for key, item in pairs(byName) do
		wanted[key] = api.ConvertToSearchString(ns.name, {
			searchString = item.name,
			isExact = true,
			categoryKey = "",
			quantity = item.count > 0 and item.count or nil,
		})
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
		ns.Print("Could not update the Auctionator list: " .. tostring(err))
	end
end
