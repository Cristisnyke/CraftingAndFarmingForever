-- Crafting and Farming Forever :: CraftFx
-- Something to watch while you craft, on every Craft Next bar on screen (UI.lua): a light sweeps along the fill while
-- a cast runs; each craft flashes the bar and floats the item up with its profit; a chip above the bar counts the
-- streak and what this session's crafts earned (rolling up to the new total); a finished batch bursts into sparks with
-- a banner. Profit is the Profit tab's figure for one craft (AH sale after the cut, less materials) at today's
-- listing, not the usual price a spike is counted at.
-- Only drawn while something moves: idle bars run no code.

local _, ns = ...

local CraftFx = {}
ns.CraftFx = CraftFx

local FX = {
	FLOAT_SECONDS = 1.3, -- a crafted item rising off the bar
	FLOAT_RISE = 38,
	FLASH_SECONDS = 0.35,
	BURST_SECONDS = 0.9,
	BURST_SPARKS = 14,
	BANNER_SECONDS = 2.8,
	CHIP_SECONDS = 8, -- the streak chip stays this long after the last craft
	CHIP_FONT = 18, -- size of the streak chip's text
	CHIP_HEIGHT = 28,
	-- Each craft: the chip jumps to POP times its size and wobbles back (WOBBLE a second, settling at DAMP), hops up
	-- HOP pixels, and its background flashes gold.
	POP = 0.6, WOBBLE = 16, DAMP = 6, HOP = 12, BUMP_SECONDS = 1.2,
	FLOAT_START = 34, -- the floating profit starts above the chip
	BANNER_Y = 80,
	SHIMMER_SECONDS = 1.6, -- a pass of the light along the fill
	ROLL_SPEED = 6, -- how fast the session total rolls up to its new value
	PROFIT_AGE = 60, -- seconds a recipe's profit is reused
	GAIN = "ff3fe07a",
	LOSS = "ffff5a4a",
	GOLD = { 1, 0.82, 0.25 },
	SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark",
	WHITE = "Interface\\Buttons\\WHITE8X8",
}

local session = { earned = 0, crafts = 0 } -- since login
local streak = { recipeID = nil, count = 0, at = 0 } -- crafts in a row of one recipe
local profitCache = {} -- [recipeID] = { at, net }
local clock = 0

