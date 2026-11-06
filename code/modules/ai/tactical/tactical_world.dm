/// Non-blocking HUD/keybinding eligibility only. Every actual menu/edit/order still enters
/// get_tactical_command/dispatch, which performs the complete ban-aware authorization check.
/proc/tactical_command_available(mob/user)
	return ishuman(user) && user.client && !user.incapacitated() && user.faction && (user.client.holder || user.skills?.getRating(SKILL_LEADERSHIP) >= SKILL_LEAD_TRAINED)

/// One personal command state, shared by the planner, native HUD and legacy designator.
/proc/get_tactical_command(mob/living/carbon/human/user)
	if(!can_use_tactical_command(user))
		return null
	var/datum/action/tactical_command/action = user.actions_by_path[/datum/action/tactical_command]
	if(!action)
		return null
	if(action.command_ui && action.command_ui.plan?.faction != user.faction)
		QDEL_NULL(action.command_ui)
	if(!action.command_ui)
		action.command_ui = new(user)
	return action.command_ui

/datum/tactical_command
	var/world_overlay_enabled = FALSE
	var/client/world_client
	var/list/world_images = list()
	/// Only images in the previous visible frame; stable identities prevent movement flicker.
	var/list/world_image_cache = list()
	var/list/world_next_image_cache = list()
	/// FIFO-bounded tile raster patterns, independent of route color and location.
	var/list/world_route_icon_cache = list()
	var/world_target_order
	var/world_refresh_timer
	var/world_menu_open = FALSE
	var/world_menu_id
	var/world_menu_serial = 0

/// Never render remote cameras, blindness, another level, or outside the local viewport.
/datum/tactical_command/proc/world_visible_tiles(facing)
	var/list/result = list()
	if(!commander?.client || commander.client.eye != commander || !isturf(commander.loc) || commander.eye_blind)
		return result
	var/list/dimensions = getviewsize(commander.client.view)
	var/half_width = min(9, round((dimensions[1] - 1) / 2))
	var/half_height = min(9, round((dimensions[2] - 1) / 2))
	for(var/turf/tile in view(9, commander))
		if(abs(tile.x - commander.x) <= half_width && abs(tile.y - commander.y) <= half_height && commander.in_fov(tile) && (isnull(facing) || tactical_in_facing_fov(commander, tile, facing)))
			result[tile] = TRUE
	return result

/datum/tactical_command/proc/world_target_visible(atom/target)
	var/turf/tile = get_turf(target)
	if(!tile || tile.z != commander.z || get_dist(commander, tile) > 9)
		return FALSE
	var/list/visible = world_visible_tiles()
	return !!visible[tile]

/datum/tactical_command/proc/clear_world_images()
	if(world_client)
		world_client.images -= world_images
	world_images.Cut()
	world_image_cache.Cut()
	world_next_image_cache.Cut()
	world_client = null

/datum/tactical_command/proc/set_world_overlay(enabled)
	if(!enabled)
		return disable_world_overlay()
	if(ui_status(commander) != UI_INTERACTIVE)
		return FALSE
	check_level()
	world_overlay_enabled = TRUE
	START_PROCESSING(SSprocessing, src)
	refresh_world_overlay()
	return TRUE

/// Signal-safe cleanup has no call path through SQL-backed command authorization or rendering.
/datum/tactical_command/proc/disable_world_overlay()
	world_overlay_enabled = FALSE
	STOP_PROCESSING(SSprocessing, src)
	if(world_refresh_timer)
		deltimer(world_refresh_timer)
		world_refresh_timer = null
	clear_world_images()
	return TRUE

/// Logout/z/death removes images from their original client even after mob.client is detached.
/datum/tactical_command/proc/world_invalidated()
	SIGNAL_HANDLER
	close_world_menu()
	disable_world_overlay()
	world_target_order = null
	selected_squad = null
	selected_zone = null
	selected_route = null
	clear_draft()
	tool = "inspect"
	update_world_controls()
	var/datum/action/ability/activable/build_designator/designator = commander?.actions_by_path[/datum/action/ability/activable/build_designator]
	if(designator && commander.selected_ability == designator)
		designator.deselect()

