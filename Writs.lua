-- Crafting and Farming Forever :: Writs
-- Craftsman's Writs: what each one costs to hand in (the writ plus the crafted item it wants) against its reward,
-- the writs picked to do, and an Auctionator list for scanning or buying them.

local _, ns = ...

local Writs = {}
ns.Writs = Writs

ns.WRIT_LIST = "Crafting and Farming Forever Writs"

Writs.TIERS = { "Journeyman", "Expert", "Artisan" }
-- A writ's daily quest has the writ's item ID less this.
local QUEST_OFFSET = 169800

-- { writ item, wanted item, level, hand-in zone, count, zone is a guess }. From Wowhead's Forever data, 2026-11-14.
-- Zones without the guess mark were reported by players; the marked ones follow the pattern those reports show
-- (each profession's writs of a level go to the same zones in the same order). No zone: not known yet.
local DATA = {
	{ 264011, 3391, 1, "Alterac Mountains" },
	{ 264012, 3383, 1, "Arathi Highlands" },
	{ 264013, 3385, 1, "Ashenvale" },
	{ 264014, 6048, 1, "Duskwood" },
	{ 264015, 5634, 1, "Hillsbrad Foothills" },
	{ 264016, 3390, 1, "Stonetalon Mountains" },
	{ 264017, 3388, 1, "Stranglethorn Vale" },
	{ 264018, 8951, 1, "Thousand Needles" },
	{ 264019, 5996, 1, "Wetlands" },
	{ 264020, 5540, 1, "Alterac Mountains" },
	{ 264021, 11128, 1, "Arathi Highlands" },
	{ 264022, 5541, 1, "Ashenvale" },
	{ 264023, 15869, 1, "Duskwood" },
	{ 264024, 3491, 1, "Hillsbrad Foothills" },
	{ 264025, 2865, 1, "Stonetalon Mountains" },
	{ 264026, 3485, 1, "Stranglethorn Vale" },
	{ 264027, 3848, 1, "Thousand Needles" },
	{ 264028, 3484, 1, "Wetlands" },
	{ 264029, 5507, 1, "Alterac Mountains" },
	{ 264030, 4384, 1, "Arathi Highlands" },
	{ 264031, 4383, 1, "Ashenvale" },
	{ 264032, 4381, 1, "Duskwood" },
	{ 264033, 6712, 1, "Hillsbrad Foothills" },
	{ 264034, 4373, 1, "Stonetalon Mountains" },
	{ 264035, 7506, 1, "Stranglethorn Vale" },
	{ 264036, 4380, 1, "Thousand Needles" },
	{ 264037, 8069, 1, "Wetlands", 200 },
	{ 264038, 18662, 1, "Alterac Mountains" },
	{ 264039, 5958, 1, "Arathi Highlands" },
	{ 264040, 7349, 1, "Ashenvale" },
	{ 264041, 2317, 1, "Duskwood" },
	{ 264042, 7358, 1, "Hillsbrad Foothills" },
	{ 264043, 7371, 1, "Stonetalon Mountains" },
	{ 264044, 4252, 1, "Stranglethorn Vale" },
	{ 264045, 4254, 1, "Thousand Needles" },
	{ 264046, 7284, 1, "Wetlands" },
	{ 264047, 5766, 1, "Alterac Mountains" },
	{ 264048, 6263, 1, "Arathi Highlands" },
	{ 264049, 7048, 1, "Ashenvale" },
	{ 264050, 4245, 1, "Duskwood" },
	{ 264051, 4317, 1, "Alterac Mountains" },
	{ 264052, 4313, 1, "Stonetalon Mountains" },
	{ 264053, 10048, 1, "Stranglethorn Vale" },
	{ 264054, 6264, 1, "Thousand Needles" },
	{ 264055, 4321, 1, "Wetlands" },
	{ 264056, 6050, 2, "Badlands" },
	{ 264057, 3823, 2, "Desolace" },
	{ 264058, 4623, 2, "Dustwallow Marsh" },
	{ 264059, 6052, 2, "Felwood" },
	{ 264060, 10592, 2, "Feralas" },
	{ 264061, 5633, 2, "Moonglade" },
	{ 264062, 3827, 2, "Ashenvale" },
	{ 264063, 6049, 2, "Searing Gorge" },
	{ 264064, 3824, 2, "Swamp of Sorrows" },
	{ 264065, 9061, 2, "Azshara" },
	{ 264066, 8949, 2, nil },
	{ 264067, 9144, 2, "Un'Goro Crater" },
	{ 264068, 7922, 2, "Badlands", 1, true },
	{ 264069, 9060, 2, "Desolace" },
	{ 264070, 6041, 2, "Swamp of Sorrows" },
	{ 264071, 7928, 2, "Felwood" },
	{ 264072, 7942, 2, "Feralas", 1, true },
	{ 264073, 3853, 2, "Moonglade" },
	{ 264074, 3837, 2, "Riverglades" },
	{ 264075, 7964, 2, "Searing Gorge", 1, true },
	{ 264076, 7943, 2, "Swamp of Sorrows", 1, true },
	{ 264077, 11144, 2, "Tanaris", 1, true },
	{ 264078, 9366, 2, nil },
	{ 264079, 7941, 2, "Un'Goro Crater", 1, true },
	{ 264080, 4396, 2, "Badlands", 1, true },
	{ 264081, 4392, 2, "Desolace" },
	{ 264082, 4393, 2, "Dustwallow Marsh" },
	{ 264083, 4395, 2, "Felwood", 1, true },
	{ 264084, 10501, 2, "Feralas" },
	{ 264085, 10560, 2, "Moonglade" },
	{ 264086, 4852, 2, "Riverglades" },
	{ 264087, 10500, 2, "Searing Gorge", 1, true },
	{ 264088, 10514, 2, "Swamp of Sorrows", 1, true },
	{ 264089, 10498, 2, "Tanaris", 1, true },
	{ 264090, 11590, 2, nil },
	{ 264091, 16005, 2, "Un'Goro Crater", 1, true },
	{ 264092, 8174, 2, "Badlands", 1, true },
	{ 264093, 5965, 2, "Desolace" },
	{ 264094, 7378, 2, "Dustwallow Marsh" },
	{ 264095, 8214, 2, "Felwood", 1, true },
	{ 264096, 8210, 2, "Feralas" },
	{ 264097, 8217, 2, "Moonglade" },
	{ 264098, 7391, 2, "Riverglades" },
	{ 264099, 8192, 2, "Searing Gorge", 1, true },
	{ 264100, 8201, 2, "Swamp of Sorrows", 1, true },
	{ 264101, 8200, 2, "Tanaris" },
	{ 264102, 8189, 2, nil },
	{ 264103, 8218, 2, "Un'Goro Crater" },
	{ 264104, 10050, 2, "Badlands", 1, true },
	{ 264105, 10023, 2, "Desolace", 1, true },
	{ 264106, 7063, 2, "Dustwallow Marsh" },
	{ 264107, 10004, 2, "Felwood" },
	{ 264108, 22246, 2, "Feralas", 1, true },
	{ 264109, 4329, 2, "Moonglade" },
	{ 264110, 9998, 2, "Riverglades", 1, true },
	{ 264111, 10009, 2, "Searing Gorge", 1, true },
	{ 264112, 10052, 2, "Swamp of Sorrows", 1, true },
	{ 264113, 10008, 2, "Tanaris", 1, true },
	{ 264114, 10042, 2, nil },
	{ 264115, 7061, 2, "Un'Goro Crater" },
	{ 264116, 9224, 3, nil },
	{ 264117, 12190, 3, nil },
	{ 264118, 13457, 3, nil },
	{ 264119, 9233, 3, "Deadwind Pass" },
	{ 264120, 9088, 3, nil },
	{ 264121, 13513, 3, nil },
	{ 264122, 3387, 3, nil },
	{ 264123, 18253, 3, nil },
	{ 264124, nil, 3, "Winterspring" },
	{ 264125, 12417, 3, nil },
	{ 264126, 12416, 3, nil },
	{ 264127, 7929, 3, nil },
	{ 264128, 7969, 3, "Deadwind Pass" },
	{ 264129, 12422, 3, nil },
	{ 264130, 20549, 3, nil },
	{ 264131, 12775, 3, nil },
	{ 264132, 15872, 3, nil },
	{ 264133, 7947, 3, "Winterspring", 1, true },
	{ 264134, 16023, 3, nil },
	{ 264135, 10504, 3, nil },
	{ 264136, 15996, 3, nil },
	{ 264137, 18645, 3, "Deadwind Pass", 1, true },
	{ 264138, 18587, 3, nil },
	{ 264139, 18232, 3, nil },
	{ 264140, 18631, 3, nil },
	{ 264141, 10548, 3, nil },
	{ 264142, 21277, 3, "Winterspring", 1, true },
	{ 264143, 15087, 3, nil },
	{ 264144, 18258, 3, nil },
	{ 264145, 15053, 3, nil },
	{ 264146, 15094, 3, "Deadwind Pass", 1, true },
	{ 264147, 15084, 3, nil },
	{ 264148, 15075, 3, nil },
	{ 264149, 15080, 3, nil },
	{ 264150, 15092, 3, nil },
	{ 264151, 15071, 3, "Winterspring", 1, true },
	{ 264152, 14130, 3, nil },
	{ 264153, 14046, 3, nil },
	{ 264154, 13864, 3, nil },
	{ 264155, 10036, 3, "Deadwind Pass", 1, true },
	{ 264156, 14108, 3, nil },
	{ 264157, 22251, 3, nil },
	{ 264158, 10025, 3, nil },
	{ 264159, 14141, 3, nil },
	{ 264160, 21340, 3, "Winterspring", 1, true },
}

Writs.list = {}
for _, entry in ipairs(DATA) do
	table.insert(Writs.list, {
		id = entry[1], item = entry[2], tier = entry[3], zone = entry[4], count = entry[5] or 1, zoneGuess = entry[6],
		-- The first writ's quest isn't in Wowhead's data, so its number is unknown.
		quest = entry[1] ~= 264011 and (entry[1] - QUEST_OFFSET) or nil,
	})
end

local function Saved()
	local saved = ns.db.writs
	saved.picked = saved.picked or {}
	saved.queued = saved.queued or {}
	return saved
end

function Writs.IsPicked(writID) return Saved().picked[writID] == true end

function Writs.PickedCount()
	local count = 0
	for _ in pairs(Saved().picked) do count = count + 1 end
	return count
end

function Writs.Toggle(writID)
	local saved = Saved()
	if saved.picked[writID] then
		saved.picked[writID], saved.queued[writID] = nil, nil
	else
		saved.picked[writID] = true
	end
	ns.UI.Refresh("writs")
end

-- Handed in today on this character. The client may not have the quest call, so no answer counts as not done.
function Writs.Done(writ)
	if not (writ.quest and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) then return false end
	local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, writ.quest)
	return ok and done == true
