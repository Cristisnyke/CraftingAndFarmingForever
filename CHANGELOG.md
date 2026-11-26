# Changelog

Each version's section is the CurseForge changelog; `tools/release.sh` uploads it. Add the next version's section before releasing.

## Unreleased

- Refactoring and code optimization.

## 1.37.4

- Rows marked "check price" now show their profit at the current auction house price instead of a lowered one. The "!" stays so you know to check the listing. The second "count it as %" box in Options is gone.

## 1.37.3

- Recipes: click a recipe for its Wowhead link, ready to copy with Ctrl+C. It goes to the page of the item that teaches it, or the recipe itself when no item does.
- Recipes: a tip at the top of the list and a line in each recipe's tooltip say that a click gives its Wowhead link.
- Usual prices now come from the last 7 days instead of 14, so they keep up with a fast-moving market.
- Profit tooltips show "Profit at today's price" when a craft is counted at its usual price, so you always see what today's listing would make.

## 1.37.2

- Price spikes: a price that has held for your last 3 scan days, or that your own sales keep getting (3 or more sold in 7 days), now counts as the new usual price instead of a spike. Crafts that really sell at today's price no longer show a loss.

## 1.37.1

- Items made from Mooncloth or transmutes (Mooncloth Bag and others) now count those materials at their auction house price, so their profit is real and no longer gets cut by the price cap.
- Refactoring and code optimization.
- Farm It and recipe source data updated from AllTheThings 5.4.19.

## 1.37.0

- **Writs and Crates tabs light up when you have some.** While you carry writs or crates (bags or bank), their tab turns gold with a pulsing glow and shows how many you have; hover it to see which ones. Inside the tab, the ones you hold are tinted gold, say "You have 1" and are listed first, even when your filters would hide them. Thanks to Soricelu for the idea.

## 1.36.0

- New Craft alert (Options tab, off by default): a sound a few seconds before the game stops crafting a batch while you still have crafts queued, so you can be alt-tabbed and come back in time to press Craft Next. Pick from six game sounds and the channel it plays on (Master, Effects, Music, Ambience or Dialog), and how many seconds early it warns (default 3). The menu also has the game's Sound in Background switch, without which nothing is heard while alt-tabbed

## 1.35.3

- Recipes with a cooldown, such as Mooncloth and transmutes, are no longer marked "check price": their profit now counts what they really sell for.

## 1.35.2

- **Fix: flasks didn't count the Alchemy Laboratory.** Recipes that need an Alchemy Lab now put the Alchemy Laboratory on your camp list like the Fermenter, with its cost in the plan. Open Alchemy once so the add-on learns which recipes need it. Thanks to felo747474 for the report.

## 1.35.1

- Refactoring and code optimization.

## 1.35.0

- **Recipe shopping lists can be turned off.** Untick **Recipe shopping lists** on the Options tab and the per-profession recipe lists are deleted and stay gone. Before, a deleted list came back. Thanks to felo747474.

## 1.34.0

- Restock knows about cooldowns: a recipe on cooldown (like Transmute: Arcanite) isn't asked for until it's ready, says "cooldown" in the Craft column, and asks for one craft at a time. Materials whose recipe is on cooldown are bought instead of crafted. Open the profession once so the add-on can read them. Thanks felo747474.
- The vendor button buys exactly the number your queue needs, even when the vendor sells an item in bundles (vials in fives), instead of whole bundles. Thanks felo747474.

## 1.33.0

- **Recipes to learn, as a shopping list.** Each of your professions gets its own Auctionator shopping list, such as **Tailoring Shopping List**, with the recipe items (patterns, plans, formulas) the character you're playing can learn right now, lowest skill first. Recipes you only get from a trainer aren't on it. It updates when you learn one or your skill goes up. Thanks to user_cggami8p66nyruw7 for the idea.

## 1.32.0

- **Farm It gathers what you can gather.** A skinner is now sent to skin Medium Leather, not to skin Light Leather and turn it into Medium Leather. The same goes for ore you can mine and herbs you can pick. Without the gathering profession, the conversion is still listed. Thanks to calmcacil for the report.

## 1.31.0

- **The Next step bar follows you.** Talk to a vendor that sells something your queue needs and the bar jumps straight to the **Buy from vendor** step, even if the auction house comes first. The same goes for the bank (bank steps), the mailbox (collecting, or mailing to your bank alt) and the auction house (the buying step). The bar says **Here: 3 of 5** while it does, and goes back to the normal order once that step is done or you walk away. Thanks to felo747474 for the idea.

