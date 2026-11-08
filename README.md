# Crafting and Farming Forever

A World of Warcraft: Forever add-on for profitable crafting.

- **Profit tab:** every recipe known by any of your characters, ranked by profit using Auctionator prices. Results that can't be sold on the auction house are left out.
- **Cheapest path:** each material is costed as the cheapest of AH, vendor or crafting it yourself.
- **Queue tab:** one queue shared across your characters, filled from the profession window, with total profit and a Craft Next button.
- **Price check:** the buy list shows each material's price at the last scan, the price the profit assumes, so you can stop buying if the shopping list shows it has gone up. Each material and section also shows its total, and the Queue tab compares what's left to buy with the gold you're carrying.
- **Live shopping list:** one Auctionator list, `Crafting and Farming Forever Queue`, holding only what you still need after your bags, bank and (with Syndicator) your alts' bags and banks.
- **Restock tab:** keeps the AH stocked. Each profitable item gets a goal (separate defaults for stackable and single items, adjustable per item). What's on the AH (through Syndicator) and what you hold count towards it, and one button queues the difference. **Show Queue** opens the queue beside it.
- **Restocking at the auction house:** a Restocking tab beside Auctionator's. It lists what you can craft that's in your bags, with how much your goals want on the AH first. Select an item to see the lowest price right now: it suggests just under that (1c for stackable goods, 1s for gear and bags, which only take whole silver), unless the lowest is yours or would lose you money. It asks first if a vendor would pay more than the price earns after the AH cut. One button posts it and moves on to the next.
- **Sales tab:** records what you sell and what expires per day, week, month and all time, read from your auction house mail, and shows each item's chance of selling within 24 hours. The more data it gathers, the better the estimate.
- **Advertise:** a small Ad box beside the chat window opens a list of your crafting professions. One click posts that profession's link, offering your materials or a price based on material cost, then the list closes. A picker in it chooses Trade, Guild, Say or Yell, with or without the profession open. The button on the Profit tab and the slash command fill in the chat box instead, for Enter to send. Crafting professions only, with a 60-second limit per destination.
- **Quotes:** each queued item shows its material cost, and its Quote button fills in a reply to your last whisper with the materials plus 10%.
- **Fresh prices:** asks for a new scan when Auctionator's data is more than 24 hours old.

## Requirements

- [Auctionator](https://www.curseforge.com/wow/addons/auctionator) (required)
- [Syndicator](https://www.curseforge.com/wow/addons/syndicator) (optional, for alts)

## Usage

Open a profession on each character once so Crafting and Farming Forever can record its recipes. Crafting and Farming Forever is one window with a tab for each part. It opens with the profession window on the tab you last used, and can be dragged anywhere. It stays exactly where you put it when other windows open or close.

| Command | What it does |
| --- | --- |
| `/cff` or `/craftfarm` | Show or hide the window |
| `/cff queue` / `profit` | Open that tab, or close it if it's showing |
| `/cff restock` | Open that tab, or close it if it's showing |
| `/cff refresh` | Re-read everything, same as the Refresh button |
| `/cff sales` | Open that tab, or close it if it's showing |
| `/cff advertise` | Post the selected profession to the chosen destination |
| `/cff clear` | Empty the queue |
| `/cff auto` | Toggle opening with the profession window |
| `/cff diag` | Print diagnostics |

On the Queue tab, **Farm It** turns the list into what to gather yourself and how: which vein or herb, which zones, which creatures, what to disenchant. The window swaps for a small list you can leave on screen, which counts down as you gather. Your own zone comes first, and hovering a row shows everything known. Press **Back** to return. The Auctionator list stays the same either way.

## Development

```sh
tools/check.sh    # syntax, accidental globals, tests (needs Lua 5.1 and luac)
tools/deploy.sh   # copy the add-on into the AddOns folder
```

`Planner.lua` has no game dependencies. Everything that reads the client is in `Data.lua`. `tests/smoke_test.lua` runs the add-on against a stubbed client, so it catches runtime errors but can't prove in-game behaviour.

## Credits

- Item sources are generated from [AllTheThings](https://github.com/ATTWoWAddon/AllTheThings) data (MIT License, see the notice in `Sources.lua`).

Vendor reagent seed prices come from CraftProfit by Vystery (MIT).
