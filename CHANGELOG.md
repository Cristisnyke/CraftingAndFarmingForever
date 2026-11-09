# Changelog

Each version's section is the CurseForge changelog; `tools/release.sh` uploads it. Add the next version's section before releasing.

## Unreleased

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
