-- Writes Changelog.lua, the in-game What's new text, from CHANGELOG.md's numbered sections (newest first, as in the
-- file). "Unreleased" is left out. tools/check.sh fails when Changelog.lua is out of date.
--   lua5.1 tools/gen_changelog.lua CHANGELOG.md > Changelog.lua

local path = assert(arg[1], "usage: lua5.1 tools/gen_changelog.lua CHANGELOG.md")

-- Markdown the game can't show: links keep their text, bold and code marks go.
local function Plain(text)
	text = text:gsub("%[(.-)%]%(.-%)", "%1"):gsub("%*%*", ""):gsub("`", "")
	return text
end

local sections, current = {}, nil
for line in io.lines(path) do
	line = line:gsub("\r$", "")
	local heading = line:match("^## (.-)%s*$")
	if heading then
		current = nil
		if heading:match("^%d+%.%d+%.%d+$") then
			current = { version = heading, lines = {} }
			table.insert(sections, current)
		end
	elseif current and line:match("%S") then
		local bullet = line:match("^%s*[-*] (.*)$")
		table.insert(current.lines, bullet and ("- " .. Plain(bullet)) or Plain(line))
	end
end

local out = {
	"-- Crafting and Farming Forever :: Changelog",
	"-- Generated from CHANGELOG.md by tools/gen_changelog.lua. Don't edit by hand: edit CHANGELOG.md and regenerate.",
	"",
	"local _, ns = ...",
	"",
	"ns.CHANGELOG = {",
}
for _, section in ipairs(sections) do
	table.insert(out, ("\t{ version = %q, lines = {"):format(section.version))
	for _, text in ipairs(section.lines) do table.insert(out, ("\t\t%q,"):format(text)) end
	table.insert(out, "\t} },")
end
table.insert(out, "}")
io.write(table.concat(out, "\n"), "\n")
