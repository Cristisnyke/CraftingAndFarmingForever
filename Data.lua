-- Crafting and Farming Forever :: Data
-- Everything read from the client and other add-ons: item data, prices, stock and learned recipes.

local ADDON, ns = ...

---------------------------------------------------------------------------
-- Item data
---------------------------------------------------------------------------
-- Item data loads asynchronously. Nothing shows or uses a name until the client has it; the views refresh when
-- it arrives, so an item is never displayed as a placeholder or sent to Auctionator without a name.

local Items = {}
ns.Items = Items
local requested = {}
local failed = {}

-- Asks again after a few seconds in case an answer never came, the next time the item is looked at.
local function Request(itemID)
	if failed[itemID] then return end
	local now = GetTime()
	if requested[itemID] and now - requested[itemID] < 5 then return end
	requested[itemID] = now
	C_Item.RequestLoadItemDataByID(itemID)
end

-- Forgets pending and failed requests, so every item still missing gets asked for again.
function Items.Retry()
	wipe(requested)
	wipe(failed)
end

-- True when the client answered that the item does not exist, so its name will never arrive.
function Items.IsMissing(itemID)
	return failed[itemID] == true
end

function Items.Name(itemID)
	local name = C_Item.GetItemNameByID(itemID)
	if name and name ~= "" then return name end
	Request(itemID)
	return nil
end

function Items.Icon(itemID)
	return C_Item.GetItemIconByID(itemID) or 134400 -- question mark icon only if the client has no icon at all
end

-- Returns true/false, or nil while the item data is loading.
function Items.CanSellOnAH(itemID)
	local name, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(itemID)
	if not name then
		Request(itemID)
		return nil
	end
	-- 1 = bind on pickup, 4 = quest item.
	return bindType ~= 1 and bindType ~= 4
end

-- Returns true/false, or nil while the item data is loading.
function Items.IsStackable(itemID)
	local name, _, _, _, _, _, _, stackCount = C_Item.GetItemInfo(itemID)
	if not name then
		Request(itemID)
		return nil
	end
	return (stackCount or 1) > 1
end

-- How many fit in one bag slot, or nil while the item data is loading.
function Items.StackSize(itemID)
	local name, _, _, _, _, _, _, stackCount = C_Item.GetItemInfo(itemID)
	if not name then
		Request(itemID)
		return nil
	end
	return stackCount or 1
end

-- True when the reagent bag takes it (a crafting reagent).
function Items.IsReagent(itemID)
	return select(17, C_Item.GetItemInfo(itemID)) == true
end

-- Daggers are bought two at a time: a rogue wants one for each hand. Not those for one hand only.
local DAGGER_CLASS, DAGGER_SUBCLASS = 2, 15
function Items.SoldInPairs(itemID)
	if not C_Item.GetItemInfoInstant then return false end
	local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	return classID == DAGGER_CLASS and subclassID == DAGGER_SUBCLASS and equipLoc == "INVTYPE_WEAPON"
end

-- What a vendor pays for one, or nil while the item data is loading.
function Items.SellPrice(itemID)
	return (select(11, C_Item.GetItemInfo(itemID)))
end

function Items.Quality(itemID)
	local _, _, quality = C_Item.GetItemInfo(itemID)
	return quality
end

ns.On("GET_ITEM_INFO_RECEIVED", function(itemID, success)
	if not itemID or not requested[itemID] then return end
	requested[itemID] = nil
	if success == false or success == nil then failed[itemID] = true end
	ns.Debounce("itemdata", 0.3, function()
		ns.InvalidateProfit()
		ns.RequestPlan()
		-- Panes the plan doesn't redraw also show names, and would keep "Loading..." until something else changed.
		ns.UI.Refresh("sales")
		ns.UI.Refresh("writs")
		ns.UI.Refresh("crates")
		ns.UI.Refresh("posting")
	end)
end)

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------

local Prices = {}
ns.Prices = Prices

-- Well-known unlimited vendor reagents, so they count as vendor items before the first merchant visit. Learned
-- merchant prices from Auctionator take priority. Values are what Forever's merchants charged the author in game.
local VENDOR_SEED = {
	[2320] = 10, [2321] = 100, [4291] = 500, [8343] = 2000, [14341] = 5000,
	[2324] = 25, [2604] = 50, [6260] = 50, [2605] = 100, [4340] = 350, [6261] = 1000, [4341] = 500, [4342] = 2500,
	[2880] = 100, [3466] = 2000, [3857] = 500,
	[3371] = 4, [3372] = 40,
	[6217] = 124,
	[2678] = 2, [2692] = 40, [3713] = 160, [159] = 5, [1179] = 25,
	[4289] = 50, [4470] = 38,
}

-- Usual prices: the lowest price seen each day goes in db.priceDays. A price that changed was seen today; one read
-- unchanged is placed on the day Auctionator last saw it (asked once per item per scan, as reads are frequent).
local priceDay = { at = 0 }
local placed = {}

local function Today()
	local now = time()
	if now ~= priceDay.at then priceDay.at, priceDay.day = now, ns.DayNumber(now) end
	return priceDay.day
end

local function NoteDay(itemID, day, price)
	local days = ns.db.priceDays[itemID]
	if not days then
		days = {}
		ns.db.priceDays[itemID] = days
	end
	if not days[day] or price < days[day] then days[day] = price end
end

local function RecordDay(itemID, price, changed)
	local today = Today()
	if changed then
		placed[itemID] = today
		NoteDay(itemID, today, price)
	elseif placed[itemID] ~= today then
		placed[itemID] = today
		local age = Auctionator.API.v1.GetAuctionAgeByItemID(ADDON, itemID)
		if age and age >= 0 and age < ns.Planner.NORMAL.DAYS then NoteDay(itemID, today - age, price) end
	end
end

-- The item's usual price (median of its daily lows), nil until enough days are seen or with the option off.
function Prices.Normal(itemID)
	if not ns.Option("normalPrice") then return nil end
	return ns.Planner.NormalPrice(ns.db.priceDays[itemID], Today())
end

-- The current price as a share of the usual one (1.5 = 150%), nil when either is unknown.
function Prices.OfNormal(itemID)
	local normal = Prices.Normal(itemID)
	local price = normal and Auctionator.API.v1.GetAuctionPriceByItemID(ADDON, itemID)
	return price and normal > 0 and price / normal or nil
end

-- Auctionator's price, noting any change since we last looked. Everything that costs or sells goes through here, so
-- this sees every item that matters, whichever scan updated it.
function Prices.AH(itemID)
	local price = Auctionator.API.v1.GetAuctionPriceByItemID(ADDON, itemID)
	if not price then return nil end
	local record = ns.db.prices[itemID]
	RecordDay(itemID, price, record and record.cur ~= price)
	if not record then
		ns.db.prices[itemID] = { cur = price }
	elseif record.cur ~= price then
		-- Within one scan the old price stays the one from before that scan.
		if record.round ~= ns.db.priceRound then
			record.old = record.cur
			record.round = ns.db.priceRound
		end
		record.cur = price
	end
	return price
