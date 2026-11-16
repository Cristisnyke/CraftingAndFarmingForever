-- Crafting and Farming Forever :: Depth
-- Listing depth: every listing of a material, as a search for that one item shows it. A price scan only knows the
-- cheapest listing, so buying fifty used to count at the price of the first five.
--
-- Listings are read two ways. From any search that passes by: you opening an item to buy it, the Restocking tab's
-- lookups. And from a check the add-on runs itself at the auction house, for what the plan and a restock would buy.
-- The check waits its turn: one search at a time, a moment after the auction house says it's ready, so your own
-- searches and other add-ons' always go first, and it holds off while you browse or buy.

local _, ns = ...

local Depth = {}
ns.Depth = Depth

Depth.MAX_AGE = ns.STALE_SECONDS -- listings older than this aren't used, like prices
Depth.REFRESH = 10 * 60 -- seconds; at the auction house an item is searched again once its listings are this old
Depth.MAX_TIERS = 40 -- price levels kept per item
Depth.version = 0 -- goes up with every change, for whoever caches something worked out from listings
Depth.round = 0 -- goes up as a check ends, for the screen lock (Lock.lua)

local YIELD = 0.3 -- seconds after the auction house is ready before a search goes out: everyone else first
local QUIET_BROWSE = 2 -- seconds the check holds off after browse results (a list search, a scan)
local QUIET_SEARCH = 15 -- and after someone else's search of one item, or a purchase being priced
local TIMEOUT = 5 -- seconds; a search with no answer by then is given up
local OWN_SECONDS = 10 -- answers for an item this soon after asking for it are ours, however many come
local LOAD_TRIES = 5 -- times an item whose data isn't loaded is waited for
local SORT_PRICE, SORT_BUYOUT = 0, 4 -- the game's auction sort orders

local pending = {} -- item IDs still to search, in order
local queued = {} -- [itemID] = true while it's in pending or being asked
local asked -- the search sent and not answered: { itemID, commodity }
local recent = {} -- [itemID] = GetTime() of our last search for it
local failed = {} -- [itemID] = time() a search for it was given up
local retried, waits = {}, {}
local total = 0 -- searches in this round, for the progress text
local quietUntil = 0
local readAt = {} -- [itemID] = GetTime() its listings were last read
local pricedAt -- GetTime() the game last priced a commodity purchase
local PURCHASE_SECONDS = 30 -- a purchase is taken to be done this long after it was priced
local shopping = {} -- [itemID] = true: what the last look at a restock would buy
-- For /cff diag: searches sent, answered, given up for no answer, answers not believed, others' searches read.
local stats = { sent = 0, answered = 0, timeouts = 0, unbelieved = 0, passive = 0 }

local function AuctionHouseOpen()
	return AuctionHouseFrame ~= nil and AuctionHouseFrame:IsShown()
end

---------------------------------------------------------------------------
-- Listings
---------------------------------------------------------------------------

-- The listings known of an item, cheapest first: { { price, units }, ..., more = true when there are listings past
-- these, at = when they were read }. Nil when it was never searched or that was too long ago.
function Depth.Of(itemID)
	local record = ns.db.depth[itemID]
	if not record or time() - record.at > Depth.MAX_AGE then return nil end
	return record
end

-- When an item's listings were read, in seconds ago; nil when they aren't known.
function Depth.Age(itemID)
	local record = Depth.Of(itemID)
	return record and time() - record.at
end

local function Same(a, b)
	if not a or not b or #a ~= #b or (a.more or false) ~= (b.more or false) then return false end
	for index, tier in ipairs(a) do
		if tier[1] ~= b[index][1] or tier[2] ~= b[index][2] then return false end
	end
	return true
end

local function Changed()
	Depth.version = Depth.version + 1
	ns.RequestPlan()
end