## 1.30.1

- **Iron Oven and Anarchist's Workbench count as camp stations.** Cooking recipes that need an Iron Oven and engineering recipes that need an Anarchist's Workbench now get the same treatment as the Fermenter: the station's cost in the plan, its crafts done back to back within its 15 minutes, and Restock making them in batches. Open the profession once so the add-on learns which recipes need one.

## 1.30.0

- **Camp station crafts restock in batches.** A Fermenter costs the same whether you make 1 dye or 30, so restocking 1 dye for 10s profit with a 12s Fermenter made no sense. Items that need a camp station are now left alone while you have their goal, and once you're under it, Restock makes 3 times the goal in one go (hover the row to see it). What isn't posted waits in your bags. Change the 3 with **Camp batch** in Options (1 turns it off).

## 1.29.0

- **Restock uses one camp station at most.** A placed camp station stands only 15 minutes, and placing one puts every station on a 1 hour cooldown. Restock now picks the one station whose crafts earn the most once the station itself (and a campfire kit) is paid for, and leaves out items needing another one ("0/4" in the Craft column; hover it for why, e.g. "only one camp station an hour, and a Master Forge pays more"). It queues only as many station crafts as fit its 15 minutes ("12/20"), and none while the cooldown runs.
- **Camp crafts come last, back to back.** The to-do list does every other craft first, sub-crafts for the station's crafts included, then has a step of its own to place the station and craft beside it. That step says how many crafts fit the 15 minutes (or the minutes your placed station has left), how long the cooldown still runs, and warns when your queue needs two different stations.

## 1.28.0

- **Fix: bank alt mode mailed campfire kits to the bank alt.** A recipe you know makes them, so they counted as crafts to sell. Campfire kits and camp stations now stay with the character who has them. Thanks to felo747474 for the report.
- **Skill up tooltips show both resale prices.** Hover a recipe to see what a vendor pays and what it sells for on the auction house after the cut. The one that isn't counted is grey and says "(not counted)": tick **Selling on the AH** to count the auction house price when it's more. Thanks to the player on CurseForge who asked.

## 1.27.0

- **Fix: placing a campfire asked for another one.** Placing a campfire kit or a camp station uses it up, so the plan wanted a new one (from your bank, or bought). The add-on now notes what you placed: for an hour, while you stay in the same zone, the steps say "your campfire is lit" or "your Fermenter is placed" and ask for nothing more. One campfire now serves every station. Thanks to felo747474 for the report.
- **Fix: on the bank alt, it still asked to mail everything to the bank alt.** The add-on read only a character's first name, which WoW Forever gives every character on your account, so a bank alt typed with both names never matched itself. It now reads both names: type the bank alt's full name in Options, such as **Snic Bank**. Your characters' full names also show in tooltips and lists now (taken from Syndicator for characters you haven't logged in to since), an alt's materials set aside for its own queued crafts are matched to it properly, and **Quote** replies to a customer with a two-part name instead of whispering the first name alone. Accented names typed in another case (élise for Élise) match too. Thanks to felo747474 for the report.
- **Recipes shows what a recipe would earn.** Two new columns in Recipes: **Profit** per craft if you learned it (same prices as the Profit tab), and **Pays back**, how many crafts' profit pays for the recipe at its auction house price. Sort by either to find the recipes worth buying. Hover a recipe for its materials and what it sells for. Open each profession once so the add-on can read the materials of recipes you don't know yet. Thanks to the player on CurseForge who asked for it.
- **Skill up counts what your crafts sell for.** The cost of a skill point is now the materials less what you get back for what you make: a vendor's price, or with the new **Selling on the AH** tick, the auction house price after its cut when that's more. A craft that sells for more than it costs shows in green with a + (you earn gold while levelling) and goes to the top. Thanks to the player on CurseForge who pointed this out.

## 1.26.0

