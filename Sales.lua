-- Crafting and Farming Forever :: Sales
-- Records what sells and what expires, and estimates the chance a listed item sells within 24 hours.
--
-- Outcomes come from the auction house mail, the only source that also covers sales made while offline. Mail that
-- is still in the box gets scanned again every visit, so each one is remembered until it can no longer be there.
-- Time on the AH comes from recording each post. A sale or expiry is matched to the oldest post of that item.
--
-- db.sales.items[lowercase name] = { name, itemID, sold, expired, gold, exposure = unit-days listed,
--                                    days = { [day number] = { s = sold, e = expired, g = copper,
--                                               c = copper paid for the sold units whose cost is known,
--                                               u = sold units with no cost on record,
--                                               d = copper of deposits lost on expired units, dk = how many
--                                                   of the expired units that covers,
--                                               x = true for results from before profit was counted } } }
-- db.sales.profitFrom            = when profit began to be counted
-- db.costs[itemID]               = { q = units held with a cost on record, c = copper paid for them }
-- db.sales.lots[i]               = { itemID, name, qty, at = posted time, dur = seconds, char,
--                                    price = copper per unit, commodity = true for stackable goods,
--                                    dep = copper of deposit per unit }
-- db.sales.incoming[i]           = { name, itemID, char, at = sold time, due = when the money arrives,
--                                    amount = copper after the AH cut (nil if unknown), rough = true when estimated,
--                                    told = true once its arrival has been announced }
-- db.sales.seen[char][i]         = { key, expires }
-- db.sales.trips[i]              = when a restock was posted (posts close together are one), the latest SMART.TRIPS
-- db.sales.inboxSeen / inboxSettled = { at, shown, total, settled }: the last mail scan, and the last after the inbox came in
-- db.deposits[itemID]            = copper per unit the last post of it cost in deposit

local _, ns = ...

local Sales = {}
ns.Sales = Sales

local DAY = 24 * 60 * 60
local MAIL_LIFETIME_DAYS = 30
local SAME_MAIL_TOLERANCE = 600 -- seconds; a mail's expiry time can differ slightly between scans
local OPEN_LOT_LIMIT = 45 * DAY
-- A post's results are all in the mailbox this long after it ended (a sale's money takes an hour). One still open
-- after that, at a look at the whole mailbox, never got a result that can be matched: a post the server refused, or
-- a mail emptied before the add-on saw it. Left open it took the next real result of that item and priced money on
-- its way at its own old price.
local LOT_RESULT_HOURS = 3

-- Used for outcomes with no recorded post, such as auctions listed before this add-on tracked them.
local ASSUMED_SOLD_SECONDS = DAY / 2
local ASSUMED_EXPIRED_SECONDS = DAY

-- Added to the time on the AH, so a single quick sale doesn't read as a near-certain seller.
local PRIOR_UNIT_DAYS = 1

-- Under this many sold plus expired units the percentage is shown as a rough estimate.
Sales.CONFIDENT_SAMPLES = 5

---------------------------------------------------------------------------
-- Auction durations
---------------------------------------------------------------------------

local DURATION_TEXT = { "AUCTION_DURATION_ONE", "AUCTION_DURATION_TWO", "AUCTION_DURATION_THREE" }
local DURATION_NAME = { "Short", "Medium", "Long" }
local DURATION_FALLBACK = { 12, 24, 48 }

-- Hours of the client's duration 1 to 3. They differ between game versions, so the game's own text decides, then what
-- Auctionator has on record for this version.
function Sales.DurationHours(index)
	local text = _G[DURATION_TEXT[index]]
	local hours = type(text) == "string" and tonumber(text:match("%d+"))
	if hours then return hours end
	local known = Auctionator and Auctionator.Constants and Auctionator.Constants.Durations
	return known and known[DURATION_NAME[index]] or DURATION_FALLBACK[index]
end

---------------------------------------------------------------------------
-- Calendar
---------------------------------------------------------------------------

local DayNumber = ns.DayNumber

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

local function ItemRecord(name, itemID)
	local items = ns.db.sales.items
	local key = name:lower()
	local item = items[key]
	if not item then
		item = { name = name, sold = 0, expired = 0, gold = 0, exposure = 0, days = {} }
		items[key] = item
	end
	item.itemID = item.itemID or itemID
	return item
end

-- Takes units off the oldest posts of this item and returns the unit-days they spent on the AH, plus how many units
-- had no post to match, the deposit paid for them and how many units that deposit is known for.
local function ConsumeLots(key, count, when, char)
	local lots = ns.db.sales.lots
	local exposure, deposit, covered = 0, 0, 0
	local index = 1
	while count > 0 and index <= #lots do
		local lot = lots[index]
		if lot.char == char and lot.name and lot.name:lower() == key and lot.at <= when then
			local take = math.min(lot.qty, count)
			exposure = exposure + take * math.min(when - lot.at, lot.dur) / DAY
			if lot.dep then deposit, covered = deposit + take * lot.dep, covered + take end
			lot.qty = lot.qty - take
			count = count - take
			if lot.qty <= 0 then
				table.remove(lots, index)
				index = index - 1
			end
		end
		index = index + 1
	end
	return exposure, count, deposit, covered
end

