-- CraftLedger :: Posting
-- The Restocking tab of the auction house: everything your characters can craft that's in this character's bags, how
-- much of it your goals want on the AH, and a button to post it. The price comes from a live search for each item.
--
-- The tab itself comes from LibAHTab, which Auctionator loads: adding one through the game's own tab functions taints
-- the player's bags.

local _, ns = ...

local Posting = {}
ns.Posting = Posting

local TAB_ID = "CraftLedgerRestocking"
local LIST_WIDTH = 500
local LOOKUP_TIMEOUT = 5 -- seconds; after this the last scanned price is used instead
local POST_TIMEOUT = 3 -- seconds; a post that never gets an answer stops blocking the button
local BAGS = { 0, 1, 2, 3, 4, 5 } -- backpack, four bags and the reagent bag
local COLOR_PROFIT, COLOR_LOSS, COLOR_MUTED, COLOR_WARN = "ff55dd55", "ffff6655", "ff999999", "ffffb040"

local function Color(hex, text)
	return "|c" .. hex .. text .. "|r"
end

local window -- the list, in the shape UI.Refresh expects
local form = {}
local selected -- itemID
local keepSelection = false -- picked by hand, so it stays selected even with nothing left to post by the goals
local reselect = false -- a post went through: read the suggested quantity and price again
local live -- the search for the selected item: { itemID, pending, waiting, lowest, mine, failed }
local posting = false
local postedSince = {} -- units posted since Syndicator last refreshed its count of your auctions

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

-- Units of each sellable item in the bags and one slot holding it. Bank items can't be posted from here.
local function BagContents()
	local counts, slots = {}, {}
	for _, bag in ipairs(BAGS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and not info.isBound then
				counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
				slots[info.itemID] = slots[info.itemID] or { bag, slot }
			end
		end
	end
	return counts, slots
end

-- One row per item in the bags that a known recipe makes. Those to post come first, then the rest for posting by hand.
function Posting.Rows()
	local ctx = ns.NewContext()
	local counts = BagContents()
	local reserved = ns.Planner.ReservedMaterials(ctx, ns.plan)
	local rows = {}
	for itemID, inBags in pairs(counts) do
		local goal = ctx.known[itemID] and ns.Items.CanSellOnAH(itemID) and ns.Restock.Goal(itemID)
		if goal then
			local onAH = ns.Stock.ForRestock(itemID)
			local posted = postedSince[itemID] or 0
			table.insert(rows, {
				itemID = itemID,
				inBags = inBags,
				onAH = onAH and (onAH + posted) or nil,
				goal = goal,
				reserved = reserved[itemID] or 0,
				toPost = ns.Planner.PostQuantity(goal, (onAH or 0) + posted, inBags, reserved[itemID] or 0),
				unitCost = ns.Planner.CraftUnitCost(ctx, itemID),
				name = ns.Items.Name(itemID) or "",
			})
		end
	end
	table.sort(rows, function(a, b)
		if (a.toPost > 0) ~= (b.toPost > 0) then return a.toPost > 0 end
		if a.name ~= b.name then return a.name < b.name end
		return a.itemID < b.itemID
	end)
	return rows
end

---------------------------------------------------------------------------
-- The price
---------------------------------------------------------------------------

local function BreakEven(row)
	return row.unitCost and row.unitCost / (1 - ns.AH_CUT) or nil
end

local function SetPriceBoxes(copper)
	if not copper then
		form.gold:SetText("")
		form.silver:SetText("")
		form.copper:SetText("")
		return
	end
	form.gold:SetText(tostring(math.floor(copper / 10000)))
	form.silver:SetText(tostring(math.floor(copper / 100) % 100))
	form.copper:SetText(tostring(copper % 100))
end

local function PriceFromBoxes()
	local total = (tonumber(form.gold:GetText()) or 0) * 10000
		+ (tonumber(form.silver:GetText()) or 0) * 100
		+ (tonumber(form.copper:GetText()) or 0)
	return total > 0 and total or nil
end

local function CurrentRow()
	for _, data in ipairs(window.list) do
		if data.row and data.row.itemID == selected then return data.row end
	end
	return nil
end

local UpdateForm

-- The search answered, or gave up: fills in the suggested price unless the user has already typed one.
local function ApplyLookup(row)
	if form.priceEdited then return end
	local price, raised = ns.Planner.PostPrice({
		lowest = live.lowest,
		lowestIsMine = live.mine,
		scanned = ns.Prices.AH(row.itemID),
		breakEven = BreakEven(row),
	})
	live.raised = raised
	SetPriceBoxes(price)
end

local function FinishLookup(itemID, lowest, mine)
	if not (live and live.pending and live.itemID == itemID) then return end
	live.lowest, live.mine = lowest, mine
	live.pending, live.waiting = false, false
	local row = CurrentRow()
	if row then ApplyLookup(row) end
	UpdateForm()
end

local function SendLookup()
	local search = live
	search.waiting = false
	local sorts = {}
	if Enum.AuctionHouseSortOrder then
		sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
	end
	C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(search.itemID), sorts, true)
	C_Timer.After(LOOKUP_TIMEOUT, function()
		if live == search and search.pending then
			search.failed = true
			FinishLookup(search.itemID, nil, nil)
		end
	end)