/// A dir-change signal fires before atom.dir is assigned. Intersect both views until
/// the zero-delay refresh observes the new direction; never expose the old rear arc.
/proc/tactical_in_facing_fov(mob/living/user, turf/tile, facing)
	if(!user.fov_view || (abs(tile.x - user.x) <= 1 && abs(tile.y - user.y) <= 1))
		return TRUE
	var/dx = tile.x - user.x
	var/dy = tile.y - user.y
	var/facing_x = (facing & EAST ? 1 : 0) - (facing & WEST ? 1 : 0)
	var/facing_y = (facing & NORTH ? 1 : 0) - (facing & SOUTH ? 1 : 0)
	var/facing_length = sqrt(facing_x * facing_x + facing_y * facing_y)
	if(!facing_length)
		return FALSE
	var/dot = facing_x * dx + facing_y * dy
	return arccos(clamp(dot / (sqrt(dx * dx + dy * dy) * facing_length), -1, 1)) < (360 - user.fov_view) / 2

/// No SQL-backed authorization in movement signals. Full authority is checked on
/// enable, every command and the periodic refresh; this only redraws an existing grant.
/datum/tactical_command/proc/world_movement_allowed()
	return tactical_command_available(commander) && commander.client == world_client && commander.faction == plan?.faction && commander.z == editor_z

/datum/tactical_command/proc/world_moved()
	SIGNAL_HANDLER
	if(!world_overlay_enabled)
		return
	if(!world_movement_allowed())
		world_invalidated()
		return
	// Synchronous local redraw retains unchanged image identities. No empty 0.2s frame.
	replace_world_images(world_visible_tiles())

/datum/tactical_command/proc/world_turned(datum/source, old_direction, new_direction)
	SIGNAL_HANDLER
	if(!world_overlay_enabled)
		return
	if(!world_movement_allowed())
		world_invalidated()
		return
	replace_world_images(world_visible_tiles(new_direction))
	if(!world_refresh_timer)
		world_refresh_timer = addtimer(CALLBACK(src, PROC_REF(world_deferred_refresh)), 0, TIMER_STOPPABLE)

/datum/tactical_command/proc/world_deferred_refresh()
	world_refresh_timer = null
	if(world_overlay_enabled && world_movement_allowed())
		replace_world_images(world_visible_tiles())

/datum/tactical_command/process()
	refresh_world_overlay()

/// Rasterize the mathematical center-to-center line in LOCAL pixel coordinates.
/// The dominant-axis samples are global-line aligned, so adjacent tile clips meet
/// exactly, including arbitrary diagonals, reversed segments and endpoint tiles.
/// Never walk a remote route: at most 32 samples for a candidate local tile.
/proc/tactical_route_pixels(turf/tile, turf/start, turf/end)
	var/list/pixels = list()
	if(!tile || !start || !end || tile.z != start.z || start.z != end.z || start == end)
		return pixels
	if(tile.x < min(start.x, end.x) || tile.x > max(start.x, end.x) || tile.y < min(start.y, end.y) || tile.y > max(start.y, end.y))
		return pixels
	var/x0 = (start.x - tile.x) * 32 + 16
	var/y0 = (start.y - tile.y) * 32 + 16
	var/x1 = (end.x - tile.x) * 32 + 16
	var/y1 = (end.y - tile.y) * 32 + 16
	var/horizontal = abs(x1 - x0) >= abs(y1 - y0)
	var/major_start = horizontal ? x0 : y0
	var/minor_start = horizontal ? y0 : x0
	var/major_end = horizontal ? x1 : y1
	var/minor_end = horizontal ? y1 : x1
	// Canonical direction makes the exact pixel pattern invariant under reversal.
	if(major_start > major_end)
		var/swap = major_start
		major_start = major_end
		major_end = swap
		swap = minor_start
		minor_start = minor_end
		minor_end = swap
	var/first = max(1, major_start)
	var/last = min(32, major_end)
	if(first > last)
		return pixels
	var/slope = (minor_end - minor_start) / (major_end - major_start)
	var/first_minor = minor_start + (first - major_start) * slope
	var/last_minor = minor_start + (last - major_start) * slope
	if(max(first_minor, last_minor) < -0.5 || min(first_minor, last_minor) >= 32.5)
		return pixels
	for(var/major in first to last)
		var/minor = round(minor_start + (major - major_start) * slope + 0.5)
		for(var/width_offset in 0 to 1)
			var/cross = minor + width_offset
			if(cross < 1 || cross > 32)
				continue
			var/px = horizontal ? major : cross
			var/py = horizontal ? cross : major
			pixels += (py - 1) * 32 + px
	return pixels

