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
--                                               x = true for results from before profit was counted } } }
-- db.sales.profitFrom            = when profit began to be counted
-- db.costs[itemID]               = { q = units held with a cost on record, c = copper paid for them }
-- db.sales.lots[i]               = { itemID, name, qty, at = posted time, dur = seconds, char,
--                                    price = copper per unit, commodity = true for stackable goods }
-- db.sales.incoming[i]           = { name, itemID, char, at = sold time, due = when the money arrives,
--                                    amount = copper after the AH cut (nil if unknown), rough = true when estimated,
--                                    told = true once its arrival has been announced }
-- db.sales.seen[char][i]         = { key, expires }

local _, ns = ...

local Sales = {}
ns.Sales = Sales

local DAY = 24 * 60 * 60
local MAIL_LIFETIME_DAYS = 30
local SAME_MAIL_TOLERANCE = 600 -- seconds; a mail's expiry time can differ slightly between scans
local OPEN_LOT_LIMIT = 45 * DAY

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

-- A number for the local calendar day. Noon keeps it stable across daylight saving changes.
local function DayNumber(when)
	local d = date("*t", when)
	return math.floor(time({ year = d.year, month = d.month, day = d.day, hour = 12 }) / DAY)
end

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
-- had no post to match.
local function ConsumeLots(key, count, when, char)
	local lots = ns.db.sales.lots
	local exposure = 0
	local index = 1
	while count > 0 and index <= #lots do
		local lot = lots[index]
		if lot.char == char and lot.name and lot.name:lower() == key and lot.at <= when then
			local take = math.min(lot.qty, count)
			exposure = exposure + take * math.min(when - lot.at, lot.dur) / DAY
			lot.qty = lot.qty - take
			count = count - take
			if lot.qty <= 0 then
				table.remove(lots, index)
				index = index - 1
			end
		end
		index = index + 1
	end
	return exposure, count
end

-- kind is "sold", "expired" or "cancelled". Cancelled auctions count as time on the AH with no result either way.
function Sales.Record(kind, name, count, money, when, char, itemID)
	local item = ItemRecord(name, itemID)
	Sales.ForgetCraftInfo()
	local exposure, unmatched = ConsumeLots(name:lower(), count, when, char)
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
	else
		item.expired = item.expired + count
		day.e = day.e + count
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
		local day = item.days[dayNumber]
		if day then
			sold, expired, gold = sold + day.s, expired + day.e, gold + day.g
		end
	end
	return sold, expired, gold
end

-- The same, but only results from since profit is counted, then the known cost of the sold units and how many of
-- them have no cost on record.
local function Tracked(item, days)
	local first = days and DayNumber(time()) - days + 1
	local sold, expired, gold, cost, unknown = 0, 0, 0, 0, 0
	for dayNumber, day in pairs(item.days) do
		if not day.x and (not first or dayNumber >= first) then
			sold, expired, gold = sold + day.s, expired + day.e, gold + day.g
			cost, unknown = cost + (day.c or 0), unknown + (day.u or 0)
		end
	end
	return sold, expired, gold, cost, unknown
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
		craftInfo = { at = now, ctx = ctx, names = names }
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

-- Sales whose money is still on its way or waiting in a mailbox: the mail hasn't been read, so they aren't in the
-- records yet. Returns units, copper expected, what they cost and whether any amount is an estimate, for one item
-- (by lowercase name) over the last N days. Units with no cost on record cost nothing, as in Sales.Profit.
local function Pending(key, days)
	local first = days and DayNumber(time()) - days + 1
	local count, gold, cost, rough = 0, 0, 0, false
	for _, entry in ipairs(ns.db.sales.incoming) do
		if entry.amount and entry.name and entry.name:lower() == key and (not first or DayNumber(entry.at) >= first) then
			count = count + 1
			gold = gold + entry.amount
			rough = rough or entry.rough or false
			local itemID = entry.itemID or CraftInfo().names[key]
			local pool = itemID and ns.db.costs[itemID]
			if pool and pool.q >= 1 then
				cost = cost + pool.c / pool.q
			end
		end
	end
	return count, gold, cost, rough
end