- **Leave characters out.** A **Characters** button on the Options tab lists your characters: cross one out and the add-on ignores it completely. Its recipes don't show on the Profit tab or in Recipes, it's never picked to craft, and what's in its bags, bank, mail and auctions isn't counted for the queue, the shopping list or restocking. Handy for a bank alt whose materials you keep for something else. The character you're playing always counts. Thanks to Larasify, who wrote this one.
- **Bank alt mode.** Let one character sell everything: tick **Bank alt mode** in Options and type your bank alt's name. Your other characters craft and mail what they make to it: open a mailbox and your crafts are attached and sent by themselves, whole stacks, 12 to a mail (if the game won't let an add-on send mail on its own, press **Send crafts** under the mailbox, or on the Next step bar). Crafts in your bank come out on the bank step to go along. What your queue still needs and your tools stay, and materials a crafter uses itself only go as far as the auction house is short of them. Postage, 30 copper per stack, comes off the profit everywhere. Crafters' Restocking tab stops suggesting posts; the bank alt posts it all. The bank alt's materials and gold stay out of your crafters' shopping: send gold over yourself.
- **Price spikes don't fool you any more.** The add-on now notes each item's lowest auction house price every day you scan. After 3 days, the middle of the last 14 is its usual price. A crafted item listed above that counts at its usual price in Profit, Queue and Restock, since a spike may be over before yours sell. Items at 130% of usual or more say so in orange ("167% of usual"), and material tooltips show materials that are unusually dear (orange) or cheap (green). Switch it off in Options.

## 1.25.0

- **Camp stations.** Crafts that need a camp station (a Fermenter for alchemy oils, a Spinning Wheel, a Loom and the like) put one on your to-do list with a campfire kit to place it at, marked "(camp)": from your bags, bank or mailbox if you have one, else bought or crafted, whichever is cheaper, and the cost counts in the queue's total. Under the crafting step the list says what to place and which crafts go beside it, and those crafts come one after another, since camp features share a 1 hour cooldown. Open your professions once so the add-on learns which recipes need a station.
- Money from sales reaching your mailbox is said in chat once, not once per sale, until you open the mailbox. The first line also says how much more is still on its way.

## 1.24.0

- **Recipes to hunt.** The Profit tab has a third mode, **Recipes**: every recipe in the game you haven't learned yet, by the skill it needs. Green ones you can learn now.
- **Where to get each recipe.** Hover a recipe to see where it comes from (trainer, vendor with its price and reputation, quest, dungeon boss, drop, world drop, holiday), whether you can buy it on the auction house, what it makes and what that sells for, and which of your characters have learned it or can learn it. Shift-click a recipe to link it in chat.
- **All your characters at once.** **This character** (bottom left) switches to **All characters**: a recipe stays listed while any character with that profession is missing it, and the row names who.
- **Hide BoP** lists only recipes whose craft you can post on the auction house.
- **New recipes glow.** When a skill-up lets you learn new recipes, the **Profit** tab and the **Recipes** button glow green with a dot, like the Changelog tab, until you look.
- The recipe data comes from AllTheThings and ships with the add-on; you don't need AllTheThings installed.
- **Choose what the add-on writes in chat.** Options has a **Chat messages** menu with a tick box for each kind: reminders, sales, plan news, what buttons did, and warnings. Turn off the ones you don't want. Commands you type, like `/cff diag`, always answer. "Reminders in chat" moved into this menu and keeps your setting.

## 1.23.0

- **Buy from vendors in one click.** At a vendor that sells something your queue needs (thread, vials, flux and the like), a **Buy for your queue** button appears under the vendor window and on the Next step bar, with the total price. Click it and it buys exactly what the "Buy from vendor" step lists, as far as that vendor sells it. Hover it to see what it buys and what this vendor doesn't have. It stops if you walk away, your bags fill up or your gold runs out.

## 1.22.0

- **Writs by zone.** The Writs tab has a Filter by zone button: tick one or more zones to see only the writs handed in there, with how many each zone has. The new Zone heading also sorts the list by where writs are handed in.

## 1.21.0

- **Crafting time on the Restock tab.** Beside the Stock level slider a clock shows about how long the restock takes to craft, including the bars, cloth and other sub-crafts its materials need. It changes as you drag the slider.

## 1.20.2

- **Tidier money amounts.** An average loss of less than half a copper showed as "-0c"; it now shows as 0c.
- Maintenance: a setting left behind by an older version of the Writs tab is cleaned out of your saved data.

## 1.20.1

- **Farm It data updated** from AllTheThings 5.4.14: a few new item sources added and some outdated ones removed.

## 1.20.0