/// Shared hit test uses the same clipped line as the visible connector.
/proc/tactical_tile_on_segment(turf/tile, turf/start, turf/end)
	return length(tactical_route_pixels(tile, start, end)) > 0

/// Coordinate membership, not viewport membership: a clipped/hidden neighbor is
/// still part of the room, so camera movement never draws false internal borders.
/proc/tactical_zone_edge_mask(turf/tile, list/coordinates)
	var/mask = 0
	if(!coordinates["[tile.x],[tile.y + 1]"])
		mask |= NORTH
	if(!coordinates["[tile.x],[tile.y - 1]"])
		mask |= SOUTH
	if(!coordinates["[tile.x + 1],[tile.y]"])
		mask |= EAST
	if(!coordinates["[tile.x - 1],[tile.y]"])
		mask |= WEST
	return mask

/datum/tactical_command/proc/world_route_icon(list/pixels)
	var/key = jointext(pixels, ",")
	var/icon/result = world_route_icon_cache[key]
	if(result)
		return result
	var/icon/raster = icon('icons/mob/tactical_command.dmi', "route")
	for(var/pixel in pixels)
		raster.DrawBox("#ffffff", ((pixel - 1) % 32) + 1, round((pixel - 1) / 32) + 1)
	result = new /icon()
	result.Insert(raster, "route", SOUTH, 1)
	if(length(world_route_icon_cache) >= 512)
		world_route_icon_cache.Cut(1, 2)
	world_route_icon_cache[key] = result
	return result

/datum/tactical_command/proc/add_world_image(turf/tile, state, tint, direction = SOUTH, label, opacity = 210, image_layer = ABOVE_MOB_LAYER, icon/raster)
	// A pathological pile of overlapping plans cannot allocate unbounded client images.
	if(length(world_images) >= 900)
		return
	var/key = "[REF(tile)]|[state]|[tint]|[direction]|[label]|[opacity]|[image_layer]|[raster ? REF(raster) : ""]"
	var/image/marker = world_image_cache[key]
	if(!marker)
		marker = image(raster || 'icons/mob/tactical_command.dmi', tile, state, image_layer, direction)
		marker.plane = GAME_PLANE
		marker.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
		marker.color = tint
		marker.alpha = opacity
		if(label)
			marker.maptext = "<span style='font-size:7px;color:white;text-shadow:1px 1px black'>[label]</span>"
			marker.maptext_x = 11
			marker.maptext_y = 17
	world_next_image_cache[key] = marker
	world_images |= marker

/datum/tactical_command/proc/draw_world_route(list/points, list/visible, tint, loop = FALSE, connectors = TRUE)
	var/list/tile_pixels = list()
	for(var/index in 1 to length(points))
		if(length(world_images) >= 900)
			return
		var/turf/point = points[index]
		if(visible[point])
			add_world_image(point, "waypoint", tint, label = "[index]")
		if(!connectors || (index == length(points) && !loop))
			continue
		var/turf/next = points[index == length(points) ? 1 : index + 1]
		if(point == next)
			continue
		for(var/turf/tile AS in visible)
			var/list/pixels = tactical_route_pixels(tile, point, next)
			if(!length(pixels))
				continue
			if(!tile_pixels[tile])
				tile_pixels[tile] = pixels
			else
				var/list/combined = tile_pixels[tile]
				combined |= pixels
	// One raster per tile, including bends/crossings; overlapping segments never
	// erase each other and do not multiply the opacity or image budget.
	for(var/turf/tile AS in tile_pixels)
		add_world_image(tile, "route", tint, raster = world_route_icon(tile_pixels[tile]))

/datum/tactical_command/proc/refresh_world_overlay()
	if(!world_overlay_enabled)
		return
	if(ui_status(commander) != UI_INTERACTIVE || (editor_z && editor_z != commander.z))
		world_invalidated()
		return
	check_level()
	update_world_controls()
	if(world_client != commander.client)
		clear_world_images()
	world_client = commander.client
	replace_world_images(world_visible_tiles())

