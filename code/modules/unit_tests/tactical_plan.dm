/// Reclassification must preserve the exact footprint and unrelated map metadata.
/datum/unit_test/tactical_zone_identity/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/turf/start = run_loc_floor_bottom_left
	var/turf/end = locate(start.x + 2, start.y + 2, start.z)
	var/area/original_area = get_area(start)
	var/original_name = original_area.name
	var/datum/tactical_zone/zone = plan.create_rectangle("Drill perimeter", end, start)
	TEST_ASSERT(zone, "Reversed rectangle corners must produce a zone")
	TEST_ASSERT_EQUAL(length(zone.turfs), 9, "Rectangle must include both boundary tiles")
	var/zone_id = zone.id
	var/list/original_tiles = zone.turfs.Copy()
	TEST_ASSERT(zone.set_purpose("fallback"), "A guard zone can become a fallback without redrawing")
	TEST_ASSERT_EQUAL(zone.id, zone_id, "Purpose changes must not replace the zone identity")
	TEST_ASSERT_EQUAL(length(zone.turfs ^ original_tiles), 0, "Purpose changes must not change footprint")
	TEST_ASSERT_EQUAL(get_area(start), original_area, "Zone marking must not replace engine areas")
	TEST_ASSERT_EQUAL(original_area.name, original_name, "Zone names must not rename mapped areas")
	TEST_ASSERT(zone.contains(start) && zone.contains(end), "Both edges belong to the zone")
	TEST_ASSERT(!zone.contains(locate(end.x + 1, end.y, end.z)), "Outside tiles cannot become guard territory")
	TEST_ASSERT(!zone.set_purpose("attack"), "Unimplemented purposes must not be accepted silently")

/// Two authored areas can share a label; room selection must follow the exact clicked area object.
/datum/unit_test/tactical_room_selection/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/turf/first_tile = run_loc_floor_bottom_left
	var/turf/second_tile = locate(first_tile.x + 10, first_tile.y, first_tile.z)
	var/area/first_room = get_area(first_tile)
	var/area/second_room = get_area(second_tile)
	TEST_ASSERT(first_room != second_room, "Fixture needs the authored test room and its surrounding area")
	var/original_name = second_room.name
	second_room.name = first_room.name
	var/datum/tactical_zone/zone = plan.create_room(null, first_tile)
	var/selected_correctly = zone && zone.contains(first_tile) && !zone.contains(second_tile) && length(zone.turfs) == length(first_room.get_turfs_by_zlevel(first_tile.z))
	// Use real mapped areas, not allocate(/area), which passes a turf location and changes the fixture.
	// Restore the temporary duplicate label before asserting, even if the test is going to fail.
	second_room.name = original_name
	TEST_ASSERT(selected_correctly, "Room selection must use identity and current Z, not matching display names")
	TEST_ASSERT_EQUAL(zone.name, tactical_label(first_room.name), "Default room label should retain the authored name")

/// Malformed and mixed-Z requests must not partially mutate a shared plan.
/datum/unit_test/tactical_geometry_validation/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/turf/start = run_loc_floor_bottom_left
	TEST_ASSERT_NULL(plan.create_zone("empty", list()), "Empty zones must be rejected")
	TEST_ASSERT_NULL(plan.create_zone("bad type", list(start, "not a turf")), "Bad geometry must fail atomically")
	TEST_ASSERT_NULL(plan.create_zone("bad purpose", list(start), "unknown"), "Purpose must be validated before insertion")
	var/turf/other_z = locate(start.x, start.y, start.z == 1 ? 2 : 1)
	TEST_ASSERT_NULL(plan.create_zone("mixed", list(start, other_z)), "Zones must not span Z levels")
	TEST_ASSERT_NULL(plan.create_rectangle("huge", locate(1, 1, start.z), locate(world.maxx, world.maxy, start.z)), "Oversize rectangles must be bounded before allocation")
	TEST_ASSERT_EQUAL(length(plan.zones), 0, "Invalid requests must leave no partial zone behind")
	TEST_ASSERT_EQUAL(plan.revision, 0, "Rejected requests must not change the shared revision")
	var/datum/tactical_zone/zone = plan.create_zone("dedup", list(start, start))
	TEST_ASSERT_EQUAL(length(zone.turfs), 1, "Repeated tile references must not inflate geometry")

/// Entrances/chokes belong to a particular defended footprint, not arbitrary distant positions.
/datum/unit_test/tactical_marker_boundaries/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/turf/start = run_loc_floor_bottom_left
	var/datum/tactical_zone/zone = plan.create_rectangle("Dock", start, locate(start.x + 2, start.y + 2, start.z))
	var/turf/boundary = locate(start.x + 3, start.y + 1, start.z)
	var/datum/tactical_marker/marker = zone.add_marker("entrance", boundary, EAST)
	TEST_ASSERT(marker, "A doorway immediately adjacent to a zone can be marked")
	TEST_ASSERT_EQUAL(marker.direction, EAST, "Approach direction must be retained")
	TEST_ASSERT_NULL(zone.add_marker("choke", locate(start.x + 5, start.y, start.z)), "A distant choke cannot silently attach to this zone")
	TEST_ASSERT_NULL(zone.add_marker("entrance", boundary, NORTHEAST), "Only supported facing directions are accepted")
	var/datum/tactical_marker/updated = zone.add_marker("entrance", boundary, WEST)
	TEST_ASSERT_EQUAL(updated, marker, "Editing a marker must not pile up duplicate positions")
	TEST_ASSERT_EQUAL(length(zone.markers), 1, "Duplicate placement should update, not duplicate")
	TEST_ASSERT_EQUAL(marker.direction, WEST, "Replacement facing must take effect")
	TEST_ASSERT(zone.remove_marker(marker.id), "A saved marker can be removed independently of its zone")
	TEST_ASSERT_EQUAL(length(zone.markers), 0, "Marker removal must clear the zone's references")