end

-- The price before the latest scan, and now. Nil when the latest scan didn't change it.
function Prices.Change(itemID)
	local record = ns.db.prices[itemID]
	if not record or record.round ~= ns.db.priceRound or not record.old or record.old == record.cur then return nil end
	return record.old, record.cur
end

-- Starts a new comparison: colours from the previous scan clear, and this scan's changes get coloured.
function Prices.NewRound()
	ns.db.priceRound = ns.db.priceRound + 1
	-- A new scan may see unchanged prices again today.
	wipe(placed)
	if ns.UI then ns.UI.RefreshAll() end
end

function Prices.Vendor(itemID)
	return Auctionator.API.v1.GetVendorPriceByItemID(ADDON, itemID) or VENDOR_SEED[itemID]
end

-- Days since the item was last seen on the AH, nil if unknown.
function Prices.ItemAgeDays(itemID)
	return Auctionator.API.v1.GetAuctionAgeByItemID(ADDON, itemID)
end

-- Seconds since the last Auctionator scan of any kind, nil if it never scanned.
function Prices.ScanAge()
	local state = Auctionator.SavedState
	if not state then return nil end
	local latest = math.max(state.TimeOfLastReplicateScan or 0, state.TimeOfLastBrowseScan or 0)
	if latest == 0 then return nil end
	return time() - latest
end

function Prices.IsStale()
	local age = Prices.ScanAge()
	return age == nil or age > ns.STALE_SECONDS
end

-- Starts whichever scan type Auctionator is set to use, as its own Scan button does. Needs the AH open.
function Prices.StartScan()
	local state = Auctionator.State
	if not (AuctionHouseFrame and AuctionHouseFrame:IsShown() and state) then
		ns.Say("chatWarnings", "Open the auction house to scan.")
		return
	end
	local frame
	if Auctionator.Config.Get(Auctionator.Config.Options.REPLICATE_SCAN) then
		frame = state.FullScanFrameRef
	else
		frame = state.IncrementalScanFrameRef
	end
	if frame then frame:InitiateScan() else ns.Say("chatWarnings", "Auctionator's scanner is not ready yet. Try again in a moment.") end
end

-- A scan of our whole list, or a full scan, starts a comparison. Searching one item, as happens while buying, doesn't,
-- or the colours would vanish just as they're needed.
local function WatchScans()
	local bus = Auctionator.EventBus
	local shoppingStart = Auctionator.Shopping.Tab.Events.SearchStart
	local shoppingEnd = Auctionator.Shopping.Tab.Events.SearchEnd
	-- Every price scan and search of our list also starts a plan check (ns.PlanCheck), ended when it finishes.
	local ends, ourSearch = {}, false
	local listener = {
		ReceiveEvent = function(_, eventName, terms)
			if ends[eventName] or (eventName == shoppingEnd and ourSearch) then
				ourSearch = false
				ns.PlanCheck.End()
			elseif eventName == shoppingEnd then
				return
			elseif eventName ~= shoppingStart then
				Prices.NewRound()
				ns.PlanCheck.Begin()
			elseif type(terms) == "table" and #terms > 0 then
				ourSearch = false
				local manager = Auctionator.Shopping.ListManager
				if not manager:GetIndexForName(ns.LIST_NAME) then return end
				local items = manager:GetByName(ns.LIST_NAME):GetAllItems()
				if #items ~= #terms then return end
				-- A one-item list's scan looks like a single search, so it must be our list's own item.
				if #terms == 1 and terms[1] ~= items[1] then return end
				Prices.NewRound()
				ourSearch = true
				ns.PlanCheck.Begin()
			end
		end,
	}
	local events = { shoppingStart }
	if shoppingEnd then table.insert(events, shoppingEnd) end
	for _, scan in ipairs({ Auctionator.FullScan, Auctionator.IncrementalScan }) do
		if scan and scan.Events then
			table.insert(events, scan.Events.ScanStart)
			for _, name in ipairs({ "ScanComplete", "ScanFailed" }) do
				if scan.Events[name] then
					ends[scan.Events[name]] = true
					table.insert(events, scan.Events[name])
				end
			end
		end
	end
	bus:Register(listener, events)
end

ns.On("PLAYER_LOGIN", WatchScans)

---------------------------------------------------------------------------
-- Stock
---------------------------------------------------------------------------

local Stock = {}
ns.Stock = Stock

-- Bags, bank and reagent bank of the logged-in character.
function Stock.Own(itemID)
	return C_Item.GetItemCount(itemID, true, false, true, false) or 0
end

-- The part of Stock.Own that's in the bank or reagent bank rather than the bags.
function Stock.Bank(itemID)
	local bagsOnly = C_Item.GetItemCount(itemID, false, false, false, false) or 0
	return math.max(0, Stock.Own(itemID) - bagsOnly)
end

local function SyndicatorAPI()
	local api = _G.Syndicator and _G.Syndicator.API
	if type(api) ~= "table" or type(api.GetInventoryInfoByItemID) ~= "function"
		or type(api.GetCurrentCharacter) ~= "function" or type(api.IsReady) ~= "function" then
		return nil
	end
	local ok, ready = pcall(api.IsReady)
	if not (ok and ready) then return nil end
	-- Syndicator's own name for the character you're playing, kept on its record: the realm part can't be worked out
	-- reliably from the realm's name on Forever, so a left-out character is matched by this where it's known.
	-- Asked once a session: this runs on every stock lookup.
	local record = not Stock.syndicatorNamed and ns.CharKey() and ns.db.chars[ns.CharKey()]
	if record then
		local named, name = pcall(api.GetCurrentCharacter)
		if named and type(name) == "string" then
			record.syndicatorKey = name
			Stock.syndicatorNamed = true
		end
	end
	return api
end

function Stock.HasSyndicator()
	return SyndicatorAPI() ~= nil
end

-- How Syndicator names a character in its results, the same form as GetCurrentCharacter.
local function SyndicatorKey(char)
	local realm = char.realmNormalized
	return realm and realm ~= "" and (char.character .. "-" .. realm) or char.character
end

-- Syndicator's names of the characters left out on the Options tab, as a set. Never the one you're playing.
local function LeftOut(me)
	local keys = {}
	for key in pairs(ns.db.ui.excludedChars or {}) do
		local char = ns.db.chars[key]
		if not char then
			keys[key] = true
		elseif char.syndicatorKey and ns.CharExcluded(key) then
			keys[char.syndicatorKey] = true
		end
	end
	if me then keys[me] = nil end
	return keys
end

-- Syndicator's characters: { { full = "Name-Realm", name, realm, classFile = "SHAMAN" or nil }, ... }. On Forever
-- the name has a surname ("Melody Stormveil"); ns.PlayerName reads it for the character you're playing.
local function SyndicatorCharacters(api)
	local ok, names = false, nil
	if type(api.GetAllCharacters) == "function" then ok, names = pcall(api.GetAllCharacters) end
	local list = {}
	if not (ok and type(names) == "table") then return list end
	for _, full in ipairs(names) do
		if type(full) == "string" then
			local details
			if type(api.GetByCharacterFullName) == "function" then
				local found, data = pcall(api.GetByCharacterFullName, full)
				details = found and type(data) == "table" and type(data.details) == "table" and data.details or nil
			end
			local name, realm = full:match("^(.*)%-(.-)$")
			table.insert(list, { full = full, name = details and details.character or name or full,
				realm = details and details.realm or realm, classFile = details and details.className })
		end
	end
	return list
