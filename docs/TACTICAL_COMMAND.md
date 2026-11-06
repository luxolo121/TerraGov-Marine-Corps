# Tactical Command: first-playtest guide

Feature branch: `feature/advanced-ai-command`. This is the marine command foundation, not a completed xeno AI rewrite or a balance pass.

## Start a test

1. Play a human with trained leadership (squad leader is the straightforward option). Human admins can also open the interface. The **Tactical Command** action sits alongside the existing designator. Command-role bans still apply to non-admin users.
2. Use the existing admin **Fun → Spawn AI squad** verb to spawn a small allied squad, or use existing NPC beacons. The new menu does not grant free reinforcements or turn player characters into bots.
3. Open Tactical Command, enter a name, and **Create squad**. Under nearby AI, **Recruit** the desired members. Recruitment requires the same faction and level, within seven tiles. **Transfer here** is an explicit move from another tactical squad.
4. Start with three to five riflemen, then add a corpsman. Existing Cadian/TGMC human AI can be recruited. Unrecruited NPCs retain their old behaviour, so recruit the units being evaluated.

## Make a defensive plan

### Command and designate directly in the game

The existing **Interact Designator** is the entry point; this revision does not add a second set of competing HUD actions. **Right-click its HUD button** to open the mode radial. The stock keybindings in this fork are **U** (Place Hologram / toggle designator) and **I** (Select Buildtype / alternate radial); existing personal bindings are unchanged. In Construction mode, the alternate action retains the existing construction picker.

- **Tactical orders** opens squad selection, Follow me/ally, Hold here/target, Guard zone, Patrol route, Set fallback and Retreat. Offscreen squads can still be selected by name. Select a recruited marine through ordinary Interact mode to select its whole squad.
- **Tactical tools** offers Select, Room, Rectangle, Route, Entrance and Choke, plus Save draft, Undo, Cancel draft and Toggle overlays. Choosing a drawing tool activates tactical targeting on the same designator.
- Target visible tiles using the normal selected-ability gesture: **middle-click**, or **shift-click** when the alternate targeting preference is enabled. Left-click weapon interactions are not repurposed. The button tooltip and chat confirmation identify the active tool and selected squad.
- Room selects the authored area's footprint; Rectangle uses two corners; Route adds ordered waypoints. Use **Save draft** for the name/classification or patrol-loop choice. Drawing and selecting do not silently issue orders.
- Entrance/Choke markings use the selected zone and a chosen facing. Place them on visible terrain, inside or directly beside that zone. Manual markers remain position/facing preferences, not a new AI defence policy.
- **Deselect — keep orders** is always available in the designator radial, even if the selected unit has left view. It clears your targeting/selection without cancelling the squad's assignment.

Private local overlays show zone edges, entrance/choke directions, numbered waypoints, selected-route connectors, drafts and selected squad members. The selected plan is emphasized. Overlays are click-through and limited to the commander's visible local game view; they do not reveal enemies or remote rooms. The overlay toggle hides them without changing orders. Permissions, level changes, logout and death clear stale rendering.

Tacview remains the full planner and roster editor for creating/recruiting/transferring squads and managing saved plans. It shares selections and geometry with the designator, rather than maintaining a second plan. Its new command-board icon is distinct from the minimap.

### Navigate the Tacview map

**Middle-mouse drag** pans the map. **Mouse-wheel** zooms toward the pointer, within 1–3×. Neither gesture places a designation. The +/- controls remain available; clicking the zoom readout resets zoom and pan. Release outside the map also ends a drag. Normal primary clicks continue to place targets at the correctly scrolled/zoomed map coordinates.

### Use the full planner

- **Room:** click the map to preview that exact authored area's footprint. Areas with the same display name are not combined. Large outdoor areas should be bounded using Rectangle instead.
- **Rectangle:** click two opposite corners, inspect the shaded preview, name it, then save. Nothing is ordered simply by drawing or clicking the map.
- Saved zones have independent names and purposes (**Guard**, **Fallback**, **Staging**). Changing a purpose does not redraw the footprint or alter the map's engine areas. Actual squad assignments are separate: a dock can be one squad's guard area and another's fallback.
- Select a zone and use **Entrance** or **Choke**, choose a facing, then click within or immediately beside it. These markers influence guard positions and idle facing; they are not independent squads or an autonomous defence planner.
- **Route:** click waypoints in order, undo a mistaken last point if needed, and save as a loop or back-and-forth patrol. It takes at least two points. A patrol waits for the point marine to arrive and the squad to regroup before advancing.

