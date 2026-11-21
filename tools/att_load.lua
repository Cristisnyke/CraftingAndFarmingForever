-- Reads AllTheThings' data files (MIT licensed) outside the game, for the generators gen_sources.lua and
-- gen_recipes.lua. Everything that depends on AllTheThings' file format is here, so an AllTheThings update that
-- changes it is fixed in one place.
--   local ATT = dofile("tools/att_load.lua")
--   local data = ATT.Load("<AddOns>/AllTheThings/db/Camelot", { "Zones", "Instances" })
--   data.categories: category name -> tree of { kind, id, fields }; fields.g holds the children
--   data.objectNames: object ID -> name; data.headerNames: header ID -> name (only plain strings)
--   data.version: the AllTheThings version from its toc, or "unknown"
-- Forever loads the Camelot data set, which is what the awp=16001 entries in it show.

local ATT = {}

-- Which constructor makes which kind of node. Any other Create* function makes an "other" node.
ATT.KIND_OF_CONSTRUCTOR = {
	CreateItem = "item", CreateItemSource = "itemsource", CreateNPC = "npc", CreateObject = "object", CreateMap = "map",
	CreateProfession = "prof", CreateQuest = "quest", CreateInstance = "inst", CreateSpell = "spell",
	CreateRecipe = "recipe", CreateAchievement = "ach", CreateHeader = "header", CreateCustomHeader = "header",
}

local function NODE_META(fields)
	return { __index = fields, __newindex = fields }
end

local function Node(kind)
	return function(id, a, b)
		local fields = a
		if kind == "itemsource" then
			kind, id, fields = "item", a, b
		end
		fields = type(fields) == "table" and fields or {}
		-- Some files run small functions over their nodes as they build them (t.g, o.qgs = ...), so a node also reads
		-- and writes its fields as if they were its own.
		return setmetatable({ kind = kind, id = id, fields = fields }, NODE_META(fields))
	end
end

function ATT.ReadFile(path)
	local file = assert(io.open(path, "rb"))
	local text = file:read("*a")
	file:close()
	return (text:gsub("^\239\187\191", ""))
end

-- A table of the localization file, by its opening text. The file needs far more of the add-on to run, so the one
-- table is cut out and run alone. A few values are looked up from the client when the add-on loads; those come out
-- as nil here and are left out.
local function LocalizationTable(text, pattern)
	local body = text:match(pattern)
	if not body then return {} end
	local unknown
	unknown = setmetatable({}, {
		__index = function() return unknown end,
		__call = function() return nil end,
		__concat = function() return unknown end,
	})
	local chunk = assert(loadstring("return " .. body))
	setfenv(chunk, setmetatable({}, { __index = function() return unknown end }))
	local ok, result = pcall(chunk)
	if not ok or type(result) ~= "table" then return {} end
	local clean = {}
	for key, value in pairs(result) do
		if type(value) == "string" then clean[key] = value end
	end
	return clean
end

-- The version in AllTheThings' toc, two folders up from the data set.
function ATT.Version(root)
	local addon = root:gsub("/+$", ""):gsub("/[^/]+/[^/]+$", "")
	local file = io.open(addon .. "/AllTheThings.toc", "rb")
	if not file then return "unknown" end
	local text = file:read("*a")
	file:close()
	return text:match("## Version:%s*([^\r\n]+)") or "unknown"
end

function ATT.Load(root, files)
	local app = setmetatable({}, { __index = function(t, key)
		local value
		if ATT.KIND_OF_CONSTRUCTOR[key] then
			value = Node(ATT.KIND_OF_CONSTRUCTOR[key])
		elseif type(key) == "string" and key:find("^Create") then
			value = Node("other")
		else
			-- Helpers the files call while building (_.ResolveQuestData and the like) hand back the table they were
			-- given, so the nodes in it survive; faction-specific parts they would pick from are left out.
			value = setmetatable({}, { __index = function() return "" end, __call = function(_, first)
				return type(first) == "table" and first or {}
			end })
		end
		rawset(t, key, value)
		return value
	end })
	local handlers, current = {}, nil
	app.AddEventHandler = function(_, handler) table.insert(handlers, { file = current, run = handler }) end

	for _, file in ipairs(files) do
		local path = root .. "/Categories/" .. file .. ".lua"
		current = file
		assert(loadstring(ATT.ReadFile(path), path))("AllTheThings", app)
	end
	-- A category that needs more of the add-on than this stub gives is skipped, and named, rather than stopping the run.
	local categories = {}
	for _, handler in ipairs(handlers) do
		local ok, err = pcall(handler.run, categories)
		if not ok then io.stderr:write(("att_load: %s skipped: %s\n"):format(handler.file, tostring(err))) end
	end

	local localization = ATT.ReadFile(root .. "/LocalizationDB.lua")
	return {
		categories = categories,
		objectNames = LocalizationTable(localization, "ObjectNames%s*=%s*(%b{})"),
		headerNames = LocalizationTable(localization, "localize%(L%.HEADER_NAMES,%s*(%b{})%)"),
		version = ATT.Version(root),
	}
end

-- A node's children: fields.g when it has one, else the fields themselves (some nodes list children directly).
function ATT.Children(node)
	local fields = node.fields
	if type(fields.g) == "table" then return fields.g end
	return fields
end

return ATT