- **Profit for the batch you really make.** The Profit tab priced every recipe as one craft at the cheapest listings, so a recipe whose cheap materials run out after a craft or two looked better than it is. Now each recipe is priced for as many crafts as its restock goal makes, with materials counted down the listings the add-on has read: the profit shown is the average per craft over that batch. Hover a row to see how many crafts it's priced for, what one craft costs, and which materials' listings haven't been read yet (those still count at their cheapest listing).
- **The gold limit on smart goals counts real costs too.** A smart goal never lets one item's stock cost more than a quarter of your gold; that now counts what making that many really costs down the listings, not that many times the cheapest.

## 1.19.0

- **One screen lock, and you can see what it's doing.** Pressing Refresh at the auction house could lock and unlock the screen several times in a row, and each time it jumped to the Queue tab. Now the screen locks once for the whole check, the window stays on the tab you had open (Restock included), and a box at the bottom of the window names the material being read ("Reading Copper Bar: 3 of 12"). The rows that need it are outlined in gold. When it's done it says it's working out the plan with the new prices, then unlocks. If another add-on's search is running, it says it's waiting instead of unlocking and locking again.
- **Restock is quicker.** The Restock tab no longer reads any listings: it picks what to craft at the cheapest prices, so opening it at the auction house doesn't lock the screen. Once you queue the restock, the auction house reads every listing of what your queue buys and decides the restock again: crafts that no longer earn your minimum profit at what the materials really cost are cut or taken off the queue, and chat says which ("Copper Bracers 10 -> 6"). For an hour after that, the Restock tab doesn't offer the cut crafts again. Crafts you queued by hand are never cut.
- **See how hard each queued craft is.** Crafts on the queue, sub-crafts and the Next step bar show their names in the profession window's colours for the character who makes them: orange always gives a skill point, yellow about every other craft, green now and then, grey never. Hover a craft to see what its colour means. A craft stays white until that character opens the profession once.

## 1.18.1

- **Money on its way works.** It never showed a sale: the add-on listened for the "A buyer has been found" chat message, but the game writes that line into the chat window itself without telling add-ons. It now hears the sale the way the game does, so the moment something sells you get a "Sold" line in chat, and the Sales tab and the minimap button show the money until it reaches your mailbox an hour later.
- **Sales records stay true to what was really posted.** When the auction house refused a post sent from another add-on (Auctionator's Selling tab, for example), the next item you posted was recorded under the refused item's name, and that record never closed. It then took the next real sale of that item and priced **money on its way** at its old price. Refused posts are now forgotten whichever add-on sent them, and records like that, which can no longer get a result, are cleared the next time you open your mailbox.

## 1.18.0

- **Sub-crafts only as far as they pay.** A sub-craft used to be all or nothing: smelt every bar, or buy every bar. Now the add-on makes bars from the ore only while that's cheaper than buying the bars, and buys the rest. When the first 50 Iron Ore are cheap and the next 50 dear, it smelts what the cheap ore makes and buys the other bars, whichever costs less in total. When the two cost the same, it buys, since that's a step less.
- **The plan checks itself after new prices.** When your shopping list search, a price scan or the add-on's own listings check finishes, the plan is worked out again with the new prices. If it changed, the rows that changed pulse gold and a note says "Plan updated for the new prices: 3 changes". If it didn't, the window pulses green and says "Plan checked: still the cheapest way". With no window open, chat says it. Buying what the list says doesn't count as a change, and closing the auction house halfway through a search gives no verdict.
- **Both sides are read.** At the auction house the add-on now reads the listings of the bars as well as the ore (and the bolts as well as the cloth), so buying 200 bars is weighed at what 200 bars really cost, not at the cheapest one's price.

## 1.17.0

- **Buying many now counts at what many cost.** A price scan only knows each material's cheapest listing, so 50 Iron Ore used to count as 50 times the price of the first few. At the auction house the add-on now reads every listing of what your queue and your restock would buy (a few seconds, after your own searches), and also learns from every item you open to buy. **Still to buy**, the restock's gold check and the choice between buying and crafting a material all use the real cost. In the Queue tab a row shows the average price ("avg 8s 33c") when the cheapest listing doesn't cover it all, and says when fewer are listed than you need.
- **Restock stops where it stops paying.** When the cheap materials run out, a craft earns less. An item whose crafts would earn less than your minimum profit at what the materials really cost is cut to the number that still pays: **Craft** shows it as 6/10, and the tooltip says why.
- **The screen locks while it reads.** For those few seconds the window goes dark, and a notice in its middle says the screen is locked and how many items are left ("Reading listings, 4 to go"). When it lifts, the Queue tab is there with the real costs. Clicks and keys do nothing meanwhile, so a search or a purchase can't get in the way. It unlocks by itself when the reading is done, when you close the auction house, when a fight starts, or if the auction house stops answering. Escape unlocks it at once.
- **Refresh** at the auction house now reads the listings of your queue's materials again, so you can bring the costs up to date whenever you like.
- **Don't forget your hammer.** Crafts that need a tool in your bags (a Blacksmith Hammer, an Arclight Spanner, a runed rod) now put it on your to-do list when it isn't in your bags: on **Take from your bank** beside your materials, or the mailbox, an alt or a vendor, marked "(tool)". When you have none at all, a **Get your tools** step says so. Open your professions once so the add-on learns which recipes need tools.
- New option **Read listings at the auction house** (on by default). Off: only the listings of items you open yourself are read.

## 1.16.0

- `/cff` with an unknown command now lists `writs` and `crates` among the commands.

## 1.15.1

- **Full bags no longer block the queue.** The game won't start a craft unless a bag slot is free, even a craft that would free slots. Bag space planning now keeps one slot free before every craft: with full bags, the Queue tab first tells you what to put in the bank (or, if there's nothing of the queue's to bank, that you're a slot short).