end

local function StartLookup(itemID)
	live = { itemID = itemID, pending = true }
	if C_AuctionHouse.IsThrottledMessageSystemReady() then
		SendLookup()
	else
		live.waiting = true
	end
end

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
	if not (live and live.pending and live.itemID == itemID) then return end
	local lowest, mine
	for index = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
		local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
		if info and info.unitPrice and (not lowest or info.unitPrice < lowest) then
			lowest, mine = info.unitPrice, info.containsOwnerItem
		end
	end
	FinishLookup(itemID, lowest, mine)
end)

ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
	local itemID = itemKey and itemKey.itemID
	if not (live and live.pending and live.itemID == itemID) then return end
	local lowest, mine
	for index = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
		local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
		-- Bid-only listings have no price to compare with.
		if info and info.buyoutAmount and (not lowest or info.buyoutAmount < lowest) then
			lowest, mine = info.buyoutAmount, info.containsOwnerItem
		end
	end
	FinishLookup(itemID, lowest, mine)
end)

---------------------------------------------------------------------------
-- Selection
---------------------------------------------------------------------------

local function SuggestedQuantity(row)
	if row.toPost > 0 then return row.toPost end
	return math.max(1, row.inBags - row.reserved)
end

local function SelectRow(row, byHand)
	selected = row and row.itemID or nil
	keepSelection = byHand or false
	reselect = false
	form.priceEdited, form.quantityEdited = false, false
	live = nil
	SetPriceBoxes(nil)
	if row then
		form.quantity:SetText(tostring(SuggestedQuantity(row)))
		StartLookup(row.itemID)
	else
		form.quantity:SetText("")
	end
end

-- Keeps the selection while it's still useful, otherwise moves on to the next thing to post.
local function ChooseSelection(rows)
	local current
	for _, row in ipairs(rows) do
		if row.itemID == selected then current = row end
	end
	if current and not reselect and (keepSelection or current.toPost > 0) then
		-- Your auctions can be counted after the row was selected. Follow that unless a quantity was typed.
		if not form.quantityEdited then form.quantity:SetText(tostring(SuggestedQuantity(current))) end
		return
	end
	if current and reselect and current.toPost > 0 then
		SelectRow(current)
		return
	end
	local nextRow = rows[1]
	if nextRow and nextRow.toPost <= 0 then nextRow = nil end
	SelectRow(nextRow)
end

