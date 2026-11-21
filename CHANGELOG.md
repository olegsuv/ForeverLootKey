## 1.3.2

- Fixed: after a click in the bags-full list the addon could say it threw the item away while the item was still on your cursor. On Forever the game doesn't let addons delete items, so the list now always leaves the throw to you (one click on the ground), without trying first.
- Bind-on-pickup loot is confirmed for you when auto loot is on.
- Two corpses looted right after each other are both auto looted (the second was skipped within 0.2 s).
- Items the game hasn't loaded yet are no longer silently left out of the bags-full list; they are loaded and shown on the next pass.
- The settings you had before the addon are remembered per character, so `/lootkey off` on an alt restores that character's own values (a value the addon had already set on another character is restored to the game default).
- Gray and white loot only lists items worth less than the loot itself; when there is nothing cheaper, the list stays hidden instead of asking you to throw away something more valuable.
- Shorter title on the bags-full list; the hint mentions the game's confirmation.

# Changelog

## 1.3.1

- Renamed to Forever Loot (same addon folder and settings, `/lootkey` still works).
- Bags full: quest items, green or better (what you won on a roll) and bind-on-pickup loot always get room.
- Bags full: the cheapest stack at the vendor goes, gray items and food / drink weaker than the best of its kind alike (the best food, the best drink and Well Fed food always stay). Gray and white loot only replaces cheaper junk.
- Bags full with loot left: whenever the junk can't go on its own (the game refuses, there is no junk, or the loot isn't worth more), a row of 4-5 bag slots (no wider than the loot window) appears under it with items you could throw away, cheapest at the vendor first and one of each kind (five gray items show as the cheapest one, same for food, drink, cloth and so on; never quest items or things that can't be sold). Each slot shows the icon, quality, count and vendor price in coins, with the bag tooltip on hover; one click throws it away and loots. Where the game doesn't let addons delete items (Forever), the click puts the item on your cursor (a hint under the slots says so): click on the ground to throw it away and the loot is taken into the freed slot. The list stays while loot is still waiting, also when you loot by hand.
- Bags full: an item is no longer put back by mistake while the game is still deleting it.
- Long option labels wrap inside the settings window.

## 1.3.0

- Optional, off by default: when your bags are full, auto loot throws away the least useful item so the new loot fits: the cheapest gray stack, else food / drink you carry 20+ better of (never Well Fed food). Gray loot only replaces cheaper gray junk. Settings: "Bags full: throw away gray junk or weak food/drink".
- Settings window: "More Forever addons" with a link to each Forever addon you don't have yet (nothing shown when you have them all).

## 1.2.1

- The settings window and the minimap button tooltip show the loaded version.

## 1.2.0

- Settings window: on/off, interact range and icon size sliders. Open it with `/lootkey`, the minimap button or the addons menu.
- Minimap button (drag it around the minimap, right-click shows the current interact target).

## 1.1.0

- Bigger icon over the interact target (64 instead of the client's 32), adjustable with `/lootkey icon <16-128>`.
- The icon stays visible even when the game shows a quest or loot marker.
- The name of the interact target is shown above it.

## 1.0.0

- First release for WoW Forever (1.60.1).
- One-key looting of the nearest corpse or object through soft-target interact.
- Instant auto loot.
- Icon over nearby interactable objects.
- `/lootkey` commands: `who`, `range`, `on`, `off`.
- English and Russian.