## 1.15.0

- The **Stock level** slider is now on the Restock tab too, under the goals. Drag it and the goals and crafts update as you move it: a row flashes green when it goes up and red when it goes down. It's the same setting as the one on the Options tab.
- **Bags too small for a big queue?** The Queue tab now checks that everything it sends you to buy and craft fits in your bags. When it doesn't, it first tells you what to put in your bank (materials the queue doesn't need yet, and crafted items), on the same bank trip as what to take out. If that's still not enough, the queue is crafted in **runs**: each run buys only the materials it needs, the crafts that use up the most bag room go first, and once the run is crafted the list moves on to the next one. Nothing changes while everything fits. You can turn it off on the Options tab (**Plan around bag space**).
- **Bank it** button on the Next step bar: on a "Make room" or "Take from your bank" step, open your bank and click it. It puts away what the step says, then takes out what your queue needs, stack by stack. It stops if the bank closes or a fight starts.

## 1.14.1

- **Gold kept** on the Options tab now takes gold, silver and copper, typed like `1g 50s 20c`, so you can keep back any amount down to 1 copper. An amount you already set is carried over.

## 1.14.0

- A restock now leaves some of your gold alone: 1 gold unless you set your own amount in the new **Gold kept** box on the Options tab. Before, a restock could plan to spend all your gold but the deposits, and since buying materials often costs more than the last scan said, you could end up with a bag of crafted items and no gold to post them.

## 1.13.1

- Restock keeps gold back for posting: a restock now counts the auction house deposits for everything it makes and everything you already hold, so buying the materials never leaves you unable to list the items. With too little gold for both, it queues fewer crafts.

## 1.13.0

- Smart restock goals work in a new way. A goal now moves by what happened to your auctions: every day that everything you listed sold, it goes up a step (you probably ran out); when auctions expire, it comes down, and the last few days decide, so an item that stops selling drops within a day or two instead of a week
- Smart goals know how often you restock. A goal never rises past what sold between two of your restocks, measured from when you post (long breaks, like overnight, count most). Until a few restocks are on record it uses one auction's length
- Smart goals look at profit: an unsold item only costs its deposit, so items that earn a lot next to their deposit get bigger steps up and shrug off a few expiries, and thin-margin items are stocked carefully. The deposit is learned the first time you post an item
- Smart goals weigh an expiry by the deposit it really lost: a short, cheap auction that expires moves the goal less than a long, dear one. This starts with auctions you post from now on; for older ones the item's last deposit is used
- Smart goals pause an item that loses money: when the deposits lost on its expired auctions lately are more than its sales earned, its goal becomes 0 and the Restock tab shows "paused" with the numbers in the tooltip. After 3 days one is tried again. If it sells, the goal grows as usual; if it expires, the pause returns for twice as long (up to 2 weeks). A goal you set yourself overrides a pause
- The Stock level slider is now cautious to aggressive: 50% stocks up to what sold between two restocks, 100% up to twice that and in bigger steps, low values stay close to the default and drop faster. A smart goal's tooltip explains in plain words why it is what it is
- Restock no longer changes its mind halfway through a trip. Once you queue a restock it's committed: buying its materials (which lowers your gold) or prices moving after you bought can't swap it for different items. The Restock tab shows what's already queued (5q) and says "Restock is on your queue"
- Pressing restock again only adds what's still missing (more sold meanwhile), and takes crafts off only when your stock says they aren't needed any more (expired auctions came back, or you lowered a goal)
- Restock crafts are queued grouped by profession, so one visit to the anvil or tanning rack does them all
- Fixed: after spending gold on materials, the Restocking tab at the auction house could ask you to post fewer than you just crafted, because smart goals shrink with your gold. That limit now only decides what to craft

