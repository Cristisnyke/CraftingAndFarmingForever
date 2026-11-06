# CraftLedger

A World of Warcraft: Forever add-on for profitable crafting.

- **Profit window:** every recipe known by any of your characters, ranked by profit using Auctionator prices. Results that can't be sold on the auction house are left out.
- **Cheapest path:** each material is costed as the cheapest of AH, vendor or crafting it yourself.
- **Queue window:** one queue shared across your characters, filled from the profession window, with total profit and a Craft Next button.
- **Price check:** the buy list shows each material's price at the last scan, the price the profit assumes, so you can stop buying if the shopping list shows it has gone up.
- **Live shopping list:** one Auctionator list, `CraftLedger Queue`, holding only what you still need after your bags, bank and (with Syndicator) your alts' bags and banks.
- **Restock window:** keeps the AH stocked. Each profitable item gets a goal (separate defaults for stackable and single items, adjustable per item). What's on the AH (through Syndicator) and what you hold count towards it, and one button queues the difference.
- **Sales window:** records what you sell and what expires per day, week, month and all time, read from your auction house mail, and shows each item's chance of selling within 24 hours. The more data it gathers, the better the estimate.
- **Advertise:** buttons beside the chat window post your profession's link in Trade chat, offering your materials or a price based on material cost. They appear whenever you're in Trade chat, with or without the profession open. Crafting professions only, with a 60-second limit between posts.
- **Quotes:** each queued item shows its material cost, and its Quote button fills in a reply to your last whisper with the materials plus 10%.
- **Fresh prices:** asks for a new scan when Auctionator's data is more than 24 hours old.

## Requirements

- [Auctionator](https://www.curseforge.com/wow/addons/auctionator) (required)
- [Syndicator](https://www.curseforge.com/wow/addons/syndicator) (optional, for alts)

## Usage

Open a profession on each character once so CraftLedger can record its recipes. The windows open with the profession window (Queue only if it has something in it), and each one can be dragged anywhere and remembers where you put it.

| Command | What it does |
| --- | --- |
| `/craftledger` or `/cledger` | Show or hide both windows |
| `/craftledger queue` / `profit` | Show or hide one window |
| `/craftledger restock` | Show or hide the Restock window |
| `/craftledger refresh` | Re-read everything, same as the Refresh button |
| `/craftledger sales` | Show or hide the Sales window |
| `/craftledger advertise` | Post the selected profession in Trade chat |
| `/craftledger clear` | Empty the queue |
| `/craftledger auto` | Toggle opening with the profession window |
| `/craftledger diag` | Print diagnostics |

## Development

```sh
tools/check.sh    # syntax, accidental globals, tests (needs Lua 5.1 and luac)
tools/deploy.sh   # copy the add-on into the AddOns folder
```

`Planner.lua` has no game dependencies. Everything that reads the client is in `Data.lua`. `tests/smoke_test.lua` runs the add-on against a stubbed client, so it catches runtime errors but can't prove in-game behaviour.

## Credits

Vendor reagent seed prices come from CraftProfit by Vystery (MIT).