/// Reconcile one complete visible frame atomically; unchanged images remain in
/// client.images. Removed/FOV-hidden tiles disappear in this same non-sleeping call.
/datum/tactical_command/proc/replace_world_images(list/visible)
	var/list/previous = world_images
	world_images = list()
	world_next_image_cache = list()
	build_world_images(visible)
	if(world_client)
		world_client.images -= previous - world_images
		world_client.images += world_images - previous
	world_image_cache = world_next_image_cache

/// Pure rendering step: all inputs have already been restricted to authorized local visibility.
/datum/tactical_command/proc/build_world_images(list/visible)
	var/datum/tactical_squad/squad = plan.find_squad(selected_squad)
	var/datum/tactical_zone/selected = plan.find_zone(selected_zone)
	var/datum/tactical_route/selected_patrol = plan.find_route(selected_route)
	// Selection and drafts take priority over background plans when the image budget is full.
	if(squad)
		for(var/mob/living/carbon/human/member AS in squad.members)
			var/turf/tile = get_turf(member)
			if(visible[tile] && member.faction == plan.faction)
				add_world_image(tile, "selected", "#ffffff")
		var/turf/order_target
		switch(squad.order)
			if("hold")
				order_target = squad.hold_position
			if("follow")
				order_target = get_turf(squad.follow_target)
			if("patrol")
				order_target = squad.route?.waypoints[squad.waypoint_index]
		if(visible[order_target])
			add_world_image(order_target, "orders", "#ffffff")
	if(anchor && visible[anchor])
		add_world_image(anchor, "selected", "#ffdf68", label = "A")
	var/list/preview_coordinates = list()
	for(var/turf/tile AS in preview)
		preview_coordinates["[tile.x],[tile.y]"] = TRUE
	for(var/turf/tile AS in visible)
		if(preview_coordinates["[tile.x],[tile.y]"])
			add_world_image(tile, "zone_[tactical_zone_edge_mask(tile, preview_coordinates)]", "#ffdf68", opacity = 220, image_layer = WALL_OBJ_LAYER)
	draw_world_route(draft_route, visible, "#ffdf68")
	// Only the selected/assigned route draws connecting strokes; all saved local waypoints remain visible.
	var/datum/tactical_route/connected_route = selected_patrol || squad?.route
	if(connected_route?.z == editor_z)
		draw_world_route(connected_route.waypoints, visible, "#62e8ff", connected_route.loop)
	for(var/datum/tactical_route/route AS in plan.routes)
		if(length(world_images) >= 900)
			return
		if(route != connected_route && route.z == editor_z)
			draw_world_route(route.waypoints, visible, "#7092a4", connectors = FALSE)
	var/list/ordered_zones = plan.zones.Copy()
	if(selected)
		ordered_zones -= selected
		ordered_zones.Insert(1, selected)
	for(var/datum/tactical_zone/zone AS in ordered_zones)
		if(length(world_images) >= 900)
			return
		if(zone.z != editor_z)
			continue
		var/tint = zone == selected ? "#62e8ff" : (zone.purpose == "fallback" ? "#ca95ff" : (zone.purpose == "staging" ? "#ffcf76" : "#83b99b"))
		for(var/datum/tactical_marker/marker AS in zone.markers)
			if(length(world_images) >= 900)
				return
			if(visible[marker.position])
				add_world_image(marker.position, marker.kind, tint, marker.direction)
	// Work is bounded by <=361 local tiles x <=32 zones, not their <=51,200 saved tiles.
	for(var/turf/tile AS in visible)
		if(length(world_images) >= 900)
			return
		// Draft priority: do not stack saved haze/edges under a draft on the same tile.
		if(preview_coordinates["[tile.x],[tile.y]"])
			continue
		for(var/datum/tactical_zone/zone AS in ordered_zones)
			if(!zone.contains(tile))
				continue
			var/tint = zone == selected ? "#62e8ff" : (zone.purpose == "fallback" ? "#ca95ff" : (zone.purpose == "staging" ? "#ffcf76" : "#83b99b"))
			add_world_image(tile, "zone_[tactical_zone_edge_mask(tile, zone.coordinates)]", tint, opacity = zone == selected ? 200 : 160, image_layer = WALL_OBJ_LAYER)
			// One interior per tile. Selected zone wins overlaps without darker patches.
			break