-- kind is "sold", "expired" or "cancelled". Cancelled auctions count as time on the AH with no result either way.
function Sales.Record(kind, name, count, money, when, char, itemID)
	local item = ItemRecord(name, itemID)
	Sales.ForgetCraftInfo()
	local exposure, unmatched, deposit, depositUnits = ConsumeLots(name:lower(), count, when, char)
	item.exposure = item.exposure + exposure
	if kind == "sold" then
		item.exposure = item.exposure + unmatched * ASSUMED_SOLD_SECONDS / DAY
	elseif kind == "expired" then
		item.exposure = item.exposure + unmatched * ASSUMED_EXPIRED_SECONDS / DAY
	end
	if kind == "cancelled" then return end

	local dayNumber = DayNumber(when)
	local day = item.days[dayNumber]
	if not day then
		day = { s = 0, e = 0, g = 0, c = 0, u = 0 }
		item.days[dayNumber] = day
	end
	if kind == "sold" then
		item.sold = item.sold + count
		item.gold = item.gold + (money or 0)
		day.s = day.s + count
		day.g = day.g + (money or 0)
		-- What these units cost to buy or make, for the profit. Units with nothing on record are estimated later.
		local cost, covered = 0, 0
		local costID = item.itemID or Sales.CraftedID(item)
		if costID then cost, covered = Sales.TakeCost(costID, count) end
		day.c = (day.c or 0) + cost
		day.u = (day.u or 0) + count - covered
		Sales.FreezeCosts(item)
	else
		item.expired = item.expired + count
		day.e = day.e + count
		-- The deposit these lost, for smart restock goals: a long auction that expires costs more than a short one.
		if depositUnits > 0 then day.d, day.dk = (day.d or 0) + deposit, (day.dk or 0) + depositUnits end
	end
end

---------------------------------------------------------------------------
-- Reading results
---------------------------------------------------------------------------

-- Chance a listed unit sells within 24 hours, from 0 to 1, and the sold plus expired units behind it. Nil with no
-- data. Sales and listed time are turned into a per-day rate, then the rate into a chance over one day.
function Sales.Chance(name)
	if not name then return nil end
	local key = name:lower()
	local item = ns.db.sales.items[key]
	local openExposure = 0
	local now = time()
	for _, lot in ipairs(ns.db.sales.lots) do
		if lot.name and lot.name:lower() == key then
			openExposure = openExposure + lot.qty * math.max(0, math.min(now - lot.at, lot.dur)) / DAY
		end
	end
	if not item or item.sold + item.expired == 0 then return nil end
	local rate = item.sold / (item.exposure + openExposure + PRIOR_UNIT_DAYS)
	return 1 - math.exp(-rate), item.sold + item.expired
end

-- Sold, expired and copper earned over the last N calendar days, today included. Nil for all time.
function Sales.Counts(item, days)
	if not days then return item.sold, item.expired, item.gold end
	local today = DayNumber(time())
	local sold, expired, gold = 0, 0, 0
	for dayNumber = today - days + 1, today do
		-- A day's results from before a profit reset are kept half a key earlier (see Sales.ResetProfit).
		for _, day in ipairs({ item.days[dayNumber] or false, item.days[dayNumber - 0.5] or false }) do
			if day then sold, expired, gold = sold + day.s, expired + day.e, gold + day.g end
		end
	end
	return sold, expired, gold
end

-- The same, but only results from since profit is counted, then the known cost of the sold units and how many of
-- them have no cost on record.
local function Tracked(item, days)
	local first = days and DayNumber(time()) - days + 1
	local sold, expired, gold, cost, unknown, estimated = 0, 0, 0, 0, 0, 0
	for dayNumber, day in pairs(item.days) do
		if not day.x and (not first or dayNumber >= first) then
			sold, expired, gold = sold + day.s, expired + day.e, gold + day.g
			cost, unknown, estimated = cost + (day.c or 0), unknown + (day.u or 0), estimated + (day.r or 0)
		end
	end
	return sold, expired, gold, cost, unknown, estimated
end

