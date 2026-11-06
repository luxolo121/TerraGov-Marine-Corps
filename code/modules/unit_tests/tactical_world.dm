/// Native scenarios substitute only external client authority/visibility. Shared identity, faction,
/// stale-z validation, draft state, order dispatch and rendering are the actual production paths.
/datum/tactical_command/test_world
	var/test_authorized = TRUE
	var/test_access_checks = 0
	var/list/test_visible = list()

/datum/tactical_command/test_world/has_command_access()
	test_access_checks++
	return test_authorized

/datum/tactical_command/test_world/world_visible_tiles()
	return test_visible.Copy()

/// Every entry point must reject unauthorized ownership, a faction change and stale level prompts.
/datum/unit_test/tactical_command_dispatch_authorization/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	user.faction = FACTION_TERRAGOV
	var/datum/tactical_command/unprivileged = allocate(/datum/tactical_command, user)
	unprivileged.plan = plan
	TEST_ASSERT(!unprivileged.dispatch("squad_create", list("name" = "Denied", "z" = user.z), user), "Production dispatcher must reject a clientless, unauthorized commander")
	TEST_ASSERT_EQUAL(length(plan.squads), 0, "Rejected production access must not create squads")
	var/datum/tactical_command/test_world/command = allocate(/datum/tactical_command/test_world, user)
	command.plan = plan
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human)
	other.faction = FACTION_TERRAGOV
	TEST_ASSERT(!command.dispatch("squad_create", list("name" = "Other user", "z" = user.z), other), "Another user must not operate this commander's personal state")
	command.test_authorized = FALSE
	TEST_ASSERT(!command.dispatch("squad_create", list("name" = "Revoked", "z" = user.z), user), "Revoked command access must be rechecked on every dispatch")
	command.test_authorized = TRUE
	user.faction = FACTION_SOM
	TEST_ASSERT(!command.dispatch("squad_create", list("name" = "Wrong faction", "z" = user.z), user), "Faction changes must not grant access to the previous faction plan")
	user.faction = FACTION_TERRAGOV
	command.dispatch("squad_create", list("name" = "Stale level", "z" = user.z + 1), user)
	TEST_ASSERT_EQUAL(length(plan.squads), 0, "A stale native prompt and a stale browser request must both leave the plan untouched")
	TEST_ASSERT(command.notice_error, "Stale level denial needs actionable feedback")

