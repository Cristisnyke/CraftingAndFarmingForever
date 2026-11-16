-- Checks calls between the add-on's files: every ns.Module.fn(...) or Module.fn(...) (through a local alias of a
-- module) must name a function some file defines. luacheck can't see this, since the modules are fields of ns.
-- Usage: lua5.1 tools/check_calls.lua <file.lua>...   Exits 1 and lists the calls when any is unknown.

local files = {}
for _, path in ipairs(arg) do
	local handle = assert(io.open(path, "r"))
	-- Whole-line comments are dropped, so an example in one can't count as a call.
	local lines = {}
	for line in handle:lines() do
		if not line:match("^%s*%-%-") then lines[#lines + 1] = line end
	end
	handle:close()
	files[#files + 1] = { path = path, lines = lines }
end

local modules = {} -- module name -> true
local defined = {} -- "Module.fn" -> true
local function Define(module, name) defined[module .. "." .. name] = true end

-- Pass 1: each file's local names for modules. "ns.Queue = Queue" and "local Queue = ns.Queue" both make Queue a
-- module; the right-hand side has to be a bare name, so "ns.farmPlan = ns.plan" isn't one.
for _, file in ipairs(files) do
	file.alias = {}
	for _, line in ipairs(file.lines) do
		local module, name = line:match("^ns%.([%w_]+)%s*=%s*([%a_][%w_]*)%s*$")
		if module and name ~= "nil" and name ~= "true" and name ~= "false" then
			file.alias[name], modules[module] = module, true
		end
		name, module = line:match("^local ([%a_][%w_]*)%s*=%s*ns%.([%w_]+)%s*$")
		if name then file.alias[name], modules[module] = module, true end
	end
end

-- Pass 2: what each module defines: "function M.fn", "function M:fn", "M.fn =", "ns.M.fn =".
for _, file in ipairs(files) do
	for _, line in ipairs(file.lines) do
		local owner, name = line:match("^%s*function ([%a_][%w_]*)[%.:]([%w_]+)")
		if not owner then owner, name = line:match("^%s*([%a_][%w_]*)%.([%w_]+)%s*=[^=]") end
		if owner then
			if owner == "ns" then
				-- ns.fn itself: a function on ns, checked like a module's.
				Define("ns", name)
			else
				Define(file.alias[owner] or owner, name)
			end
		end
		local module
		module, name = line:match("^%s*ns%.([%w_]+)%.([%w_]+)%s*=[^=]")
		if module then Define(module, name) end
	end
end

-- Pass 3: the calls.
local unknown = {}
for _, file in ipairs(files) do
	for number, line in ipairs(file.lines) do
		-- ns.fn(...): a function on ns itself (ns.Print, ns.Debounce).
		for at, name in line:gmatch("()ns%.([%w_]+)%s*%(") do
			local before = at > 1 and line:sub(at - 1, at - 1) or ""
			if not before:match("[%w_%.]") and not defined["ns." .. name] then
				unknown[#unknown + 1] = ("%s:%d: ns.%s"):format(file.path, number, name)
			end
		end
		for module, name in line:gmatch("ns%.([%w_]+)[%.:]([%w_]+)%s*%(") do
			if modules[module] and not defined[module .. "." .. name] then
				unknown[#unknown + 1] = ("%s:%d: ns.%s.%s"):format(file.path, number, module, name)
			end
		end
		for at, owner, name in line:gmatch("()([%a_][%w_]*)[%.:]([%w_]+)%s*%(") do
			local before = at > 1 and line:sub(at - 1, at - 1) or ""
			local module = file.alias[owner]
			if module and not before:match("[%w_%.]") and not defined[module .. "." .. name] then
				unknown[#unknown + 1] = ("%s:%d: %s.%s (ns.%s)"):format(file.path, number, owner, name, module)
			end
		end
	end
end

if #unknown > 0 then
	print("Calls to functions no file defines:")
	for _, entry in ipairs(unknown) do print("  " .. entry) end
	os.exit(1)
end