/datum/tactical_command/proc/update_world_controls()
	var/datum/tactical_squad/squad = plan?.find_squad(selected_squad)
	var/datum/tactical_zone/zone = plan?.find_zone(selected_zone)
	var/datum/tactical_route/route = plan?.find_route(selected_route)
	var/context = squad ? "[squad.name]: [squad.order] ([squad.status])" : "No squad selected"
	var/datum/action/ability/activable/build_designator/designator = commander?.actions_by_path[/datum/action/ability/activable/build_designator]
	if(designator && designator.designator_mode != BUILD_DESIGNATOR_MODE)
		var/mode = world_target_order || tool
		designator.button.name = "[designator.name] — [context]"
		designator.button.desc = "Right-click (Select Buildtype binding) reopens [designator.tactical_menu == "main" ? "the mode menu" : designator.tactical_menu]. Use [world_click_gesture()] on visible terrain. Mode: [mode]. [context]. Zone: [zone?.name || "none"]. Route: [route?.name || "none"]. Back changes menus; Interact handles ordinary move/follow."
		// Keybinding overlays already occupy the upper part of this button. Do not add tool text.
		designator.button.maptext = null
	var/datum/action/tactical_overlay/overlay_action = commander?.actions_by_path[/datum/action/tactical_overlay]
	if(overlay_action)
		overlay_action.set_toggle(world_overlay_enabled)
		overlay_action.button.name = "Tactical Overlay — [world_overlay_enabled ? "shown" : "hidden"]"

/datum/tactical_command/proc/world_click_gesture()
	return (commander?.client?.prefs?.toggles_gameplay & MIDDLESHIFTCLICKING) ? "middle-click" : "shift-click"

/// All quick controls use the same authorization and current-z validation as the full planner.
/datum/tactical_command/proc/world_execute(action, list/params, quiet = FALSE)
	if(!islist(params))
		params = list()
	if(isnull(params["z"]))
		params["z"] = commander.z
	notice_error = FALSE
	var/result = dispatch(action, params, commander)
	if(ui_status(commander) != UI_INTERACTIVE)
		world_invalidated()
		return FALSE
	if(!quiet || notice_error)
		to_chat(commander, notice_error ? span_warning(notice) : span_notice(notice))
	update_world_controls()
	refresh_world_overlay()
	SStgui.update_uis(src)
	return result && !notice_error

/datum/tactical_command/proc/activate_world_targeting(order)
	if(ui_status(commander) != UI_INTERACTIVE)
		return FALSE
	var/datum/action/ability/activable/build_designator/designator = commander.actions_by_path[/datum/action/ability/activable/build_designator]
	if(!designator)
		return FALSE
	if(designator.designator_mode != TACTICAL_DESIGNATOR_MODE)
		designator.swap_mode(TACTICAL_DESIGNATOR_MODE)
	if(commander.selected_ability != designator)
		designator.action_activate()
	world_target_order = order
	set_world_overlay(TRUE)
	update_world_controls()
	return TRUE

/// Prefer the selected zone only when the click actually hits it. Otherwise use stable plan order.
/datum/tactical_command/proc/world_zone_at(turf/position, adjacent = FALSE)
	var/datum/tactical_zone/selected = plan.find_zone(selected_zone)
	if(selected && world_zone_hit(selected, position, adjacent))
		return selected
	for(var/datum/tactical_zone/zone AS in plan.zones)
		if(world_zone_hit(zone, position, FALSE))
			return zone
	if(adjacent)
		for(var/datum/tactical_zone/zone AS in plan.zones)
			if(world_zone_hit(zone, position, TRUE))
				return zone
	return null

/datum/tactical_command/proc/world_zone_hit(datum/tactical_zone/zone, turf/position, adjacent = FALSE)
	if(!position || zone.z != position.z)
		return FALSE
	if(zone.contains(position))
		return TRUE
	if(adjacent)
		for(var/turf/neighbor AS in RANGE_TURFS(1, position))
			if(zone.contains(neighbor))
				return TRUE
	return FALSE

/datum/tactical_command/proc/world_route_hit(datum/tactical_route/route, turf/position)
	if(!position || route.z != position.z)
		return FALSE
	if(position in route.waypoints)
		return TRUE
	for(var/index in 1 to length(route.waypoints))
		if(index == length(route.waypoints) && !route.loop)
			break
		if(tactical_tile_on_segment(position, route.waypoints[index], route.waypoints[index == length(route.waypoints) ? 1 : index + 1]))
			return TRUE
	return FALSE

