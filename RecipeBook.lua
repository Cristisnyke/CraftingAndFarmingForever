-- Crafting and Farming Forever :: RecipeBook
-- Every recipe in the game (RecipeSources.lua, from AllTheThings) against what your characters know: which are still
-- to learn, who can learn them now, and where each one comes from. The Profit tab's Recipes mode shows it.

local _, ns = ...
local Book = {}
ns.RecipeBook = Book

-- Short names for the Source column, and their order when sorting by it.
Book.KIND = {
	t = { label = "Trainer", order = 1 },
	v = { label = "Vendor", order = 2 },
	q = { label = "Quest", order = 3 },
	i = { label = "Dungeon", order = 4 },
	d = { label = "Drop", order = 5 },
	o = { label = "Treasure", order = 6 },
	w = { label = "World drop", order = 7 },
	x = { label = "Other", order = 8 },
}
-- Reputation needed, by the lowest value of each standing.
Book.STANDINGS = { { 42000, "Exalted" }, { 21000, "Revered" }, { 9000, "Honored" }, { 3000, "Friendly" } }
Book.FACTION = { Horde = 1, Alliance = 2 }
Book.FACTION_NAME = { [1] = "Horde", [2] = "Alliance" }
-- At most this many NPCs or zones named on one line of the tooltip.
Book.NAMES_SHOWN = 3

---------------------------------------------------------------------------
-- Names the client gives (NPCs, quests, zones): looked up when shown, NPCs remembered between sessions
---------------------------------------------------------------------------

function Book.NPCName(npcID)
	ns.db.npcNames = ns.db.npcNames or {}
	local cached = ns.db.npcNames[npcID]
	if cached then return cached end
	local getter = C_TooltipInfo and C_TooltipInfo.GetHyperlink
	if not getter then return nil end
	local ok, info = pcall(getter, ("unit:Creature-0-0-0-0-%d-0000000000"):format(npcID))
	local line = ok and type(info) == "table" and info.lines and info.lines[1]
	local name = line and line.leftText
	if type(name) ~= "string" or name == "" then return nil end
	ns.db.npcNames[npcID] = name
	return name
end

function Book.MapName(mapID)
	local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
	return info and info.name
end

function Book.QuestName(questID)
	local log = C_QuestLog
	local title = log and log.GetTitleForQuestID and log.GetTitleForQuestID(questID)
	if title and title ~= "" then return title end
	if log and log.RequestLoadQuestByID then pcall(log.RequestLoadQuestByID, questID) end
	return nil
end

function Book.InstanceName(source)
	if source.inst and EJ_GetInstanceInfo then
		local ok, name = pcall(EJ_GetInstanceInfo, source.inst)
		if ok and type(name) == "string" and name ~= "" then return name end
	end
	return Book.MapName(source.im)
end

function Book.FactionName(factionID)
	local rep = C_Reputation
	if rep and rep.GetFactionDataByID then
		local data = rep.GetFactionDataByID(factionID)
		if data and data.name then return data.name end
	end
	if GetFactionInfoByID then return (GetFactionInfoByID(factionID)) end
	return nil
end

function Book.CurrencyName(currencyID)
	local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(currencyID)
	return info and info.name
end

function Book.Standing(value)
	for _, standing in ipairs(Book.STANDINGS) do
		if value >= standing[1] then return standing[2] end
	end
	return nil -- Neutral or below: nothing to earn
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------

function Book.Data(recipeID)
	return ns.RecipeData[recipeID]
end

function Book.Profession(recipeID)
	local data = ns.RecipeData[recipeID]
	if data then return data.p end
	local recipe = ns.db.recipes[recipeID]
	if recipe and recipe.p then return recipe.p end
	for professionID, list in pairs(ns.db.recipeLists or {}) do
		if list.ids[recipeID] then return professionID end
	end
	return nil
end

local spellNames = {}
local function SpellName(spellID)
	if spellNames[spellID] then return spellNames[spellID] end
	local name
	if C_Spell and C_Spell.GetSpellName then
		name = C_Spell.GetSpellName(spellID)
	elseif GetSpellInfo then
		name = GetSpellInfo(spellID)
	end
	if name and name ~= "" then spellNames[spellID] = name end
	return name
end