-- What one craft earns, as the Profit tab works it out; nil when the item can't be sold or isn't priced.
local function NetEach(recipeID)
	local cached = profitCache[recipeID]
	if cached and clock - cached.at < FX.PROFIT_AGE then return cached.net end
	local recipe = ns.db.recipes[recipeID]
	local net
	if recipe and recipe.o and ns.Items.CanSellOnAH(recipe.o) then
		-- At today's listing (todayNet) when the Profit tab counts the sale at the usual price: you're about to post
		-- what you craft now, so that is what this craft earns (Smelt Tin: +10c at today's price, -32c at usual).
		local result = ns.Planner.Profit(ns.NewContext(), recipeID)
		net = result and (result.todayNet or result.net)
	end
	profitCache[recipeID] = { at = clock, net = net }
	return net
end

local function Signed(copper)
	if copper >= 0 then return ("|c%s+%s|r"):format(FX.GAIN, ns.Money(copper)) end
	return ("|c%s%s|r"):format(FX.LOSS, ns.Money(copper))
end

---------------------------------------------------------------------------
-- The effects layer of one bar
---------------------------------------------------------------------------

local Tick

local function Layer(bar)
	if bar.cf.fx then return bar.cf.fx end
	local fx = CreateFrame("Frame", nil, bar)
	fx:SetAllPoints(bar)
	fx:SetFrameLevel((bar:GetFrameLevel() or 0) + 8)
	fx.floats, fx.sparks = {}, {}

	fx.shimmer = fx:CreateTexture(nil, "ARTWORK")
	fx.shimmer:SetTexture(FX.WHITE)
	fx.shimmer:SetBlendMode("ADD")
	fx.shimmer:SetVertexColor(1, 1, 1, 0.1)
	fx.shimmer:SetWidth(30)
	fx.shimmer:Hide()

	fx.flash = fx:CreateTexture(nil, "OVERLAY")
	fx.flash:SetTexture(FX.WHITE)
	fx.flash:SetBlendMode("ADD")
	fx.flash:SetPoint("TOPLEFT", 2, -2)
	fx.flash:SetPoint("BOTTOMRIGHT", -2, 2)
	fx.flash:Hide()

	-- Streak and session earnings, above the middle of the bar.
	local chip = CreateFrame("Frame", nil, fx)
	chip:SetPoint("BOTTOM", bar, "TOP", 0, 3)
	chip:SetHeight(FX.CHIP_HEIGHT)
	chip.back = chip:CreateTexture(nil, "BACKGROUND")
	chip.back:SetAllPoints(chip)
	chip.back:SetColorTexture(0.03, 0.05, 0.1, 0.92)
	local line = chip:CreateTexture(nil, "BORDER")
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	line:SetHeight(2)
	line:SetColorTexture(FX.GOLD[1], FX.GOLD[2], FX.GOLD[3], 0.9)
	chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	chip.text:SetPoint("CENTER", 0, 1)
	local font = chip.text:GetFont()
	if font then chip.text:SetFont(font, FX.CHIP_FONT, "OUTLINE") end
	chip:Hide()
	fx.chip = chip

	fx.banner = fx:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	fx.banner:SetPoint("BOTTOM", bar, "TOP", 0, FX.BANNER_Y)
	fx.banner:Hide()

	fx:SetScript("OnUpdate", function(self, elapsed) Tick(self, elapsed) end)
	bar.cf.fx = fx
	return fx
end

local function Float(fx, icon, text, x)
	local float
	for _, f in ipairs(fx.floats) do
		if not f:IsShown() then float = f break end
	end
	if not float then
		float = CreateFrame("Frame", nil, fx)
		float:SetSize(120, 18)
		float.icon = float:CreateTexture(nil, "OVERLAY")
		float.icon:SetSize(16, 16)
		float.icon:SetPoint("LEFT")
		float.text = float:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		float.text:SetPoint("LEFT", float.icon, "RIGHT", 3, 0)
		fx.floats[#fx.floats + 1] = float
	end
	float.icon:SetTexture(icon)
	float.text:SetText(text)
	float.t, float.x = 0, x
	float:Show()
end

local function Burst(fx)
	local width = fx:GetWidth() or 0
	for i = 1, FX.BURST_SPARKS do
		local spark = fx.sparks[i]
		if not spark then
			spark = fx:CreateTexture(nil, "OVERLAY")
			spark:SetTexture(FX.SPARK)
			spark:SetBlendMode("ADD")
			spark:SetSize(14, 14)
			fx.sparks[i] = spark
		end
		local angle = (i / FX.BURST_SPARKS) * 2 * math.pi + math.random() * 0.4
		local speed = 40 + math.random() * 70
		spark.t, spark.x0 = 0, width * (0.2 + 0.6 * math.random())
		spark.vx, spark.vy = math.cos(angle) * speed * 1.6, math.sin(angle) * speed
		spark:SetVertexColor(FX.GOLD[1], FX.GOLD[2], FX.GOLD[3])
		spark:Show()
	end
	fx.bursting = true
end

-- One frame of every effect on a bar; the layer stops running when nothing moves.
Tick = function(fx, elapsed)
	clock = clock + elapsed
	local busy = false
	local bar = fx:GetParent()
	local width = fx:GetWidth() or 0

	-- A cast just started: the bar may not say "crafting" yet.
	if (fx.grace or 0) > 0 then
		fx.grace = fx.grace - elapsed
		busy = true
	end

	-- The light along the fill while a cast runs.
	if bar.cf and bar.cf.state == "crafting" and width > 60 then
		busy = true
		local fillWidth = width * math.min((bar.fill:GetValue() or 0), 1)
		local x = (clock % FX.SHIMMER_SECONDS) / FX.SHIMMER_SECONDS * math.max(fillWidth, 1)
		fx.shimmer:ClearAllPoints()
		fx.shimmer:SetPoint("TOP", bar, "TOPLEFT", x, -2)
		fx.shimmer:SetPoint("BOTTOM", bar, "BOTTOMLEFT", x, 2)
		fx.shimmer:SetShown(fillWidth > 30)
	else
		fx.shimmer:Hide()
	end

	if fx.flash:IsShown() then
		fx.flashT = fx.flashT + elapsed
		local left = 1 - fx.flashT / FX.FLASH_SECONDS
		if left <= 0 then fx.flash:Hide() else fx.flash:SetAlpha(0.45 * left) busy = true end
	end

	for _, float in ipairs(fx.floats) do
		if float:IsShown() then
			float.t = float.t + elapsed
			local p = float.t / FX.FLOAT_SECONDS
			if p >= 1 then
				float:Hide()
			else
				busy = true
				float:ClearAllPoints()
				float:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", float.x, FX.FLOAT_START + (1 - (1 - p) * (1 - p)) * FX.FLOAT_RISE)
				float:SetAlpha(p < 0.6 and 1 or (1 - p) / 0.4)
			end
		end
	end

	if fx.bursting then
		fx.bursting = false
		for _, spark in ipairs(fx.sparks) do
			if spark:IsShown() then
				spark.t = spark.t + elapsed
				local p = spark.t / FX.BURST_SECONDS
				if p >= 1 then
					spark:Hide()
				else
					fx.bursting, busy = true, true
					spark:ClearAllPoints()
					spark:SetPoint("CENTER", bar, "LEFT", spark.x0 + spark.vx * spark.t,
						spark.vy * spark.t - 60 * spark.t * spark.t)
					spark:SetAlpha(1 - p)
				end
			end
		end
	end

	if fx.banner:IsShown() then
		fx.bannerT = fx.bannerT + elapsed
		local p = fx.bannerT / FX.BANNER_SECONDS
		if p >= 1 then
			fx.banner:Hide()
		else
			busy = true
			-- Pops in, holds, fades.
			fx.banner:SetAlpha(p < 0.08 and p / 0.08 or p > 0.75 and (1 - p) / 0.25 or 1)
			fx.banner:ClearAllPoints()
			fx.banner:SetPoint("BOTTOM", bar, "TOP", 0, FX.BANNER_Y + 8 * (1 - math.min(p / 0.08, 1)))
		end
	end

	local chip = fx.chip
	if chip:IsShown() then
		if clock - streak.at > FX.CHIP_SECONDS and not (bar.cf and bar.cf.state == "crafting") then
			chip:Hide()
		else
			busy = true
			-- The session total rolls up to its new value.
			fx.shownEarned = fx.shownEarned + (session.earned - fx.shownEarned) * math.min(1, elapsed * FX.ROLL_SPEED)
			if math.abs(session.earned - fx.shownEarned) < 1 then fx.shownEarned = session.earned end
			local text = ("|cffffd24ax%d|r streak"):format(streak.count)
			if fx.hasProfit then text = text .. "   session " .. Signed(fx.shownEarned) end
			chip.text:SetText(text)
			chip:SetWidth((chip.text:GetStringWidth() or 0) + 24)
			-- Each craft: a big pop that wobbles back, a hop and a gold flash.
			local since = clock - streak.at
			local decay = since < FX.BUMP_SECONDS and math.exp(-FX.DAMP * since) or 0
			if chip.SetScale then
				chip:SetScale(math.max(0.85, 1 + FX.POP * decay * math.cos(FX.WOBBLE * since)))
			end
			chip:ClearAllPoints()
			chip:SetPoint("BOTTOM", bar, "TOP", 0, 3 + FX.HOP * decay)
			local flash = math.min(1, decay * 1.5)
			chip.back:SetColorTexture(0.03 + 0.6 * flash, 0.05 + 0.45 * flash, 0.1, 0.92)
		end
	end

	if not busy then fx:SetScript("OnUpdate", nil) end
end

local function Wake(fx)
	fx:SetScript("OnUpdate", function(self, elapsed) Tick(self, elapsed) end)
end

---------------------------------------------------------------------------
-- Events from the queue
---------------------------------------------------------------------------

-- A cast started (Queue.lua): the light along the fill runs.
function CraftFx.Casting()
	for _, bar in ipairs(ns.UI.craftBars) do
		if bar:IsVisible() then
			local fx = Layer(bar)
			fx.grace = 1
			Wake(fx)
		end
	end
end

-- A craft finished (Queue.lua). done and total: the batch so far (nil outside one).
function CraftFx.Crafted(recipeID, done, total)
	if streak.recipeID == recipeID and clock - streak.at < 30 then
		streak.count = streak.count + 1
	else
		streak.recipeID, streak.count = recipeID, 1
	end
	streak.at = clock
	session.crafts = session.crafts + 1
	local net = NetEach(recipeID)
	if net then session.earned = session.earned + net end
	local recipe = ns.db.recipes[recipeID]
	local icon = recipe and recipe.o and ns.Items.Icon(recipe.o)
	local finished = done and total and total > 1 and done >= total
	for _, bar in ipairs(ns.UI.craftBars) do
		if bar:IsVisible() then
			local fx = Layer(bar)
			local width = fx:GetWidth() or 0
			fx.flashT = 0
			fx.flash:SetAlpha(0.45)
			fx.flash:Show()
			local x = width * math.min((bar.fill:GetValue() or 0), 1)
			Float(fx, icon, net and Signed(net) or "+1", math.max(0, math.min(x - 20, width - 120)))
			if not fx.chip:IsShown() then fx.shownEarned = session.earned - (net or 0) end
			fx.hasProfit = fx.hasProfit or net ~= nil
			fx.chip:Show()
			if finished then
				Burst(fx)
				local name = recipe and recipe.o and ns.Items.Name(recipe.o)
				local earned = net and ("  " .. Signed(net * total)) or ""
				fx.banner:SetText(("Batch complete! |cffffffff%d %s|r%s"):format(total, name or "crafted", earned))
				fx.bannerT = 0
				fx.banner:Show()
			end
			Wake(fx)
		end
	end
end

function CraftFx.Diag()
	return ("%d crafts this session, %s"):format(session.crafts, ns.Money(session.earned))
end