-- An item's results by day for smart restock goals: { { age = days ago, s, e, d }, ... } over the last `window`
-- days, and the days since its first result (today included). Nil with nothing on record. d is the deposit the
-- day's expired units lost: what their posts paid where that's on record, the item's last known deposit for the
-- rest, nil when neither is known.
function Sales.History(name, window)
	local item = name and ns.db.sales.items[name:lower()]
	if not item then return nil end
	local today = DayNumber(time())
	local days, byAge, oldest = {}, {}, nil
	local usual = item.itemID and ns.db.deposits[item.itemID]
	for dayNumber, day in pairs(item.days) do
		local age = today - math.ceil(dayNumber) -- a day moved by a profit reset sits half a key earlier
		if age >= 0 and (day.s > 0 or day.e > 0) then
			if not oldest or age > oldest then oldest = age end
			if age < window then
				local entry = byAge[age]
				if not entry then
					entry = { age = age, s = 0, e = 0 }
					byAge[age] = entry
					days[#days + 1] = entry
				end
				entry.s, entry.e = entry.s + day.s, entry.e + day.e
				local unknown = day.e - (day.dk or 0)
				if day.e > 0 and (unknown <= 0 or usual) then
					entry.d = (entry.d or 0) + (day.d or 0) + math.max(0, unknown) * (usual or 0)
				end
			end
		end
	end
	if not oldest then return nil end
	return days, oldest + 1
end

-- How many days ago the oldest auction of this item that's still running was posted, nil with none running. Up to
-- that day nothing can be called sold out yet.
function Sales.RunningAge(name)
	if not name then return nil end
	local key, now = name:lower(), time()
	local oldest
	for _, lot in ipairs(ns.db.sales.lots) do
		if lot.qty > 0 and lot.name and lot.name:lower() == key and lot.at + lot.dur > now then
			if not oldest or lot.at < oldest then oldest = lot.at end
		end
	end
	return oldest and DayNumber(now) - DayNumber(oldest) or nil
end

---------------------------------------------------------------------------
-- Restock times and deposits
---------------------------------------------------------------------------

-- When restocks were posted. Posts within SMART.SESSION of the one before belong to the same restock. The first
-- time, it's filled from the posts still on record from the last three days: older ones are too thin to go by,
-- since a post leaves the record once its result is read from the mail.
local SEED_DAYS = 3

local function Trips()
	local sales = ns.db.sales
	if not sales.trips then
		local times, now = {}, time()
		for _, lot in ipairs(sales.lots) do
			if lot.at and lot.at >= now - SEED_DAYS * DAY then times[#times + 1] = lot.at end
		end
		table.sort(times)
		sales.trips = {}
		for _, at in ipairs(times) do Sales.NoteTrip(at) end
	end
	return sales.trips
end

function Sales.NoteTrip(at)
	local trips = ns.db.sales.trips or Trips()
	local smart = ns.Planner.SMART
	local last = trips[#trips]
	if last and at - last < smart.SESSION then return end
	trips[#trips + 1] = at
	while #trips > smart.TRIPS do table.remove(trips, 1) end
end

-- Days your stock has to last between two restocks (see Planner.RestockGap), nil until enough are on record.
function Sales.RestockGap()
	return ns.Planner.RestockGap(Trips())
end

-- What listing one unit cost in deposit the last time it was posted, nil if never seen. Lost when it doesn't sell.
function Sales.Deposit(itemID)
	return ns.db.deposits[itemID]
end

function Sales.Item(name)
	return name and ns.db.sales.items[name:lower()] or nil
end

-- Known recipes and today's craft costs, kept for a moment: every row and summary box asks.
local craftInfo
local CRAFT_INFO_SECONDS = 5

local function CraftInfo()
	local now = GetTime()
	if not craftInfo or now - craftInfo.at > CRAFT_INFO_SECONDS then
		local ctx = ns.NewContext()
		local names = {}
		for itemID in pairs(ctx.known) do
			local name = ns.Items.Name(itemID)
			if name then names[name:lower()] = itemID end
		end
		craftInfo = { at = now, ctx = ctx, names = names, unit = {} }
	end
	return craftInfo
end

function Sales.ForgetCraftInfo()
	craftInfo = nil
end

-- The item's ID when a recipe one of your characters knows makes it. Sold mail has no ID, so the name decides too.
function Sales.CraftedID(item)
	local info = CraftInfo()
	if item.itemID and info.ctx.known[item.itemID] then return item.itemID end
	return info.names[item.name:lower()]
end

-- Today's cost to craft one of a crafted item at market prices, nil when unknown.
local function CraftUnit(itemID)
	local info = CraftInfo()
	if info.unit[itemID] == nil then info.unit[itemID] = ns.Planner.CraftUnitCost(info.ctx, itemID) or false end
	return info.unit[itemID] or nil
end
Sales.CraftUnit = CraftUnit

-- What making `units` of a crafted item costs in one go, the materials bought down their listings where those were
-- read (Planner.CraftCostFor). Nil when unknown.
function Sales.CraftCost(itemID, units)
	return ns.Planner.CraftCostFor(CraftInfo().ctx, itemID, units)
end

-- Sold crafted units with no cost on record (made before costs were kept) get the cost to craft one at that
-- moment, once, and keep it: a profit that moved with every price scan was confusing (the user, 2026-11-14).
-- day.r counts the units costed this way, so the profit still shows as an estimate. Units stay in day.u while
-- there's no price to go on.
function Sales.FreezeCosts(item)
	local unit
	for _, day in pairs(item.days) do
		if not day.x and (day.u or 0) > 0 then
			if unit == nil then
				local itemID = Sales.CraftedID(item)
				unit = itemID and CraftUnit(itemID) or false
			end
			if not unit then return end
			day.c = (day.c or 0) + day.u * unit
			day.r = (day.r or 0) + day.u
			day.u = 0
		end
	end
end

-- Sales whose money is still on its way or waiting in a mailbox: the mail hasn't been read, so they aren't in the
-- records yet. Returns units, copper expected, what they cost and whether any of it is an estimate, for one item
-- (by lowercase name) over the last N days. Units with no cost on record count at today's cost to craft one, as in
-- Sales.Profit.
local function Pending(key, days)
	local first = days and DayNumber(time()) - days + 1
	local count, gold, cost, rough = 0, 0, 0, false
	for _, entry in ipairs(ns.db.sales.incoming) do
		if entry.amount and not entry.x and entry.name and entry.name:lower() == key
			and (not first or DayNumber(entry.at) >= first) then
			count = count + 1
			gold = gold + entry.amount
			rough = rough or entry.rough or false
			local itemID = entry.itemID or CraftInfo().names[key]
			local pool = itemID and ns.db.costs[itemID]
			if pool and pool.q >= 1 then
				cost = cost + pool.c / pool.q
			elseif itemID and CraftInfo().ctx.known[itemID] then
				cost = cost + (CraftUnit(itemID) or 0)
				rough = true
			end
		end
	end
	return count, gold, cost, rough
end

-- Profit over the last N days (nil for all time): the money received, after the AH cut, less what the sold units
-- cost you. Then whether part of it is an estimate, and sold, expired and copper received. Only results from since
-- profit is counted. Crafted units with no cost on record (made before costs were kept) count at today's cost to
-- craft one, as an estimate: counting them as free made everything made from old stock look like pure profit.
function Sales.Profit(item, days)
	Sales.FreezeCosts(item)
	local sold, expired, gold, cost, unknown, estimated = Tracked(item, days)
	local rough = estimated > 0
	if unknown > 0 then
		local itemID = Sales.CraftedID(item)
		if itemID then
			cost = cost + unknown * (CraftUnit(itemID) or 0)
			rough = true
		end
	end
	-- Sold, but the money is still on its way.
	local pendingCount, pendingGold, pendingCost, pendingRough = Pending(item.name:lower(), days)
	return gold + pendingGold - cost - pendingCost, rough or pendingRough, sold + pendingCount, expired, gold + pendingGold
end

-- Starts profit again from nothing, as when it first began: every result so far (and sale whose money is on its
-- way) leaves the profit and the Sales list, but still feeds the chance to sell and the tooltips' history. What
-- the things you hold cost is kept. Today's results move to a key of their own, so that sales later today count.
function Sales.ResetProfit()
	local today = DayNumber(time())
	for _, item in pairs(ns.db.sales.items) do
		local days = item.days or {}
		local now, before = days[today], days[today - 0.5]
		if now and before then
			for _, field in ipairs({ "s", "e", "g", "c", "u", "r" }) do before[field] = (before[field] or 0) + (now[field] or 0) end
			days[today] = nil
		elseif now then
			days[today - 0.5], days[today] = now, nil
		end
		for _, day in pairs(days) do day.x = true end
	end
	for _, entry in ipairs(ns.db.sales.incoming) do entry.x = true end
	ns.db.sales.profitFrom = time()
	if ns.UI then ns.UI.Refresh("sales") end
end

-- Sold, expired, copper received, profit and whether the profit is partly estimated, over the last N days. Only
-- items your characters craft unless everything is asked for.
function Sales.Totals(days, everything)
	local sold, expired, gold, profit, rough = 0, 0, 0, 0, false
	for _, item in pairs(ns.db.sales.items) do
		if everything or Sales.CraftedID(item) then
			local p, r, s, e, g = Sales.Profit(item, days)
			sold, expired, gold, profit, rough = sold + s, expired + e, gold + g, profit + p, rough or r
		end
	end
	-- Money on its way for items with no results on record yet.
	local done = {}
	for _, entry in ipairs(ns.db.sales.incoming) do
		local key = entry.name and entry.name:lower()
		if key and not done[key] and not ns.db.sales.items[key] then
			done[key] = true
			if everything or Sales.CraftedID({ name = entry.name, itemID = entry.itemID }) then
				local count, pendingGold, cost, r = Pending(key, days)
				sold, gold, profit, rough = sold + count, gold + pendingGold, profit + pendingGold - cost, rough or r
			end
		end
	end
	return sold, expired, gold, profit, rough
end

-- Every item with results, most profit over the last 30 days first. Only items your characters craft unless
-- everything is asked for.
function Sales.AllItems(everything)
	local list, recent = {}, {}
	for _, item in pairs(ns.db.sales.items) do
		local sold, expired = Tracked(item)
		if sold + expired + Pending(item.name:lower()) > 0 and (everything or Sales.CraftedID(item)) then
			table.insert(list, item)
			recent[item] = Sales.Profit(item, 30)
		end
	end
	table.sort(list, function(a, b)
		if recent[a] ~= recent[b] then return recent[a] > recent[b] end
		return a.name < b.name
	end)
	return list
end

---------------------------------------------------------------------------
-- What things cost
---------------------------------------------------------------------------
-- A running record of what the items you hold cost, so a sale's profit is counted from what went into it: auction
-- house purchases at the price paid, crafts at what their materials cost. Each item is one pool with an average
-- cost, shared by all characters, since mail moves things between them. Materials with no purchase on record (held
-- before this record began, gathered, looted, traded) count at the market price on the day they're used: they could
-- have been sold for that. (1.7.1 counted them as free, so a bag made from two bolts you had and one you bought
-- showed the cost of one bolt and far too much profit. The user chose market value on 2026-11-13.)

function Sales.AddCost(itemID, qty, copper)
	if not (itemID and qty and qty > 0) then return end
	local entry = ns.db.costs[itemID]
	if not entry then
		entry = { q = 0, c = 0 }
		ns.db.costs[itemID] = entry
	end
	entry.q = entry.q + qty
	entry.c = entry.c + math.max(0, copper or 0)
end

-- Takes units out of an item's pool at its average cost. Returns the copper they cost and how many of them the
-- pool covered; the rest have no cost on record.
function Sales.TakeCost(itemID, qty)
	local entry = ns.db.costs[itemID]
	if not entry or entry.q <= 0 or qty <= 0 then return 0, 0 end
	local take = math.min(qty, entry.q)
	local cost = entry.c * take / entry.q
	entry.q = entry.q - take
	entry.c = entry.c - cost
	if entry.q < 0.001 then ns.db.costs[itemID] = nil end
	return cost, take
end

-- An auction house purchase: the price paid, or the market price when the game didn't say.
function Sales.NotePurchase(itemID, count, paid)
	if not paid then
		local market = ns.Prices.AH(itemID)
		paid = market and market * count or 0
	end
	Sales.AddCost(itemID, count, paid)
end

-- A finished craft: its materials leave their pools and their cost moves to what was made. Materials with no cost
-- on record count at the vendor's price when a vendor sells them, else at the market's cheapest way to get one
-- (nothing when there's no price at all).
function Sales.NoteCraft(recipe)
	if not recipe.o then return end
	local total, ctx = 0, nil
	for _, slot in ipairs(recipe.r or {}) do
		local count, itemID = slot[1], slot[2]
		for index = 2, #slot do
			if ns.db.costs[slot[index]] then
				itemID = slot[index]
				break
			end
		end
		if itemID then
			local cost, covered = Sales.TakeCost(itemID, count)
			if covered < count then
				local unit = ns.Prices.Vendor(itemID)
				if not (unit and unit > 0) then
					ctx = ctx or CraftInfo().ctx
					unit = ns.Planner.ItemCost(ctx, itemID)
				end
				cost = cost + (count - covered) * (unit or 0)
			end
			total = total + cost
		end
	end
	local qmin = recipe.qmin or 1
	local made = (qmin + (recipe.qmax or qmin)) / 2
	Sales.AddCost(recipe.o, made > 0 and made or 1, total)
	if ns.UI then ns.UI.Refresh("sales") end
end

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
	if unit ~= "player" or (issecretvalue and issecretvalue(spellID)) then return end
	local recipe = ns.db.recipes[spellID]
	if recipe then Sales.NoteCraft(recipe) end
end)

---------------------------------------------------------------------------
-- Auction posts
---------------------------------------------------------------------------

local PENDING_POST_SECONDS = 60
local REFUSAL_SECONDS = 10 -- an auction house error this soon after a post is its refusal
-- Oldest first: posts sent quickly can still be waiting for the server when the next one goes.
local pendingPosts = {}

local function OnPost(itemLocation, duration, quantity, price, commodity)
	local post = {
		itemID = C_Item.GetItemID(itemLocation),
		qty = quantity or 1,
		dur = Sales.DurationHours(duration or 2) * 60 * 60,
		at = time(),
		price = type(price) == "number" and price > 0 and price or nil,
		commodity = commodity or nil,
	}
	-- The deposit, for smart restock goals: what a unit that doesn't sell costs.
	local ok, deposit
	if commodity then
		ok, deposit = pcall(C_AuctionHouse.CalculateCommodityDeposit, post.itemID, duration or 2, post.qty)
	else
		ok, deposit = pcall(C_AuctionHouse.CalculateItemDeposit, itemLocation, duration or 2, post.qty)
	end
	if ok and type(deposit) == "number" and deposit >= 0 then post.deposit = deposit / post.qty end
	if post.itemID then ns.Items.Name(post.itemID) end
	table.insert(pendingPosts, post)
end

-- The server refused the latest post, so the next confirmation isn't for it. Whoever sent it: a refused post from
-- Auctionator's Selling tab used to stay waiting, and the next post that went through was recorded as that item.
ns.On("AUCTION_HOUSE_SHOW_ERROR", function()
	local latest = pendingPosts[#pendingPosts]
	if latest and time() - latest.at <= REFUSAL_SECONDS then table.remove(pendingPosts) end
end)

-- A post only counts once the server confirms it, since a post can fail.
ns.On("AUCTION_HOUSE_AUCTION_CREATED", function()
	-- One that never got an answer failed, so it mustn't be mistaken for this one.
	while pendingPosts[1] and time() - pendingPosts[1].at > PENDING_POST_SECONDS do table.remove(pendingPosts, 1) end
	local post = table.remove(pendingPosts, 1)
	if not post or not post.itemID then return end
	post.name = ns.Items.Name(post.itemID)
	post.char = ns.CharKey()
	if post.deposit then
		ns.db.deposits[post.itemID] = post.deposit
		post.dep, post.deposit = post.deposit, nil
	end
	Sales.NoteTrip(post.at)
	if ns.Restock then ns.Restock.ForgetSmart() end
	table.insert(ns.db.sales.lots, post)
	if ns.UI then ns.UI.Refresh("sales") end
	if ns.Posting then ns.Posting.OnPosted(post) end
end)

ns.On("PLAYER_LOGIN", function()
	hooksecurefunc(C_AuctionHouse, "PostItem", function(itemLocation, duration, quantity, bid, buyout)
		OnPost(itemLocation, duration, quantity, buyout or bid, false)
	end)
	hooksecurefunc(C_AuctionHouse, "PostCommodity", function(itemLocation, duration, quantity, unitPrice)
		OnPost(itemLocation, duration, quantity, unitPrice, true)
	end)
end)

-- Turns a client subject format such as "Auction successful: %s" into a pattern that captures the item.
local function SubjectPattern(format)
	local escaped = format:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
	return "^" .. escaped:gsub("%%s", "(.+)") .. "$"
end

---------------------------------------------------------------------------
-- Money on its way
---------------------------------------------------------------------------

-- The game holds a sale's money for an hour before mailing it, and tells the moment it sells, wherever the character
-- is: AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION, from which the game's own UI writes "A buyer has been found for your
-- auction of X" into chat (no CHAT_MSG_SYSTEM: listening for that one never heard a sale). That starts the hour. It
-- names the item only, so the amount comes from the price recorded when it was posted; stackable goods are counted
-- as one unit sold, since it doesn't say how many.
Sales.PAYOUT_DELAY = 60 * 60
local INCOMING_LIFETIME = 30 * DAY
local AUCTION_SOLD = 4 -- Enum.AuctionHouseNotification.AuctionSold, when the client has no Enum for it

-- What one sale of this item pays after the AH cut, and whether that's an estimate.
local function ExpectedPayout(name, char)
	local key = name:lower()
	local fallbackID
	for _, lot in ipairs(ns.db.sales.lots) do
		if lot.char == char and lot.name and lot.name:lower() == key then
			if lot.price then return math.floor(lot.price * (1 - ns.AH_CUT)), lot.commodity and true or false, lot.itemID end
			fallbackID = fallbackID or lot.itemID
		end
	end
	local item = ns.db.sales.items[key]
	local itemID = fallbackID or (item and item.itemID)
	local market = itemID and ns.Prices.AH(itemID)
	if market then return math.floor(market * (1 - ns.AH_CUT)), true, itemID end
	return nil, true, itemID
end

local dueTimerAt
-- Set once chat has said money is waiting; later arrivals stay quiet until the mailbox is opened. A busy hour of
-- sales would otherwise write one line per sale an hour later.
local mailboxTold

-- Says once, in chat, when money has reached a mailbox, and keeps the displays counting down.
local function AnnounceArrivals()
	local now = time()
	local count, total, nextDue, later = 0, 0, nil, 0
	for _, entry in ipairs(ns.db.sales.incoming) do
		if entry.due <= now then
			if not entry.told then
				entry.told = true
				count = count + 1
				total = total + (entry.amount or 0)
			end
		else
			later = later + (entry.amount or 0)
			if not nextDue or entry.due < nextDue then nextDue = entry.due end
		end
	end
	if count > 0 and not mailboxTold then
		mailboxTold = true
		ns.Say("chatSales", ("%s from %s is waiting in the mailbox%s."):format(
			total > 0 and ns.Money(total) or "Money", ns.Plural(count, "sale", "sales"),
			later > 0 and (" (" .. ns.Money(later) .. " more on its way)") or ""))
	end
	if nextDue and dueTimerAt ~= nextDue then
		dueTimerAt = nextDue
		C_Timer.After(nextDue - now + 1, function()
			if dueTimerAt == nextDue then dueTimerAt = nil end
			AnnounceArrivals()
		end)
	end
	if ns.UI then ns.UI.Refresh("sales") end
	if ns.MinimapButton and ns.MinimapButton.Update then ns.MinimapButton.Update() end
end

function Sales.NoteSold(name, when)
	local char = ns.CharKey()
	if not char or not name or name == "" then return end
	local amount, rough, itemID = ExpectedPayout(name, char)
	table.insert(ns.db.sales.incoming, {
		name = name, itemID = itemID, char = char, at = when, due = when + Sales.PAYOUT_DELAY,
		amount = amount, rough = rough or nil,
	})
	local _, total = Sales.Incoming()
	ns.Say("chatSales", ("Sold: %s. %s arrives in the mailbox in an hour%s."):format(name,
		amount and ((rough and "About " or "") .. ns.Money(amount)) or "The money",
		total > (amount or 0) and (" (" .. ns.Money(total) .. " on its way in all)") or ""))
	AnnounceArrivals()
end

-- Every sale whose money hasn't been collected, soonest first, then: copper still on its way, copper waiting in a
-- mailbox, when the next one arrives (nil if none is on its way), and whether any amount is an estimate.
function Sales.Incoming()
	local now = time()
	local list = {}
	local onItsWay, waiting, nextDue, rough = 0, 0, nil, false
	for _, entry in ipairs(ns.db.sales.incoming) do
		table.insert(list, entry)
		if entry.due > now then
			onItsWay = onItsWay + (entry.amount or 0)
			if not nextDue or entry.due < nextDue then nextDue = entry.due end
		else
			waiting = waiting + (entry.amount or 0)
		end
		rough = rough or entry.rough or not entry.amount
	end
	table.sort(list, function(a, b) return a.due < b.due end)
	return list, onItsWay, waiting, nextDue, rough
end

-- "12 min", "1 h 05 min", for a time that's still ahead.
function Sales.WaitText(seconds)
	local minutes = math.max(1, math.ceil(seconds / 60))
	if minutes < 60 then return minutes .. " min" end
	return ("%d h %02d min"):format(math.floor(minutes / 60), minutes % 60)
end

-- Opening the mailbox collects what has arrived for this character.
local function ClearCollected()
	mailboxTold = nil
	local char, now = ns.CharKey(), time()
	local incoming = ns.db.sales.incoming
	for index = #incoming, 1, -1 do
		local entry = incoming[index]
		if (entry.char == char and entry.due <= now) or now - entry.at > INCOMING_LIFETIME then
			table.remove(incoming, index)
		end
	end
	if ns.UI then ns.UI.Refresh("sales") end
	if ns.MinimapButton and ns.MinimapButton.Update then ns.MinimapButton.Update() end
end

ns.On("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", function(notification, text)
	local kinds = Enum and Enum.AuctionHouseNotification
	if notification ~= (kinds and kinds.AuctionSold or AUCTION_SOLD) then return end
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
	local name = text:match("|h%[(.-)%]|h") or text -- a link, should it come as one
	if name ~= "" then Sales.NoteSold(name, time()) end
end)
ns.On("MAIL_SHOW", ClearCollected)
ns.On("PLAYER_LOGIN", function() ns.WhenDataReady(AnnounceArrivals) end)

---------------------------------------------------------------------------
-- Mail
---------------------------------------------------------------------------

local function MailKinds()
	return {
		{ kind = "sold", pattern = SubjectPattern(AUCTION_SOLD_MAIL_SUBJECT or "Auction successful: %s") },
		{ kind = "expired", pattern = SubjectPattern(AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s") },
		{ kind = "cancelled", pattern = SubjectPattern(AUCTION_REMOVED_MAIL_SUBJECT or "Auction cancelled: %s") },
	}
end

-- Kind, item name and count from a subject; the count is nil when the subject doesn't state one.
local function ParseSubject(subject, kinds)
	for _, entry in ipairs(kinds) do
		local text = subject:match(entry.pattern)
		if text then
			local name, count = text:match("^(.*) %((%d+)%)$")
			if name then return entry.kind, name, tonumber(count) end
			return entry.kind, text, nil
		end
	end
	return nil
end

local function ItemIDFromName(name)
	local fn = C_Item.GetItemInfoInstant
	if not fn then return nil end
	local ok, itemID = pcall(fn, name)
	return ok and itemID or nil
end

-- settled: the inbox has come in from the server (MAIL_INBOX_UPDATE). Right as the mailbox opens it may still be the
-- last visit's.
function Sales.ScanMail(settled)
	local char = ns.CharKey()
	if not char then return end
	local seenByChar = ns.db.sales.seen
	seenByChar[char] = seenByChar[char] or {}
	local seen = seenByChar[char]
	local now = time()
	local kinds = MailKinds()
	local matched = {}
	local outcomes = {}

	for index = 1, GetInboxNumItems() do
		local _, _, _, subject, money, _, daysLeft = GetInboxHeaderInfo(index)
		local kind, name, count
		if subject and daysLeft then kind, name, count = ParseSubject(subject, kinds) end
		-- A sale's mail with no money in it has had its gold taken and is about to go. It was counted when it still
		-- held the gold; as its money is part of what tells mails apart, it used to count again as a second sale for
		-- nothing, which doubled the units sold and their cost.
		if kind == "sold" and (money or 0) <= 0 then kind = nil end
		if kind then
			local itemID
			if kind ~= "sold" then
				local _, attachedID, _, attachedCount = GetInboxItem(index, 1)
				itemID = attachedID
				count = attachedCount or count
			elseif not count and GetInboxInvoiceInfo then
				-- Not every sale states its quantity in the subject; the invoice's 11th value is the count.
				count = select(11, GetInboxInvoiceInfo(index))
			end
			count = count or 1

			-- Not the count: a sale's only arrives once its invoice has loaded, so the same mail could count twice.
			local key = table.concat({ kind, name, money or 0 }, "|")
			local expires = now + daysLeft * DAY
			local known = false
			for seenIndex, record in ipairs(seen) do
				-- Each record answers for one mail, so identical sales still count separately.
				if not matched[seenIndex] and record.key == key and math.abs(record.expires - expires) < SAME_MAIL_TOLERANCE then
					matched[seenIndex] = true
					known = true
					break
				end
			end
			if not known then
				table.insert(seen, { key = key, expires = expires })
				matched[#seen] = true
				table.insert(outcomes, {
					kind = kind, name = name, count = count, money = money, itemID = itemID or ItemIDFromName(name),
					when = math.min(now, expires - MAIL_LIFETIME_DAYS * DAY),
				})
			end
		end
	end

	-- Oldest first, so the oldest posts are matched to the oldest results.
	table.sort(outcomes, function(a, b) return a.when < b.when end)
	for _, outcome in ipairs(outcomes) do
		Sales.Record(outcome.kind, outcome.name, outcome.count, outcome.money, outcome.when, char, outcome.itemID)
	end

	for index = #seen, 1, -1 do
		if seen[index].expires < now then table.remove(seen, index) end
	end
	local lots = ns.db.sales.lots
	local shown, total = GetInboxNumItems()
	local wholeInbox = settled and (total or shown) <= shown
	-- For checking from the saved data why posts were or weren't cleared.
	ns.db.sales.inboxSeen = { at = now, shown = shown, total = total, settled = settled and true or false }
	if settled then ns.db.sales.inboxSettled = ns.db.sales.inboxSeen end
	for index = #lots, 1, -1 do
		local lot = lots[index]
		if now - lot.at > OPEN_LOT_LIMIT
			or (wholeInbox and lot.char == char and now - lot.at - lot.dur > LOT_RESULT_HOURS * 3600) then
			table.remove(lots, index)
		end
	end

	if #outcomes > 0 then
		ns.InvalidateProfit()
		ns.UI.Refresh("sales")
	end
end

ns.On("MAIL_INBOX_UPDATE", function() Sales.ScanMail(true) end)

---------------------------------------------------------------------------
-- Repair: sales counted twice
---------------------------------------------------------------------------
-- Up to 1.10.1 a sale's mail was counted a second time, for no money, when its gold was taken while the mailbox
-- was open (see Sales.ScanMail). The mails seen are still on record, so the extra units can be taken back out: off
-- the units sold, off their cost (units with no cost on record first, as the second count came after the real one)
-- and back into the pool they were taken from. Runs once.

local function RemoveSold(item, day, count)
	count = math.min(count, day.s)
	if count <= 0 then return 0 end
	local unknown = math.min(count, day.u or 0)
	local rest, covered = count - unknown, day.s - (day.u or 0)
	if rest > 0 and covered > 0 and (day.c or 0) > 0 then
		local back = day.c * math.min(1, rest / covered)
		day.c = day.c - back
		local costID = item.itemID or Sales.CraftedID(item)
		if costID then Sales.AddCost(costID, rest, back) end
	end
	if day.u then day.u = day.u - unknown end
	day.s = day.s - count
	item.sold = math.max(0, item.sold - count)
	return count
end

function Sales.RepairEmptiedMail()
	local sales = ns.db.sales
	if sales.emptiedMailFixed then return end
	sales.emptiedMailFixed = true
	local from = sales.profitFrom or 0
	-- Per item and calendar day: real sale mails, and the second counts by whether they came since profit began.
	local groups = {}
	for _, seen in pairs(sales.seen) do
		for index = #seen, 1, -1 do
			local kind, name, money = seen[index].key:match("^(%a+)|(.*)|(%d+)$")
			if kind == "sold" then
				local when = seen[index].expires - MAIL_LIFETIME_DAYS * DAY
				local id = name:lower() .. "|" .. DayNumber(when)
				local group = groups[id]
				if not group then
					group = { key = name:lower(), day = DayNumber(when), real = 0, late = 0, early = 0 }
					groups[id] = group
				end
				if tonumber(money) > 0 then
					group.real = group.real + 1
				else
					if when >= from then group.late = group.late + 1 else group.early = group.early + 1 end
					table.remove(seen, index)
				end
			end
		end
	end
	local changed = false
	for _, group in pairs(groups) do
		local item = sales.items[group.key]
		local extra = group.late + group.early
		if item and extra > 0 then
			-- Results from before a profit reset sit half a key earlier.
			local now, before = item.days[group.day], item.days[group.day - 0.5]
			local sold = (now and now.s or 0) + (before and before.s or 0)
			local each = math.max(1, math.floor(sold / (group.real + extra) + 0.5))
			local lateLeft, earlyLeft = group.late * each, group.early * each
			if now then lateLeft = lateLeft - RemoveSold(item, now, lateLeft) end
			if before then earlyLeft = earlyLeft - RemoveSold(item, before, earlyLeft) end
			-- Whatever the expected day didn't hold comes off the other one.
			local left = lateLeft + earlyLeft
			if before and left > 0 then left = left - RemoveSold(item, before, left) end
			if now and left > 0 then RemoveSold(item, now, left) end
			changed = true
		end
	end
	if changed then
		ns.Say("chatWarnings", "Sales profit was counted wrong until now: taking the gold from a sale's mail counted the sale twice. Sorry for the confusion. Your records are corrected; for a clean start, press Reset profit in the Sales tab.")
		Sales.ForgetCraftInfo()
		ns.InvalidateProfit()
		if ns.UI then ns.UI.Refresh("sales") end
	end
end

ns.On("PLAYER_LOGIN", function() ns.WhenDataReady(Sales.RepairEmptiedMail) end)
-- The inbox comes in a moment after the mailbox opens, with MAIL_INBOX_UPDATE; an empty one may never send that. So
-- the mailbox is looked at again shortly after it opens, as having come in.
local INBOX_SETTLE_SECONDS = 2
local mailOpen = 0 -- which opening of the mailbox, while open; 0 while closed
local mailOpenings = 0
ns.On("MAIL_SHOW", function()
	Sales.ScanMail(false)
	mailOpenings = mailOpenings + 1
	mailOpen = mailOpenings
	local this = mailOpen
	C_Timer.After(INBOX_SETTLE_SECONDS, function()
		if mailOpen == this then Sales.ScanMail(true) end
	end)
end)
ns.On("MAIL_CLOSED", function() mailOpen = 0 end)