-- The recipe's own name (what the profession window lists), else its recipe item's, else nil while loading.
function Book.Name(recipeID)
	local recipe = ns.db.recipes[recipeID]
	if recipe and recipe.n then return recipe.n end
	local name = SpellName(recipeID)
	if name then return name end
	local data = ns.RecipeData[recipeID]
	return data and data.i and ns.Items.Name(data.i) or nil
end

function Book.Icon(recipeID)
	local data = ns.RecipeData[recipeID]
	if data and data.i then return ns.Items.Icon(data.i) end
	local recipe = ns.db.recipes[recipeID]
	if recipe and recipe.o then return ns.Items.Icon(recipe.o) end
	local texture = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(recipeID))
		or (GetSpellTexture and GetSpellTexture(recipeID))
	return texture or 134400
end

-- The recipe item's auction house price, and whether it binds when picked up (then it can't be bought). The item's
-- own binding wins over AllTheThings' mark; nil price with bound false means none seen on the AH.
function Book.Price(recipeID)
	local data = ns.RecipeData[recipeID]
	if not (data and data.i) then return nil, nil end
	local sellable = ns.Items.CanSellOnAH(data.i)
	if sellable == nil then sellable = data.b ~= 1 end
	if not sellable then return nil, true end
	return ns.Prices.AH(data.i), false
end

-- Whether what it makes can go on the auction house: true, false (binds on pickup, or makes no item) or nil (not
-- known yet, or the item still loading). Then the item, false for no item, nil when not known.
function Book.Sellable(recipeID)
	local output = ns.Recipes.Output(recipeID)
	if output == false then return false, false end
	if not output then return nil, nil end
	return ns.Items.CanSellOnAH(output), output
end

---------------------------------------------------------------------------
-- Characters
---------------------------------------------------------------------------

-- The professions a character has: those whose skill was read, and those of recipes it knows.
function Book.CharProfessions(charKey)
	local set = {}
	local char = ns.db.chars[charKey]
	if not char then return set end
	for professionID in pairs(char.skill or {}) do set[professionID] = true end
	for recipeID in pairs(char.recipes or {}) do
		local recipe = ns.db.recipes[recipeID]
		if recipe and recipe.p then set[recipe.p] = true end
	end
	return set
end

-- learned | learn (has the skill, or its skill isn't known yet) | skill (needs more) | none (doesn't have the
-- profession); then the skill needed and the skill the character has (nil when not read yet).
-- professions (optional): Book.CharProfessions(charKey), when the caller already has it.
function Book.Status(charKey, recipeID, professions)
	if ns.Recipes.Knows(charKey, recipeID) then return "learned" end
	local professionID = Book.Profession(recipeID)
	local char = ns.db.chars[charKey]
	professions = professions or Book.CharProfessions(charKey)
	if not (char and professionID and professions[professionID]) then return "none" end
	local data = ns.RecipeData[recipeID]
	local need = data and data.s
	local skill = char.skill and char.skill[professionID]
	local have = skill and skill.level
	if need and have and have < need then return "skill", need, have end
	return "learn", need, have
end

function Book.CharFaction(charKey)
	local char = ns.db.chars[charKey]
	return char and Book.FACTION[char.faction] or nil
end

-- A recipe's sources for a character: the other faction's left out, unless they're all there is.
function Book.Sources(recipeID, faction)
	local data = ns.RecipeData[recipeID]
	if not data then return {} end
	if not faction then return data.w end
	local mine = {}
	for _, source in ipairs(data.w) do
		if not source.fa or source.fa == faction then table.insert(mine, source) end
	end
	return #mine > 0 and mine or data.w
end

-- The Source column: the first source's kind, and how many other kinds there are.
function Book.SourceLabel(sources)
	local first = sources[1]
	if not first then return "Unknown", 99 end
	local kinds, others = { [first.k] = true }, 0
	for _, source in ipairs(sources) do
		if not kinds[source.k] then
			kinds[source.k] = true
			others = others + 1
		end
	end
	local kind = Book.KIND[first.k] or Book.KIND.x
	local label = first.ev and (kind.label .. "*") or kind.label
	if others > 0 then label = ("%s +%d"):format(label, others) end
	return label, kind.order
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