## Give orders

Select a named squad, then:

- **Follow me:** keep a formation around the commander while engaging visible threats without pursuing them as a movement goal.
- **Hold here / Hold at target:** take positions around the commander or a clicked map location.
- **Guard [zone]:** spread out inside the selected footprint, preferring marked approaches. Once inside, movement paths stay inside the zone, including around concave boundaries.
- **Patrol [route]:** follow the saved ordered waypoints with regrouping and a brief arrival dwell.
- Choose a **Fallback zone** to establish the destination. This alone does not move anyone. **Retreat to fallback** gives the actual withdrawal order and remains active until another order is issued.

The existing interact designator is also a quick-order tool: selecting a recruited marine selects its **whole tactical squad** for a tile→Hold or living ally→Follow command. Individual medical/pickup/attack requests do not silently override a squad assignment; the designator tells you when to use Tactical Command or release the unit first.

The added tactical radial exposes the same orders and drafts in-world; legacy construction and unmanaged-unit interactions remain available. This UI revision does **not** implement the later path/formation, automatic unmarked-zone perimeter patrol, role-specialization, fire-avoidance or zone-classification behaviour changes from the playtest list.

**Deselect — keep orders** clears both command-view and legacy designator selection/highlights, not the squad's assignment. Use Hold to stop or replace a patrol/follow order. Release/Disband returns NPCs to legacy autonomous AI; it is not a stop command. Roster entries remain accessible after a unit leaves view, and show activity such as regrouping, fighting, supporting, or a blocked route.

## What this build changes in the brain

Managed NPCs use a persistent squad assignment as their movement authority. A combat target is a target to shoot, not a replacement destination. The existing controller lifecycle, equipment, firing, medical actions and movement clock remain in use, but greedy escort/pursuit/task selection is bypassed for recruited units.

Formation slots are distinct where space allows. Friendly occupancy is respected instead of shoving through players. Support work is deliberately local: medics and engineers only take adjacent work compatible with their assigned position. Folding barricades opened by managed NPCs are scheduled for restoration after passage when clear; pre-existing openings are not supposed to be closed. Player takeover releases the unit and cancels queued AI work.

## First playtest checklist

Keep the number and loadouts of NPCs fixed when comparing with the earlier round. These are acceptance checks to perform in play, not claims that full-round behaviour has already passed.

1. Draw an outdoor perimeter; select an indoor room; reclassify one without losing its shape. Confirm the preview matches the real room.
2. Recruit two squads. Transfer one member. Select a squad after it moves offscreen and clear selection without cancelling its order.
3. Guard a perimeter and bait it with disposable xenos outside. The marines may shoot outward, but should not leave the footprint to chase.
4. Follow a moving player while xenos approach from the side. Units should keep regrouping, not abandon the player for a pursuit.
5. Patrol three waypoints, including two close together. Check real traversal, regrouping and both loop/back-and-forth modes.
6. Set a fallback, select some unrelated zone, then Retreat. They must use the squad's fallback and stay there until reassigned.
7. Channel an action beside passing NPCs; cross a folding barricade with them; verify spacing, no shoving, and safe restoration.
8. Add a corpsman, hurt a nearby member, and place an injured friendly farther away. Observe useful local treatment without the medic wandering out of the squad.
9. Block a route or choose an inaccessible region. Look for a visible blocked status and recover by giving a reachable order.

Useful feedback: squad name/order, map location, what the player did, expected result, actual result, and whether the roster reported a blockage. A screenshot of the command map and roster is more useful than "AI stuck" alone.

## Deliberate limits

- Plans are faction-shared and round-local; they are not saved across rounds or map changes. Commanders of the same faction can change the shared plan; personal selections are not shared.
- The map uses existing static minimap terrain and friendly positions, not enemy contacts. Editing and new assignments are current-level only; there is no autonomous multi-level shuttle/elevator routing.
- Initial caps: 32 zones (1,600 tiles each), 32 routes (32 points each), 16 squads (24 members each), 16 approach markers per zone. The existing overall AI instance cap still applies.
- Support is bounded, not a complete logistics system. No long-distance casualty retrieval, autonomous ammunition supply, full engineer planning, offensive clearing/scouting, or new NPC economy is promised here.
- Retreat is manual. Damage-rate-based xeno judgement, hive construction blueprints, new xeno squad policy and balance remain later work.
- Automated compilation, native scenario tests and browser-render proof are recorded separately from actual human playtesting. Neither passing tests nor a screenshot establishes that the squad feels good in a live fight.