/datum/tactical_command/proc/world_route_at(turf/position)
	var/datum/tactical_route/selected = plan.find_route(selected_route)
	if(selected && world_route_hit(selected, position))
		return selected
	for(var/datum/tactical_route/route AS in plan.routes)
		if(world_route_hit(route, position))
			return route
	return null

/datum/tactical_command/proc/world_click(atom/target)
	if(ui_status(commander) != UI_INTERACTIVE || !world_target_visible(target))
		return FALSE
	check_level()
	var/turf/position = get_turf(target)
	if(world_target_order)
		var/order = world_target_order
		if(order == "guard" || order == "fallback")
			var/datum/tactical_zone/zone = world_zone_at(position)
			if(!zone)
				to_chat(commander, span_warning("Target a saved zone. An unrelated selected zone is not used."))
				return FALSE
			if(!world_execute("zone_select", list("id" = zone.id), TRUE))
				return FALSE
			if(!world_execute(order == "fallback" ? "fallback" : "order", list("id" = zone.id, "order" = "guard")))
				return FALSE
		else if(order == "patrol")
			var/datum/tactical_route/route = world_route_at(position)
			if(!route)
				to_chat(commander, span_warning("Target a saved patrol waypoint or route line."))
				return FALSE
			if(!world_execute("route_select", list("id" = route.id), TRUE) || !world_execute("order", list("order" = "patrol")))
				return FALSE
		else
			return FALSE
		world_target_order = null
		return_to_interact()
		return TRUE
	if(tool != "inspect")
		var/current_tool = tool
		if(tool == "entrance" || tool == "choke")
			var/datum/tactical_zone/zone = world_zone_at(position, TRUE)
			if(!zone)
				to_chat(commander, span_warning("Place this approach inside or immediately beside a saved zone."))
				return FALSE
			if(!world_execute("zone_select", list("id" = zone.id), TRUE))
				return FALSE
			// Read facing at EACH placement. The full planner keeps its independent facing selector.
			if(!world_execute("marker_facing", list("direction" = commander.dir), TRUE))
				return FALSE
		var/auto_saving = current_tool == "room" || (current_tool == "rectangle" && anchor && !length(preview))
		if(!world_execute("map_click", list("x" = position.x, "y" = position.y), auto_saving))
			return FALSE
		if((current_tool == "room" || current_tool == "rectangle") && length(preview))
			return world_save()
		return TRUE
	if(ishuman(target))
		var/mob/living/carbon/human/human = target
		var/datum/component/ai_controller/controller = human.GetComponent(/datum/component/ai_controller)
		var/datum/ai_behavior/human/brain = controller?.ai_behavior
		if(istype(brain) && brain.tactical_squad?.plan == plan)
			return world_execute("squad_select", list("id" = brain.tactical_squad.id))
	// No overlapping-geometry popup: each kind resolves with selected-hit priority.
	var/datum/tactical_zone/zone = world_zone_at(position)
	var/datum/tactical_route/route = world_route_at(position)
	if(zone)
		world_execute("zone_select", list("id" = zone.id))
	if(route)
		world_execute("route_select", list("id" = route.id))
	cursor = position
	return !!(zone || route)

/// Native quick saves never solicit names, classifications or route modes. Tacview edits those.
/datum/tactical_command/proc/world_save()
	if(ui_status(commander) != UI_INTERACTIVE)
		return FALSE
	var/current_tool = tool
	if(current_tool == "route")
		if(!world_execute("route_save", list("name" = "Patrol [plan.id_counter + 1]", "loop" = TRUE)))
			return FALSE
	else if((current_tool == "room" || current_tool == "rectangle") && length(preview))
		var/label = "Zone [plan.id_counter + 1]"
		if(current_tool == "room")
			var/area/room = get_area(cursor)
			label = "[room.name] [plan.id_counter + 1]"
		if(!world_execute("zone_save", list("name" = label, "purpose" = "guard")))
			return FALSE
	else
		return FALSE
	return_to_interact()
	return TRUE

