# Development

## Requirements

- Lua 5.1 and `luac5.1`, the version the game client runs.
- `rsync` for `tools/deploy.sh`.
- A World of Warcraft: Forever install with Auctionator and Syndicator for testing in game.

## Layout

The game loads the files in the order listed in `CraftingAndFarmingForever.toc`. They share one namespace table (`ns`) and set no globals apart from the saved data and the slash command.

| File | Purpose |
| --- | --- |
| `Core.lua` | Events, debounce, saved data (including late loading), character records, money formatting |
| `Planner.lua` | Pure logic: cheapest-path cost, profit, expanding the queue into a plan. No game APIs. |
| `Sources.lua` | Generated table of where materials come from, for Farm It. Don't edit by hand. |
| `Farm.lua` | Turns the plan's materials into the Farm It gathering list |
| `Data.lua` | Every client read: item data, Auctionator prices and scan age, stock, recipe scanning |
| `Queue.lua` | Queue operations, restock goals, plan rebuilds, Craft Next |
| `Sales.lua` | Sold and expired records from mail, post tracking, chance to sell |
| `Shopping.lua` | Keeps the `Crafting and Farming Forever Queue` Auctionator list in sync, editing it in place |
| `UI.lua` | The tabbed window and its panes, the Next step bar (also the Farm It list), the recipe-page Queue button, the scan prompt, advertising, the slash command |
| `Posting.lua` | The Restocking tab in the auction house: candidate items, live price search, posting |
| `Changelog.lua` | Generated from `CHANGELOG.md` by `tools/gen_changelog.lua`: the What's new text. Don't edit by hand. |
| `WhatsNew.lua` | The Changelog tab's contents, lit until the installed version's notes are opened (`db.lastSeenVersion`), and the missing-Syndicator chat warning |

### Rules that keep it working

- **Keep `Planner.lua` free of game APIs.** Anything that reads the client goes in `Data.lua`, so the planner can be tested on its own.
- **Don't copy Auctionator, Syndicator or CraftProfit code.** Their licenses are All Rights Reserved. Call the public APIs (`Auctionator.API.v1`, Syndicator's API) and `LibAHTab` through LibStub at runtime, and write everything else against the game's API.
- **Item names load asynchronously.** Never show or send a name until the client has it, or you get question-mark items.
- **Saved data can arrive after `ADDON_LOADED`.** Don't create `CraftingAndFarmingForeverDB` early. `Core.lua` adopts it when it appears and assigns it at logout.
- **Characters are keyed by GUID,** because names aren't unique across linked realms.
- **Never anchor to Blizzard panels.** `ProfessionsFrame` slides as other windows open; anything anchored to it moves too. Anchor to `UIParent`.
- **Don't hook `ProfessionsRecipeListRecipeMixin.Init`.** It breaks the recipe rows on the Forever client.
- **Check available recipes with `Recipes.OpenRecipes()`,** the open window's own list. Stored profession IDs differ between parent and expansion professions.
- **Gear and bags must be posted in whole silver.** A copper price is refused with `AUCTION_HOUSE_SHOW_ERROR` 10.
- **Add-ons can't call `SendChatMessage` from a click.** The Ad box uses secure macro buttons, which only update out of combat. The other advertise paths prefill the chat box.
- **`Auctionator.API.v1.CreateShoppingList` replaces and re-expands the list.** Use it only to create the list; `Shopping.lua` edits it in place after that.

## Checks and tests

```sh
tools/check.sh
```

It also runs `luacheck` (settings and the list of game globals in `.luacheckrc`) and `shellcheck` on `tools/*.sh` when they are installed (`sudo pacman -S luacheck shellcheck`), and skips them with a note when they are not. A new game global the add-on reads must be added to `.luacheckrc`.

It must pass before every commit. It:

1. fails if a `.lua` file in the repository root isn't listed in the toc;
2. syntax-checks every add-on and test file with `luac5.1`;
3. fails on accidental globals (only `CraftingAndFarmingForeverDB`, `SLASH_CFF1` and `SLASH_CFF2` are allowed);
4. runs `tests/planner_test.lua` (logic) and `tests/smoke_test.lua` (flows).