end

-- The writ's name without "Craftsman's Writ: ", for a writ whose item has no ID here.
function Writs.Name(writ)
	local name = ns.Items.Name(writ.id)
	return name and (name:match(":%s*(.+)$") or name) or nil
end

-- Every writ with its costs, for the level (nil = all) and, with craftableOnly, only items a character can make.
function Writs.Rows(tier, craftableOnly)
	local ctx = ns.NewContext()
	local rows = {}
	for _, writ in ipairs(Writs.list) do
		if not tier or writ.tier == tier then
			local row = ns.Planner.Writ(ctx, writ)
			if row.craftable or not craftableOnly then
				row.picked = Writs.IsPicked(writ.id)
				row.done = Writs.Done(writ)
				row.haveWrit = ns.Stock.Own(writ.id) > 0
				row.haveItem = writ.item and ns.Stock.Own(writ.item) >= writ.count or false
				table.insert(rows, row)
			end
		end
	end
	return rows
end

-- Replaces a list in Auctionator. Returns how many searches it holds and how many names were still loading. The
-- crates list uses it too.
local function WriteList(listName, wanted)
	local strings, loading = {}, 0
	for itemID, quantity in pairs(wanted) do
		local name = ns.Items.Name(itemID)
		if name then
			table.insert(strings, ns.Shopping.SearchString(name, quantity ~= true and quantity or nil))
		elseif not ns.Items.IsMissing(itemID) then
			loading = loading + 1
		end
	end
	table.sort(strings)
	if #strings > 0 then Auctionator.API.v1.CreateShoppingList(ns.name, listName, strings) end
	return #strings, loading