-- tiers = { { price, units }, ... } in any order.
local function Store(itemID, tiers, more)
	table.sort(tiers, function(a, b) return a[1] < b[1] end)
	local record = { at = time() }
	for _, tier in ipairs(tiers) do
		local last = record[#record]
		if last and last[1] == tier[1] then
			last[2] = last[2] + tier[2]
		elseif #record < Depth.MAX_TIERS then
			record[#record + 1] = { tier[1], tier[2] }
		else
			more = true
			break
		end
	end
	record.more = more or nil
	local old = Depth.Of(itemID)
	ns.db.depth[itemID] = record
	readAt[itemID] = GetTime()
	if not Same(old, record) then Changed() end
end

-- Units just bought are gone from the listings: taken off the cheapest, until the next search says how it is now.
function Depth.Bought(itemID, count)
	local record = ns.db.depth[itemID]
	if not record then return end
	-- Read again since this purchase was priced: those listings are already without it.
	local now = GetTime()
	if pricedAt and now - pricedAt < PURCHASE_SECONDS and (readAt[itemID] or 0) > pricedAt then return end
	while count > 0 and record[1] do
		local take = math.min(count, record[1][2])
		record[1][2], count = record[1][2] - take, count - take
		if record[1][2] <= 0 then table.remove(record, 1) end
	end
	Changed()
end

-- Whether an item's listings are worth keeping: something the add-on may have to buy, not everything you look at.
local function Wanted(itemID)
	return queued[itemID] or shopping[itemID] or ns.db.depth[itemID] ~= nil
		or (ns.plan and (ns.plan.buy[itemID] ~= nil or (ns.plan.compare and ns.plan.compare[itemID])))
end

-- The client sometimes answers a search with nothing though there are listings. An empty answer only counts when
-- the client says it has the results and all of them.
local function Believed(count, full, itemKey)
	if count > 0 then return true end
	if not full then return false end
	return not C_AuctionHouse.HasSearchResults or C_AuctionHouse.HasSearchResults(itemKey) == true
end

-- Both return true when the answer could be read. Your own auctions are left out: you can't buy those.
local function ReadCommodity(itemID)
	local count = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
	local full = not C_AuctionHouse.HasFullCommoditySearchResults or C_AuctionHouse.HasFullCommoditySearchResults(itemID)
	if not Believed(count, full, C_AuctionHouse.MakeItemKey(itemID)) then return false end
	local tiers = {}
	for index = 1, count do
		local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
		if info and info.unitPrice and info.unitPrice > 0 then
			local own = info.numOwnerItems or (info.containsOwnerItem and info.quantity) or 0
			local units = (info.quantity or 0) - own
			if units > 0 then tiers[#tiers + 1] = { info.unitPrice, units } end
		end
	end
	Store(itemID, tiers, not full)
	return true
end

local function ReadItem(itemKey)
	local count = C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0
	local full = not C_AuctionHouse.HasFullItemSearchResults or C_AuctionHouse.HasFullItemSearchResults(itemKey)
	if not Believed(count, full, itemKey) then return false end
	local tiers = {}
	for index = 1, count do
		local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
		-- Bid-only listings can't be bought outright.
		if info and info.buyoutAmount and info.buyoutAmount > 0 and not info.containsOwnerItem then
			tiers[#tiers + 1] = { info.buyoutAmount, info.quantity or 1 }
		end
	end
	Store(itemKey.itemID, tiers, not full)
	return true
end

local function IsEquipment(itemID)
	local classID = select(6, C_Item.GetItemInfoInstant(itemID))
	return classID == Enum.ItemClass.Weapon or classID == Enum.ItemClass.Armor
end

---------------------------------------------------------------------------
-- The check
---------------------------------------------------------------------------

local Next

local function Later(delay)
	ns.Debounce("depth", delay, function() Next() end)
end

local function RefreshStatus()
	ns.Debounce("depthStatus", 0.5, function()
		if ns.UI then ns.UI.RefreshQueue() end
	end)
end

-- finished: every search of the round was answered or given up (not cut short by the auction house closing).
local function Stop(finished)
	wipe(pending)
	wipe(queued)
	wipe(retried)
	wipe(waits)
	asked, total = nil, 0
	Depth.round = Depth.round + 1
	if ns.Lock then ns.Lock.Update() end
	if finished and ns.PlanCheck then ns.PlanCheck.End() end
end

-- Seconds the check still holds off for your own searches and purchases.
function Depth.Holding(now)
	return math.max(0, quietUntil - (now or GetTime()))
end

-- Searches left and searches in this round; nil when no check is running.
function Depth.Status()
	local left = #pending + (asked and 1 or 0)
	if left == 0 then return nil end
	return left, total
end

local function Answered(ok)
	local itemID = asked.itemID
	asked = nil
	if ok then stats.answered = stats.answered + 1 end
	if not ok and not retried[itemID] then
		-- Once more, after the others.
		retried[itemID] = true
		pending[#pending + 1] = itemID
	else
		queued[itemID] = nil
		if not ok then failed[itemID] = time() end
	end
	if #pending == 0 then Stop(true) end
	RefreshStatus()
	Later(YIELD)
end

Next = function()
	if asked or #pending == 0 then return end
	if not AuctionHouseOpen() then return Stop() end
	local now = GetTime()
	if now < quietUntil then return Later(quietUntil - now + 0.05) end
	-- Not ready: AUCTION_HOUSE_THROTTLED_SYSTEM_READY comes when it is.
	if not C_AuctionHouse.IsThrottledMessageSystemReady() then return end

	for index, itemID in ipairs(pending) do
		local stackable = ns.Items.IsStackable(itemID)
		local itemKey
		if stackable ~= nil then
			-- Equipment is listed per item level: the sell search with a key of no level finds them all.
			local equipment = not stackable and IsEquipment(itemID)
			itemKey = equipment and { itemID = itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
				or C_AuctionHouse.MakeItemKey(itemID)
			-- The client ignores searches for items it hasn't got the details of yet; asking fetches them.
			if C_AuctionHouse.GetItemKeyInfo(itemKey) then
				table.remove(pending, index)
				local search = { itemID = itemID, commodity = stackable }
				asked, recent[itemID] = search, now
				if ns.Lock then ns.Lock.Start() end
				local sorts = { { sortOrder = stackable and SORT_PRICE or SORT_BUYOUT, reverseSort = false } }
				if equipment then
					C_AuctionHouse.SendSellSearchQuery(itemKey, sorts, true)
				else
					C_AuctionHouse.SendSearchQuery(itemKey, sorts, true)
				end
				stats.sent = stats.sent + 1
				C_Timer.After(TIMEOUT, function()
					if asked == search then
						stats.timeouts = stats.timeouts + 1
						Answered(false)
					end
				end)
				return
			end
		end
		waits[itemID] = (waits[itemID] or 0) + 1
	end

	-- Nothing could be sent: item data is still loading. Those that never load are dropped.
	for index = #pending, 1, -1 do
		local itemID = pending[index]
		if (waits[itemID] or 0) >= LOAD_TRIES then
			table.remove(pending, index)
			queued[itemID], failed[itemID] = nil, time()
		end
	end
	if #pending == 0 then
		Stop(true)
		RefreshStatus()
	else
		Later(1)
	end
end

-- Searches these items, in this order, skipping those whose listings are fresh. Only at the auction house.
-- again: fresh ones too, and those a search was given up for (the Refresh button).
function Depth.Check(items, again)
	if not (AuctionHouseOpen() and ns.Option("depthCheck")) then return end
	local now = time()
	local added = false
	for _, itemID in ipairs(items) do
		local record = ns.db.depth[itemID]
		local fresh = record and now - record.at < Depth.REFRESH
		local gaveUp = failed[itemID] and now - failed[itemID] < Depth.REFRESH
		if not queued[itemID] and (again or not (fresh or gaveUp)) then
			failed[itemID] = nil
			queued[itemID] = true
			pending[#pending + 1] = itemID
			total = total + 1
			added = true
		end
	end
	if added then
		if ns.PlanCheck then ns.PlanCheck.Begin() end
		RefreshStatus()
		Later(YIELD)
	end
end

-- What the plan buys, then what the restock last looked at would buy.
function Depth.CheckWanted(again)
	if not (AuctionHouseOpen() and ns.Option("depthCheck")) then return end
	local items, seen = {}, {}
	local function Add(set)
		local ids = {}
		for itemID in pairs(set) do
			if not seen[itemID] then
				seen[itemID] = true
				ids[#ids + 1] = itemID
			end
		end
		table.sort(ids)
		for _, itemID in ipairs(ids) do items[#items + 1] = itemID end
	end
	Add(ns.plan.buy)
	-- Both sides of each buy-or-craft choice: the bars and the ore they're smelted from.
	Add(ns.plan.compare or {})
	Add(shopping)
	Depth.Check(items, again)
end

-- The materials a restock would buy (itemID -> anything), noted each time the Restock rows are worked out.
function Depth.SetShopping(items)
	wipe(shopping)
	for itemID in pairs(items) do shopping[itemID] = true end
	Depth.CheckWanted()
end

-- How many of the restock's materials have no listings read: their cost is still the cheapest listing times the count.
function Depth.Unchecked()
	local missing = 0
	for itemID in pairs(shopping) do
		if not Depth.Of(itemID) then missing = missing + 1 end
	end
	return missing
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function Quiet(seconds)
	quietUntil = math.max(quietUntil, GetTime() + seconds)
end

-- True when the answer is to a search of ours, also when it comes in more than one part.
local function Ours(itemID)
	if asked and asked.itemID == itemID then return true end
	return recent[itemID] ~= nil and GetTime() - recent[itemID] < OWN_SECONDS
end

local function Count(ok, ours)
	if not ok then
		stats.unbelieved = stats.unbelieved + 1
	elseif not ours then
		stats.passive = stats.passive + 1
	end
end

function Depth.Diag()
	local known, inPlan, deep = 0, 0, 0
	for itemID in pairs(ns.db.depth) do
		if Depth.Of(itemID) then known = known + 1 end
	end
	for itemID in pairs(ns.plan.buy) do
		inPlan = inPlan + 1
		if ns.plan.deep[itemID] then deep = deep + 1 end
	end
	return ("%d items known, %d of %d to buy priced by them; check %s, sent %d, answered %d, no answer %d, "
		.. "not believed %d, read from other searches %d, waiting %d"):format(known, deep, inPlan,
		ns.Option("depthCheck") and "on" or "off", stats.sent, stats.answered, stats.timeouts, stats.unbelieved,
		stats.passive, #pending + (asked and 1 or 0))
end

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
	if not itemID then return end
	local ours = Ours(itemID)
	if not ours then Quiet(QUIET_SEARCH) end
	if not (ours or Wanted(itemID)) then return end
	local ok = ReadCommodity(itemID)
	Count(ok, ours)
	if asked and asked.itemID == itemID then Answered(ok) end
end)

local function ItemResults(itemKey)
	local itemID = itemKey and itemKey.itemID
	if not itemID then return end
	local ours = Ours(itemID)
	if not ours then Quiet(QUIET_SEARCH) end
	-- Someone else's search of equipment is for one item level only: not the whole market.
	if not ours and (not Wanted(itemID) or IsEquipment(itemID)) then return end
	local ok = ReadItem(itemKey)
	Count(ok, ours)
	if asked and asked.itemID == itemID then Answered(ok) end
end
ns.On("ITEM_SEARCH_RESULTS_UPDATED", ItemResults)
ns.On("ITEM_SEARCH_RESULTS_ADDED", ItemResults)

ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function() Quiet(QUIET_BROWSE) end)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function() Quiet(QUIET_BROWSE) end)
-- A purchase being priced: nothing is sent that could get in its way.
ns.On("COMMODITY_PRICE_UPDATED", function()
	pricedAt = GetTime()
	Quiet(QUIET_SEARCH)
end)

ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
	if #pending > 0 and not asked then Later(YIELD) end
end)
ns.On("ITEM_KEY_ITEM_INFO_RECEIVED", function()
	if #pending > 0 and not asked then Later(YIELD) end
end)

ns.On("AUCTION_HOUSE_SHOW", function()
	C_Timer.After(1, Depth.CheckWanted)
end)
-- The next visit starts afresh, also with the items a search was given up for.
ns.On("AUCTION_HOUSE_CLOSED", function()
	Stop()
	wipe(failed)
	wipe(recent)
	quietUntil = 0
end)