/// Alternate between world targeting and shared planner dispatch throughout one real draft.
/datum/unit_test/tactical_world_draft_roundtrip/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/turf/start = run_loc_floor_bottom_left
	var/turf/end = locate(start.x + 2, start.y + 2, start.z)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, start)
	user.faction = FACTION_TERRAGOV
	var/datum/tactical_command/test_world/command = allocate(/datum/tactical_command/test_world, user)
	command.plan = plan
	command.test_visible = list()
	command.test_visible[start] = TRUE
	command.test_visible[end] = TRUE
	command.dispatch("tool", list("tool" = "rectangle", "z" = start.z), user)
	TEST_ASSERT(command.world_click(start), "Visible world corner should enter the shared rectangle draft")
	command.dispatch("map_click", list("x" = end.x, "y" = end.y, "z" = end.z), user)
	TEST_ASSERT_EQUAL(length(command.preview), 9, "World first corner and planner second corner must share exactly one draft")
	command.dispatch("draft_undo", list("z" = start.z), user)
	TEST_ASSERT_EQUAL(command.anchor, start, "Undo of second rectangle corner should retain the first")
	TEST_ASSERT_EQUAL(length(command.preview), 0, "Undo must remove only the preview")
	command.world_click(end)
	command.dispatch("zone_save", list("name" = "Combined drawing", "purpose" = "guard", "z" = start.z), user)
	var/datum/tactical_zone/zone = plan.find_zone(command.selected_zone)
	TEST_ASSERT(zone && zone.contains(start) && zone.contains(end), "The shared save must preserve the world-authored footprint")
	command.dispatch("tool", list("tool" = "entrance", "z" = start.z), user)
	command.dispatch("marker_facing", list("direction" = EAST, "z" = start.z), user)
	command.world_click(start)
	TEST_ASSERT_EQUAL(length(zone.markers), 1, "World entrance placement must edit the same selected zone")
	var/datum/tactical_marker/marker = zone.markers[1]
	TEST_ASSERT_EQUAL(marker.direction, EAST, "Native facing choice must survive shared dispatch")
	command.dispatch("draft_undo", list("z" = start.z), user)
	TEST_ASSERT_EQUAL(length(zone.markers), 0, "Undo must remove the last native marker without deleting the zone")
	command.dispatch("tool", list("tool" = "route", "z" = start.z), user)
	command.world_click(start)
	command.world_click(end)
	command.dispatch("route_save", list("name" = "Route", "loop" = FALSE, "z" = start.z), user)
	var/datum/tactical_route/route = plan.find_route(command.selected_route)
	TEST_ASSERT(route && route.waypoints[1] == start && route.waypoints[2] == end, "World route must save in clicked order")
	TEST_ASSERT(!route.loop, "Native back-and-forth route must not silently become a loop")
	command.dispatch("tool", list("tool" = "route", "z" = start.z), user)
	var/turf/hidden = get_step(start, NORTH)
	TEST_ASSERT(!command.world_click(hidden), "Invisible world coordinates must be refused before any drafting mutation")
	TEST_ASSERT_EQUAL(length(command.draft_route), 0, "A rejected hidden click must not append a waypoint")
	command.dispatch("clear_draft", list("z" = start.z), user)
	TEST_ASSERT_EQUAL(length(plan.routes), 1, "Cancel must not remove an already saved patrol")

/// An offscreen deselect is not a stop command, and native orders must enforce the same z guard.
/datum/unit_test/tactical_world_order_and_deselect/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/turf/start = run_loc_floor_bottom_left
	var/turf/end = get_step(start, EAST)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, start)
	user.faction = FACTION_TERRAGOV
	var/mob/living/carbon/human/member = allocate(/mob/living/carbon/human, start)
	member.faction = FACTION_TERRAGOV
	member.AddComponent(/datum/component/ai_controller, /datum/ai_behavior/human)
	var/datum/tactical_squad/squad = new(plan, "Test team")
	TEST_ASSERT(squad.add_member(member), "Fixture must be a real recruited human AI")
	var/datum/tactical_route/route = plan.create_route("Patrol", list(start, end))
	var/datum/tactical_command/test_world/command = allocate(/datum/tactical_command/test_world, user)
	command.plan = plan
	command.dispatch("squad_select", list("id" = squad.id, "z" = start.z), user)
	command.dispatch("route_select", list("id" = route.id, "z" = start.z), user)
	TEST_ASSERT(command.world_execute("order", list("order" = "patrol")), "Native quick order must reach the actual squad API")
	TEST_ASSERT_EQUAL(squad.route, route, "Patrol command must use the shared selected route")
	command.test_visible.Cut()
	TEST_ASSERT(command.world_execute("deselect"), "Deselect must work with no visible squad member")
	TEST_ASSERT_NULL(command.selected_squad, "Deselect must clear shared personal selection")
	TEST_ASSERT_EQUAL(squad.order, "patrol", "Deselect must not stop a patrol")
	TEST_ASSERT_EQUAL(squad.route, route, "Deselect must not discard the assigned route")
	command.dispatch("squad_select", list("id" = squad.id, "z" = start.z), user)
	member.forceMove(locate(start.x, start.y, start.z == 1 ? 2 : 1))
	TEST_ASSERT(!command.world_execute("order", list("order" = "hold")), "Native quick order must reject a squad now on another level")
	TEST_ASSERT_EQUAL(squad.order, "patrol", "Rejected replacement must preserve the old assignment")