/// Completing a quick command returns ordinary move/follow to the existing Interact gesture.
/datum/tactical_command/proc/return_to_interact()
	world_target_order = null
	var/datum/action/ability/activable/build_designator/designator = commander?.actions_by_path[/datum/action/ability/activable/build_designator]
	if(designator && designator.designator_mode != INTERACT_DESIGNATOR_MODE)
		designator.swap_mode(INTERACT_DESIGNATOR_MODE)
	update_world_controls()

/// Menus belong to one mob/client/level and one invocation, not merely a surviving client.
/datum/tactical_command/proc/world_menu_valid(mob/expected_owner, client/expected_client, expected_z, expected_id)
	return expected_id == world_menu_id && commander == expected_owner && expected_client && commander?.client == expected_client && expected_client.mob == commander && commander.z == expected_z && ui_status(commander) == UI_INTERACTIVE

/// Mark finished and hide immediately; show_radial_menu owns final deletion when its wait unwinds.
/datum/tactical_command/proc/close_world_menu()
	if(!world_menu_id)
		world_menu_open = FALSE
		return
	var/datum/radial_menu/menu = GLOB.radial_menus[world_menu_id]
	if(menu)
		menu.selected_choice = null
		menu.finished = TRUE
		menu.hide()
	world_menu_id = null
	world_menu_open = FALSE

/datum/tactical_command/proc/show_world_radial(list/choices, radius = 32, angle = 45)
	if(world_menu_open || ui_status(commander) != UI_INTERACTIVE)
		return null
	var/mob/expected_owner = commander
	var/client/expected_client = commander.client
	var/expected_z = commander.z
	var/expected_id = "tactical_[REF(src)]_[++world_menu_serial]"
	world_menu_id = expected_id
	world_menu_open = TRUE
	for(var/label in choices)
		var/image/choice_image = choices[label]
		choice_image.maptext = "<div style='font-size:7px;text-align:center;color:white;text-shadow:1px 1px black'>[label]</div>"
		choice_image.maptext_width = 64
		choice_image.maptext_height = 12
		choice_image.maptext_x = -16
		choice_image.maptext_y = -10
	var/choice = show_radial_menu(commander, commander, choices, uniqueid = expected_id, radius = radius, custom_check = CALLBACK(src, PROC_REF(world_menu_valid), expected_owner, expected_client, expected_z, expected_id), tooltips = TRUE, angle_override = angle)
	var/still_valid = world_menu_valid(expected_owner, expected_client, expected_z, expected_id)
	// An invalidated older menu must never clear the guard for a subsequently opened one.
	if(world_menu_id == expected_id)
		world_menu_id = null
		world_menu_open = FALSE
	return still_valid ? choice : null

/// Keep the alternate button in the last tactical submenu, just as Construction remembers its picker.
/datum/tactical_command/proc/remember_world_menu(menu)
	var/datum/action/ability/activable/build_designator/designator = commander?.actions_by_path[/datum/action/ability/activable/build_designator]
	if(designator)
		designator.tactical_menu = menu
	update_world_controls()

/datum/tactical_command/proc/world_back()
	remember_world_menu("main")
	var/datum/action/ability/activable/build_designator/designator = commander?.actions_by_path[/datum/action/ability/activable/build_designator]
	designator?.select_mode()

/datum/tactical_command/proc/world_tool_menu()
	if(world_menu_open || ui_status(commander) != UI_INTERACTIVE)
		return
	remember_world_menu("designate")
	var/prompt_z = commander.z
	var/list/states
	if(tool == "route")
		states = list("Finish" = "save", "Undo" = "undo", "Cancel" = "cancel", "Back" = "back")
	else if(tool != "inspect")
		states = list("Undo" = "undo", "Cancel" = "cancel", "Back" = "back")
	else
		states = list("Room" = "room", "Rectangle" = "rectangle", "Route" = "patrol", "Entrance" = "entrance_tool", "Choke" = "choke_tool", "Back" = "back")
	var/list/choices = list()
	for(var/label in states)
		choices[label] = image('icons/mob/tactical_command.dmi', icon_state = states[label])
	var/choice = show_world_radial(choices, 56)
	if(!choice || ui_status(commander) != UI_INTERACTIVE || commander.z != prompt_z)
		return
	switch(choice)
		if("Back")
			world_back()
			return
		if("Finish")
			world_save()
			return
		if("Undo")
			world_execute("draft_undo")
			return
		if("Cancel")
			world_execute("clear_draft")
			return_to_interact()
			return
	var/new_tool = lowertext(choice)
	if(world_execute("tool", list("tool" = new_tool, "z" = prompt_z)))
		activate_world_targeting()
		var/instructions = "Target visible tiles with [world_click_gesture()]."
		switch(new_tool)
			if("room")
				instructions += " One click saves the room as a guard zone."
			if("rectangle")
				instructions += " Two opposite corners save a guard zone."
			if("route")
				instructions += " Add points, then reopen this menu and Finish to save a loop."
			if("entrance", "choke")
				instructions += " Place in/beside a saved zone; each marker faces the way you are facing."
		to_chat(commander, span_notice(instructions))

