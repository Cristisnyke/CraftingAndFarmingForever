-- Crafting and Farming Forever :: Vendor
-- The vendor step done for you, with a merchant open: buys what the plan says to get from a vendor, as far as this
-- merchant sells it, on a click (the Next step bar's button or the one under the merchant window). One purchase at a
-- time, a moment apart, each found again by item ID first, as the merchant's list (and its filter) can change.

local _, ns = ...
local Vendor = {}
ns.Vendor = Vendor

local TIMING = {
	STEP = 0.2,   -- between purchases
	SETTLE = 1,   -- after the last one, before counting what arrived
}

local open = false
-- job = { buys = { { itemID, left, maxStack } }, index, before = { [itemID] = count }, spent, stopped }
local job

function Vendor.IsOpen()
	return open
end

function Vendor.Busy()
	return job ~= nil
end

-- One merchant slot: item ID, price of one unit, units per purchase, units left (-1 = unlimited), or nil when it
-- isn't for plain gold.
local function Slot(index)
	local price, stack, available, purchasable, extended
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(index)
		if not info then return nil end
		price, stack, available = info.price, info.stackCount, info.numAvailable
		purchasable, extended = info.isPurchasable, info.hasExtendedCost
	elseif GetMerchantItemInfo then
		local _
		_, _, price, stack, available, purchasable, _, extended = GetMerchantItemInfo(index)
	end
	if not price or price <= 0 or extended or purchasable == false then return nil end
	local itemID = GetMerchantItemID and GetMerchantItemID(index)
	if not itemID and GetMerchantItemLink then
		local link = GetMerchantItemLink(index)
		itemID = link and tonumber(link:match("item:(%d+)"))
	end
	if not itemID then return nil end
	stack = math.max(stack or 1, 1)
	local maxStack = GetMerchantItemMaxStack and GetMerchantItemMaxStack(index) or stack
	return { itemID = itemID, index = index, unit = price / stack, stack = stack, available = available or -1,
		maxStack = math.max(maxStack or stack, stack) }
end

-- What this merchant sells for gold, by item ID.
local function Stock()
	local found = {}
	local count = open and GetMerchantNumItems and GetMerchantNumItems() or 0
	for index = 1, count do
		local slot = Slot(index)
		if slot and not found[slot.itemID] then found[slot.itemID] = slot end
	end
	return found
end

-- What the vendor step would buy here: { buys = { { itemID, units, cost, short } }, cost, notHere = { [itemID] =
-- units } }, from the plan the Queue tab shows. Exact units, even when the merchant lists a bundle (vials in fives):
-- BuyMerchantItem takes units, as the game's shift-click does. short = units this merchant hasn't got (limited stock). Nil while the merchant is closed or nothing is to buy.
function Vendor.Pending()
	if not open then return nil end
	local wanted = ns.ActivePlan().vendor or {}
	if next(wanted) == nil then return nil end
	local stock = Stock()
	local result = { buys = {}, cost = 0, notHere = {} }
	local ids = {}
	for itemID in pairs(wanted) do table.insert(ids, itemID) end
	table.sort(ids)
	for _, itemID in ipairs(ids) do
		local units, slot = wanted[itemID], stock[itemID]
		if units > 0 and slot then
			local buy = units
			local short = 0
			if slot.available >= 0 and buy > slot.available * slot.stack then
				buy = slot.available * slot.stack
				short = units - buy
			end
			if buy > 0 then
				local cost = math.floor(buy * slot.unit + 0.5)
				table.insert(result.buys, { itemID = itemID, units = buy, cost = cost, short = short })
				result.cost = result.cost + cost
			end
		elseif units > 0 then
			result.notHere[itemID] = units
		end
	end
	if #result.buys == 0 then return nil end
	return result
end

-- The button's text and whether it can be clicked, for the Next step bar and the merchant window alike.
function Vendor.ButtonText()
	if job then return ("Buying... %d / %d"):format(job.done, job.total), false end
	if not open then return "Talk to a vendor and this buys for you", false end
	local pending = Vendor.Pending()
	if not pending then return "Nothing here for your queue", false end
	return ("Buy for your queue: %s"):format(ns.Money(pending.cost)), true
end

-- What a click buys here and what this merchant hasn't got, under a tooltip's title.
function Vendor.AddTooltipLines(tooltip)
	tooltip:AddLine("Buys what the queue's \"Buy from vendor\" step needs, as far as this vendor sells it. One "
		.. "purchase at a time; it stops if you walk away, your bags fill up or your gold runs out.", 1, 1, 1, true)
	local pending = open and Vendor.Pending()
	if not pending then return end
	tooltip:AddLine(" ")
	for _, buy in ipairs(pending.buys) do
		tooltip:AddDoubleLine(("%s x%d"):format(ns.Items.Name(buy.itemID) or "?", buy.units), ns.Money(buy.cost),
			1, 1, 1, 1, 1, 1)
		if buy.short > 0 then tooltip:AddLine(("  only part: %d more to find elsewhere"):format(buy.short), 1, 0.6, 0.2) end
	end
	local missing = {}
	for itemID in pairs(pending.notHere) do table.insert(missing, itemID) end
	table.sort(missing)
	for _, itemID in ipairs(missing) do
		tooltip:AddLine(("%s x%d: not sold here"):format(ns.Items.Name(itemID) or "?", pending.notHere[itemID]),
			0.6, 0.6, 0.6)
	end
end

-- Under the merchant window: there whenever this merchant sells something the queue needs.
local merchantButton
local function SyncMerchantButton()
	if not merchantButton then
		if not open or not MerchantFrame or not (ns.UI and ns.UI.FlatButton) then return end
		merchantButton = ns.UI.FlatButton(MerchantFrame, "", 230, 24, true)
		merchantButton:SetPoint("TOPLEFT", MerchantFrame, "BOTTOMLEFT", 0, -4)
		merchantButton:SetScript("OnClick", function()
			ns.SayWhyNot(Vendor.Run())
		end)
		merchantButton:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText("Crafting and Farming Forever")
			Vendor.AddTooltipLines(GameTooltip)
			GameTooltip:Show()
		end)
		merchantButton:SetScript("OnLeave", GameTooltip_Hide)
	end
	local text, enabled = Vendor.ButtonText()
	merchantButton:SetShown(open and (job ~= nil or enabled))
	merchantButton:SetText(text)
	merchantButton:SetEnabled(enabled)