## 1.12.0

- New Crates tab for Waylaid Crates: every labelled crate with its auction house price, its cheapest bundle of materials (crafted by your characters when that's cheaper), the Merchant's Favor it pays, and the gold each Merchant's Favor costs you. The cheapest one is marked "best buy". Sort by any column or show one level
- Writs and crates go on your queue: + on a writ or a crate adds it to the Queue tab, and the queue's shopping list gets the writ or crate and what it needs, less what you hold. An item or bundle that's cheaper to craft yourself is planned as a craft. A crate comes off the queue when you fill it, a writ when you hand it in
- Writs: the "List for a price scan" and "Shop picked" buttons and the separate Auctionator list are gone; the queue does that now. You can delete the old "Crafting and Farming Forever Writs" list in Auctionator

## 1.11.0

- New Writs tab for Craftsman's Writs: every writ with its auction house price, the cost of the item it wants (crafted by your characters when that's cheaper), what the coin pouch gives back, and the gold each reputation point costs you. It starts with the writs whose item your characters can craft; tick the box to see them all. Sort by any column or show one level
- Writs: "List for a price scan" puts the writs and their items on an Auctionator list so one search gets today's prices. Pick writs with + and "Shop picked" lists what to buy and queues the crafts

## 1.10.2

- Sales: fixed profit showing a loss on items that made money. Taking the gold from a sale's mail counted that sale a second time, for no money, so the Sold column was up to double and the cost was taken twice. Your recorded sales are corrected the first time you log in. We're sorry for the confusion this caused. For a clean start, we recommend pressing Reset profit in the Sales tab after updating
- Sales: an item's cost is fixed when it sells and no longer moves with later price scans. Materials count at what you paid for them at the auction house; items made before costs were kept count at the cost to craft one at the time of the sale (still marked ~)

## 1.10.1

- Smoother at the auction house and mailbox: buying many materials in a row or taking gold from a lot of mail no longer redraws the Queue, Restock and Next step bar after every single purchase, just once when you're done

## 1.10.0

