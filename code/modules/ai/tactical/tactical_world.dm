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
	var/world_target_order
	var/world_refresh_timer
	var/world_menu_open = FALSE
	var/world_menu_id
	var/world_menu_serial = 0

/// Never render remote cameras, blindness, another level, or outside the local viewport.
/datum/tactical_command/proc/world_visible_tiles()
	var/list/result = list()
	if(!commander?.client || commander.client.eye != commander || !isturf(commander.loc) || commander.eye_blind)
		return result
	var/list/dimensions = getviewsize(commander.client.view)
	var/half_width = min(9, round((dimensions[1] - 1) / 2))
	var/half_height = min(9, round((dimensions[2] - 1) / 2))
	for(var/turf/tile in view(9, commander))
		if(abs(tile.x - commander.x) <= half_width && abs(tile.y - commander.y) <= half_height && commander.in_fov(tile))
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

/// Clear stale sight immediately; coalesce movement/turn bursts into one bounded local redraw.
/datum/tactical_command/proc/world_moved()
	SIGNAL_HANDLER
	if(!world_overlay_enabled)
		return
	clear_world_images()
	if(!world_refresh_timer)
		world_refresh_timer = addtimer(CALLBACK(src, PROC_REF(world_deferred_refresh)), 0.2 SECONDS, TIMER_STOPPABLE)

/datum/tactical_command/proc/world_deferred_refresh()
	world_refresh_timer = null
	refresh_world_overlay()

/datum/tactical_command/process()
	refresh_world_overlay()

/// A line test against LOCAL tiles: never walk a map-wide route to draw a local segment.
/proc/tactical_tile_on_segment(turf/tile, turf/start, turf/end)
	if(!tile || !start || !end || tile.z != start.z || start.z != end.z)
		return FALSE
	if(tile.x < min(start.x, end.x) || tile.x > max(start.x, end.x) || tile.y < min(start.y, end.y) || tile.y > max(start.y, end.y))
		return FALSE
	var/dx = end.x - start.x
	var/dy = end.y - start.y
	return abs((tile.x - start.x) * dy - (tile.y - start.y) * dx) <= max(abs(dx), abs(dy)) / 2

/datum/tactical_command/proc/add_world_image(turf/tile, state, tint, direction = SOUTH, label)
	// A pathological pile of overlapping plans cannot allocate unbounded client images.
	if(length(world_images) >= 900)
		return
	var/image/marker = image('icons/mob/tactical_command.dmi', tile, state, ABOVE_MOB_LAYER, direction)
	marker.plane = GAME_PLANE
	marker.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	marker.color = tint
	marker.alpha = 210
	if(label)
		marker.maptext = "<span style='font-size:7px;color:white;text-shadow:1px 1px black'>[label]</span>"
		marker.maptext_x = 11
		marker.maptext_y = 17
	world_images += marker

/datum/tactical_command/proc/draw_world_route(list/points, list/visible, tint, loop = FALSE, connectors = TRUE)
	var/list/drawn_strokes = list()
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
		var/line_direction = abs(next.x - point.x) > abs(next.y - point.y) ? EAST : NORTH
		for(var/turf/tile AS in visible)
			if(length(world_images) >= 900)
				return
			if(!drawn_strokes[tile] && tile != point && tile != next && tactical_tile_on_segment(tile, point, next))
				add_world_image(tile, "route", tint, line_direction)
				drawn_strokes[tile] = TRUE

/datum/tactical_command/proc/refresh_world_overlay()
	clear_world_images()
	if(!world_overlay_enabled)
		return
	if(ui_status(commander) != UI_INTERACTIVE || (editor_z && editor_z != commander.z))
		world_invalidated()
		return
	check_level()
	update_world_controls()
	var/list/visible = world_visible_tiles()
	if(!length(visible))
		return
	world_client = commander.client
	build_world_images(visible)
	world_client.images += world_images

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
	var/list/preview_lookup = list()
	for(var/turf/tile AS in preview)
		preview_lookup[tile] = TRUE
	for(var/turf/tile AS in visible)
		if(preview_lookup[tile])
			add_world_image(tile, "zone", "#ffdf68")
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
		for(var/datum/tactical_zone/zone AS in ordered_zones)
			if(!zone.contains(tile))
				continue
			var/tint = zone == selected ? "#62e8ff" : (zone.purpose == "fallback" ? "#ca95ff" : (zone.purpose == "staging" ? "#ffcf76" : "#83b99b"))
			for(var/direction in GLOB.cardinals)
				if(!zone.contains(get_step(tile, direction)))
					add_world_image(tile, "boundary", tint, direction)
			// Overlapping interiors need not stack unreadable outlines. Selected zone has priority.
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
		designator.button.desc = "Right-click (Select Buildtype key, default I) for tactical orders/tools, save, undo, cancel and overlays. Use [world_click_gesture()] on visible terrain or marines. Mode: [mode]. [context]. Zone: [zone?.name || "none"]. Route: [route?.name || "none"]."
		if(designator.designator_mode == TACTICAL_DESIGNATOR_MODE)
			designator.button.maptext = "<span style='font-size:6px;color:white;text-shadow:1px 1px black'>[uppertext(mode)]</span>"
		else
			designator.button.maptext = null