end

local function Changed()
	SyncMerchantButton()
	if ns.UI and ns.UI.SyncVendorButton then ns.UI.SyncVendorButton() end
end
Vendor.Sync = Changed

local function Count(itemID)
	return C_Item.GetItemCount(itemID) or 0
end

local function Finish()
	local done = job
	job = nil
	if not done then return end
	local got, short = {}, {}
	for _, buy in ipairs(done.buys) do
		local units = Count(buy.itemID) - (done.before[buy.itemID] or 0)
		local name = ns.Items.Name(buy.itemID) or "?"
		if units > 0 then table.insert(got, ("%s x%d"):format(name, units)) end
		if units < buy.want then table.insert(short, ("%s x%d"):format(name, buy.want - units)) end
	end
	local spent = done.money - GetMoney()
	if #got > 0 then
		ns.Say("chatDone", ("Vendor: bought %s for %s."):format(table.concat(got, ", "), ns.Money(math.max(spent, 0))))
	end
	if done.stopped then
		ns.Say("chatDone", ("Vendor: stopped (%s)."):format(done.stopped))
	end
	if #short > 0 then ns.Say("chatDone", "Vendor: still missing " .. table.concat(short, ", ") .. ".") end
	ns.RequestPlan()
	Changed()
end

local Step

local function Later(delay)
	local this = job
	C_Timer.After(delay, function()
		if job == this then Step() end
	end)
end

-- Done buying: what was bought gets a moment to reach the bags before it's counted.
local function Settle()
	job.settling = true
	Later(TIMING.SETTLE)
end

Step = function()
	if not job then return end
	if job.settling then return Finish() end
	if job.stopped then return Settle() end
	if not open then
		job.stopped = job.stopped or "the merchant closed"
		return Settle()
	end
	local buy = job.buys[job.index]
	while buy and buy.left <= 0 do
		job.index = job.index + 1
		buy = job.buys[job.index]
	end
	if not buy then return Settle() end
	local slot = Stock()[buy.itemID]
	if not slot then
		buy.left = 0
		return Later(TIMING.STEP)
	end
	local amount = math.min(buy.left, slot.maxStack)
	if GetMoney() < amount * slot.unit then
		job.stopped = "not enough gold"
		return Settle()
	end
	BuyMerchantItem(slot.index, amount)
	buy.left = buy.left - amount
	job.done = job.done + amount
	Changed()
	Later(TIMING.STEP)
end

-- Units bought and to buy while a job runs, else nil.
function Vendor.Progress()
	if job then return job.done, job.total end
end

-- Starts buying. Returns false and why when it can't.
function Vendor.Run()
	if job then return false, "Already buying." end
	if not open then return false, "Talk to a vendor first." end
	local pending = Vendor.Pending()
	if not pending then return false, "This vendor sells nothing your queue needs." end
	if GetMoney() < pending.cost then
		return false, ("Not enough gold: this costs %s."):format(ns.Money(pending.cost))
	end
	local buys, before, total = {}, {}, 0
	for _, item in ipairs(pending.buys) do
		table.insert(buys, { itemID = item.itemID, left = item.units, want = item.units })
		before[item.itemID] = Count(item.itemID)
		total = total + item.units
	end
	job = { buys = buys, index = 1, before = before, money = GetMoney(), done = 0, total = total }
	Changed()
	Step()
	return true
end

-- Bags full or gold gone: the rest would fail one by one with the same red message.
ns.On("UI_ERROR_MESSAGE", function(_, message)
	if not job or job.stopped or not message then return end
	if message == ERR_INV_FULL or message == ERR_BAG_FULL then
		job.stopped = "your bags are full"
	elseif message == ERR_NOT_ENOUGH_MONEY then
		job.stopped = "not enough gold"
	end
end)

local function SetOpen(state)
	if open == state then return end
	open = state
	-- The next step of the job notices, and counts what arrived after a moment, so the last purchase isn't missed.
	if not open and job then job.stopped = job.stopped or "the merchant closed" end
	Changed()
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh("next") end
end

ns.On("MERCHANT_SHOW", function() SetOpen(true) end)
ns.On("MERCHANT_CLOSED", function() SetOpen(false) end)
ns.On("MERCHANT_UPDATE", function() Changed() end)
local function IsMerchant(kind)
	local types = Enum and Enum.PlayerInteractionType
	return types and types.Merchant ~= nil and kind == types.Merchant
end
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind)
	if IsMerchant(kind) then SetOpen(true) end
end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind)
	if IsMerchant(kind) then SetOpen(false) end
end)