end

-- Which of Syndicator's characters a record here is: the name Syndicator gave it while you played it, else the only
-- one whose full name (or, for records saved before surnames were read, first name) and class match. Nil when that's
-- none or more than one.
local function SyndicatorMatch(char, characters)
	if char.syndicatorKey then return char.syndicatorKey end
	if not char.name then return nil end
	local class = char.classFile or (char.class and char.class:upper():gsub("%s", ""))
	local match
	for _, other in ipairs(characters) do
		local first = other.name:match("^(%S+)")
		if (other.name == char.name or first == char.name)
			and (not class or not other.classFile or other.classFile == class) then
			if match then return nil end
			match = other.full
		end
	end
	return match
end

-- A character's full name ("Snic Pal" on WoW Forever, where the first name is the account's). Records saved before
-- surnames were read hold only the first name until that character logs in again: their full name comes from
-- Syndicator (its name for the character while it was played, else the one character of that first name and class).
-- Nil for an unknown key. What Syndicator says is kept for the session.
local fullNames = {}
local function WithoutRealm(syndicatorKey)
	return syndicatorKey:match("^(.*)%-[^%-]*$") or syndicatorKey
end

function Stock.CharName(key)
	local char = key and ns.db.chars[key]
	if not char then return nil end
	if char.name and char.name:find(" ", 1, true) then return char.name end
	if char.syndicatorKey then return WithoutRealm(char.syndicatorKey) end
	if fullNames[key] ~= nil then return fullNames[key] or char.name end
	local api = SyndicatorAPI()
	if not api then return char.name end -- asked again once Syndicator is ready
	local match = SyndicatorMatch(char, SyndicatorCharacters(api))
	fullNames[key] = match and WithoutRealm(match) or false -- no match is remembered too: lists ask this a lot
	return fullNames[key] or char.name
end
ns.CharName = Stock.CharName

-- Every character the Options tab can leave out, one row each: Syndicator's characters, with the records here that are
-- the same character, then records Syndicator doesn't know that have recipes. Old records of a character with nothing
-- in them aren't listed. { { key, label, guids = { record keys }, me = true for the one you're playing }, ... }
function Stock.Characters()
	local myKey = ns.CharKey()
	local api = SyndicatorAPI() -- first, so the character you're playing has its Syndicator name
	local characters = api and SyndicatorCharacters(api) or {}
	local list, byFull, names = {}, {}, {}
	for _, other in ipairs(characters) do
		local entry = { key = other.full, label = other.name, realm = other.realm, guids = {} }
		byFull[other.full] = entry
		names[other.name] = (names[other.name] or 0) + 1
		table.insert(list, entry)
	end
	-- The same name on two realms: the realm tells them apart.
	for _, entry in ipairs(list) do
		if names[entry.label] > 1 and entry.realm then entry.label = entry.label .. " (" .. entry.realm .. ")" end
	end
	for key, char in pairs(ns.db.chars) do
		local full = SyndicatorMatch(char, characters)
		local entry = full and byFull[full]
		if entry then
			table.insert(entry.guids, key)
			if key == myKey then entry.me = true end
		elseif key == myKey or next(char.recipes or {}) then
			table.insert(list, { key = key, label = ns.CharLabel(key), guids = { key }, me = key == myKey or nil })
		end
	end
	table.sort(list, function(a, b) return a.label < b.label end)
	return list
end

-- Whether a row of Stock.Characters is ticked, and ticking it: its Syndicator name and every record of it here.
function Stock.IsLeftOut(entry)
	local excluded = ns.db.ui.excludedChars
	if not excluded then return false end
	if excluded[entry.key] then return true end
	for _, key in ipairs(entry.guids or {}) do
		if excluded[key] then return true end
	end
	return false
end

function Stock.SetLeftOut(entry, on)
	local excluded = ns.db.ui.excludedChars or {}
	excluded[entry.key] = on or nil
	for _, key in ipairs(entry.guids or {}) do excluded[key] = on or nil end
	ns.db.ui.excludedChars = next(excluded) and excluded or nil
end

-- Bags and bank of other characters on the connected realm and same faction, since those can mail to this one.
function Stock.Alts(itemID)
	local api = SyndicatorAPI()
	if not api then return {} end
	local ok, info = pcall(api.GetInventoryInfoByItemID, itemID, true, true)
	if not ok or type(info) ~= "table" then return {} end
	local me = api.GetCurrentCharacter()
	local leftOut = LeftOut(me)
	local result = {}
	for _, char in ipairs(info.characters or {}) do
		local key = SyndicatorKey(char)
		local count = (char.bags or 0) + (char.bank or 0)
		-- Bank alt mode: the bank alt's things are for selling, kept apart from the crafters' materials.
		local seller = ns.Seller and ns.Seller.Enabled() and ns.Seller.IsName(char.character or key)
		if key ~= me and not leftOut[key] and count > 0 and not seller then
			table.insert(result, { name = char.character or key, count = count })
		end
	end
	return result
end

-- The bags as Planner.SpacePlan reads them: slots, what's in them and what each item takes. Bag 5 is the reagent bag,
-- which only takes crafting reagents. Nil when the bags can't be read.
local REAGENT_BAG = 5
function Stock.BagSpace()
	if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return nil end
	local space = { slots = 0, reagentSlots = 0, usedOther = 0, usedReagent = 0, bags = {}, itemSlots = {},
		stack = Items.StackSize, isReagent = Items.IsReagent }
	for bag = 0, REAGENT_BAG do
		local slots = C_Container.GetContainerNumSlots(bag) or 0
		if bag == REAGENT_BAG then
			space.reagentSlots = slots
		else
			space.slots = space.slots + slots
		end
		for slot = 1, slots do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				local itemID = info.itemID
				space.bags[itemID] = (space.bags[itemID] or 0) + (info.stackCount or 1)
				space.itemSlots[itemID] = (space.itemSlots[itemID] or 0) + 1
				if Items.IsReagent(itemID) then
					space.usedReagent = space.usedReagent + 1
				else
					space.usedOther = space.usedOther + 1
				end
			end
		end
	end
	if space.slots == 0 then return nil end
	return space
end

-- Mailbox: what the last look in this character's mailbox found, plus auction house purchases made since, which go
-- to the mailbox. Bought items count as soon as the purchase succeeds, so they drop off the shopping list at once.
-- db.mail[charKey]      = { items = { [itemID] = count }, scanned = time }
-- db.purchases[charKey] = { { itemID, count, at }, ... }  bought since that look
-- The price paid goes to the cost record behind the Sales tab's profit.
local PURCHASE_LIFETIME = 30 * 24 * 3600 -- mail is deleted after 30 days