/// Render actual geometry into images: no hidden tile, no clickable decoration, bounded lifetime.
/datum/unit_test/tactical_world_overlay_lifecycle/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/turf/start = run_loc_floor_bottom_left
	var/turf/end = locate(start.x + 3, start.y, start.z)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, start)
	user.faction = FACTION_TERRAGOV
	var/datum/tactical_command/test_world/command = allocate(/datum/tactical_command/test_world, user)
	command.plan = plan
	command.check_level()
	var/datum/tactical_zone/zone = plan.create_rectangle("Visible edge", start, end)
	zone.add_marker("entrance", start, WEST)
	zone.add_marker("choke", end, EAST)
	var/datum/tactical_route/route = plan.create_route("Visible stroke", list(start, end))
	command.selected_zone = zone.id
	command.selected_route = route.id
	var/list/visible = list()
	visible[start] = TRUE
	visible[get_step(start, EAST)] = TRUE
	command.build_world_images(visible)
	var/saw_entrance = FALSE
	var/saw_boundary = FALSE
	var/saw_route = FALSE
	for(var/image/decoration AS in command.world_images)
		TEST_ASSERT(visible[decoration.loc], "Renderer must never create a world image on a tile outside authorized visibility")
		TEST_ASSERT_EQUAL(decoration.mouse_opacity, MOUSE_OPACITY_TRANSPARENT, "World overlays must never intercept gameplay clicks")
		saw_entrance = saw_entrance || decoration.icon_state == "entrance"
		saw_boundary = saw_boundary || decoration.icon_state == "boundary"
		saw_route = saw_route || decoration.icon_state == "route"
	TEST_ASSERT(saw_entrance && saw_boundary && saw_route, "Real entrance, boundary and selected patrol stroke must all be drawn")
	command.world_overlay_enabled = TRUE
	command.world_target_order = "hold"
	command.draft_route = list(start, end)
	command.world_invalidated()
	TEST_ASSERT_EQUAL(length(command.world_images), 0, "Logout/z/death invalidation must discard every image")
	TEST_ASSERT(!command.world_overlay_enabled, "Invalidation must stop future refreshes")
	TEST_ASSERT_NULL(command.world_target_order, "An armed order cannot survive invalidation")
	TEST_ASSERT_EQUAL(length(command.draft_route), 0, "A partial draft must not leak into another level/login")
	command.build_world_images(visible)
	command.test_authorized = FALSE
	command.world_overlay_enabled = TRUE
	command.refresh_world_overlay()
	TEST_ASSERT_EQUAL(length(command.world_images), 0, "Permission loss must remove the previous images before refusing refresh")
	TEST_ASSERT(!command.world_overlay_enabled, "Revoked permission must unregister processing")

/// Record the target at the legacy/tactical routing boundary; authorization and mutation are
/// exercised separately above, without fabricating a network client in the native runner.
/datum/action/ability/activable/build_designator/test_world
	var/datum/tactical_squad/received_squad

/datum/action/ability/activable/build_designator/test_world/designate_tactical_squad(atom/target, datum/tactical_squad/squad)
	received_squad = squad
	return TRUE