/datum/tactical_command/proc/world_click_gesture()
	return (commander?.client?.prefs?.toggles_gameplay & MIDDLESHIFTCLICKING) ? "middle-click" : "shift-click"

/// HUD callers capture z before any sleeping prompt; dispatch rejects stale answers.
/datum/tactical_command/proc/world_execute(action, list/params)
	if(!islist(params))
		params = list()
	if(isnull(params["z"]))
		params["z"] = commander.z
	notice_error = FALSE
	var/result = dispatch(action, params, commander)
	if(ui_status(commander) != UI_INTERACTIVE)
		world_invalidated()
		return FALSE
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

/datum/tactical_command/proc/world_click(atom/target)
	if(ui_status(commander) != UI_INTERACTIVE || !world_target_visible(target))
		return FALSE
	check_level()
	var/turf/position = get_turf(target)
	if(world_target_order)
		var/order = world_target_order
		cursor = position
		var/list/params = list("order" = order, "at_cursor" = order == "hold")
		if(order == "follow")
			if(!isliving(target))
				to_chat(commander, span_warning("Choose a conscious living ally to follow."))
				return FALSE
			params["follow_ref"] = REF(target)
		if(!world_execute("order", params))
			return FALSE
		world_target_order = null
		update_world_controls()
		return TRUE
	if(tool != "inspect")
		return world_execute("map_click", list("x" = position.x, "y" = position.y))
	if(ishuman(target))
		var/mob/living/carbon/human/human = target
		var/datum/component/ai_controller/controller = human.GetComponent(/datum/component/ai_controller)
		var/datum/ai_behavior/human/brain = controller?.ai_behavior
		if(istype(brain) && brain.tactical_squad?.plan == plan)
			world_execute("squad_select", list("id" = brain.tactical_squad.id))
			to_chat(commander, span_notice("Selected [brain.tactical_squad.name] ([brain.tactical_squad.order]). Right-click the designator for tactical orders or Deselect — keep orders."))
			return TRUE
	var/list/choices = list()
	for(var/datum/tactical_zone/zone AS in plan.zones)
		if(zone.contains(position))
			choices["Zone: [zone.name] ([zone.id])"] = list("zone_select", zone.id)
	for(var/datum/tactical_route/route AS in plan.routes)
		if(position in route.waypoints)
			choices["Route: [route.name] ([route.id])"] = list("route_select", route.id)
	if(length(choices))
		var/choice = choices[1]
		var/click_z = commander.z
		if(length(choices) > 1)
			choice = input(commander, "Choose the plan at this tile", "Tactical selection") as null|anything in choices
		if(choice)
			var/list/selection = choices[choice]
			return world_execute(selection[1], list("id" = selection[2], "z" = click_z))
	cursor = position
	to_chat(commander, span_notice("Target [position.x], [position.y]. Select a marine or saved zone/waypoint; use the designator radial for tactical orders."))
	return TRUE

/// Native list prompts retain access to squads and plans after their last member leaves sight.
/datum/tactical_command/proc/world_choose(kind)
	var/list/choices = list()
	var/prompt_z = commander.z
	switch(kind)
		if("squad")
			for(var/datum/tactical_squad/squad AS in plan.squads)
				choices["[squad.name] — [squad.order], [length(squad.members)] marines ([squad.id])"] = squad.id
		if("zone")
			for(var/datum/tactical_zone/zone AS in plan.zones)
				if(zone.z == prompt_z)
					choices["[zone.name] — [zone.purpose] ([zone.id])"] = zone.id
		if("route")
			for(var/datum/tactical_route/route AS in plan.routes)
				if(route.z == prompt_z)
					choices["[route.name] — [length(route.waypoints)] points ([route.id])"] = route.id
	if(!length(choices))
		to_chat(commander, span_warning("No saved [kind] is available here. Use Tactical tools in the designator radial for geometry; create/recruit squads in Tacview."))
		return FALSE
	var/choice = input(commander, "Select [kind] (selection alone never gives orders)", "Tactical Command") as null|anything in choices
	if(!choice)
		return FALSE
	return world_execute("[kind]_select", list("id" = choices[choice], "z" = prompt_z))

/datum/tactical_command/proc/world_save()
	if(tool == "entrance" || tool == "choke")
		to_chat(commander, span_notice("Approach markers save when placed. Undo reverses the last placement; Cancel leaves saved markers intact."))
		return
	var/prompt_z = commander.z
	var/saving_route = tool == "route"
	if(!(saving_route ? length(draft_route) >= 2 : length(preview)))
		to_chat(commander, span_warning("Preview a room/rectangle or place at least two route points first."))
		return
	var/label = input(commander, "Name this [saving_route ? "route" : "zone"]", "Save tactical draft") as null|text
	if(isnull(label))
		return
	if(saving_route)
		var/mode = input(commander, "Patrol traversal", "Save route") as null|anything in list("Loop", "Back and forth")
		if(mode)
			world_execute("route_save", list("name" = label, "loop" = mode == "Loop", "z" = prompt_z))
	else
		var/purpose = input(commander, "Zone purpose (classification, not an order)", "Save zone") as null|anything in list("guard", "fallback", "staging")
		if(purpose)
			world_execute("zone_save", list("name" = label, "purpose" = purpose, "z" = prompt_z))

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
	var/choice = show_radial_menu(commander, commander, choices, uniqueid = expected_id, radius = radius, custom_check = CALLBACK(src, PROC_REF(world_menu_valid), expected_owner, expected_client, expected_z, expected_id), tooltips = TRUE, angle_override = angle)
	var/still_valid = world_menu_valid(expected_owner, expected_client, expected_z, expected_id)
	// An invalidated older menu must never clear the guard for a subsequently opened one.
	if(world_menu_id == expected_id)
		world_menu_id = null
		world_menu_open = FALSE
	return still_valid ? choice : null