local function MailRecord()
	local key = ns.CharKey()
	if not key then return nil end
	ns.db.mail[key] = ns.db.mail[key] or { items = {}, scanned = 0 }
	return ns.db.mail[key], key
end

function Stock.Mail(itemID)
	local key = ns.CharKey()
	local record = key and ns.db.mail[key]
	local count = record and record.items[itemID] or 0
	for _, purchase in ipairs(key and ns.db.purchases[key] or {}) do
		if purchase.itemID == itemID then count = count + purchase.count end
	end
	return count
end

-- Reads every attachment in the open mailbox. Cash-on-delivery mail isn't yours until paid, so it doesn't count.
function Stock.ScanMailbox()
	local record, key = MailRecord()
	if not record then return end
	local items = {}
	local slots = ATTACHMENTS_MAX_RECEIVE or 16
	for index = 1, GetInboxNumItems() do
		local _, _, _, _, _, cod, _, hasItem = GetInboxHeaderInfo(index)
		if hasItem and (cod or 0) == 0 then
			for slot = 1, slots do
				local _, itemID, _, count = GetInboxItem(index, slot)
				if itemID then items[itemID] = (items[itemID] or 0) + (count or 1) end
			end
		end
	end
	record.items, record.scanned = items, time()
	-- Purchases made before this look are in it now.
	local pending = {}
	for _, purchase in ipairs(ns.db.purchases[key] or {}) do
		if purchase.at > record.scanned then table.insert(pending, purchase) end
	end
	ns.db.purchases[key] = pending
	ns.RequestPlan()
end

function Stock.AddPurchase(itemID, count, paid)
	local _, key = MailRecord()
	if not (key and itemID and count and count > 0) then return end
	if ns.Sales then ns.Sales.NotePurchase(itemID, count, paid) end
	if ns.Depth then ns.Depth.Bought(itemID, count) end
	ns.db.purchases[key] = ns.db.purchases[key] or {}
	local now = time()
	local kept = {}
	for _, purchase in ipairs(ns.db.purchases[key]) do
		if now - purchase.at < PURCHASE_LIFETIME then table.insert(kept, purchase) end
	end
	table.insert(kept, { itemID = itemID, count = count, at = now })
	ns.db.purchases[key] = kept
	ns.RequestPlan()
end

ns.On("MAIL_SHOW", function() Stock.ScanMailbox() end)
ns.On("MAIL_INBOX_UPDATE", function() ns.Debounce("mailbox", 0.3, Stock.ScanMailbox) end)

-- Commodities (stackable goods): the amount confirmed is bought when the server says it succeeded.
local commodityPurchase
-- The total the game last quoted for the amount about to be bought.
local commodityQuote
-- Other items: buyouts of listings seen in a search, completed when the server confirms that auction.
local listings, buyouts = {}, {}

local function NoteListings(itemKey)
	if not (itemKey and itemKey.itemID) then return end
	for index = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
		local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
		if info and info.auctionID then
			listings[info.auctionID] = { itemID = itemKey.itemID, count = info.quantity or 1, buyout = info.buyoutAmount }
		end
	end
end

ns.On("PLAYER_LOGIN", function()
	if not C_AuctionHouse then return end
	if C_AuctionHouse.ConfirmCommoditiesPurchase then
		hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, quantity)
			commodityPurchase = { itemID = itemID, count = quantity, paid = commodityQuote }
		end)
	end
	if C_AuctionHouse.PlaceBid then
		hooksecurefunc(C_AuctionHouse, "PlaceBid", function(auctionID, bid)
			local listing = listings[auctionID]
			-- A bid below the buyout isn't a purchase yet.
			if listing and listing.buyout and bid and bid >= listing.buyout then buyouts[auctionID] = listing end
		end)
	end
end)
ns.On("COMMODITY_PURCHASE_SUCCEEDED", function()
	if commodityPurchase then
		Stock.AddPurchase(commodityPurchase.itemID, commodityPurchase.count, commodityPurchase.paid)
	end
	commodityPurchase, commodityQuote = nil, nil
end)
ns.On("COMMODITY_PURCHASE_FAILED", function() commodityPurchase, commodityQuote = nil, nil end)
ns.On("COMMODITY_PRICE_UPDATED", function(_, total)
	commodityQuote = type(total) == "number" and total > 0 and total or nil
end)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", NoteListings)
ns.On("ITEM_SEARCH_RESULTS_ADDED", NoteListings)
ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
	local bought = buyouts[auctionID]
	buyouts[auctionID] = nil
	if bought then Stock.AddPurchase(bought.itemID, bought.count, bought.buyout) end
end)
ns.On("AUCTION_HOUSE_CLOSED", function() wipe(listings) end)

