-- CraftLedger :: Sales
-- Records what sells and what expires, and estimates the chance a listed item sells within 24 hours.
--
-- Outcomes come from the auction house mail, the only source that also covers sales made while offline. Mail that
-- is still in the box gets scanned again every visit, so each one is remembered until it can no longer be there.
-- Time on the AH comes from recording each post. A sale or expiry is matched to the oldest post of that item.
--
-- db.sales.items[lowercase name] = { name, itemID, sold, expired, gold, exposure = unit-days listed,
--                                    days = { [day number] = { s = sold, e = expired, g = copper } } }
-- db.sales.lots[i]               = { itemID, name, qty, at = posted time, dur = seconds, char }
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
		day = { s = 0, e = 0, g = 0 }
		item.days[dayNumber] = day
	end
	if kind == "sold" then
		item.sold = item.sold + count
		item.gold = item.gold + (money or 0)
		day.s = day.s + count
		day.g = day.g + (money or 0)
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

function Sales.Item(name)
	return name and ns.db.sales.items[name:lower()] or nil
end

function Sales.Totals(days)
	local sold, expired, gold = 0, 0, 0
	for _, item in pairs(ns.db.sales.items) do
		local s, e, g = Sales.Counts(item, days)
		sold, expired, gold = sold + s, expired + e, gold + g
	end
	return sold, expired, gold
end

-- Every item with results, best sellers over the last 30 days first.
function Sales.AllItems()
	local list, recent = {}, {}
	for _, item in pairs(ns.db.sales.items) do
		if item.sold + item.expired > 0 then
			table.insert(list, item)
			recent[item] = Sales.Counts(item, 30)
		end
	end
	table.sort(list, function(a, b)
		if recent[a] ~= recent[b] then return recent[a] > recent[b] end
		return a.name < b.name
	end)
	return list
end

---------------------------------------------------------------------------
-- Auction posts
---------------------------------------------------------------------------

local PENDING_POST_SECONDS = 60
-- Oldest first: posts sent quickly can still be waiting for the server when the next one goes.
local pendingPosts = {}

local function OnPost(itemLocation, duration, quantity)
	local post = {
		itemID = C_Item.GetItemID(itemLocation),
		qty = quantity or 1,
		dur = Sales.DurationHours(duration or 2) * 60 * 60,
		at = time(),
	}
	if post.itemID then ns.Items.Name(post.itemID) end
	table.insert(pendingPosts, post)
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
	hooksecurefunc(C_AuctionHouse, "PostItem", OnPost)
	hooksecurefunc(C_AuctionHouse, "PostCommodity", OnPost)
end)

---------------------------------------------------------------------------
-- Mail
---------------------------------------------------------------------------

-- Turns a client subject format such as "Auction successful: %s" into a pattern that captures the item.
local function SubjectPattern(format)
	local escaped = format:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
	return "^" .. escaped:gsub("%%s", "(.+)") .. "$"
end

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
