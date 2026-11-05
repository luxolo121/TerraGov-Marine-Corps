# Low-population xeno support

SGS's normal hive can operate without an occupied or map-placed queen. This is
intentional fork behaviour, independent of the marine tactical AI system.

## Mother's Blessings

Drone, Hivelord, Hivemind and Larva retain the innate access granted by the fork's
`94809bc9f` customisation. Use the visible **Mothers Blessings** action button, the
existing keybinding, or the Hive Status purchase entry. Drone and Hivelord keep
access when becoming primordial. Losing temporary ruler powers does not remove
abilities that belong to the current caste.

This does not grant the menu to every caste. Existing psychic-point costs,
one-time purchases, prerequisites and mode restrictions still apply. Primordial
unlocks remain purchasable by eligible non-rulers. Encounter's explicitly
ruler-only ability purchases are unchanged.

## No placeholder queen required

For the normal hive, `requires_living_ruler = FALSE` means:

- Non-larva evolution progress continues without a ruler.
- Hive announcements and speech remain available, including after queen death.
- Healing does not incur the missing-queen penalty; ordinary weeds, damage,
  regeneration and fire restrictions still apply.
- The ruler-dependent nested-larva burrow condition no longer needs a queen on
  the same level. The guard against burrowing an attached player remains.
- Queen absence does not start the shipside orphan-collapse timer, and obsolete
  orphan timers/HUDs are cancelled. Neither Nuclear War nor Sovl War can resolve
  a queenless hive's round through that orphan-collapse callback.

Queens still exist and retain their actual powers. Ruler-only command authority,
overwatch, dropship control, caste limits/death cooldowns, and real queen-target
checks are not bypassed. Ordinary defeat conditions, including loss of silos,
nuclear outcomes and elimination, are unchanged. Other hive types retain their
previous ruler-dependence policy.

## Preservation findings (2026-11-05)

Comparing the old fork `c480c43` to the integrated feature baseline `8717351be`
found actual queen placements unchanged in Blue Moon (140,66), Research Outpost
(124,101), and Desparity (16,98), all local map z=1. Icy Caves contained no queen
in either source. No map placement was added or removed by this fix; normal-hive
functionality now does not depend on which map contains a dummy queen.

The four custom base-caste Blessings entries also survived the merge. The fixes
address hidden-button discoverability, the missing primordial Drone entry, a
duplicate Hivelord entry, and ruler cleanup using instance lookup on a list of
type paths. These findings should not be described as wholesale merge deletion.

Native regressions live in `code/modules/unit_tests/xeno_blessings.dm` and
`queenless_hive.dm`: real mob action creation/maturation, ruler cleanup, paid
queenless purchases, evolution, communications, healing and orphan/silo outcomes.
Compilation and automated coverage do not substitute for a human playtest.
