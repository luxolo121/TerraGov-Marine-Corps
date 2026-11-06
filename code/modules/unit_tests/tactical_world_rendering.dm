/// A diagonal is a continuous line, not an EAST/NORTH stamp. Exercise the actual
/// pixels and icon cache used by rendering, including both sides of tile seams.
/datum/unit_test/tactical_world_route_raster/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/list/ends = list(locate(start.x + 4, start.y + 4, start.z), locate(start.x + 4, start.y + 1, start.z), locate(start.x + 1, start.y + 4, start.z))
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, start)
	var/datum/tactical_command/command = allocate(/datum/tactical_command, user)
	for(var/turf/end AS in ends)
		var/list/global_pixels = list()
		for(var/turf/tile AS in block(start, locate(start.x + 4, start.y + 4, start.z)))
			var/list/pixels = tactical_route_pixels(tile, start, end)
			var/list/reversed = tactical_route_pixels(tile, end, start)
			TEST_ASSERT_EQUAL(jointext(pixels, ","), jointext(reversed, ","), "Reversing a segment must produce identical pixels at every tile seam")
			if(!length(pixels))
				continue
			var/icon/raster = icon(command.world_route_icon(pixels), "route")
			TEST_ASSERT_EQUAL(raster.Width(), 32, "A route must never extend into a hidden neighboring turf")
			TEST_ASSERT_EQUAL(raster.Height(), 32, "A route raster must be clipped vertically too")
			for(var/pixel in pixels)
				var/px = ((pixel - 1) % 32) + 1
				var/py = round((pixel - 1) / 32) + 1
				TEST_ASSERT(raster.GetPixel(px, py), "The actual production icon must contain each computed line pixel")
				global_pixels["[(tile.x - start.x) * 32 + px],[(tile.y - start.y) * 32 + py]"] = TRUE
		var/dx = (end.x - start.x) * 32
		var/dy = (end.y - start.y) * 32
		var/horizontal = dx >= dy
		var/extent = max(dx, dy)
		for(var/distance in 0 to extent)
			var/px = 16 + (horizontal ? distance : round(distance * dx / dy + 0.5))
			var/py = 16 + (horizontal ? round(distance * dy / dx + 0.5) : distance)
			TEST_ASSERT(global_pixels["[px],[py]"], "Every dominant-axis sample must exist: no gap at a diagonal tile seam")
	var/turf/negative_start = locate(start.x, start.y + 4, start.z)
	var/turf/negative_end = locate(start.x + 4, start.y, start.z)
	var/turf/middle = locate(start.x + 2, start.y + 2, start.z)
	var/list/descending = tactical_route_pixels(middle, negative_start, negative_end)
	TEST_ASSERT(((31 - 1) * 32 + 1) in descending, "Descending diagonals must enter at the upper-left tile edge")
	TEST_ASSERT(((1 - 1) * 32 + 31) in descending, "Descending diagonals must exit at the lower-right tile edge")
	TEST_ASSERT(!tactical_tile_on_segment(locate(start.x + 4, start.y, start.z), start, ends[1]), "A bounding-box hit is not sufficient to count as a visible line hit")
	TEST_ASSERT(!length(tactical_route_pixels(start, start, start)), "A repeated waypoint must not divide by zero")