-- Every recipe of the professions in the set: AllTheThings', plus any the game listed or a character knows that
-- AllTheThings doesn't have yet. When the game's own list of a profession was seen (it lists unlearned recipes too),
-- AllTheThings' recipes missing from it aren't in this game and are left out; hidden counts those.
function Book.RecipeIDs(professions)
	local ids, seen, hidden = {}, {}, 0
	local lists = ns.db.recipeLists or {}
	local function Add(recipeID)
		if seen[recipeID] then return end
		seen[recipeID] = true
		table.insert(ids, recipeID)
	end
	for recipeID, data in pairs(ns.RecipeData) do
		if professions[data.p] then
			local list = lists[data.p]
			if list and not list.ids[recipeID] and not Book.KnownByAnyone(recipeID) then
				hidden = hidden + 1
			else
				Add(recipeID)
			end
		end
	end
	for professionID, list in pairs(lists) do
		if professions[professionID] then
			for recipeID in pairs(list.ids) do Add(recipeID) end
		end
	end
	for _, char in pairs(ns.db.chars) do
		for recipeID in pairs(char.recipes or {}) do
			local recipe = ns.db.recipes[recipeID]
			if recipe and professions[recipe.p] then Add(recipeID) end
		end
	end
	return ids, hidden
end

function Book.KnownByAnyone(recipeID)
	for key in pairs(ns.db.chars) do
		if ns.Recipes.Knows(key, recipeID) then return true end
	end
	return false
end

local STATUS_RANK = { learn = 1, skill = 2, learned = 3, none = 4 }

