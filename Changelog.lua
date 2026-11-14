-- Crafting and Farming Forever :: Changelog
-- Generated from CHANGELOG.md by tools/gen_changelog.lua. Don't edit by hand: edit CHANGELOG.md and regenerate.

local _, ns = ...

ns.CHANGELOG = {
	{ version = "1.10.1", lines = {
		"- Smoother at the auction house and mailbox: buying many materials in a row or taking gold from a lot of mail no longer redraws the Queue, Restock and Next step bar after every single purchase, just once when you're done",
	} },
	{ version = "1.10.0", lines = {
		"- Restock: when you don't have the gold for a full restock, the Restock tab says so and offers a partial one: the items that earn the most profit for their material cost, cut to what you can afford. Materials you already hold count as free, and anything you queued by hand is paid for first. The Craft column shows what fits out of what's needed, like 3/8 (part of smart goals, so the same switch turns it off)",
		"- Restock: smart goals. An item's goal now follows your own sales: more of what sells well, fewer of what keeps expiring, and it keeps adjusting as you sell (recent days count most). One item's stock never costs more than a quarter of your gold to make, and daggers are stocked in pairs, since buyers usually want two. Smart goals show in blue, and the tooltip says why. A goal you set yourself always stays. The Options tab has a Stock level slider for how much to keep (50% of a day's sales to start with), and a switch to turn smart goals off",
	} },
	{ version = "1.9.0", lines = {
		"- Profit: a crafted item listed for more than 400% of its material cost (often one odd listing, like 7s of materials posted for 20g) now counts at 200% of the material cost, so it can't show a huge profit that won't sell. Its row on the Profit and Queue tabs says \"check price\" in orange, and the tooltip shows the real listing. Both numbers, and the limit itself, are on the Options tab",
	} },
	{ version = "1.8.2", lines = {
		"- Sales tab: new Reset profit button, top right. It starts your profit again from zero, from now, after asking you to confirm. Your sales history still counts for the chance to sell",
	} },
	{ version = "1.8.1", lines = {
		"- Sales profit: materials you already had, or gathered, now count at the market price on the day you craft with them. They used to count as free, so something made mostly from materials in your bags showed far too much profit. Sales already recorded keep the profit they had",
		"- Items crafted before the add-on recorded costs count at today's cost to craft one, with their profit marked ~",
	} },
	{ version = "1.8.0", lines = {
		"- New Options tab, before Changelog, to switch parts of the add-on on or off and word its messages your way. You can also open it by right-clicking the minimap button, with /cff options, or from the game's own Options under AddOns",
		"- Advertising: write your own message (put {profession} where your profession link goes), choose where it's posted, or turn advertising off, which removes the Ad box beside the chat and the Advertise button",
		"- Quotes: write your own whisper using {item}, {count} and {price}. The quote margin moved from the Queue tab to Options",
		"- Also in Options: open with the profession window, the minimap button, the Next step bar, the \"scan now?\" question at the auction house, and the reminder lines in chat",
		"- Right-clicking the minimap button now opens Options. The Next step bar still folds with its own button or /cff next",
	} },
	{ version = "1.7.1", lines = {
		"- Sales profit now follows your gold: items crafted before 1.7.0, and materials you already had then, cost nothing instead of today's market price. Selling things made from your own gathered or old stock no longer shows a loss. Profit counted since 1.7.0 is worked out again this way",
	} },
	{ version = "1.7.0", lines = {
		"- Sales tab shows profit, not just sales: what you received after the auction house cut, less what the materials cost you. Materials bought at the auction house count at the price you paid, vendor materials at the vendor's price, and ones you gathered yourself at nothing. The boxes along the top show your profit today, in the last 7 days and in the last 30, with the sales total underneath (money still on its way included), and each item has Sales and Profit columns",
		"- Profit starts from zero with this version: earlier sales stay out of it, though they still feed each item's chance to sell. Materials you already hold count at today's prices, and items crafted before this version count at today's cost to craft one, marked with ~",
		"- Sales tab lists only the items your characters craft. Tick \"Show everything I sell, not only my crafts\" to include spare materials, drops and the rest",
	} },
	{ version = "1.6.0", lines = {
		"- Money on its way: the game mails a sale's money an hour after it sells. When one of your auctions sells, the add-on now tells you in chat how much is coming, counts down the hour on the Sales tab and the minimap button, and tells you when it's in your mailbox, wherever you are in the world",
		"- Sales tab: four summary boxes along the top show the money on its way and what you earned today, in the last 7 days and in the last 30",
		"- Minimap button: left-click opens or closes the window, right-click folds the Next step bar, drag moves it. It works with minimap button collectors and broker bars, and /cff minimap hides it",
		"- New look: the windows, buttons, tabs and lists share one flat dark-blue style that matches the Craft Next bar, with striped rows, marked section headings and cleaner item icons",
		"- Sales tab: Sells, Sold and Expired are now lined-up columns under a heading, and expired counts stand out in red",
	} },
	{ version = "1.5.3", lines = {
		"- Farm It: gathering is now the first step. Fetching from alts, the bank, the auction house, the mailbox and the vendor come after it, so you only go to town once for what's still missing",
		"- Removed a leftover troubleshooting log that recorded every auction house search, and old settings from earlier versions, so your saved data is smaller",
	} },
	{ version = "1.5.2", lines = {
		"- Materials you hold now count however deep down they're used: wool in your bags makes the cloth that makes the bolt your queue needs, instead of the bolt being bought because cloth has a market price",
		"- When what you hold covers only part of a material, that part is crafted and only the rest is bought (6 ore in the bank: smelt 6 bars, buy the other 4), instead of buying all of them whenever the missing ore is dearer than bars",
		"- A price of zero (a bad scan result) no longer makes a material free or a result worthless; it counts as no price",
		"- Craft Next no longer makes one craft too many when clicked right after a batch ends, before the plan has caught up",
	} },
	{ version = "1.5.1", lines = {
		"- Fixed the Craft Next progress bar counting one craft too many during a batch (2 / 7 when you queued 6)",
		"- New look for the Craft Next bar: one blue colour scheme on the window's dark background, with a thin blue edge, instead of the grey-white bar",
		"- Restocking no longer undercuts: it suggests the same price as the lowest listing",
		"- Fixed known recipes being forgotten (your smelting recipes could vanish, so the add-on bought bars instead of smelting them and the profit for bar recipes came out too low). A recipe is now only removed when the game clearly says you no longer know it. Open the affected profession once to get missing recipes back",
	} },
	{ version = "1.5.0", lines = {
		"- Craft Next is now a progress bar too. While you craft it fills through the crafts of that recipe (say 7 / 20) and shows how long until all 20 are done, plus how long all your queued crafts will take. A thin blue line under it fills as you work through the whole queue. Before you start, it says how long the next batch takes. Times are learned from your own casts. Hover it for the time per recipe",
		"- Craft Next opens the profession it needs: no more \"Open Mining to finish Smelt Bronze\". The button says \"Open Mining: Smelt Bronze x12\", opens it (switching from the one you have open) and starts crafting once it has loaded",
	} },
	{ version = "1.4.0", lines = {
		"- Shopping list: what you buy at the auction house leaves the list as soon as the purchase goes through. It counts as waiting in your mailbox, and once everything on the list is bought the queue says \"Collect from your mailbox\"; opening the mailbox counts what's really there",
		"- Buying is easier to find: the buying step in the Queue tab and the Next step bar says to open the auction house's Shopping tab (Auctionator) and click the \"Crafting and Farming Forever Queue\" list, hover it for step-by-step help, and chat says the same when you open the auction house with something to buy",
		"- Craft Next goes strictly in order: it never jumps ahead to a later craft while the current one (smelting bars, say) isn't finished. When it can't craft, the button says what to finish and how many are left, such as \"Finish Smelt Bronze: 8 left\", and the Next step bar keeps it on screen",
	} },
	{ version = "1.3.0", lines = {
		"- New Next step bar at the top of the screen: while anything is queued it shows the next thing to do (get from an alt, take from the bank, buy, sub-craft or craft), with a Craft Next button when it's time to craft. Fold it to one line with the - button; it disappears when the queue is empty. Drag to move it, or type /cff next to fold or unfold it. It stays out of the way in combat, dungeons, raids and battlegrounds",
		"- Farm It: the separate Farm list is gone. The Next step bar now shows everything to gather and where (mining, herbs, skinning and so on together), with a Buy It button to go back to buying",
		"- Queue with several characters: the to-do list, shopping list and Next step bar are now for the character you're logged in on. Crafts another character makes (say your tailor's, while you're on your blacksmith) aren't bought or made here; they're listed last as \"Log in to <character>\", and that character's list shows what to buy and craft when you log in there",
	} },
	{ version = "1.2.3", lines = {
		"- Queue: the tab is now a numbered to-do list in the order you'd do it. Getting materials from alts and your bank comes first, then buying, then sub-crafts, and your queued crafts last, so you reach the crafting station with everything on you. The Farm list follows the same order",
	} },
	{ version = "1.2.2", lines = {
		"- Queue: when something you queued is also needed as a material for another queued craft (tin bars for bronze, for example), the extra crafts now show under Sub-crafts. Before, Craft Next asked for more than you could see in the queue",
	} },
	{ version = "1.2.1", lines = {
		"- The Auctionator shopping list now only holds the materials you need to buy. It no longer lists the items you're crafting, which made it look like you should buy them",
	} },
	{ version = "1.2.0", lines = {
		"- New: Skill up mode on the Profit tab, for levelling. It lists the recipes that can still give you a skill point, cheapest per skill point first. Recipes are coloured orange, yellow and green as in the game, with each colour's chance of a point",
		"- New: Changelog tab after Sales, with what changed in each version. It turns green after an update until you've had a look",
		"- Profit and Skill up: click a column heading to sort by it, click again to reverse",
		"- Profit: tick Hide unprofitable recipes to hide recipes that would make no profit",
		"- Profit: the Advertise button moved under the profession tabs; hover it to see what it posts",
		"- Restock: clear columns for Sells, AH, Have, Craft and Goal",
		"- Restock: goals you set yourself are white, with a button to go back to the default; default goals are grey",
		"- The window can be resized: drag the bottom-right corner, right-click it for the default size",
		"- More reminders when auction house prices are over a day old: in chat after you log in, at the top of the Farm list, and every time you quote an order. Material tooltips mark prices that are a day or more old",
		"- Farm list: Buy It switches back to buying and reopens the queue",
		"- Farm It knows a few more places to gather from",
		"- Crafting and Farming Forever needs both Auctionator and Syndicator to work properly. If Syndicator is missing or turned off, a reminder appears in chat when you log in",
		"- Coming soon: TradeSkillMaster (TSM) support",
	} },
	{ version = "1.1.0", lines = {
		"- Queue: type the number of crafts straight into each row's box (0 removes the entry)",
		"- Queue: Materials and Profit columns, both for the whole entry",
		"- Queue: Shift - takes ten off, down to one",
		"- Queue: the remove button is a red cross at the end of the row, away from - and +",
		"- Queue: Clear asks before emptying the queue",
		"- Profit: right-click or Ctrl-click + to type how many crafts to queue",
		"- Restock: type an item's goal straight into its row's box",
		"- Queue: Buy It and Farm It side by side, with the current mode lit",
		"- Queue: entries that would lose money are shaded red, and Remove losing removes them after asking",
		"- Queue: an entry another character has to craft shows their name",
		"- Queue: says how to add crafts when it's empty",
		"- Profit: Sells and Profit column headings; hover them for what they mean",
		"- Sell chance is white when likely, so green only means profit (and item quality)",
		"- Refresh explains what it does when you hover it",
		"- Farm list: one close button instead of Back and ×",
		"- \"1 item\" and \"2 items\" instead of \"item(s)\"",
	} },
	{ version = "1.0.1", lines = {
		"- Sales and Restocking rows no longer stay on \"Loading...\" after the item's name arrives",
		"- Solid window background, so the game world and other windows no longer show through the lists",
	} },
	{ version = "1.0.0", lines = {
		"First release.",
		"- Profit list for every recipe your characters know, with cheapest-path material costs",
		"- One craft queue shared by all characters, with Craft Next",
		"- Live Auctionator shopping list that leaves out what you own",
		"- Farm It gathering list",
		"- Restock goals and a Restocking tab at the auction house",
		"- Sales history with chance to sell",
		"- Advertise box and whole-order quotes with an adjustable margin",
	} },
}