local function BuildList()
	local rows = Posting.Rows()
	ChooseSelection(rows)
	local list = {}
	for _, row in ipairs(rows) do
		table.insert(list, { kind = "post", row = row, selected = row.itemID == selected })
	end
	if #list == 0 then
		table.insert(list, { kind = "note", text = "Nothing to post: no items in your bags that your recipes make." })
	end
	return list
end

function Posting.Select(itemID)
	for _, data in ipairs(window.list) do
		if data.row and data.row.itemID == itemID then
			SelectRow(data.row, true)
			break
		end
	end
	ns.UI.Refresh("posting")
end

function Posting.SelectNext()
	local list = window.list
	for index, data in ipairs(list) do
		if data.row and data.row.itemID == selected then
			local following = list[index + 1] or list[1]
			if following.row then Posting.Select(following.row.itemID) end
			return
		end
	end
end

---------------------------------------------------------------------------
-- Posting
---------------------------------------------------------------------------

local function SelectedLocation()
	local _, slots = BagContents()
	local slot = selected and slots[selected]
	return slot and ItemLocation:CreateFromBagAndSlot(slot[1], slot[2]) or nil
end

local function IsCommodity(location)
	return C_AuctionHouse.GetItemCommodityStatus(location) == Enum.ItemCommodityStatus.Commodity
end

local function Quantity()
	local quantity = tonumber(form.quantity:GetText())
	return quantity and quantity >= 1 and math.floor(quantity) or nil
end

local function Duration()
	return ns.db.restock.duration
end

local function Deposit(location, quantity)
	if not (location and quantity) then return nil end
	if IsCommodity(location) then
		return C_AuctionHouse.CalculateCommodityDeposit(selected, Duration(), quantity)
	end
	return C_AuctionHouse.CalculateItemDeposit(location, Duration(), quantity)
end

function Posting.PostSelected()
	local location = SelectedLocation()
	local quantity, price = Quantity(), PriceFromBoxes()
	if posting or not (location and quantity and price) or not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
	quantity = math.min(quantity, C_AuctionHouse.GetAvailablePostCount(location) or quantity)
	posting = true
	-- A true answer means the game wants a confirmation first, and its sell frames show that dialog.
	if IsCommodity(location) then
		if C_AuctionHouse.PostCommodity(location, Duration(), quantity, price) then
			AuctionHouseFrame.CommoditiesSellFrame:CachePendingPost(location, Duration(), quantity, price)
		end
	else
		if C_AuctionHouse.PostItem(location, Duration(), quantity, nil, price) then
			AuctionHouseFrame.ItemSellFrame:CachePendingPost(location, Duration(), quantity, nil, price)
		end
	end
	C_Timer.After(POST_TIMEOUT, function()
		if posting then
			posting = false
			UpdateForm()
		end
	end)
	UpdateForm()
end

-- Called by Sales once the server has confirmed a post.
function Posting.OnPosted(post)
	postedSince[post.itemID] = (postedSince[post.itemID] or 0) + post.qty
	posting = false
	reselect = post.itemID == selected
	ns.RequestPlan()
end

ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
	if not window or not window.frame:IsVisible() then return end
	if live and live.waiting then SendLookup() end
	UpdateForm()
end)

ns.On("PLAYER_LOGIN", function()
	local registry = _G.Syndicator and _G.Syndicator.CallbackRegistry
	if registry and registry.RegisterCallback then
		pcall(registry.RegisterCallback, registry, "AuctionsCacheUpdate", function()
			wipe(postedSince)
			ns.RequestPlan()
		end, Posting)
	end
end)

ns.On("AUCTION_HOUSE_CLOSED", function()
	live, posting = nil, false
	selected = nil
end)

---------------------------------------------------------------------------
-- The form
---------------------------------------------------------------------------

local function LookupText()
	if not live then return "" end
	if live.pending then return Color(COLOR_MUTED, "Searching the auction house...") end
	if live.failed then return Color(COLOR_WARN, "No answer from the auction house. Using the last scan.") end
	if not live.lowest then return Color(COLOR_MUTED, "Nobody else is selling this. Using the last scan.") end
	return "Lowest now: " .. ns.Money(live.lowest) .. (live.mine and Color(COLOR_MUTED, " (yours)") or "")