/datum/unit_test/tactical_world_legacy_selection_sync/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/turf/start = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, start)
	user.faction = FACTION_TERRAGOV
	var/datum/tactical_command/test_world/command = allocate(/datum/tactical_command/test_world, user)
	command.plan = plan
	var/datum/action/tactical_command/access = allocate(/datum/action/tactical_command, user)
	access.give_action(user)
	access.command_ui = command
	var/datum/action/ability/activable/build_designator/test_world/designator = allocate(/datum/action/ability/activable/build_designator/test_world, user)
	designator.give_action(user)
	user.actions_by_path[/datum/action/ability/activable/build_designator] = designator
	var/mob/living/carbon/human/member = allocate(/mob/living/carbon/human, start)
	member.faction = FACTION_TERRAGOV
	member.AddComponent(/datum/component/ai_controller, /datum/ai_behavior/human)
	var/datum/tactical_squad/alpha = new(plan, "Alpha")
	TEST_ASSERT(alpha.add_member(member), "Legacy selection fixture needs a recruited marine")
	var/datum/tactical_squad/bravo = new(plan, "Bravo")
	designator.selected_mob = member
	command.dispatch("squad_select", list("id" = bravo.id, "z" = start.z), user)
	TEST_ASSERT_NULL(designator.selected_mob, "Selecting Bravo in the planner must clear Alpha's old individual representative")
	designator.designate_target(get_step(start, EAST))
	TEST_ASSERT_EQUAL(designator.received_squad, bravo, "A tile click after planner selection must route to Bravo, not Alpha or global legacy designation")
	designator.selected_mob = member
	command.dispatch("squad_create", list("name" = "Charlie", "z" = start.z), user)
	var/datum/tactical_squad/charlie = plan.find_squad(command.selected_squad)
	TEST_ASSERT(charlie && charlie != alpha && charlie != bravo, "Create fixture must select a genuinely new squad")
	TEST_ASSERT_NULL(designator.selected_mob, "Creating Charlie must also clear the stale Alpha representative")
	COOLDOWN_RESET(designator, order_cooldown)
	designator.designate_target(get_step(start, NORTH))
	TEST_ASSERT_EQUAL(designator.received_squad, charlie, "A tile click after creation must route to the new shared selection")
	var/mob/living/carbon/human/unmanaged = allocate(/mob/living/carbon/human, start)
	unmanaged.faction = FACTION_TERRAGOV
	designator.select_mob_to_interact(unmanaged)
	TEST_ASSERT_NULL(command.selected_squad, "Explicit unmanaged selection must opt out of the previous tactical squad")
	TEST_ASSERT_EQUAL(designator.selected_mob, unmanaged, "Opting out must preserve the intended legacy individual target")

/datum/unit_test/tactical_world_reenable_after_z_change/Run()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	user.faction = FACTION_TERRAGOV
	var/datum/tactical_command/test_world/command = allocate(/datum/tactical_command/test_world, user)
	command.editor_z = user.z + 1
	command.draft_route = list(get_turf(user), get_step(user, NORTH))
	TEST_ASSERT(command.set_world_overlay(TRUE), "Deliberate re-enable must accept the commander's new level")
	TEST_ASSERT(command.world_overlay_enabled, "Stale previous editor_z must not immediately disable the newly enabled overlay")
	TEST_ASSERT_EQUAL(command.editor_z, user.z, "Re-enable must synchronize the editor's level before rendering")
	TEST_ASSERT_EQUAL(length(command.draft_route), 0, "Re-enable must discard old-level partial geometry")
	command.set_world_overlay(FALSE)

/// Exercise immediate invalidation of the actual radial object, not just a stale-answer guard.
/datum/unit_test/tactical_world_radial_lifetime/Run()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	user.faction = FACTION_TERRAGOV
	var/datum/tactical_command/test_world/command = allocate(/datum/tactical_command/test_world, user)
	var/datum/radial_menu/menu = allocate(/datum/radial_menu)
	var/menu_id = "tactical_lifetime_test_[REF(command)]"
	GLOB.radial_menus[menu_id] = menu
	command.world_menu_open = TRUE
	command.world_menu_id = menu_id
	menu.selected_choice = "Retreat"
	command.test_authorized = FALSE
	var/access_checks_before = command.test_access_checks
	command.world_invalidated()
	TEST_ASSERT_EQUAL(command.test_access_checks, access_checks_before, "Signal cleanup must not enter potentially sleeping command authorization")
	TEST_ASSERT(menu.finished, "Logout/z/death invalidation must actively finish the pending radial")
	TEST_ASSERT_NULL(menu.selected_choice, "Invalidation must discard even an already-clicked stale choice")
	TEST_ASSERT(!command.world_menu_open, "A dead radial must not block reopening the command menu")
	TEST_ASSERT_NULL(command.world_menu_id, "The old radial must lose ownership of this command state")
	TEST_ASSERT(!command.world_menu_valid(user, null, user.z, menu_id), "A detached old menu may not regain validity while its wait unwinds")
	// Normally show_radial_menu removes this key after its wait; this fixture has no wait thread.
	GLOB.radial_menus -= menu_id
