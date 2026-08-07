# Brainrot Defense — Game Overview

Six players. One plot each. The zombies are coming and your brainrots are the
only thing between them and your base.

## Lore

The zombie infection took the world. The survivor who became the player fled
into the deep forest to die quietly — and found the brainrots living there
instead. They agreed to help.

They are not pets. They are allies who fight because the alternative is losing
the forest too.

## The loop

1. Enemies spawn at the edge of your plot and walk toward your **core**
2. Your stationed brainrots intercept and kill them
3. Dead enemies drop coins
4. Coins buy stronger brainrots at the **hatchery in the centre of the map**
5. Stronger brainrots survive harder waves and upgrade your base
6. Repeat, with more enemies

The centre is shared ground. Leaving your plot to hatch means your defence has
to hold without you — which is why brainrots engage on their own rather than
being commanded.

## Decisions already made

**The base has health, not the brainrots.** The economy is *collect brainrots*;
pets that die fight that directly, and cost healing, revives, death states and
respawn timers. Enemies that reach the core damage it and stop production until
repaired. Real stakes, nothing destroyed.

**Auto-engage, not tower defence.** No rounds, no placement puzzle. Each
brainrot holds a post and fights what comes near it. If defending required your
presence, you could never walk to the hatchery — the map would fight the design.

**Eggs stay.** A shop is satisfying; gacha is compulsive. A shop item is just an
egg with one outcome (`weights = { Pet = 1 }`), so both can exist with no new
system.

**Melee only, for now.** Ranged brainrots are free later: `attackRange` already
exists in `PetConfig`, so a sniper is one number.

**PvE only.** Stealing from other plots is the Steal a Brainrot hook, but PvP is
a different game and a much bigger conversation.

## Plot layout

Each plot under `Workspace.Plot` (named `1`–`6`) is expected to contain:

| Child | Type | Purpose |
| --- | --- | --- |
| `Spawn` | `BasePart` | where the owner spawns |
| `Core` | `BasePart` or `Model` | the thing being defended |
| `EnemySpawns` | `Folder` of `BasePart` | where enemies enter |

Anything missing is warned about once, not fatal — a half-built plot still
loads.

Brainrots ring the core rather than standing on placed posts. Fixed posts are
placement strategy, which belongs after we know defending is fun; a ring needs
nothing built and covers every approach, where a placed line only covers one.

## What carries over

Almost everything. The clicker and the defence game share far more than they
differ.

**Unchanged:** `DataService`, `CurrencyService`, `VfxService`, `PetService`
(retargeted only), `PetInventoryService`, `DropService` (enemies drop coins
exactly like rocks did), every file in `client/UI`, `Sound`, `Format`,
`Remotes`, `EggConfig`, `PetConfig`.

**Adapted:** `BreakableService` → `EnemyService`. Health, per-player damage
contribution, split rewards and respawn all carry; movement is the new part.
`BreakableHealth` needs no changes at all — it reads `Health`/`MaxHealth`
attributes off any part and does not know what a breakable is.

**Replaced:** `AreaService` and the barriers, by plots.

**Dropped:** `Targeting`. Defenders pick their own fights.

## Build order

1. **Plot assignment** — one player, one plot, spawn there
2. **One enemy** walking to one core, killed by existing pet combat
3. Base health and repair
4. Placement — only if ringing the core turns out to be too passive
5. Waves and scaling
6. Base upgrades

Stop after 2 and judge it. If defending one enemy with one brainrot does not
feel good, nothing after it will fix that.