end

function UpdateForm()
	if not form.post then return end
	local row = CurrentRow()
	form.panel:SetShown(row ~= nil)
	if not row then return end

	form.icon:SetTexture(ns.Items.Icon(row.itemID))
	form.name:SetText(row.name)
	form.lookup:SetText(LookupText())

	local price, quantity = PriceFromBoxes(), Quantity()
	local location = SelectedLocation()
	local notes = {}
	if live and live.raised then
		table.insert(notes, Color(COLOR_WARN, "Lowest is under your material cost, so this is your break-even price."))
	end
	if quantity and quantity > row.inBags - row.reserved and row.reserved > 0 then
		table.insert(notes, Color(COLOR_WARN, ("Your queue needs %d of these."):format(row.reserved)))
	end
	form.note:SetText(table.concat(notes, "\n"))

	for index, button in ipairs(form.durations) do
		local hours = ns.Sales.DurationHours(index)
		button:SetText(index == Duration() and ("|cffffffff%dh|r"):format(hours) or (hours .. "h"))
		if index == Duration() then button:LockHighlight() else button:UnlockHighlight() end
	end

	local deposit = Deposit(location, quantity)
	form.deposit:SetText("Deposit: " .. (deposit and ns.Money(deposit) or "?"))
	if price and quantity then
		local received = price * quantity * (1 - ns.AH_CUT)
		local text = "You get " .. ns.Money(received) .. " after the AH cut."
		if row.unitCost then
			local profit = received - row.unitCost * quantity
			text = text .. "\nProfit: " .. Color(profit >= 0 and COLOR_PROFIT or COLOR_LOSS, ns.Money(profit))
		end
		form.result:SetText(text)
		form.post:SetText(("Post %d at %s each"):format(quantity, ns.Money(price)))
	else
		form.result:SetText(price and "" or Color(COLOR_MUTED, "Type a price to post this."))
		form.post:SetText("Post")
	end

	form.post:SetEnabled(not posting and location ~= nil and price ~= nil and quantity ~= nil
		and quantity <= row.inBags and GetMoney() >= (deposit or 0)
		and C_AuctionHouse.IsThrottledMessageSystemReady() and true or false)
end

local function NumberBox(parent, width)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetScript("OnEnterPressed", box.ClearFocus)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	return box
end

local function Text(parent, template, top)
	local text = parent:CreateFontString(nil, "OVERLAY", template)
	text:SetPoint("TOPLEFT", 8, -top)
	text:SetPoint("TOPRIGHT", -8, -top)
	text:SetJustifyH("LEFT")
	return text
end