-- For restocking: units on the AH across characters (nil if they can't be seen), and units held anywhere else:
-- bags and banks of all characters, plus mail, since expired auctions come back that way.
function Stock.ForRestock(itemID)
	-- Crafts mailed to the bank alt that it hasn't seen in its mailbox yet count as held too.
	local owned = Stock.Own(itemID) + (ns.Seller and ns.Seller.InTransit(itemID) or 0)
	local api = SyndicatorAPI()
	if not api then return nil, owned end
	local ok, info = pcall(api.GetInventoryInfoByItemID, itemID, true, true)
	if not ok or type(info) ~= "table" then return nil, owned end
	local me = api.GetCurrentCharacter()
	local leftOut = LeftOut(me)
	local onAH = 0
	for _, char in ipairs(info.characters or {}) do
		local key = SyndicatorKey(char)
		if not leftOut[key] then
			onAH = onAH + (char.auctions or 0)
			owned = owned + (char.mail or 0)
			if key ~= me then owned = owned + (char.bags or 0) + (char.bank or 0) end
		end
	end
	return onAH, owned
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------

local Recipes = {}
ns.Recipes = Recipes
local readThisSession = {}
-- [charKey|recipeID] = GetTime() when the open profession first listed a known recipe as not learned. It's only
-- forgotten when a scan at least FORGET_AFTER seconds later still says so, so a list that's still loading or switching
-- can't wipe it. Not saved: a real unlearn is confirmed the next time the window is open long enough.
local notLearnedSince = {}
local FORGET_AFTER = 10

-- The profession the client currently has open. The window's own answer is what other Forever add-ons rely on;
-- the API calls are fallbacks. An ID of 0 means no profession.
local function ProfessionInfo()
	local sources = {
		ProfessionsFrame and ProfessionsFrame.GetProfessionInfo and function() return ProfessionsFrame:GetProfessionInfo() end,
		C_TradeSkillUI.GetBaseProfessionInfo,
		C_TradeSkillUI.GetChildProfessionInfo,
	}
	for i = 1, 3 do
		local info = sources[i] and sources[i]()
		if info and info.professionID and info.professionID ~= 0 then return info end
	end
	return nil
end

-- The same profession can be reported as its parent or as an expansion child, so recipes are filed under the parent.
local function ProfessionKey(info)
	local parent = info.parentProfessionID
	if parent and parent ~= 0 then return parent, info.parentProfessionName or info.professionName end
	return info.professionID, info.professionName
end

function Recipes.OpenProfession()
	if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then return nil end
	local info = ProfessionInfo()
	if not info then return nil end
	return ProfessionKey(info)
end

-- The recipes in the open profession window, as a set. Asking the window itself is reliable where comparing
-- profession IDs is not. Empty when no window is open.
function Recipes.OpenRecipes()
	local set = {}
	if ProfessionsFrame and ProfessionsFrame:IsShown() then
		for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do set[recipeID] = true end
	end
	return set
end

-- Names of what the recipe needs nearby and doesn't have, such as an anvil.
function Recipes.UnmetRequirements(recipeID)
	local unmet = {}
	local fn = C_TradeSkillUI.GetRecipeRequirements
	if not fn then return unmet end
	local ok, requirements = pcall(fn, recipeID)
	if ok and type(requirements) == "table" then
		for _, requirement in ipairs(requirements) do
			if requirement.met == false and requirement.name then table.insert(unmet, requirement.name) end
		end
	end
	return unmet
end

-- Tools a recipe needs in the bags (a Blacksmith Hammer, an Arclight Spanner), as the game names them. The game
-- calls them totems. The item that is each tool, by its English name: the game only gives the tool's name.
ns.TOOLS = {
	[5956] = "Blacksmith Hammer",
	[6219] = "Arclight Spanner",
	[10498] = "Gyromatic Micro-Adjustor",
	[6218] = "Runed Copper Rod",
	[6339] = "Runed Silver Rod",
	[11130] = "Runed Golden Rod",
	[11145] = "Runed Truesilver Rod",
	[16207] = "Runed Arcanite Rod",
	[9149] = "Philosopher's Stone",
	[2901] = "Mining Pick",
	[7005] = "Skinning Knife",
}

-- The items that are a tool, by the tool's name: the client's name for the item where it has loaded, else the English
-- one. Empty for a tool this list doesn't know.
function Recipes.ToolItems(name)
	local items = {}
	for itemID, english in pairs(ns.TOOLS) do
		if name == english or name == Items.Name(itemID) then table.insert(items, itemID) end
	end
	table.sort(items)
	return items
end

-- The requirements the client lists for a recipe (tools, places), nil when it can't say.
local function Requirements(recipeID)
	local fn = C_TradeSkillUI.GetRecipeRequirements
	if not fn then return nil end
	local ok, requirements = pcall(fn, recipeID)
	if not ok or type(requirements) ~= "table" then return nil end
	return requirements
end

-- Names of the tools a recipe needs, nil for none. Requirements of the tool kind count; when the client doesn't say
-- the kind, a name this add-on knows as a tool does. Places (an anvil, a forge) aren't tools.
function Recipes.Tools(recipeID)
	local requirements = Requirements(recipeID)
	if not requirements then return nil end
	local totem = Enum.RecipeRequirementType and Enum.RecipeRequirementType.Totem
	local tools
	for _, requirement in ipairs(requirements) do
		local name = requirement.name
		local isTool
		if requirement.type ~= nil and totem ~= nil then
			isTool = requirement.type == totem
		else
			isTool = name and #Recipes.ToolItems(name) > 0
		end
		if name and isTool then
			tools = tools or {}
			table.insert(tools, name)
		end
	end
	return tools
end

-- Camp stations (Forever's camping): a Fermenter, a Loom and the like are items you place at a campfire, used up when
-- placed, and some recipes can only be crafted beside one. Only those found nowhere in the world are listed: the
-- camp Anvil isn't, as every town has an anvil. Item IDs from Wowhead Forever (2026-11-22; Iron Oven and Anarchist's Workbench 2026-11-23). Placing one needs the
-- profession at the item's skill and a campfire nearby; every camp feature shares a 1 hour cooldown.
ns.CAMP = {
	stations = {
		[279970] = "Fermenter", [279990] = "Alchemy Laboratory", [279943] = "Spinning Wheel", [279959] = "Loom",
		[279941] = "Tanning Rack", [279945] = "Sewing Machine", [279985] = "Arcane Salvager",
		[279987] = "Arcane Forge", [279955] = "Master Forge", [279952] = "Molten Foundry", [279964] = "Greenhouse",
		[279965] = "Fishing Rack", [279940] = "Toxin Study", [279969] = "Field Guide", [279949] = "Repair Bot",
		[279957] = "Cookie's Feast", [279982] = "Iron Oven", [279989] = "Anarchist's Workbench",
	},
	-- Basic, Journeyman and Expert Campfire Kit: any of them takes a station.
	fires = { 279981, 279961, 279974 },
}

-- The items that place a station, by the station's name (client name where loaded, else English). Empty for a place
-- that isn't a camp station (an anvil, a forge).
function Recipes.StationItems(name)
	local items = {}
	for itemID, english in pairs(ns.CAMP.stations) do
		if name == english or name == Items.Name(itemID) then table.insert(items, itemID) end
	end
	table.sort(items)
	return items
end

-- Campfire kits and camp stations: used up where they're placed, never sold or mailed to the bank alt.
function Recipes.IsCampItem(itemID)
	if ns.CAMP.stations[itemID] then return true end
	for _, fire in ipairs(ns.CAMP.fires) do
		if fire == itemID then return true end
	end
	return false
end

function Recipes.CampfireItems()
	local items = {}
	for _, itemID in ipairs(ns.CAMP.fires) do table.insert(items, itemID) end
	return items
end

-- Placed camp items: using a campfire kit or a station uses it up, so the plan would ask for another one. A placed
-- one counts as there while its minutes haven't passed and you're still on the same map: a station stands
-- STATION_MINUTES (15, the player's word), a campfire FIRE_MINUTES (a guess: not known on Forever). Placing a station
-- starts COOLDOWN_MINUTES that every station shares (using a Master Forge puts the Fermenter on cooldown too); the
-- campfire kit isn't counted in it.
-- db.campPlaced[itemID] = { at = time(), map = C_Map.GetBestMapForUnit("player"), char = character key };
-- db.campCooldown[character key] = time() the last station was placed.
ns.CAMP.STATION_MINUTES = 15
ns.CAMP.FIRE_MINUTES = 60
ns.CAMP.COOLDOWN_MINUTES = 60

local function CurrentMap()
	return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
end

local function Lifetime(itemID)
	return (ns.CAMP.stations[itemID] and ns.CAMP.STATION_MINUTES or ns.CAMP.FIRE_MINUTES) * 60
end

-- Seconds a placed item still stands, nil when it doesn't (or was never placed).
local function StandsFor(itemID, now, map)
	local records = ns.db and ns.db.campPlaced
	local record = records and records[itemID]
	if not record or record.map ~= map then return nil end
	local left = record.at + Lifetime(itemID) - now
	return left > 0 and left or nil
end

-- The first of the items placed and still standing, else nil.
function Recipes.CampPlaced(items)
	local now, map = time(), CurrentMap()
	for _, itemID in ipairs(items) do
		if StandsFor(itemID, now, map) then return itemID end
	end
	return nil
end

-- For the planner (Planner.CampWindow): { window = seconds a new station stands, cooldown = seconds before this
-- character can place another station (0: now), itemID / name / left = the station placed and still standing }.
function Recipes.CampState()
	local now, map = time(), CurrentMap()
	local at = ns.db and ns.db.campCooldown and ns.db.campCooldown[ns.CharKey()]
	local state = { window = ns.CAMP.STATION_MINUTES * 60,
		cooldown = at and math.max(0, at + ns.CAMP.COOLDOWN_MINUTES * 60 - now) or 0 }
	for itemID, english in pairs(ns.CAMP.stations) do
		local left = StandsFor(itemID, now, map)
		if left and (not state.left or left > state.left) then
			state.itemID, state.name, state.left = itemID, Items.Name(itemID) or english, left
		end
	end
	return state
end

local function CampItems()
	local items = {}
	for itemID in pairs(ns.CAMP.stations) do table.insert(items, itemID) end
	for _, itemID in ipairs(ns.CAMP.fires) do table.insert(items, itemID) end
	return items
end

local function NotePlaced(itemID)
	ns.db.campPlaced = ns.db.campPlaced or {}
	ns.db.campPlaced[itemID] = { at = time(), map = CurrentMap(), char = ns.CharKey() }
	if ns.CAMP.stations[itemID] then
		ns.db.campCooldown = ns.db.campCooldown or {}
		ns.db.campCooldown[ns.CharKey()] = time()
	end
	ns.RequestPlan()
end

-- Seen two ways: the item's own use spell (C_Item.GetItemSpell), or, when that isn't known, one fewer of it in the
-- bags right after a cast than when the cast was sent.
local campSpells, campCounts = {}, nil
local function CampItemBySpell(spellID)
	for _, itemID in ipairs(CampItems()) do
		if not campSpells[itemID] and C_Item.GetItemSpell then
			local _, itemSpell = C_Item.GetItemSpell(itemID)
			campSpells[itemID] = itemSpell
		end
		if campSpells[itemID] == spellID then return itemID end
	end
	return nil
end

-- Recipe cooldowns (transmutes and the like), per character: char.cooldowns[recipeID] = { r = ready at (time()), l =
-- full length in seconds when known }. An entry means the recipe has a cooldown at all. Read from the client at each
-- profession scan and just after the recipe is cast.
local function ReadCooldown(char, recipeID)
	local read = C_TradeSkillUI and C_TradeSkillUI.GetRecipeCooldown
	if not read then return false end
	local ok, left, _, charges, maxCharges = pcall(read, recipeID)
	if not ok then return false end
	local base = GetSpellBaseCooldown and select(2, pcall(GetSpellBaseCooldown, recipeID))
	local length = type(base) == "number" and base > 0 and base / 1000 or nil
	left = type(left) == "number" and left > 0 and left or 0
	-- With charges, one left means it can be cast now.
	if (maxCharges or 0) > 0 and (charges or 0) > 0 then left = 0 end
	local old = char.cooldowns and char.cooldowns[recipeID]
	if left <= 0 and not length and not old then return false end
	char.cooldowns = char.cooldowns or {}
	local ready = left > 0 and math.floor(time() + left) or 0
	local entry = { r = ready, l = length or (old and old.l) }
	if old and old.r == entry.r and old.l == entry.l then return false end
	char.cooldowns[recipeID] = entry
	return true
end

-- Seconds until charKey can cast the recipe again (0 = ready) and whether it has a cooldown at all.
function Recipes.Cooldown(charKey, recipeID)
	local char = charKey and ns.db.chars[charKey]
	local entry = char and char.cooldowns and char.cooldowns[recipeID]
	if not entry then return 0, false end
	return math.max(0, (entry.r or 0) - time()), true
end

-- Just cast: read the cooldown it started (the length learned earlier if the client says nothing yet).
local function NoteCooldownCast(recipeID)
	local char = ns.CharRecord()
	if not (char and ns.db.recipes[recipeID]) then return end
	C_Timer.After(0.5, function()
		local changed = ReadCooldown(char, recipeID)
		local now = char.cooldowns and char.cooldowns[recipeID]
		if now and now.r <= time() and now.l then
			now.r = math.floor(time() + now.l)
			changed = true
		end
		if changed and ns.RequestPlan then ns.RequestPlan() end
	end)
end

ns.On("UNIT_SPELLCAST_SENT", function(unit)
	if unit ~= "player" or not ns.db then return end
	campCounts = {}
	for _, itemID in ipairs(CampItems()) do campCounts[itemID] = C_Item.GetItemCount(itemID) end
end)

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
	if unit ~= "player" or not ns.db then return end
	if type(spellID) == "number" and not (issecretvalue and issecretvalue(spellID)) then
		NoteCooldownCast(spellID)
		local itemID = CampItemBySpell(spellID)
		if itemID then
			campCounts = nil
			NotePlaced(itemID)
			return
		end
	end
	local before = campCounts
	campCounts = nil
	if not before then return end
	C_Timer.After(0.5, function()
		for itemID, count in pairs(before) do
			if count > 0 and C_Item.GetItemCount(itemID) == count - 1 then NotePlaced(itemID) end
		end
	end)
end)

-- Names of the camp stations a recipe needs, nil for none: place requirements (the client's spell focus kind, or any
-- when it doesn't say the kind) that name a camp station.
function Recipes.Stations(recipeID)
	local requirements = Requirements(recipeID)
	if not requirements then return nil end
	local kinds = Enum.RecipeRequirementType
	local focus = kinds and kinds.SpellFocus
	local stations
	for _, requirement in ipairs(requirements) do
		local name = requirement.name
		local isPlace = requirement.type == nil or focus == nil or requirement.type == focus
		if name and isPlace and #Recipes.StationItems(name) > 0 then
			stations = stations or {}
			table.insert(stations, name)
		end
	end
	return stations
end

local function BasicReagentType()
	return Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 0
end

local function ItemIDFromLink(link)
	return link and tonumber(link:match("item:(%d+)")) or nil
end

-- The materials and result of a schematic: { o, qmin, qmax, r, x } (see Recipes.Read), or nil when a required slot
-- is still empty (its data hasn't loaded).
local function Compact(recipeID, schematic)
	local slots = {}
	local usesCurrency = false
	local basic = BasicReagentType()
	for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
		if slot.reagentType == basic and slot.required ~= false then
			local entry = { slot.quantityRequired or 1 }
			local hasCurrency = false
			for _, reagent in ipairs(slot.reagents or {}) do
				if reagent.itemID then table.insert(entry, reagent.itemID) end
				if reagent.currencyID then hasCurrency = true end
			end
			if #entry > 1 then
				table.insert(slots, entry)
			elseif hasCurrency then
				usesCurrency = true
			else
				return nil -- a required slot with no contents: the data isn't complete yet, so don't keep it
			end
		end
	end
	local output = schematic.outputItemID
	if not output or output <= 0 then
		output = ItemIDFromLink(C_TradeSkillUI.GetRecipeItemLink(recipeID))
	end
	return {
		o = output,
		qmin = schematic.quantityMin or 1,
		qmax = schematic.quantityMax or schematic.quantityMin or 1,
		r = slots,
		x = usesCurrency or nil,
	}
end

-- Compact copy of a recipe, so costs work for professions and characters not currently open.
function Recipes.Read(recipeID, recipeInfo, professionID, professionName)
	local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
	if type(schematic) ~= "table" then return nil end
	local recipe = Compact(recipeID, schematic)
	if not recipe then return nil end
	recipe.n = recipeInfo and recipeInfo.name or schematic.name
	recipe.p = professionID
	recipe.pn = professionName
	recipe.t = Recipes.Tools(recipeID)
	recipe.f = Recipes.Stations(recipeID)
	ns.db.recipes[recipeID] = recipe
	return recipe
end

-- A recipe nobody knows yet, for what it would earn (Recipes mode): its materials and result, read from the game
-- (which describes unlearned recipes too) and kept in db.recipePreview. A known recipe is its own record. Asked of
-- the client at most every PREVIEW_RETRY seconds while its data hasn't loaded.
Recipes.PREVIEW_RETRY = 30
local previewAsked = {}
function Recipes.Preview(recipeID)
	local known = ns.db.recipes[recipeID]
	if known then return known end
	ns.db.recipePreview = ns.db.recipePreview or {}
	local saved = ns.db.recipePreview[recipeID]
	if saved then return saved end
	local now = GetTime()
	if previewAsked[recipeID] and now - previewAsked[recipeID] < Recipes.PREVIEW_RETRY then return nil end
	previewAsked[recipeID] = now
	local fn = C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic
	if not fn then return nil end
	local ok, schematic = pcall(fn, recipeID, false)
	local recipe = ok and type(schematic) == "table" and Compact(recipeID, schematic) or nil
	if recipe then ns.db.recipePreview[recipeID] = recipe end
	return recipe
end

-- What a recipe makes, learned or not: an item ID, false when it makes no item (most enchants), nil when not known
-- yet. Read from the open profession window's list (ScanOpenProfession), else asked of the client; only a list read
-- with the window ready may say "no item", since a recipe whose data hasn't loaded looks the same.
-- db.recipeOutputs[recipeID] = item ID, or 0 for no item.
function Recipes.Output(recipeID)
	local recipe = ns.db.recipes[recipeID]
	if recipe then return recipe.o or false end
	ns.db.recipeOutputs = ns.db.recipeOutputs or {}
	local saved = ns.db.recipeOutputs[recipeID]
	if saved then return saved ~= 0 and saved or false end
	local fn = C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic
	local ok, schematic = false, nil
	if fn then ok, schematic = pcall(fn, recipeID, false) end
	local output = ok and type(schematic) == "table" and schematic.outputItemID
	if output and output > 0 then
		ns.db.recipeOutputs[recipeID] = output
		return output
	end
	return nil
end

local function ReadOutputs(ids)
	ns.db.recipeOutputs = ns.db.recipeOutputs or {}
	ns.db.recipePreview = ns.db.recipePreview or {}
	local outputs, previews = ns.db.recipeOutputs, ns.db.recipePreview
	for _, recipeID in ipairs(ids) do
		if not (outputs[recipeID] and previews[recipeID]) and not ns.db.recipes[recipeID] then
			local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
			if ok and type(schematic) == "table" then
				local output = schematic.outputItemID
				outputs[recipeID] = output and output > 0 and output or 0
				previews[recipeID] = previews[recipeID] or Compact(recipeID, schematic)
			end
		end
	end
end

-- For the Recipes list: the game's own list of the profession, unlearned recipes included, so AllTheThings' recipes
-- this game doesn't have are left out and ones AllTheThings doesn't have yet are added; and what each makes.
local function RememberList(professionID, ids, notLearned)
	if next(notLearned) then
		local set = {}
		for _, recipeID in ipairs(ids) do set[recipeID] = true end
		ns.db.recipeLists = ns.db.recipeLists or {}
		ns.db.recipeLists[professionID] = { at = time(), ids = set }
	end
	ReadOutputs(ids)
end

local function ScanOpenProfession()
	-- Reagents can be missing from recipes until the list is ready; the list-update event comes again when it is.
	if not C_TradeSkillUI.IsTradeSkillReady() then return end
	-- Only the player's own professions, not linked, guild or NPC views.
	for _, check in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting" }) do
		local fn = C_TradeSkillUI[check]
		if fn and fn() then return end
	end
	local char = ns.CharRecord()
	local base = ProfessionInfo()
	local ids = C_TradeSkillUI.GetAllRecipeIDs()
	if not char or not base or type(ids) ~= "table" then return end

	local baseKey, baseName = ProfessionKey(base)
	local learned, notLearned, filedHere, filedElsewhere = {}, {}, 0, 0
	for _, recipeID in ipairs(ids) do
		local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if info and info.learned == false then notLearned[recipeID] = true end
		if info and info.learned then
			learned[recipeID] = info
			local stored = ns.db.recipes[recipeID]
			if stored and stored.p then
				if stored.p == baseKey then filedHere = filedHere + 1 else filedElsewhere = filedElsewhere + 1 end
			end
		end
	end
	-- An empty answer means the list isn't ready yet, not that everything was unlearned.
	if not next(learned) then return end
	-- While the window switches professions it can report the new one with the old one's list still in it. Read
	-- then, the new profession's recipes looked unlearned and were forgotten (Smelt Bronze and the other smelts
	-- went missing that way). Mostly recipes of another profession means that: wait for the next list update.
	if filedElsewhere > filedHere then return end
	RememberList(baseKey, ids, notLearned)

	-- Each recipe's colour for this character right now, for levelling. It changes with every skill point.
	char.skillUps = char.skillUps or {}
	local skillChanged, cooldownChanged = false, false
	for recipeID, info in pairs(learned) do
		local old = char.skillUps[recipeID]
		local difficulty, skillUps = info.relativeDifficulty, info.numSkillUps
		if not old or old.d ~= difficulty or old.n ~= skillUps then
			char.skillUps[recipeID] = { d = difficulty, n = skillUps }
			skillChanged = true
		end
		if ReadCooldown(char, recipeID) then cooldownChanged = true end
		if not readThisSession[recipeID] then
			if Recipes.Read(recipeID, info, baseKey, baseName) then
				readThisSession[recipeID] = true
			end
		end
	end

	if base.skillLevel and base.maxSkillLevel then
		char.skill = char.skill or {}
		local old = char.skill[baseKey]
		if not old or old.level ~= base.skillLevel or old.max ~= base.maxSkillLevel then
			char.skill[baseKey] = { level = base.skillLevel, max = base.maxSkillLevel }
			skillChanged = true
		end
	end
	if cooldownChanged then
		if ns.Restock and ns.Restock.ForgetSmart then ns.Restock.ForgetSmart() end
		if ns.RequestPlan then ns.RequestPlan() end
	end
	if skillChanged and ns.UI then
		ns.UI.Refresh("profit")
		ns.UI.Refresh("queue") -- queued crafts are coloured by it too
		if ns.UI.UpdateNextStep then ns.UI.UpdateNextStep() end
	end
	-- The client only gives a profession's link while it's open, so keep it for advertising later.
	local link = C_TradeSkillUI.GetTradeSkillListLink and C_TradeSkillUI.GetTradeSkillListLink()
	if link then
		char.links = char.links or {}
		char.links[baseKey] = link
	end
	local changed = false
	-- Forgetting needs the game to say outright, twice and FORGET_AFTER seconds apart, that a recipe of this
	-- profession isn't learned. Missing from the list is never enough: that's what a list still loading or still
	-- showing another profession looks like.
	local charKey, now = ns.CharKey(), GetTime()
	for recipeID in pairs(char.recipes) do
		local recipe = ns.db.recipes[recipeID]
		local key = charKey .. "|" .. recipeID
		if notLearned[recipeID] and recipe and recipe.p == baseKey then
			local since = notLearnedSince[key]
			if not since then
				notLearnedSince[key] = now
			elseif now - since >= FORGET_AFTER then
				char.recipes[recipeID] = nil
				notLearnedSince[key] = nil
				changed = true
			end
		elseif learned[recipeID] then
			notLearnedSince[key] = nil
		end
	end
	for recipeID in pairs(learned) do
		if not char.recipes[recipeID] then
			char.recipes[recipeID] = true
			changed = true
		end
	end
	if changed then
		ns.InvalidateProfit()
		ns.RequestPlan()
	end
	if ns.OnProfessionScanned then ns.OnProfessionScanned() end
end

local function RequestScan()
	ns.Debounce("recipescan", 0.3, ScanOpenProfession)
end

-- Reads every recipe of the open profession again, even those already read this session.
function Recipes.Rescan()
	wipe(readThisSession)
	if ProfessionsFrame and ProfessionsFrame:IsShown() then RequestScan() end
end

ns.On("TRADE_SKILL_LIST_UPDATE", RequestScan)
ns.On("TRADE_SKILL_DATA_SOURCE_CHANGED", RequestScan)
ns.On("TRADE_SKILL_SHOW", RequestScan)

-- Recipes known by each output item, across every character recorded so far except those left out.
local NONE = {}
function Recipes.KnownMap()
	local known, seen = {}, {}
	for key, char in pairs(ns.db.chars) do
		for recipeID in pairs(ns.CharExcluded(key) and NONE or char.recipes) do
			local recipe = ns.db.recipes[recipeID]
			if recipe and recipe.o and not seen[recipeID] then
				seen[recipeID] = true
				known[recipe.o] = known[recipe.o] or {}
				table.insert(known[recipe.o], recipeID)
			end
		end
	end
	return known
end

-- Every profession known on any character not left out: { { id, name }, ... } by name.
function Recipes.KnownProfessions()
	local names = {}
	for key, char in pairs(ns.db.chars) do
		for recipeID in pairs(ns.CharExcluded(key) and NONE or char.recipes) do
			local recipe = ns.db.recipes[recipeID]
			if recipe and recipe.p then names[recipe.p] = recipe.pn or tostring(recipe.p) end
		end
	end
	local list = {}
	for id, name in pairs(names) do table.insert(list, { id = id, name = name }) end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

-- Gathering professions aren't for hire: Herbalism, Mining, Skinning, Fishing.
local GATHERING = { [182] = true, [186] = true, [393] = true, [356] = true }

function Recipes.IsCraftingProfession(professionID)
	return professionID ~= nil and not GATHERING[professionID]
end

-- Farm It's gathering kinds (Sources.lua's k) by profession skill line.
Recipes.GATHER_KINDS = { [186] = "mine", [182] = "herb", [393] = "skin", [356] = "fish" }

-- The gathering professions the logged-in character has, as char.gathering = { mine = true, ... }. Herbalism and
-- Skinning have no recipes, so they can't be told from char.recipes. Left nil when the client can't say.
function Recipes.ReadGathering()
	if not GetProfessions or not GetProfessionInfo then return end
	local char = ns.CharRecord()
	if not char then return end
	local found = {}
	for _, index in pairs({ GetProfessions() }) do
		local line = select(7, GetProfessionInfo(index))
		local kind = line and Recipes.GATHER_KINDS[line]
		if kind then found[kind] = true end
	end
	local changed = char.gathering == nil
	for _, kind in pairs(Recipes.GATHER_KINDS) do
		if not changed and (char.gathering[kind] or false) ~= (found[kind] or false) then changed = true end
	end
	char.gathering = found
	if changed and ns.RequestPlan then ns.RequestPlan() end
end

-- Whether the logged-in character can gather this kind (mine, herb, skin, fish): true / false, nil = not known yet.
function Recipes.CanGather(kind)
	local char = ns.CharKey() and ns.db.chars[ns.CharKey()]
	if not char or not char.gathering then return nil end
	return char.gathering[kind] == true
end

-- Farm It's gathering kind for an item, when it's mined, picked, skinned or fished.
function Recipes.GatherKind(itemID)
	local source = ns.SourceData and ns.SourceData[itemID]
	return source and source.k or nil
end

ns.WhenDataReady(function() Recipes.ReadGathering() end)
ns.On("SKILL_LINES_CHANGED", function() ns.Debounce("gathering", 0.5, Recipes.ReadGathering) end)

-- True when the character knows at least one recipe filed under the profession.
function Recipes.CharHasProfession(charKey, professionID)
	local char = charKey and ns.db.chars[charKey]
	if not char then return false end
	for recipeID in pairs(char.recipes) do
		local recipe = ns.db.recipes[recipeID]
		if recipe and recipe.p == professionID then return true end
	end
	return false
end

function Recipes.ProfessionName(professionID)
	for _, profession in ipairs(Recipes.KnownProfessions()) do
		if profession.id == professionID then return profession.name end
	end
	return nil
end

-- A character left out on the Options tab knows nothing, so it's never picked to craft.
function Recipes.Knows(charKey, recipeID)
	local char = charKey and ns.db.chars[charKey]
	return char ~= nil and char.recipes[recipeID] == true and not ns.CharExcluded(charKey)
end

-- The logged-in character when it knows the recipe, then the preferred one, then anyone who does.
-- A recipe's colour for a character (0 orange, 1 yellow, 2 green, 3 grey) and skill points per craft, as of the
-- last time that character had the profession open. nil when never seen.
function Recipes.Difficulty(charKey, recipeID)
	local char = charKey and ns.db.chars[charKey]
	local info = char and char.skillUps and char.skillUps[recipeID]
	if not info or info.d == nil then return nil end
	return info.d, info.n
end

function Recipes.Crafter(recipeID, preferred)
	local me = ns.CharKey()
	if Recipes.Knows(me, recipeID) then return me end
	if Recipes.Knows(preferred, recipeID) then return preferred end
	local best
	for key in pairs(ns.db.chars) do
		if Recipes.Knows(key, recipeID) and (not best or key < best) then best = key end
	end
	return best or preferred or me
end
