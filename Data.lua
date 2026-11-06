-- CraftLedger :: Data
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
	end)
end)

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------

local Prices = {}
ns.Prices = Prices

-- Well-known unlimited vendor reagents, so they count as vendor items before the first merchant visit. Learned
-- merchant prices from Auctionator take priority. Seed values from CraftProfit by Vystery (MIT).
local VENDOR_SEED = {
	[2320] = 10, [2321] = 100, [4291] = 500, [8343] = 2000, [14341] = 5000,
	[2324] = 25, [2604] = 50, [6260] = 50, [2605] = 100, [4340] = 100, [6261] = 250, [4341] = 500, [4342] = 2500,
	[2880] = 100, [3466] = 2000, [3857] = 500,
	[3371] = 20, [3372] = 200, [8925] = 2000,
	[6217] = 124,
	[2678] = 10, [2692] = 20, [3713] = 40, [159] = 25, [1179] = 125,
	[4289] = 5, [4470] = 38,
}

function Prices.AH(itemID)
	return Auctionator.API.v1.GetAuctionPriceByItemID(ADDON, itemID)
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
		ns.Print("Open the auction house to scan.")
		return
	end
	local frame
	if Auctionator.Config.Get(Auctionator.Config.Options.REPLICATE_SCAN) then
		frame = state.FullScanFrameRef
	else
		frame = state.IncrementalScanFrameRef
	end
	if frame then frame:InitiateScan() else ns.Print("Auctionator's scanner is not ready yet. Try again in a moment.") end
end

---------------------------------------------------------------------------
-- Stock
---------------------------------------------------------------------------

local Stock = {}
ns.Stock = Stock

-- Bags, bank and reagent bank of the logged-in character.
function Stock.Own(itemID)
	return C_Item.GetItemCount(itemID, true, false, true, false) or 0
end

local function SyndicatorAPI()
	local api = _G.Syndicator and _G.Syndicator.API
	if type(api) ~= "table" or type(api.GetInventoryInfoByItemID) ~= "function"
		or type(api.GetCurrentCharacter) ~= "function" or type(api.IsReady) ~= "function" then
		return nil
	end
	local ok, ready = pcall(api.IsReady)
	return ok and ready and api or nil
end

function Stock.HasSyndicator()
	return SyndicatorAPI() ~= nil
end

-- Bags and bank of other characters on the connected realm and same faction, since those can mail to this one.
function Stock.Alts(itemID)
	local api = SyndicatorAPI()
	if not api then return {} end
	local ok, info = pcall(api.GetInventoryInfoByItemID, itemID, true, true)
	if not ok or type(info) ~= "table" then return {} end
	local me = api.GetCurrentCharacter()
	local result = {}
	for _, char in ipairs(info.characters or {}) do
		local key = char.realmNormalized and char.realmNormalized ~= "" and (char.character .. "-" .. char.realmNormalized)
			or char.character
		local count = (char.bags or 0) + (char.bank or 0)
		if key ~= me and count > 0 then
			table.insert(result, { name = char.character or key, count = count })
		end
	end
	return result
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------

local Recipes = {}
ns.Recipes = Recipes
local readThisSession = {}

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
Recipes.ProfessionInfo = ProfessionInfo

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

local function BasicReagentType()
	return Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 0
end

local function ItemIDFromLink(link)
	return link and tonumber(link:match("item:(%d+)")) or nil
end

-- Compact copy of a recipe, so costs work for professions and characters not currently open.
function Recipes.Read(recipeID, recipeInfo, professionID, professionName)
	local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
	if type(schematic) ~= "table" then return nil end
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
	local recipe = {
		n = recipeInfo and recipeInfo.name or schematic.name,
		o = output,
		qmin = schematic.quantityMin or 1,
		qmax = schematic.quantityMax or schematic.quantityMin or 1,
		p = professionID,
		pn = professionName,
		r = slots,
		x = usesCurrency or nil,
	}
	ns.db.recipes[recipeID] = recipe
	return recipe
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

	local learned = {}
	for _, recipeID in ipairs(ids) do
		local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
		if info and info.learned then
			learned[recipeID] = true
			if not readThisSession[recipeID] then
				if Recipes.Read(recipeID, info, ProfessionKey(base)) then
					readThisSession[recipeID] = true
				end
			end
		end
	end
	-- An empty answer means the list isn't ready yet, not that everything was unlearned.
	if not next(learned) then return end

	local baseKey = ProfessionKey(base)
	local changed = false
	for recipeID in pairs(char.recipes) do
		local recipe = ns.db.recipes[recipeID]
		if not learned[recipeID] and recipe and recipe.p == baseKey then
			char.recipes[recipeID] = nil
			changed = true
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

ns.On("TRADE_SKILL_LIST_UPDATE", RequestScan)
ns.On("TRADE_SKILL_DATA_SOURCE_CHANGED", RequestScan)
ns.On("TRADE_SKILL_SHOW", RequestScan)

-- Recipes known by each output item, across every character recorded so far.
function Recipes.KnownMap()
	local known, seen = {}, {}
	for _, char in pairs(ns.db.chars) do
		for recipeID in pairs(char.recipes) do
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

function Recipes.Knows(charKey, recipeID)
	local char = charKey and ns.db.chars[charKey]
	return char ~= nil and char.recipes[recipeID] == true
end

-- The logged-in character when it knows the recipe, then the preferred one, then anyone who does.
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