local function CreateForm(parent)
	local panel = CreateFrame("Frame", nil, parent)
	panel:SetPoint("TOPLEFT", LIST_WIDTH + 8, -8)
	panel:SetPoint("BOTTOMRIGHT", -8, 8)
	form.panel = panel

	form.icon = panel:CreateTexture(nil, "ARTWORK")
	form.icon:SetSize(32, 32)
	form.icon:SetPoint("TOPLEFT", 8, -4)
	form.name = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	form.name:SetPoint("LEFT", form.icon, "RIGHT", 6, 0)
	form.name:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
	form.name:SetJustifyH("LEFT")

	form.lookup = Text(panel, "GameFontHighlightSmall", 46)

	local priceEdited = function(_, userInput)
		if userInput then
			form.priceEdited = true
			if live then live.raised = nil end
			UpdateForm()
		end
	end
	Text(panel, "GameFontHighlightSmall", 68):SetText("Price each")
	form.gold = NumberBox(panel, 56)
	form.gold:SetPoint("TOPLEFT", 14, -84)
	form.silver = NumberBox(panel, 28)
	form.silver:SetPoint("LEFT", form.gold, "RIGHT", 16, 0)
	form.copper = NumberBox(panel, 28)
	form.copper:SetPoint("LEFT", form.silver, "RIGHT", 16, 0)
	for _, part in ipairs({ { form.gold, "g" }, { form.silver, "s" }, { form.copper, "c" } }) do
		part[1]:SetScript("OnTextChanged", priceEdited)
		local suffix = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		suffix:SetPoint("LEFT", part[1], "RIGHT", 2, 0)
		suffix:SetText(part[2])
	end

	Text(panel, "GameFontHighlightSmall", 112):SetText("Quantity")
	form.quantity = NumberBox(panel, 56)
	form.quantity:SetPoint("TOPLEFT", 14, -128)
	form.quantity:SetScript("OnTextChanged", function(_, userInput)
		if userInput then
			form.quantityEdited = true
			UpdateForm()
		end
	end)
	local all = ns.UI.HeaderButton(panel, "All", 44, function()
		local row = CurrentRow()
		if row then
			form.quantity:SetText(tostring(row.inBags))
			form.quantityEdited = true
			UpdateForm()
		end
	end)
	all:SetPoint("LEFT", form.quantity, "RIGHT", 6, 0)

	Text(panel, "GameFontHighlightSmall", 156):SetText("Duration")
	form.durations = {}
	for index = 1, 3 do
		local button = ns.UI.HeaderButton(panel, "", 50, function()
			ns.db.restock.duration = index
			UpdateForm()
		end)
		button:SetPoint("TOPLEFT", 8 + (index - 1) * 54, -172)
		form.durations[index] = button
	end

	form.deposit = Text(panel, "GameFontHighlightSmall", 204)
	form.result = Text(panel, "GameFontHighlightSmall", 222)
	form.note = Text(panel, "GameFontNormalSmall", 256)

	form.post = ns.UI.HeaderButton(panel, "Post", 100, function() Posting.PostSelected() end)
	form.post:SetHeight(26)
	form.post:ClearAllPoints()
	form.post:SetPoint("BOTTOMLEFT", 8, 32)
	form.post:SetPoint("BOTTOMRIGHT", -8, 32)

	local skip = ns.UI.HeaderButton(panel, "Next item", 100, function() Posting.SelectNext() end)
	skip:ClearAllPoints()
	skip:SetPoint("BOTTOMLEFT", 8, 6)
	skip:SetPoint("BOTTOMRIGHT", -8, 6)
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

local function CreateTab()
	if window or not AuctionHouseFrame then return end
	local lib = _G.LibStub and _G.LibStub("LibAHTab-1-0", true)
	if not lib then
		ns.Print("The Restocking tab needs Auctionator's tab library, which isn't loaded.")
		return
	end

	local frame = CreateFrame("Frame", "CraftLedgerRestockingFrame", AuctionHouseFrame)
	frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 4, -30)
	frame:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -4, 27)

	window = { key = "posting", frame = frame, list = {}, offset = 0, rows = {}, build = BuildList, update = UpdateForm }
	ns.UI.windows.posting = window
	Posting.window = window

	local listArea = CreateFrame("Frame", nil, frame)
	listArea:SetPoint("TOPLEFT", 0, 0)
	listArea:SetPoint("BOTTOMLEFT", 0, 0)
	listArea:SetWidth(LIST_WIDTH)
	ns.UI.CreateListArea(window, listArea, 10, 8, 8, ns.UI.ROW_HEIGHT)

	CreateForm(frame)
	frame:SetScript("OnShow", function() ns.UI.Refresh("posting") end)
	lib:CreateTab(TAB_ID, frame, "Restocking", "CraftLedger Restocking")
end

ns.On("AUCTION_HOUSE_SHOW", function()
	-- The next frame, so it lands after the tabs Auctionator adds as the auction house opens.
	C_Timer.After(0, CreateTab)
end)
