-- CraftLedger :: Core
-- Event dispatch, debouncing and saved data.

local ADDON, ns = ...
ns.name = ADDON
ns.LIST_NAME = "CraftLedger Queue"
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
	print("|cff66ccffCraftLedger|r: " .. tostring(text))
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
-- db.recipes[recipeID] = { n = name, o = outputItemID, qmin, qmax, p = professionID, pn = professionName,
--                          r = { { qty, itemID, altItemID, ... }, ... }, x = true if it also costs a currency }
-- db.chars[guid]       = { name, realm, class, recipes = { [recipeID] = true } }
-- db.queue[i]          = { recipeID, qty, char = guid, restock = true if added by the Restock button }
-- db.restock           = { stackGoal, singleGoal, minProfitSilver, goals = { [itemID] = per-item goal } }
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
	db.sales = db.sales or {}
	db.sales.items = db.sales.items or {}
	db.sales.lots = db.sales.lots or {}
	db.sales.seen = db.sales.seen or {}
	db.restock = db.restock or {}
	db.restock.stackGoal = db.restock.stackGoal or 10
	db.restock.singleGoal = db.restock.singleGoal or 1
	db.restock.minProfitSilver = db.restock.minProfitSilver or 1
	db.restock.goals = db.restock.goals or {}
	return db
end

local function Merge(loaded, session)
	for id, recipe in pairs(session.recipes) do loaded.recipes[id] = recipe end
	for guid, char in pairs(session.chars) do
		local target = loaded.chars[guid]
		if target then
			target.name, target.realm, target.class = char.name, char.realm, char.class
			for id in pairs(char.recipes) do target.recipes[id] = true end
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

local function AdoptSavedData()
	if adopted then return true end
	local loaded = _G.CraftLedgerDB
	if type(loaded) ~= "table" then return false end
	adopted = true
	Normalize(loaded)
	Merge(loaded, ns.db)
	ns.db = loaded
	if ns.OnDataChanged then ns.OnDataChanged() end
	return true
end

ns.On("ADDON_LOADED", function(name)
	if name ~= ADDON or AdoptSavedData() then return end
	-- Saved data may still be on its way: keep checking for a while after loading.
	local tries = 0
	local function Check()
		tries = tries + 1
		if not AdoptSavedData() and tries < 120 then C_Timer.After(1, Check) end
	end
	C_Timer.After(1, Check)
end)

ns.On("PLAYER_LOGOUT", function()
	AdoptSavedData()
	_G.CraftLedgerDB = ns.db
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

function ns.Money(copper)
	if not copper then return "?" end
	local sign = copper < 0 and "-" or ""
	copper = math.floor(math.abs(copper) + 0.5)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then return ("%s%dg %02ds"):format(sign, g, s) end
	if s > 0 then return ("%s%ds %02dc"):format(sign, s, c) end
	return ("%s%dc"):format(sign, c)
end
