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

**The core's health is the run's life total.** Brainrots can be downed, but
never destroyed — they get back up between waves, because the economy is
*collect brainrots* and permanently losing one fights that directly.

Every enemy that walks past your line takes a permanent bite out of the core,
and at zero the run ends. So losing your defenders is the *cause* of losing
rather than the definition of it: you watch what it costs instead of being told
you failed.

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

1. ~~Plot assignment~~ — done
2. ~~One enemy walking to a core, killed by the existing pet combat~~ — done
3. ~~Core health, endless waves, highest-wave score~~ — done
4. Base upgrades — box → chest → vault, raising core health and defence slots
5. Placement — only if ringing the core turns out to be too passive
6. More enemy types — a fast one and a tanky one change what a line needs