- Restock: when you don't have the gold for a full restock, the Restock tab says so and offers a partial one: the items that earn the most profit for their material cost, cut to what you can afford. Materials you already hold count as free, and anything you queued by hand is paid for first. The Craft column shows what fits out of what's needed, like 3/8 (part of smart goals, so the same switch turns it off)
- Restock: smart goals. An item's goal now follows your own sales: more of what sells well, fewer of what keeps expiring, and it keeps adjusting as you sell (recent days count most). One item's stock never costs more than a quarter of your gold to make, and daggers are stocked in pairs, since buyers usually want two. Smart goals show in blue, and the tooltip says why. A goal you set yourself always stays. The Options tab has a Stock level slider for how much to keep (50% of a day's sales to start with), and a switch to turn smart goals off

## 1.9.0

- Profit: a crafted item listed for more than 400% of its material cost (often one odd listing, like 7s of materials posted for 20g) now counts at 200% of the material cost, so it can't show a huge profit that won't sell. Its row on the Profit and Queue tabs says "check price" in orange, and the tooltip shows the real listing. Both numbers, and the limit itself, are on the Options tab

## 1.8.2

- Sales tab: new Reset profit button, top right. It starts your profit again from zero, from now, after asking you to confirm. Your sales history still counts for the chance to sell

## 1.8.1

- Sales profit: materials you already had, or gathered, now count at the market price on the day you craft with them. They used to count as free, so something made mostly from materials in your bags showed far too much profit. Sales already recorded keep the profit they had
- Items crafted before the add-on recorded costs count at today's cost to craft one, with their profit marked ~

## 1.8.0

- New Options tab, before Changelog, to switch parts of the add-on on or off and word its messages your way. You can also open it by right-clicking the minimap button, with `/cff options`, or from the game's own Options under AddOns
- Advertising: write your own message (put {profession} where your profession link goes), choose where it's posted, or turn advertising off, which removes the Ad box beside the chat and the Advertise button
- Quotes: write your own whisper using {item}, {count} and {price}. The quote margin moved from the Queue tab to Options
- Also in Options: open with the profession window, the minimap button, the Next step bar, the "scan now?" question at the auction house, and the reminder lines in chat
- Right-clicking the minimap button now opens Options. The Next step bar still folds with its own button or `/cff next`

## 1.7.1

- Sales profit now follows your gold: items crafted before 1.7.0, and materials you already had then, cost nothing instead of today's market price. Selling things made from your own gathered or old stock no longer shows a loss. Profit counted since 1.7.0 is worked out again this way

## 1.7.0

- Sales tab shows profit, not just sales: what you received after the auction house cut, less what the materials cost you. Materials bought at the auction house count at the price you paid, vendor materials at the vendor's price, and ones you gathered yourself at nothing. The boxes along the top show your profit today, in the last 7 days and in the last 30, with the sales total underneath (money still on its way included), and each item has Sales and Profit columns
- Profit starts from zero with this version: earlier sales stay out of it, though they still feed each item's chance to sell. Materials you already hold count at today's prices, and items crafted before this version count at today's cost to craft one, marked with ~
- Sales tab lists only the items your characters craft. Tick "Show everything I sell, not only my crafts" to include spare materials, drops and the rest

## 1.6.0

- Money on its way: the game mails a sale's money an hour after it sells. When one of your auctions sells, the add-on now tells you in chat how much is coming, counts down the hour on the Sales tab and the minimap button, and tells you when it's in your mailbox, wherever you are in the world
- Sales tab: four summary boxes along the top show the money on its way and what you earned today, in the last 7 days and in the last 30
- Minimap button: left-click opens or closes the window, right-click folds the Next step bar, drag moves it. It works with minimap button collectors and broker bars, and `/cff minimap` hides it
- New look: the windows, buttons, tabs and lists share one flat dark-blue style that matches the Craft Next bar, with striped rows, marked section headings and cleaner item icons
- Sales tab: Sells, Sold and Expired are now lined-up columns under a heading, and expired counts stand out in red

## 1.5.3

- Farm It: gathering is now the first step. Fetching from alts, the bank, the auction house, the mailbox and the vendor come after it, so you only go to town once for what's still missing
- Removed a leftover troubleshooting log that recorded every auction house search, and old settings from earlier versions, so your saved data is smaller

## 1.5.2

- Materials you hold now count however deep down they're used: wool in your bags makes the cloth that makes the bolt your queue needs, instead of the bolt being bought because cloth has a market price
- When what you hold covers only part of a material, that part is crafted and only the rest is bought (6 ore in the bank: smelt 6 bars, buy the other 4), instead of buying all of them whenever the missing ore is dearer than bars
- A price of zero (a bad scan result) no longer makes a material free or a result worthless; it counts as no price
- Craft Next no longer makes one craft too many when clicked right after a batch ends, before the plan has caught up

## 1.5.1

- Fixed the Craft Next progress bar counting one craft too many during a batch (2 / 7 when you queued 6)
- New look for the Craft Next bar: one blue colour scheme on the window's dark background, with a thin blue edge, instead of the grey-white bar
- Restocking no longer undercuts: it suggests the same price as the lowest listing
- Fixed known recipes being forgotten (your smelting recipes could vanish, so the add-on bought bars instead of smelting them and the profit for bar recipes came out too low). A recipe is now only removed when the game clearly says you no longer know it. Open the affected profession once to get missing recipes back

## 1.5.0

- Craft Next is now a progress bar too. While you craft it fills through the crafts of that recipe (say 7 / 20) and shows how long until all 20 are done, plus how long all your queued crafts will take. A thin blue line under it fills as you work through the whole queue. Before you start, it says how long the next batch takes. Times are learned from your own casts. Hover it for the time per recipe
- Craft Next opens the profession it needs: no more "Open Mining to finish Smelt Bronze". The button says "Open Mining: Smelt Bronze x12", opens it (switching from the one you have open) and starts crafting once it has loaded

## 1.4.0

- Shopping list: what you buy at the auction house leaves the list as soon as the purchase goes through. It counts as waiting in your mailbox, and once everything on the list is bought the queue says "Collect from your mailbox"; opening the mailbox counts what's really there
- Buying is easier to find: the buying step in the Queue tab and the Next step bar says to open the auction house's Shopping tab (Auctionator) and click the "Crafting and Farming Forever Queue" list, hover it for step-by-step help, and chat says the same when you open the auction house with something to buy
- Craft Next goes strictly in order: it never jumps ahead to a later craft while the current one (smelting bars, say) isn't finished. When it can't craft, the button says what to finish and how many are left, such as "Finish Smelt Bronze: 8 left", and the Next step bar keeps it on screen

## 1.3.0

- New Next step bar at the top of the screen: while anything is queued it shows the next thing to do (get from an alt, take from the bank, buy, sub-craft or craft), with a Craft Next button when it's time to craft. Fold it to one line with the - button; it disappears when the queue is empty. Drag to move it, or type `/cff next` to fold or unfold it. It stays out of the way in combat, dungeons, raids and battlegrounds
- Farm It: the separate Farm list is gone. The Next step bar now shows everything to gather and where (mining, herbs, skinning and so on together), with a Buy It button to go back to buying
- Queue with several characters: the to-do list, shopping list and Next step bar are now for the character you're logged in on. Crafts another character makes (say your tailor's, while you're on your blacksmith) aren't bought or made here; they're listed last as "Log in to <character>", and that character's list shows what to buy and craft when you log in there

## 1.2.3

- Queue: the tab is now a numbered to-do list in the order you'd do it. Getting materials from alts and your bank comes first, then buying, then sub-crafts, and your queued crafts last, so you reach the crafting station with everything on you. The Farm list follows the same order

## 1.2.2

- Queue: when something you queued is also needed as a material for another queued craft (tin bars for bronze, for example), the extra crafts now show under Sub-crafts. Before, Craft Next asked for more than you could see in the queue

## 1.2.1

- The Auctionator shopping list now only holds the materials you need to buy. It no longer lists the items you're crafting, which made it look like you should buy them

## 1.2.0

- New: Skill up mode on the Profit tab, for levelling. It lists the recipes that can still give you a skill point, cheapest per skill point first. Recipes are coloured orange, yellow and green as in the game, with each colour's chance of a point
- New: Changelog tab after Sales, with what changed in each version. It turns green after an update until you've had a look
- Profit and Skill up: click a column heading to sort by it, click again to reverse
- Profit: tick Hide unprofitable recipes to hide recipes that would make no profit
- Profit: the Advertise button moved under the profession tabs; hover it to see what it posts
- Restock: clear columns for Sells, AH, Have, Craft and Goal
- Restock: goals you set yourself are white, with a button to go back to the default; default goals are grey
- The window can be resized: drag the bottom-right corner, right-click it for the default size
- More reminders when auction house prices are over a day old: in chat after you log in, at the top of the Farm list, and every time you quote an order. Material tooltips mark prices that are a day or more old
- Farm list: Buy It switches back to buying and reopens the queue
- Farm It knows a few more places to gather from
- Crafting and Farming Forever needs both Auctionator and Syndicator to work properly. If Syndicator is missing or turned off, a reminder appears in chat when you log in
- Coming soon: TradeSkillMaster (TSM) support

## 1.1.0

- Queue: type the number of crafts straight into each row's box (0 removes the entry)
- Queue: Materials and Profit columns, both for the whole entry
- Queue: Shift - takes ten off, down to one
- Queue: the remove button is a red cross at the end of the row, away from - and +
- Queue: Clear asks before emptying the queue
- Profit: right-click or Ctrl-click + to type how many crafts to queue
- Restock: type an item's goal straight into its row's box
- Queue: Buy It and Farm It side by side, with the current mode lit
- Queue: entries that would lose money are shaded red, and Remove losing removes them after asking
- Queue: an entry another character has to craft shows their name
- Queue: says how to add crafts when it's empty
- Profit: Sells and Profit column headings; hover them for what they mean
- Sell chance is white when likely, so green only means profit (and item quality)
- Refresh explains what it does when you hover it
- Farm list: one close button instead of Back and ×
- "1 item" and "2 items" instead of "item(s)"

## 1.0.1

- Sales and Restocking rows no longer stay on "Loading..." after the item's name arrives
- Solid window background, so the game world and other windows no longer show through the lists

## 1.0.0

First release.

- Profit list for every recipe your characters know, with cheapest-path material costs
- One craft queue shared by all characters, with Craft Next
- Live Auctionator shopping list that leaves out what you own
- Farm It gathering list
- Restock goals and a Restocking tab at the auction house
- Sales history with chance to sell
- Advertise box and whole-order quotes with an adjustable margin