/datum/tactical_command/proc/world_orders_menu()
	if(world_menu_open || ui_status(commander) != UI_INTERACTIVE)
		return
	remember_world_menu("orders")
	var/prompt_z = commander.z
	var/prompt_squad = selected_squad
	var/list/states = list("Guard" = "guard", "Patrol" = "patrol", "Fallback" = "fallback", "Retreat" = "retreat", "Deselect" = "deselect", "Back" = "back")
	var/list/choices = list()
	for(var/label in states)
		choices[label] = image('icons/mob/tactical_command.dmi', icon_state = states[label])
	var/choice = show_world_radial(choices, 56)
	if(!choice || ui_status(commander) != UI_INTERACTIVE || commander.z != prompt_z || selected_squad != prompt_squad)
		return
	if(choice == "Back")
		world_back()
		return
	if(choice == "Deselect")
		world_execute("deselect")
		return_to_interact()
		return
	if(!plan.find_squad(selected_squad))
		to_chat(commander, span_warning("Select a recruited marine with ordinary Interact first. Tacview can select an offscreen squad."))
		return
	if(choice == "Retreat")
		if(world_execute("order", list("order" = "retreat", "z" = prompt_z)))
			return_to_interact()
		return
	if(choice in list("Guard", "Patrol", "Fallback"))
		if(!world_execute("clear_draft", quiet = TRUE))
			return
		if(activate_world_targeting(lowertext(choice)))
			to_chat(commander, span_notice("[choice]: [world_click_gesture()] [choice == "Patrol" ? "a saved waypoint or route line" : "the saved zone"]. [choice == "Fallback" ? "This sets the destination without ordering retreat." : "The order applies to the clicked geometry."]"))

/// Visibility is independent of the selected designator tool. Actual activation remains ban-aware.
/datum/action/tactical_overlay
	name = "Tactical Overlay"
	desc = "Show or hide local tactical zones, approaches and routes. This does not change any squad orders or selected tool."
	action_icon = 'icons/mob/tactical_command.dmi'
	action_icon_state = "overlay"
	action_type = ACTION_TOGGLE

/datum/action/tactical_overlay/should_show()
	return ..() && (owner?.client?.holder || owner?.skills?.getRating(SKILL_LEADERSHIP) >= SKILL_LEAD_TRAINED)

/datum/action/tactical_overlay/can_use_action(silent, override_flags, selecting)
	return tactical_command_available(owner)

/datum/action/tactical_overlay/action_activate()
	var/datum/tactical_command/command = get_tactical_command(owner)
	if(!command)
		return
	command.set_world_overlay(!command.world_overlay_enabled)
	command.update_world_controls()
	to_chat(owner, span_notice("Tactical overlay [command.world_overlay_enabled ? "shown" : "hidden"]. Squad orders are unchanged."))


/// Planner/native changes cannot leave the legacy designator pointing at a DIFFERENT squad.
/datum/tactical_command/proc/sync_legacy_selection(datum/tactical_squad/squad)
	var/datum/action/ability/activable/build_designator/designator = commander.actions_by_path[/datum/action/ability/activable/build_designator]
	if(!designator?.selected_mob)
		return
	var/datum/component/ai_controller/controller = designator.selected_mob.GetComponent(/datum/component/ai_controller)
	var/datum/ai_behavior/human/brain = controller?.ai_behavior
	if(istype(brain) && brain.tactical_squad == squad)
		return
	designator.unindicate_target(designator.selected_mob)
	designator.selected_mob = null