end
Writs.WriteList = WriteList

local function Report(listName, ok, count, loading, extra)
	if not ok then
		ns.Print("Could not write the Auctionator list: " .. tostring(count))
	elseif count == 0 then
		ns.Print(loading > 0 and "The names are still loading. Try again in a moment." or "Nothing to list.")
	else
		ns.Print(("Auctionator's list \"%s\" now has %d searches%s. Search it in the Shopping tab at the auction house.%s")
			:format(listName, count, extra or "",
				loading > 0 and (" %d names were still loading: press again in a moment."):format(loading) or ""))
	end
end
Writs.Report = Report

-- Every shown writ and the item it wants, with no amounts: searching the list refreshes their prices.
function Writs.ListForScan(rows)
	local wanted = {}
	for _, row in ipairs(rows) do
		wanted[row.writ.id] = true
		if row.writ.item then wanted[row.writ.item] = true end
	end
	local ok, count, loading = pcall(WriteList, ns.WRIT_LIST, wanted)
	Report(ns.WRIT_LIST, ok, count, loading)
end

-- The picked writs you don't hold yet, and their items where buying is the cheapest way. Items that are cheaper to
-- craft go on the craft queue instead, once per pick, so its own shopping list covers their materials.
function Writs.ShopPicked()
	local saved = Saved()
	local wanted, queued = {}, 0
	for _, row in ipairs(Writs.Rows()) do
		local writ = row.writ
		if row.picked and not row.done then
			if not row.haveWrit then wanted[writ.id] = 1 end
			if writ.item and not row.haveItem then
				if row.kind == "craft" and row.recipeID then
					if not saved.queued[writ.id] then
						saved.queued[writ.id] = true
						ns.Queue.Add(row.recipeID, row.crafts or 1)
						queued = queued + 1
					end
				elseif row.kind ~= "vendor" then
					wanted[writ.item] = (wanted[writ.item] or 0) + writ.count
				end
			end
		end
	end
	local ok, count, loading = pcall(WriteList, ns.WRIT_LIST, wanted)
	if ok and count == 0 and queued > 0 then
		ns.Print(("%d crafts added to the queue. Nothing to buy for the picked writs."):format(queued))
	else
		Report(ns.WRIT_LIST, ok, count, loading, queued > 0 and (", and %d crafts were added to the queue"):format(queued) or "")
	end
	ns.UI.Refresh("writs")
end
