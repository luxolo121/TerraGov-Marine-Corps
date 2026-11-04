# Custom fork upstream integration

## Baselines

- Integration date: 2026-11-04.
- Previous fork: `c480c43f63c9171cf849313a57cd7a3c2d542cf4`.
- Upstream: `tgstation/TerraGov-Marine-Corps` at `193da9a212ab5c4132e8445dbab5905f3b3f369a`.
- Common ancestor: `e2bc9555e138fe2823ac602ddb5e62d7f08a5f10`.
- Preserves the fork's 41 unique commits and integrates 1,048 upstream commits through a real merge.
- Code remains under the repository's AGPL-3.0 license; existing code and asset notices remain in place.

## Preservation and compatibility

The small-population access, skills, role/evolution gates, disk timings, CAS availability,
fixed weapon seasons, medical/balance modifiers, custom weapons, Cadian content, ODM prototype,
and custom map placements remain. New advanced marine/xeno command AI is not part of this update.

Important adaptations:

- Barricade changes now live in upstream's split files. Acid-smoke damage, armor, wiring time and construction changes were retained; the obsolete monolithic file was removed.
- The three one-minute nuclear-disk segments are overrides on the nuclear subtype, leaving unrelated generic code generators at upstream defaults.
- Fixed all-heavy availability includes upstream's new remote-vehicle gear as well as the custom RL-222 and ammunition.
- The custom Guardsman remains alongside upstream's new PMC loadouts.
- The ODM beam uses named icon/icon-state arguments following upstream's parameter reordering.
- Radiation, Ravager and medical changes use current upstream APIs. Shared marine damage/penetration factors also cover new ammo in already-scaled families, without individually rebalancing it.
- RL-222 impact callbacks no longer delete the globally shared ammo datum. They end projectile range after hit processing; deleting the projectile inside the callback would break the subsequent damage call. APHE avoids a second detonation at range-end after a living hit.
- Non-rulers retain primordial purchase access through upstream's flag system. Normal affordability and one-time checks are retained: the old early return unintentionally bypassed these as well as the ruler gate.
- Vending remains role/squad-unrestricted. ID-less purchasing now returns safely instead of dereferencing a missing card; working ID-less purchasing was not present before.
- Map-placed xenos can initialize before mode selection. Hive tier calculations now handle that state without reading a null mode, retaining the established calculation once a mode exists.
- MP-19 timing constants are normalized from 0.12/0.07 seconds to 0.15/0.10 seconds. At the standard 20 FPS, the autofire scheduler already rounds these intervals up to those firing ticks; this preserves the unmodified weapon's actual cadence and satisfies the existing timing invariant. Attachment/modifier combinations have not been exhaustively playtested.

Asset reconciliation compared state metadata and decoded pixels, not PNG file hashes:
all 17 fork-added and 3 fork-modified states survived across five conflicted DMIs
(787 final states, 2,285 frames). Three maps were compared by decoded turf contents
(54,474 tiles); the custom queen placements and upstream map edits do not overlap.

## Build and CI

Use `dependencies.sh`, not the outdated root Dockerfile, for toolchain versions.
The verified isolated environment uses BYOND 516.1659, Node 22.11.0, Yarn 4.9.1,
rust-g 3.11.0 and the upstream SpacemanDMM suite-1.11 release. The rust-g release
requires GLIBC 2.39; Ubuntu 24.04 supplies it without modifying a game host.
The official Linux asset downloaded from rust-g's 3.11.0 release reports 3.10.0
through its own version function. The loaded file was verified (SHA-256
`841c139a760a57fd999483fc49da45967b6c5c8a1050465f103322f7f1bb51f4`);
this release-label discrepancy was not hidden by changing the game's version check.

CI branch filters include both `main` and legacy `master`. Scheduled changelog and
TGS-DMAPI workflows use the repository's configured default branch. The CI SQL
fixture and workflow agree on their disposable database name and credentials.
OpenDream's current compiler release targets .NET 10, so its CI runtime was updated
from 9.x to 10.x after validating the distributed compiler with .NET 10.0.14.
The alternate-BYOND test discovery step now emits its declared job output, including
an explicit empty array when no alternate versions are configured, so matrix
expansion does not try to parse an absent output as JSON.
The main-map test matrix now takes the maximum client version from the collected
dependency output rather than a nonexistent matrix property; the alternate-test
aggregator explicitly declares that dependency. Changelog and documentation jobs
use supported checkout/script/cache action versions.

Strict all-map compilation uses:

```sh
tools/build/build --ci dm -DCIBUILDING -DCITESTING -DALL_MAPS -Werror --no-warning=TG0001 --no-warning=loop_checks
```

Use the long warning-exception option: the build wrapper does not correctly parse
the two-letter `-NW` alias. Disabling loop checks is intentional in upstream test
mode; other unexpected compiler warnings remain fatal.

Focused regression tests live in `code/modules/unit_tests/custom_ammo.dm`,
`custom_hive.dm` and `fork_upgrade.dm`: repeated RL-222 hits, pre-mode hive
initialization, nuclear segment completion, heavy-season
availability, actual barricade acid damage, Guardsman equipment and ID-less vending.

## Before deployment

This repository update does not deploy or restart a live server. Back up player data
and inspect compatibility before deployment. In particular, upstream removed old
SR-42 item paths such as `/obj/item/ammo_magazine/sniper/elite`. A saved loadout
containing such a path can fail JATUM deserialization before loadout-version fixes
run. No production saves were inspected, changed or reset during this integration.

Source review and automated tests are not a multiplayer balance playtest. Existing
quirks such as the DU probability expression and the ODM prototype's unused fuel
fields were not silently redesigned.

## Verification results

- BYOND 516.1659: strict all-map compile and ordinary CI/unit-test compile both pass on the final game source; the normal non-test release build has zero errors and zero warnings.
- Research Outpost and Big Red: **48/48 unit tests each**, including seven focused custom regressions; no DM runtimes, fresh success markers and native process exit 0 on both maps.
- DreamChecker: no diagnostics.
- OpenDream compiler and annotator: pass against all 2,638 tracked DM/DME source files.
- Assets/maps: 1,455 DMI files, 284 DMM files and full maplint pass.
- TGUI: formatting/lint/types, 35 tests across seven files, and production bundle build pass.
- Changelog, miscellaneous checks (2 PHP and 113 JSON files), include ordering, file-directory and grep checks pass.
- Six updated CI/build/docs/changelog workflows pass actionlint. All 12 workflow YAML files parse; 30 shell steps pass syntax checking. Alternate-test discovery was exercised with both no configured versions and one configured version.

The unchanged `remove_guide_comments`, `round_id_linker`, `run_approval` and `stale`
bot workflows still have inherited retired-action/runner findings. They were not
re-enabled or redesigned as a side effect of this integration.

Earlier runs on an internal Docker network passed the game tests but exited with
signal 11 after shutdown. Minimal worlds also exhibited shutdown problems under
network isolation. The final runs used a disposable bridge with outbound access,
no published ports and DreamDaemon `-invisible`; the identical compiled unit-test
binary then passed and exited normally on both maps. This is a validated fixture
correction, not a game-code teardown fix or a claim of an exact BYOND engine cause.
Disposable databases, containers and networks were removed after verification.

These are local isolated checks, not a claim of a completed GitHub-hosted run,
interactive-client playtest, full runtime map matrix or live deployment.