/datum/unit_test/tactical_world_connected_room/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/turf/end = locate(start.x + 2, start.y + 2, start.z)
	var/turf/center = locate(start.x + 1, start.y + 1, start.z)
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/datum/tactical_zone/zone = plan.create_rectangle("Connected room", start, end)
	TEST_ASSERT_EQUAL(tactical_zone_edge_mask(center, zone.coordinates), 0, "A room interior must not draw a box around every tile")
	TEST_ASSERT_EQUAL(tactical_zone_edge_mask(start, zone.coordinates), SOUTH|WEST, "Only genuinely exposed room edges should be drawn")
	var/list/concave = zone.coordinates.Copy()
	concave -= "[center.x],[center.y]"
	TEST_ASSERT(tactical_zone_edge_mask(get_step(center, SOUTH), concave) & NORTH, "An actual interior hole must retain its boundary")
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, start)
	var/datum/tactical_command/command = allocate(/datum/tactical_command, user)
	command.plan = plan
	command.editor_z = start.z
	command.preview = block(start, end)
	var/list/visible = list()
	visible[center] = TRUE
	command.replace_world_images(visible)
	TEST_ASSERT_EQUAL(length(command.world_images), 1, "A saved zone under a draft must not double the haze opacity")
	var/image/fill = command.world_images[1]
	TEST_ASSERT_EQUAL(fill.icon_state, "zone_0", "Viewport clipping must not create false room edges")
	TEST_ASSERT_EQUAL(fill.layer, WALL_OBJ_LAYER, "Room haze must remain below marine silhouettes")
	var/icon/interior = icon(fill.icon, fill.icon_state)
	TEST_ASSERT(interior.GetPixel(16, 16), "Deep inside a large room there must still be a faint interior indication")
	var/icon/border = icon('icons/mob/tactical_command.dmi', "zone_10")
	TEST_ASSERT_EQUAL(border.GetPixel(1, 16), "#ebfaff", "Connected west edge must run flush to the tile boundary")
	TEST_ASSERT_EQUAL(border.GetPixel(16, 1), "#ebfaff", "Connected south edge must run flush to the tile boundary")

/// The client transport is substituted, not the production movement/render path.
/datum/tactical_command/test_world/rendering
/datum/tactical_command/test_world/rendering/world_movement_allowed()
	return TRUE

/datum/unit_test/tactical_world_motion_and_cache/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/turf/shared = get_step(start, EAST)
	var/turf/entered = get_step(shared, EAST)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, start)
	var/datum/tactical_command/test_world/rendering/command = allocate(/datum/tactical_command/test_world/rendering, user)
	command.plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	command.plan.create_rectangle("Motion", start, entered)
	command.editor_z = start.z
	command.world_overlay_enabled = TRUE
	command.test_visible[start] = TRUE
	command.test_visible[shared] = TRUE
	command.replace_world_images(command.test_visible)
	var/image/retained
	for(var/image/marker AS in command.world_images)
		if(marker.loc == shared)
			retained = marker
	TEST_ASSERT(retained, "Fixture requires one still-visible room tile")
	command.test_visible -= start
	command.test_visible[entered] = TRUE
	var/access_checks = command.test_access_checks
	command.world_moved()
	TEST_ASSERT_EQUAL(command.test_access_checks, access_checks, "Movement signals must not enter SQL-backed authorization")
	TEST_ASSERT(retained in command.world_images, "An unchanged visible image must retain identity during movement, not blink off")
	TEST_ASSERT_EQUAL(length(command.world_images), 2, "Movement must render the newly visible tile immediately, with no clear-and-delay gap")
	for(var/image/marker AS in command.world_images)
		TEST_ASSERT(command.test_visible[marker.loc], "A newly hidden tile must be removed in the same movement call")
	var/icon/first = command.world_route_icon(list(1))
	TEST_ASSERT_EQUAL(command.world_route_icon(list(1)), first, "Identical raster patterns must reuse their icon")
	for(var/pixel in 2 to 520)
		command.world_route_icon(list(pixel))
	TEST_ASSERT_EQUAL(length(command.world_route_icon_cache), 512, "Per-commander raster memory must be bounded")
	TEST_ASSERT(command.world_route_icon(list(1)) != first, "The oldest raster must be evicted instead of allowing unlimited growth")
	command.disable_world_overlay()
	TEST_ASSERT_EQUAL(length(command.world_images), 0, "Explicit hide must still remove every image")
	TEST_ASSERT_EQUAL(length(command.world_image_cache), 0, "Hidden image identities must not be retained forever")