/datum/tactical_command/proc/world_tool_menu()
	if(world_menu_open || ui_status(commander) != UI_INTERACTIVE)
		return
	var/prompt_z = commander.z
	var/list/choices = list()
	var/list/states = list("Select" = "selected", "Room" = "zone", "Rectangle" = "zone", "Route" = "waypoint", "Entrance" = "entrance", "Choke" = "choke", "Save draft" = "command", "Undo" = "orders", "Cancel draft" = "designate", "Toggle overlays" = "overlay")
	for(var/label in states)
		choices[label] = image('icons/mob/tactical_command.dmi', icon_state = states[label])
	var/choice = show_world_radial(choices, 64, 36)
	if(!choice || ui_status(commander) != UI_INTERACTIVE || commander.z != prompt_z)
		return
	switch(choice)
		if("Save draft")
			world_save()
			return
		if("Undo")
			world_execute("draft_undo")
			return
		if("Cancel draft")
			world_execute("clear_draft")
			return
		if("Toggle overlays")
			set_world_overlay(!world_overlay_enabled)
			to_chat(commander, span_notice("Local tactical overlays [world_overlay_enabled ? "shown" : "hidden"]. Orders are unchanged."))
			return
	var/new_tool = choice == "Select" ? "inspect" : lowertext(choice)
	if(new_tool == "entrance" || new_tool == "choke")
		if(!plan.find_zone(selected_zone) && !world_choose("zone"))
			return
		var/list/directions = list("North" = NORTH, "East" = EAST, "South" = SOUTH, "West" = WEST)
		var/facing = input(commander, "Marker faces toward this approach", "Approach facing") as null|anything in directions
		if(!facing || !world_execute("marker_facing", list("direction" = directions[facing], "z" = prompt_z)))
			return
	if(world_execute("tool", list("tool" = new_tool, "z" = prompt_z)))
		activate_world_targeting()
		to_chat(commander, span_notice("[capitalize(new_tool)]: [world_click_gesture()] visible tiles. Right-click the designator → Tactical tools for Save / Undo / Cancel."))

/datum/tactical_command/proc/world_orders_menu()
	if(world_menu_open || ui_status(commander) != UI_INTERACTIVE)
		return
	var/prompt_z = commander.z
	var/prompt_squad = selected_squad
	var/list/states = list("Select squad" = "selected", "Follow me" = "orders", "Follow ally" = "selected", "Hold here" = "orders", "Hold target" = "designate", "Guard zone" = "zone", "Patrol route" = "waypoint", "Set fallback" = "zone", "Retreat" = "orders", "Deselect" = "selected")
	var/list/choices = list()
	for(var/label in states)
		choices[label] = image('icons/mob/tactical_command.dmi', icon_state = states[label])
	var/choice = show_world_radial(choices, 64, 36)
	if(!choice || ui_status(commander) != UI_INTERACTIVE || commander.z != prompt_z || selected_squad != prompt_squad)
		return
	if(choice == "Deselect")
		world_execute("deselect")
		return
	if(choice == "Select squad")
		world_choose("squad")
		set_world_overlay(TRUE)
		return
	if(!plan.find_squad(selected_squad))
		to_chat(commander, span_warning("Select a squad first, either here or by targeting a recruited marine with the designator."))
		return
	switch(choice)
		if("Follow me")
			world_execute("order", list("order" = "follow", "z" = prompt_z))
		if("Hold here")
			world_execute("order", list("order" = "hold", "z" = prompt_z))
		if("Hold target", "Follow ally")
			activate_world_targeting(choice == "Hold target" ? "hold" : "follow")
			to_chat(commander, span_notice("[choice]: [world_click_gesture()] the visible target. Right-click the designator → Deselect — keep orders to cancel selection."))
		if("Guard zone", "Set fallback")
			if(world_choose("zone") && selected_squad == prompt_squad)
				world_execute(choice == "Set fallback" ? "fallback" : "order", list("id" = selected_zone, "order" = "guard", "z" = prompt_z))
		if("Patrol route")
			if(world_choose("route") && selected_squad == prompt_squad)
				world_execute("order", list("order" = "patrol", "z" = prompt_z))
		if("Retreat")
			world_execute("order", list("order" = "retreat", "z" = prompt_z))
	set_world_overlay(TRUE)


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