/// Waypoints are a copied ordered route, never a mutable UI draft or unordered zone.
/datum/unit_test/tactical_route_identity/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/turf/start = run_loc_floor_bottom_left
	var/turf/middle = locate(start.x + 1, start.y, start.z)
	var/turf/end = locate(start.x + 2, start.y, start.z)
	var/list/draft = list(start, middle, end)
	var/datum/tactical_route/route = plan.create_route("Dock sweep", draft, FALSE)
	TEST_ASSERT(route, "Valid ordered patrol must be accepted")
	draft.Cut()
	TEST_ASSERT_EQUAL(length(route.waypoints), 3, "Clearing an editor draft must not erase a saved route")
	TEST_ASSERT_EQUAL(route.waypoints[2], middle, "Route order must be preserved")
	TEST_ASSERT_EQUAL(route.loop, FALSE, "Back-and-forth patrol must remain distinct from a loop")
	TEST_ASSERT_NULL(plan.create_route("one point", list(start)), "A patrol requires at least two waypoints")
	TEST_ASSERT_NULL(plan.create_route("no progress", list(start, start)), "Consecutive duplicate waypoints are invalid")
	var/turf/other_z = locate(start.x, start.y, start.z == 1 ? 2 : 1)
	TEST_ASSERT_NULL(plan.create_route("mixed", list(start, other_z)), "Patrol geometry may not silently cross Z levels")

/// Plan deletion must not strand an order or silently erase another squad's fallback.
/datum/unit_test/tactical_assignment_reference_guards/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/turf/start = run_loc_floor_bottom_left
	var/datum/tactical_zone/zone = plan.create_zone("Dock", list(start))
	var/datum/tactical_squad/squad = new(plan, "Alpha")
	squad.zone = zone
	TEST_ASSERT(!plan.delete_zone(zone), "An actively assigned zone must not be deleted")
	squad.zone = null
	squad.fallback_zone = zone
	TEST_ASSERT(!plan.delete_zone(zone), "Fallback references must protect the same reusable zone")
	squad.fallback_zone = null
	var/datum/tactical_route/route = plan.create_route("Sweep", list(start, get_step(start, NORTH)))
	squad.route = route
	TEST_ASSERT(!plan.delete_route(route), "An assigned patrol route must not be deleted")
	squad.route = null
	TEST_ASSERT(plan.delete_route(route), "An unassigned route should be deletable")
	TEST_ASSERT(plan.delete_zone(zone), "Unreferenced geometry should be deletable")
	TEST_ASSERT_NULL(plan.find_zone("not-a-zone"), "Unknown browser IDs must not resolve")
	TEST_ASSERT(plan.remove_squad(squad), "Explicit squad removal should clean up the plan")
	TEST_ASSERT_EQUAL(length(plan.squads), 0, "Squad removal must not leave a stale selection target")

/// Export the actual generated terrain and an authored room for browser/coordinate integration proof.
/// This lives inside UNIT_TESTS: no world screenshots or fixture exports are added to production.
/datum/unit_test/tactical_minimap_contract/Run()
	var/list/ground_levels = SSmapping.levels_by_trait(ZTRAIT_GROUND)
	TEST_ASSERT(length(ground_levels), "The map fixture must provide a ground level")
	var/ground_z = ground_levels[1]
	var/datum/hud_displays/map = SSminimaps.minimaps_by_z["[ground_z]"]
	TEST_ASSERT(map?.hud_image, "Tactical command needs the real static minimap, not contact overlays")
	TEST_ASSERT_EQUAL(map.hud_image.Width(), 480, "Tactical map coordinate scale assumes the existing 480px minimap")
	TEST_ASSERT_EQUAL(map.hud_image.Height(), 480, "Tactical map coordinate scale assumes the existing 480px minimap")
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/datum/tactical_zone/sample_zone
	for(var/area/room AS in GLOB.areas)
		var/list/room_tiles = room.get_turfs_by_zlevel(ground_z)
		if(length(room_tiles) < 9 || length(room_tiles) > 1600)
			continue
		sample_zone = plan.create_zone(room.name, room_tiles)
		if(sample_zone)
			break
	TEST_ASSERT(sample_zone, "The real map must expose at least one selectable authored room")
	var/list/room_points = list()
	for(var/turf/tile AS in sample_zone.turfs)
		room_points += list(list("x" = tile.x, "y" = tile.y))
	var/list/export = list(
		"map" = icon2base64(map.hud_image),
		"offset_x" = map.x_offset,
		"offset_y" = map.y_offset,
		"max_x" = world.maxx,
		"max_y" = world.maxy,
		"z" = ground_z,
		"room_name" = sample_zone.name,
		"room_points" = room_points,
		"center" = list("x" = sample_zone.center.x, "y" = sample_zone.center.y),
	)
	TEST_ASSERT(text2file(json_encode(export), "data/tactical_minimap_fixture.json"), "Native terrain evidence must be retained for browser validation")