-- opts: professionID (nil for every profession of the characters looked at), who ("me" or "all"), me (charKey),
-- showLearned, search (lowercase text), hideBound (leave out recipes whose craft can't go on the auction house).
-- Each row: recipeID, name, skill, status (the best of the characters looked at), chars = { { key, status, need,
-- have } } for those with the profession, sources, source (label), sourceOrder, price, bound.
-- info: learnedHidden, notInGame, learnNow, noProfession (the one character looked at lacks the tab's profession),
-- boundHidden and unchecked (what it makes not known yet, so kept) with hideBound.
function Book.Rows(opts)
	local keys = {}
	if opts.who == "all" then
		for key in pairs(ns.db.chars) do table.insert(keys, key) end
		table.sort(keys)
	else
		keys[1] = opts.me
	end
	local professions = {}
	if opts.professionID then
		professions[opts.professionID] = true
	else
		for _, key in ipairs(keys) do
			for professionID in pairs(Book.CharProfessions(key)) do professions[professionID] = true end
		end
	end
	local info = { learnedHidden = 0, learnNow = 0, boundHidden = 0, unchecked = 0 }
	if opts.professionID and opts.who ~= "all" and not Book.CharProfessions(opts.me)[opts.professionID] then
		info.noProfession = true
	end
	local ids
	ids, info.notInGame = Book.RecipeIDs(professions)
	local faction = Book.CharFaction(opts.me)
	local has = {}
	for _, key in ipairs(keys) do has[key] = Book.CharProfessions(key) end
	local rows = {}
	for _, recipeID in ipairs(ids) do
		local chars, best = {}, nil
		for _, key in ipairs(keys) do
			local status, need, have = Book.Status(key, recipeID, has[key])
			if status ~= "none" or #keys == 1 then
				table.insert(chars, { key = key, status = status, need = need, have = have })
				if not best or STATUS_RANK[status] < STATUS_RANK[best] then best = status end
			end
		end
		local name = Book.Name(recipeID)
		local matches = not opts.search or opts.search == ""
			or (name and name:lower():find(opts.search, 1, true) ~= nil)
		local sellable = true
		if best and matches and opts.hideBound and not (best == "learned" and not opts.showLearned) then
			sellable = Book.Sellable(recipeID)
			if sellable == nil then info.unchecked = info.unchecked + 1 end
		end
		if best and matches then
			if best == "learned" and not opts.showLearned then
				info.learnedHidden = info.learnedHidden + 1
			elseif sellable == false then
				info.boundHidden = info.boundHidden + 1
			else
				local data = ns.RecipeData[recipeID]
				local sources = Book.Sources(recipeID, faction)
				local label, order = Book.SourceLabel(sources)
				local price, bound = Book.Price(recipeID)
				if best == "learn" then info.learnNow = info.learnNow + 1 end
				table.insert(rows, { recipeID = recipeID, name = name, skill = data and data.s, status = best, chars = chars,
					sources = sources, source = label, sourceOrder = order, price = price, bound = bound })
			end
		end
	end
	return rows, info
end

-- Sorting: key name | chance (skill needed) | cost (source) | profit (recipe's AH price). Missing values go last;
-- ties by skill, then name.
function Book.Sort(rows, key, ascending)
	local function Value(row)
		if key == "name" then return row.name and row.name:lower() end
		if key == "cost" then return row.sourceOrder end
		if key == "profit" then return row.price end
		return row.skill
	end
	local values = {}
	for _, row in ipairs(rows) do values[row] = Value(row) end
	table.sort(rows, function(a, b)
		local va, vb = values[a], values[b]
		if va ~= vb then
			if va == nil then return false end
			if vb == nil then return true end
			if ascending then return va < vb end
			return va > vb
		end
		local sa, sb = a.skill or 0, b.skill or 0
		if sa ~= sb then return sa < sb end
		local na, nb = a.name or "~", b.name or "~"
		if na ~= nb then return na < nb end
		return a.recipeID < b.recipeID
	end)
	return rows
end

---------------------------------------------------------------------------
-- New to learn: what lights the Profit tab and the Recipes button
---------------------------------------------------------------------------

-- Recipes a character can learn right now: its skill in the profession was read and is high enough, not learned.
-- New ones are those it couldn't the last time Recipes was open on it (char.learnableSeen), like an unread
-- changelog: always-learnable recipes (a paladin has over a hundred) would otherwise keep it lit for good.
local newCache = {}
Book.fresh = {} -- became learnable while you played this session: "new" on their rows

function Book.Learnable(charKey)
	local set = {}
	local professions = Book.CharProfessions(charKey)
	for _, recipeID in ipairs((Book.RecipeIDs(professions))) do
		local status, _, have = Book.Status(charKey, recipeID, professions)
		if status == "learn" and have then set[recipeID] = true end
	end
	return set
end

-- What the answer depends on, so it's only worked out again when that changes.
local function Signature(char)
	local parts = {}
	for professionID, skill in pairs(char.skill or {}) do parts[#parts + 1] = professionID .. ":" .. tostring(skill.level) end
	table.sort(parts)
	local known, lists = 0, 0
	for _ in pairs(char.recipes or {}) do known = known + 1 end
	for _, list in pairs(ns.db.recipeLists or {}) do lists = lists + (list.at or 0) end
	return table.concat(parts, ",") .. "|" .. known .. "|" .. lists
end

function Book.NewCount(charKey)
	local char = charKey and ns.db and ns.db.chars[charKey]
	if not char then return 0 end
	local signature = Signature(char)
	local cached = newCache[charKey]
	if cached and cached.signature == signature then return cached.count end
	local seen, count = char.learnableSeen or {}, 0
	for recipeID in pairs(Book.Learnable(charKey)) do
		if not seen[recipeID] then count = count + 1 end
	end
	newCache[charKey] = { signature = signature, count = count }
	return count
end

-- The Recipes list was looked at: what's learnable now is no longer new. The very first look marks nothing "new"
-- on the rows (all of it would be).
function Book.MarkSeen(charKey)
	local char = charKey and ns.db.chars[charKey]
	if not char or Book.NewCount(charKey) == 0 then return false end
	local first = char.learnableSeen == nil
	local seen = char.learnableSeen or {}
	for recipeID in pairs(Book.Learnable(charKey)) do
		if not seen[recipeID] then
			seen[recipeID] = true
			if not first then Book.fresh[recipeID] = true end
		end
	end
	char.learnableSeen = seen
	newCache[charKey] = nil
	return true
end

---------------------------------------------------------------------------
-- Where it comes from, in words
---------------------------------------------------------------------------

local function Names(list, lookup, fallback)
	local names, missing = {}, false
	for index, id in ipairs(list or {}) do
		if index > Book.NAMES_SHOWN then
			table.insert(names, ("and %d more"):format(#list - Book.NAMES_SHOWN))
			break
		end
		local name = lookup(id)
		if name then table.insert(names, name) else missing = true end
	end
	if #names == 0 then return fallback, missing end
	return table.concat(names, ", "), missing
end

local function CostText(cost)
	local kind, id, count = cost[1], cost[2], cost[3]
	if kind == "g" then return ns.Money(count) end
	local name = kind == "c" and Book.CurrencyName(id) or kind == "i" and ns.Items.Name(id)
	return ("%d %s"):format(count, name or (kind == "c" and "tokens" or "items")), name == nil
end

-- One line per source, for the tooltip: { text, detail }. missing is true when a name is still loading, so the
-- tooltip can be drawn again a moment later.
-- The main line for each kind of source. npcs and where are already in words (nil / "" when there are none).
-- Returns the text and whether a name is still loading.
local SOURCE_TEXT = {
	t = function(source, npcs, where, professionName)
		if not npcs then return ("Trainer: any %s trainer"):format(professionName) end
		local place = source.inst and (" in " .. (Book.InstanceName(source) or "a dungeon")) or where
		return ("Trainer: %s%s"):format(npcs, place)
	end,
	v = function(_, npcs, where) return ("Vendor: %s%s"):format(npcs or "a vendor", where) end,
	q = function(source, npcs, where)
		local quests, missing = Names(source.q, Book.QuestName, "a quest")
		return ("Quest: %s%s%s"):format(quests, npcs and (" from " .. npcs) or "", where), missing
	end,
	i = function(source, npcs)
		local from = npcs and (", from " .. npcs) or source.boss and ", any boss" or ""
		return ("Dungeon drop: %s%s"):format(Book.InstanceName(source) or "a dungeon", from)
	end,
	d = function(source, npcs, where)
		if not npcs then return ("Drop: mobs%s"):format(where) end
		return ("%s: %s%s"):format(source.rare and "Rare mob" or "Drop", npcs, where)
	end,
	o = function(source, _, where) return ("Found in %s%s"):format(source.o and source.o[1] or "a treasure", where) end,
	w = function() return "World drop: any mob around the right level, anywhere" end,
	x = function(source) return source.d or source.h or "Somewhere else" end,
}

-- The second line: costs, limited supply, reputation, container, faction, holiday. Nil when there's nothing to say.
local function SourceDetails(source, charKey)
	local details, missing = {}, false
	for _, cost in ipairs(source.c or {}) do
		local costText, costMissing = CostText(cost)
		missing = missing or costMissing
		table.insert(details, "costs " .. costText)
	end
	if source.l then table.insert(details, "limited supply") end
	local standing = source.rep and Book.Standing(source.rep[2])
	if standing then
		table.insert(details, ("needs %s with %s"):format(standing, Book.FactionName(source.rep[1]) or "a faction"))
	end
	if source.ci then
		local container = ns.Items.Name(source.ci)
		missing = missing or container == nil
		table.insert(details, "comes in " .. (container or "a container"))
	end
	-- Said only when it isn't the character's own side (all the sources are the other side's, or it's unknown).
	if source.fa and source.fa ~= Book.CharFaction(charKey) then
		table.insert(details, Book.FACTION_NAME[source.fa] .. " only")
	end
	if source.ev then table.insert(details, "during " .. source.ev) end
	return #details > 0 and table.concat(details, ", ") or nil, missing
end

function Book.SourceLines(recipeID, charKey)
	local lines, missing = {}, false
	if not ns.RecipeData[recipeID] then
		table.insert(lines, { text = "Not in AllTheThings' data yet, so where it comes from isn't known." })
		return lines, missing
	end
	local professionID = Book.Profession(recipeID)
	local professionName = professionID and ns.Recipes.ProfessionName(professionID) or "profession"
	for _, source in ipairs(Book.Sources(recipeID, Book.CharFaction(charKey))) do
		local npcs, npcMissing = Names(source.n, Book.NPCName, nil)
		local zones = Names(source.m, Book.MapName, nil)
		local text, textMissing = (SOURCE_TEXT[source.k] or SOURCE_TEXT.x)(source, npcs, zones and (" in " .. zones) or "",
			professionName)
		local detail, detailMissing = SourceDetails(source, charKey)
		missing = missing or npcMissing or textMissing or detailMissing
		table.insert(lines, { text = text, detail = detail, note = source.d and source.k ~= "x" and source.d or nil })
	end
	return lines, missing
end