-- Profit over the last N days (nil for all time): the money received, after the AH cut, less what the sold units
-- cost you. Then whether part of it is an estimate, and sold, expired and copper received. Only results from since
-- profit is counted. It follows your gold: units with no cost on record (made before then, or from gathered
-- materials) cost nothing, since that money was spent before profit was counted, or never.
function Sales.Profit(item, days)
	local sold, expired, gold, cost = Tracked(item, days)
	-- Sold, but the money is still on its way.
	local pendingCount, pendingGold, pendingCost, pendingRough = Pending(item.name:lower(), days)
	return gold + pendingGold - cost - pendingCost, pendingRough, sold + pendingCount, expired, gold + pendingGold
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
-- A running record of what you paid for the items you hold, so a sale's profit is counted from real spending:
-- auction house purchases at the price paid, crafts at what their materials cost, materials you gathered at
-- nothing. Each item is one pool with an average cost, shared by all characters, since mail moves things between
-- them. What you already held when this record began costs nothing: it was paid for before profit was counted, so
-- profit follows your gold. (1.7.0 valued it at market prices, so selling things made from old or gathered stock
-- showed a loss while gold went up.)

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
-- on record were gathered, so they're free, unless a vendor sells them: then they were bought there.
function Sales.NoteCraft(recipe)
	if not recipe.o then return end
	local total = 0
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
			local vendor = ns.Prices.Vendor(itemID)
			if covered < count and vendor and vendor > 0 then cost = cost + (count - covered) * vendor end
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
	if post.itemID then ns.Items.Name(post.itemID) end
	table.insert(pendingPosts, post)
end

-- The server refused the latest post, so the next confirmation isn't for it.
function Sales.ForgetLastPost()
	table.remove(pendingPosts)
end

-- A post only counts once the server confirms it, since a post can fail.
ns.On("AUCTION_HOUSE_AUCTION_CREATED", function()
	-- One that never got an answer failed, so it mustn't be mistaken for this one.
	while pendingPosts[1] and time() - pendingPosts[1].at > PENDING_POST_SECONDS do table.remove(pendingPosts, 1) end
	local post = table.remove(pendingPosts, 1)
	if not post or not post.itemID then return end
	post.name = ns.Items.Name(post.itemID)
	post.char = ns.CharKey()
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

-- The game holds a sale's money for an hour before mailing it, and says "A buyer has been found for your auction of
-- X" in chat the moment it sells, wherever the character is. That message starts the hour. It names the item only,
-- so the amount comes from the price recorded when it was posted; stackable goods are counted as one unit sold,
-- since the message doesn't say how many.
Sales.PAYOUT_DELAY = 60 * 60
local INCOMING_LIFETIME = 30 * DAY

local function SoldPattern()
	return SubjectPattern(_G.ERR_AUCTION_SOLD_S or "A buyer has been found for your auction of %s.")
end

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

-- Says once, in chat, when money has reached a mailbox, and keeps the displays counting down.
local function AnnounceArrivals()
	local now = time()
	local count, total, nextDue = 0, 0, nil
	for _, entry in ipairs(ns.db.sales.incoming) do
		if entry.due <= now then
			if not entry.told then
				entry.told = true
				count = count + 1
				total = total + (entry.amount or 0)
			end
		elseif not nextDue or entry.due < nextDue then
			nextDue = entry.due
		end
	end
	if count > 0 then
		ns.Print(("%s from %s is waiting in the mailbox."):format(total > 0 and ns.Money(total) or "Money",
			ns.Plural(count, "sale", "sales")))
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
	ns.Print(("Sold: %s. %s arrives in the mailbox in an hour%s."):format(name,
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

ns.On("CHAT_MSG_SYSTEM", function(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return end
	local name = text:match(SoldPattern())
	if name then Sales.NoteSold(name, time()) end
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

function Sales.ScanMail()
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
	for index = #lots, 1, -1 do
		if now - lots[index].at > OPEN_LOT_LIMIT then table.remove(lots, index) end
	end

	if #outcomes > 0 then
		ns.InvalidateProfit()
		ns.UI.Refresh("sales")
	end
end

ns.On("MAIL_INBOX_UPDATE", Sales.ScanMail)
ns.On("MAIL_SHOW", Sales.ScanMail)
