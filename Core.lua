-- Crafting and Farming Forever :: Core
-- Event dispatch, debouncing and saved data.

local ADDON, ns = ...
ns.name = ADDON
ns.LIST_NAME = "Crafting and Farming Forever Queue"
ns.AH_CUT = 0.05
ns.STALE_SECONDS = 24 * 60 * 60

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event]) do
		local ok, err = pcall(fn, ...)
		if not ok then geterrorhandler()(err) end
	end
end)

local pending = {}

-- Runs fn once, delay seconds after the first request.
function ns.Debounce(key, delay, fn)
	if pending[key] then return end
	pending[key] = true
	C_Timer.After(delay, function()
		pending[key] = nil
		fn()
	end)
end

function ns.Print(text)
	print("|cff66ccffCrafting and Farming Forever|r: " .. tostring(text))
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
-- db.recipes[recipeID] = { n = name, o = outputItemID, qmin, qmax, p = professionID, pn = professionName,
--                          r = { { qty, itemID, altItemID, ... }, ... }, x = true if it also costs a currency }
-- db.chars[guid]       = { name, realm, class, recipes = { [recipeID] = true }, links = { [professionID] = link },
--                          skillUps = { [recipeID] = { d = colour 0-3, n = points per craft } },
--                          skill = { [professionID] = { level, max } } } (both as of the profession's last opening)
-- db.queue[i]          = { recipeID, qty, char = guid, restock = true if added by the Restock button }
-- db.prices[itemID]    = { cur = last seen copper, old = copper before it changed, round = scan of that change }
-- db.priceRound        = number of the latest full scan or scan of our shopping list
-- db.restock           = { stackGoal, singleGoal, minProfitSilver, duration = 1 to 3 for posting,
--                          goals = { [itemID] = per-item goal } }
-- db.lastAuctionRefusal = { kind, text, at, code }, what the auction house last refused
-- db.mail              = { [charKey] = { items = { [itemID] = count }, scanned } }, the mailbox's last contents
-- db.purchases         = { [charKey] = { { itemID, count, at }, ... } }, AH purchases since then, waiting in the mail
-- db.lastSeenVersion   = the add-on version whose What's new the player has seen
-- db.ui                = { autoOpen, tab, queueBeside, farmMode, adDestination, quoteMargin (%), positions = { main|next = { x, y } }, ... }
--
-- On the Forever client the saved table can reach the global after ADDON_LOADED. Creating the global early can
-- make the client skip the file, so the session works on a provisional table until the real one arrives, and the
-- global is only assigned at logout if the client never supplied one.

local function Normalize(db)
	db.version = db.version or 1
	db.recipes = db.recipes or {}
	db.chars = db.chars or {}
	db.queue = db.queue or {}
	db.ui = db.ui or {}
	if db.ui.autoOpen == nil then db.ui.autoOpen = true end
	db.ui.quoteMargin = db.ui.quoteMargin or 10
	db.prices = db.prices or {}
	db.priceRound = db.priceRound or 1
	db.sales = db.sales or {}
	db.sales.items = db.sales.items or {}
	db.sales.lots = db.sales.lots or {}
	db.sales.seen = db.sales.seen or {}
	db.sales.incoming = db.sales.incoming or {}
	db.restock = db.restock or {}
	db.restock.stackGoal = db.restock.stackGoal or 10
	db.restock.singleGoal = db.restock.singleGoal or 1
	db.restock.minProfitSilver = db.restock.minProfitSilver or 1
	db.restock.goals = db.restock.goals or {}
	db.restock.duration = db.restock.duration or 2
	db.mail = db.mail or {}
	db.purchases = db.purchases or {}
	-- Left behind by older versions: the auction debug log, the separate windows before the tabbed one, renamed options.
	db.auctionLog = nil
	db.ui.hideLosing, db.ui.manualChat = nil, nil
	if db.ui.positions then
		for window in pairs(db.ui.positions) do
			if window ~= "main" and window ~= "next" then db.ui.positions[window] = nil end
		end
	end
	-- Mail records used to include the count, which can change between scans of one mail.
	for _, records in pairs(db.sales.seen) do
		for _, record in ipairs(records) do
			record.key = record.key:gsub("^(%a+|.-)|%d+|(%d+)$", "%1|%2")
		end
	end
	return db
end

local function Merge(loaded, session)
	for id, recipe in pairs(session.recipes) do loaded.recipes[id] = recipe end
	for guid, char in pairs(session.chars) do
		local target = loaded.chars[guid]
		if target then
			target.name, target.realm, target.class = char.name, char.realm, char.class
			for id in pairs(char.recipes) do target.recipes[id] = true end
			for _, field in ipairs({ "links", "skillUps", "skill" }) do
				for id, value in pairs(char[field] or {}) do
					target[field] = target[field] or {}
					target[field][id] = value
				end
			end
		else
			loaded.chars[guid] = char
		end
	end
	for _, entry in ipairs(session.queue) do table.insert(loaded.queue, entry) end
	-- Mail results aren't merged: they get read again on the next mailbox visit, since no mail is marked as seen.
	for _, lot in ipairs(session.sales.lots) do table.insert(loaded.sales.lots, lot) end
end

ns.db = Normalize({})
local adopted = false

-- Code that needs to know whether saved data existed (the What's new window) waits for this: it runs once the saved
-- data is adopted, or once it's clear there is none (a first install). ns.savedDataFound tells which.
local readyCallbacks = {}
ns.dataReady = false

function ns.WhenDataReady(fn)
	if ns.dataReady then fn() else table.insert(readyCallbacks, fn) end
end

local function MarkDataReady(found)
	if ns.dataReady then return end
	ns.dataReady, ns.savedDataFound = true, found
	for _, fn in ipairs(readyCallbacks) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
	readyCallbacks = {}
end

local function AdoptSavedData()
	if adopted then return true end
	local loaded = _G.CraftingAndFarmingForeverDB
	if type(loaded) ~= "table" then return false end
	adopted = true
	Normalize(loaded)
	Merge(loaded, ns.db)
	ns.db = loaded
	if ns.OnDataChanged then ns.OnDataChanged() end
	MarkDataReady(true)
	return true
end

ns.On("ADDON_LOADED", function(name)
	if name ~= ADDON or AdoptSavedData() then return end
	-- Saved data may still be on its way: keep checking for a while after loading.
	local tries = 0
	local function Check()
		tries = tries + 1
		if AdoptSavedData() then return end
		if tries < 120 then C_Timer.After(1, Check) else MarkDataReady(false) end
	end
	C_Timer.After(1, Check)
end)

ns.On("PLAYER_LOGOUT", function()
	AdoptSavedData()
	_G.CraftingAndFarmingForeverDB = ns.db
end)

---------------------------------------------------------------------------
-- Characters
---------------------------------------------------------------------------
-- Keyed by GUID: on linked Forever realms name + realm is not a reliable identity.

function ns.CharKey()
	return UnitGUID("player")
end

function ns.CharRecord()
	local key = ns.CharKey()
	if not key then return nil end
	local char = ns.db.chars[key]
	if not char then
		char = { recipes = {} }
		ns.db.chars[key] = char
	end
	char.name = UnitName("player")
	char.realm = GetRealmName()
	char.class = select(1, UnitClass("player"))
	return char
end

function ns.CharLabel(key)
	local char = key and ns.db.chars[key]
	if not char then return "Unknown" end
	for otherKey, other in pairs(ns.db.chars) do
		if otherKey ~= key and other.name == char.name then
			return ("%s (%s)"):format(char.name or "?", char.class or char.realm or "?")
		end
	end
	return char.name or "?"
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------

-- "1 item", "2 items": the count with the right form of the word.
function ns.Plural(count, one, many)
	return ("%d %s"):format(count, count == 1 and one or many)
end

function ns.Money(copper)
	if not copper then return "?" end
	local sign = copper < 0 and "-" or ""
	copper = math.floor(math.abs(copper) + 0.5)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then return ("%s%dg %02ds"):format(sign, g, s) end
	if s > 0 then return ("%s%ds %02dc"):format(sign, s, c) end
	return ("%s%dc"):format(sign, c)
end