Add a logic test to `planner_test.lua` and a flow test to `smoke_test.lua`. The smoke test loads the whole add-on against a stubbed client, so it catches runtime errors in code the logic tests don't reach. It can't prove the real client behaves like the stubs: a feature isn't working until it's been seen working in game.

## Deploying to the game

```sh
tools/deploy.sh ["/path/to/_forever_/Interface/AddOns"]
```

Copies only the `.toc`, `.lua` and `LICENSE` files into `AddOns/CraftingAndFarmingForever`. Then:

- changed files: `/reload` in game;
- a new file added to the toc, or a first install: restart the client.

## Debugging in game

- `/cff diag` prints diagnostics and stores them as `lastDiag` in the saved data.
- Saved data is only written on `/reload` or logout: `WTF/Account/<account>/SavedVariables/CraftingAndFarmingForever.lua`.
- Lua errors are easiest to read from BugSack's saved data.

## Regenerating Sources.lua

Farm It's data comes from the AllTheThings add-on's Camelot data set, the one Forever loads. Regenerate it when AllTheThings gets a meaningful update:

```sh
lua5.1 tools/gen_sources.lua "<AddOns>/AllTheThings/db/Camelot" > Sources.lua
tools/check.sh
```

The generated file carries AllTheThings' MIT notice. Keep it.

## Renaming migration

`tools/migrate-name.sh ["<_forever_ dir>"]` moves an install from the old name, CraftLedger. With no argument it refuses to run while the game is running. See the [user guide](USER_GUIDE.md#upgrading-from-craftledger).

## Releases

Work and commit on `main` locally. A version is published only once it has been confirmed working in game; passing tests aren't enough.

1. Add a `## x.y.z` section to `CHANGELOG.md` describing the changes, then `lua5.1 tools/gen_changelog.lua CHANGELOG.md > Changelog.lua`, and commit both. The section becomes the CurseForge changelog and the in-game Changelog tab, so write it for players: short, plain bullets about what they'll notice, no code names. `tools/check.sh` fails if `Changelog.lua` is out of date. Work in progress goes under `## Unreleased`, which the game doesn't show.
2. Try `tools/release.sh x.y.z --dry-run`. It runs the checks, finds the CurseForge game version that matches the toc's `## Interface`, and shows what it would upload, without changing anything.
3. `tools/release.sh x.y.z` (add `--beta` or `--alpha` for a test build) bumps `## Version` in the toc, commits, tags `vx.y.z`, pushes to GitHub, builds the zip with `tools/package.sh` and uploads it to CurseForge. CurseForge reviews the file before it goes live.
4. If the upload fails after the push, fix the cause and run `tools/release.sh x.y.z --upload-only`.

The script needs the CurseForge API token in `~/.config/cff/curseforge-token` (readable only by you, never in the repository) and `## X-Curse-Project-ID` in the toc.

`tools/package.sh [ref]` builds the zip on its own: `dist/CraftingAndFarmingForever-<version>.zip`, one `CraftingAndFarmingForever` folder with the toc, the `.lua` files, `LICENSE` and `Media`. GitHub's "Download ZIP" is rejected by CurseForge, because its folder is named `CraftingAndFarmingForever-main` and holds the whole repository.

The add-on is All Rights Reserved (`LICENSE`, chosen 2026-11-08). The license goes into the game folder and the release zip with the code. Contributions from others need their written agreement that their changes fall under these terms.

Before making the repository public:

- check that the name isn't taken on CurseForge and Wago;
- keep `THIRD-PARTY-NOTICES.md` and the README credits current when a dependency or data source changes.

AllTheThings licensing was checked on 2026-11-08: its GitHub repository carries only the MIT `LICENSE`. The packaged add-on also has a `LICENSE.txt` reading "All Rights Reserved unless otherwise explicitly stated", and the MIT `LICENSE` is that explicit statement. The author, Crieve, added the MIT `LICENSE` on 2026-02-16 and deleted the old All Rights Reserved file a minute later (commits `0f35cf3` and `90067a4`). AllTheThings' CurseForge page may still show All Rights Reserved; the repository is the current statement. The vendor seed prices in `Data.lua` were replaced on 2026-11-08 with prices seen at the game's merchants, because CraftProfit, their earlier source, changed from MIT to All Rights Reserved.