/datum/unit_test/tactical_world_turn_visibility/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, start)
	user.fov_view = 120
	var/turf/north = locate(start.x, start.y + 3, start.z)
	var/turf/east = locate(start.x + 3, start.y, start.z)
	TEST_ASSERT(tactical_in_facing_fov(user, north, NORTH), "New forward arc should be eligible after a turn")
	TEST_ASSERT(!tactical_in_facing_fov(user, north, SOUTH), "The former forward arc must not survive a turn as visible rear information")
	TEST_ASSERT(tactical_in_facing_fov(user, east, EAST), "Direction math must also work for east-facing commanders")
	TEST_ASSERT(!tactical_in_facing_fov(user, east, WEST), "Opposite horizontal facing must not reveal the old arc")
	TEST_ASSERT(tactical_in_facing_fov(user, get_step(start, EAST), WEST), "Match the game's intentional always-visible adjacent 3x3 area")

/// Export actual production icon compositions for visual review. This is a native
/// raster receipt, deliberately not represented as DreamSeeker gameplay proof.
/datum/unit_test/tactical_world_visual_exports/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/turf/end = locate(start.x + 4, start.y + 4, start.z)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, start)
	var/datum/tactical_command/command = allocate(/datum/tactical_command, user)
	command.plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	command.editor_z = start.z
	var/list/visible = list()
	for(var/turf/tile AS in block(start, end))
		visible[tile] = TRUE
	var/icon/routes = icon('icons/mob/tactical_command.dmi', "route")
	routes.Scale(480, 160)
	var/list/ends = list(end, locate(start.x + 4, start.y + 1, start.z), locate(start.x + 1, start.y + 4, start.z))
	for(var/index in 1 to length(ends))
		command.clear_world_images()
		command.draw_world_route(list(start, ends[index]), visible, "#62e8ff")
		routes.Blend(compose(command, start), ICON_OVERLAY, (index - 1) * 160 + 1, 1)
	TEST_ASSERT(fcopy(routes, "data/tactical-rendering-routes.png"), "Must preserve the actual native raster receipt")
	command.plan.create_rectangle("Saved room", start, end)
	var/icon/zones = icon('icons/mob/tactical_command.dmi', "route")
	zones.Scale(320, 160)
	command.preview = block(start, end)
	command.replace_world_images(visible)
	zones.Blend(compose(command, start), ICON_OVERLAY, 1, 1)
	command.preview.Cut()
	command.replace_world_images(visible)
	zones.Blend(compose(command, start), ICON_OVERLAY, 161, 1)
	TEST_ASSERT(fcopy(zones, "data/tactical-rendering-zones.png"), "Must preserve draft and saved room connected edges and faint interiors")
	var/list/states = list("command", "orders", "designate", "overlay", "room", "rectangle", "patrol", "entrance_tool", "choke_tool", "save", "undo", "cancel", "guard", "fallback", "retreat", "tools", "back", "deselect")
	var/icon/icons = icon('icons/mob/tactical_command.dmi', "route")
	icons.Scale(288, 64)
	icons.DrawBox("#24343b", 1, 1, 288, 64)
	for(var/index in 1 to length(states))
		var/icon/glyph = icon('icons/mob/tactical_command.dmi', states[index])
		icons.Blend(glyph, ICON_OVERLAY, ((index - 1) % 9) * 32 + 1, round((index - 1) / 9) * 32 + 1)
	TEST_ASSERT(fcopy(icons, "data/tactical-rendering-icons.png"), "Must preserve all distinct native menu and HUD sprites")

/datum/unit_test/tactical_world_visual_exports/proc/compose(datum/tactical_command/command, turf/origin)
	var/icon/scene = icon('icons/mob/tactical_command.dmi', "route")
	scene.Scale(160, 160)
	scene.DrawBox("#24343b", 1, 1, 160, 160)
	for(var/grid = 32; grid <= 160; grid += 32)
		scene.DrawBox("#37454b", grid, 1, grid, 160)
		scene.DrawBox("#37454b", 1, grid, 160, grid)
	for(var/image/marker AS in command.world_images)
		var/icon/pixels = icon(marker.icon, marker.icon_state, marker.dir)
		pixels.Blend(marker.color, ICON_MULTIPLY)
		pixels.Blend(rgb(255, 255, 255, marker.alpha), ICON_MULTIPLY)
		var/turf/tile = marker.loc
		scene.Blend(pixels, ICON_OVERLAY, (tile.x - origin.x) * 32 + 1, (tile.y - origin.y) * 32 + 1)
	return scene
