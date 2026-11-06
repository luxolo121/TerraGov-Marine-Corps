/// Personal editor state. The shared plan contains orders, never another commander's selection.
/datum/tactical_command
	var/mob/living/carbon/human/commander
	var/datum/tactical_plan/plan
	var/editor_z
	var/selected_squad
	var/selected_zone
	var/selected_route
	var/tool = "inspect"
	var/turf/anchor
	var/turf/cursor
	var/list/preview = list()
	var/list/draft_route = list()
	var/list/marker_undo = list()
	var/notice = "Select a squad, or create one and recruit nearby AI marines."
	var/notice_error = FALSE
	var/map_image
	var/marker_direction = NORTH
	var/geometry_revision = -1
	var/list/span_cache = list()

/datum/tactical_command/New(mob/living/carbon/human/user)
	. = ..()
	commander = user
	plan = get_tactical_plan(user.faction)
	RegisterSignal(user, COMSIG_QDELETING, PROC_REF(owner_deleted))
	RegisterSignals(user, list(COMSIG_MOB_LOGOUT, COMSIG_MOVABLE_Z_CHANGED, COMSIG_MOB_DEATH), PROC_REF(world_invalidated))
	RegisterSignals(user, list(COMSIG_MOVABLE_MOVED, COMSIG_ATOM_DIR_CHANGE), PROC_REF(world_moved))

/datum/tactical_command/proc/owner_deleted()
	SIGNAL_HANDLER
	qdel(src)

/datum/tactical_command/Destroy()
	close_world_menu()
	disable_world_overlay()
	SStgui.close_uis(src)
	if(commander)
		UnregisterSignal(commander, list(COMSIG_QDELETING, COMSIG_MOB_LOGOUT, COMSIG_MOVABLE_Z_CHANGED, COMSIG_MOB_DEATH, COMSIG_MOVABLE_MOVED, COMSIG_ATOM_DIR_CHANGE))
	commander = null
	plan = null
	preview = null
	draft_route = null
	return ..()

/datum/tactical_command/ui_state(mob/user)
	return GLOB.always_state

/// Kept separate so native scenarios can supply authority without manufacturing a BYOND client.
/datum/tactical_command/proc/has_command_access()
	return can_use_tactical_command(commander)

/datum/tactical_command/ui_status(mob/user, datum/ui_state/state)
	return user == commander && has_command_access() && user.faction == plan?.faction ? UI_INTERACTIVE : UI_CLOSE

/datum/tactical_command/ui_interact(mob/user, datum/tgui/ui)
	if(ui_status(user) != UI_INTERACTIVE)
		return
	set_world_overlay(TRUE)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "TacticalCommand", "Tactical Command")
		ui.open()

/// Every coordinate is an integer on the commander's CURRENT level, not a browser-supplied z.
/datum/tactical_command/proc/read_position(list/params)
	var/px = params["x"]
	var/py = params["y"]
	if(!isnum(px) || !isnum(py) || px != round(px) || py != round(py))
		return null
	if(px < 1 || px > world.maxx || py < 1 || py > world.maxy)
		return null
	return locate(px, py, commander.z)

/datum/tactical_command/proc/feedback(message, error = FALSE)
	notice = message
	notice_error = error
	return TRUE

/datum/tactical_command/proc/clear_draft()
	anchor = null
	preview = list()
	draft_route = list()
	marker_undo = list()

/datum/tactical_command/proc/check_level()
	if(editor_z == commander.z)
		return
	editor_z = commander.z
	clear_draft()
	cursor = null
	selected_zone = null
	selected_route = null
	tool = "inspect"
	world_target_order = null
	var/datum/hud_displays/map = SSminimaps.minimaps_by_z["[editor_z]"]
	map_image = map?.hud_image ? icon2base64(map.hud_image) : null

/// Row spans retain exact room footprints without shipping thousands of per-turf objects.
/datum/tactical_command/proc/encode_tiles(list/tiles)
	var/list/rows = list()
	for(var/turf/tile AS in tiles)
		LAZYADDASSOC(rows, "[tile.y]", tile.x)
	var/list/spans = list()
	for(var/row in rows)
		var/list/xs = sortList(rows[row], GLOBAL_PROC_REF(cmp_numeric_asc))
		var/start
		var/last
		for(var/x in xs)
			if(isnull(start))
				start = x
			else if(x != last + 1)
				spans += list(list(start, text2num(row), last - start + 1))
				start = x
			last = x
		if(!isnull(start))
			spans += list(list(start, text2num(row), last - start + 1))
	return spans

/datum/tactical_command/proc/encode_points(list/points)
	var/list/result = list()
	for(var/turf/point AS in points)
		result += list(list("x" = point.x, "y" = point.y))
	return result

/datum/tactical_command/ui_data(mob/user)
	if(ui_status(user) != UI_INTERACTIVE)
		return list()
	check_level()
	if(geometry_revision != plan.revision)
		geometry_revision = plan.revision
		span_cache = list()
	var/list/data = list("z" = editor_z, "revision" = plan.revision, "faction" = plan.faction, "tool" = tool, "notice" = notice, "notice_error" = notice_error, "selected_squad" = selected_squad, "selected_zone" = selected_zone, "selected_route" = selected_route)
	var/datum/hud_displays/map = SSminimaps.minimaps_by_z["[editor_z]"]
	data["marker_direction"] = marker_direction
	data["map"] = map_image
	data["offset_x"] = map?.x_offset || 0
	data["offset_y"] = map?.y_offset || 0
	data["max_x"] = world.maxx
	data["max_y"] = world.maxy
	data["cursor"] = cursor ? list("x" = cursor.x, "y" = cursor.y) : null
	data["anchor"] = anchor ? list("x" = anchor.x, "y" = anchor.y) : null
	data["preview"] = encode_tiles(preview)
	data["preview_count"] = length(preview)
	data["draft_route"] = encode_points(draft_route)
	var/list/zones = list()
	for(var/datum/tactical_zone/zone AS in plan.zones)
		if(zone.z != editor_z)
			continue
		var/list/markers = list()
		for(var/datum/tactical_marker/marker AS in zone.markers)
			markers += list(list("id" = marker.id, "kind" = marker.kind, "x" = marker.position.x, "y" = marker.position.y, "direction" = marker.direction))
		if(!span_cache[zone.id])
			span_cache[zone.id] = encode_tiles(zone.turfs)
		zones += list(list("id" = zone.id, "name" = zone.name, "purpose" = zone.purpose, "count" = length(zone.turfs), "spans" = span_cache[zone.id], "markers" = markers))
	data["zones"] = zones
	var/list/routes = list()
	for(var/datum/tactical_route/route AS in plan.routes)
		if(route.z == editor_z)
			routes += list(list("id" = route.id, "name" = route.name, "loop" = route.loop, "points" = encode_points(route.waypoints)))
	data["routes"] = routes
	var/list/squads = list()
	for(var/datum/tactical_squad/squad AS in plan.squads)
		var/list/members = list()
		for(var/mob/living/carbon/human/member AS in squad.members)
			members += list(list("id" = REF(member), "name" = member.real_name, "status" = squad.get_member_status(member), "z" = member.z, "health" = round(member.health)))
		squads += list(list("id" = squad.id, "name" = squad.name, "order" = squad.order, "status" = squad.status, "zone" = squad.zone?.id, "route" = squad.route?.id, "fallback" = squad.fallback_zone?.id, "zone_name" = squad.zone?.name, "route_name" = squad.route?.name, "fallback_name" = squad.fallback_zone?.name, "waypoint" = squad.waypoint_index, "members" = members))
	data["squads"] = squads
	var/list/recruits = list()
	var/list/friendlies = list()
	for(var/mob/living/carbon/human/human AS in GLOB.alive_human_list)
		if(human.faction != plan.faction || human.z != editor_z)
			continue
		var/datum/component/ai_controller/component = human.GetComponent(/datum/component/ai_controller)
		var/datum/ai_behavior/human/brain = component?.ai_behavior
		if(!istype(brain))
			brain = null
		friendlies += list(list("x" = human.x, "y" = human.y, "name" = human.real_name, "player" = !!human.client, "self" = human == user, "squad" = brain?.tactical_squad?.id))
		if(brain && !human.client && human.stat == CONSCIOUS && get_dist(user, human) <= 7)
			recruits += list(list("id" = REF(human), "name" = human.real_name, "squad" = brain.tactical_squad?.id, "squad_name" = brain.tactical_squad?.name))
	data["recruits"] = recruits
	data["friendlies"] = friendlies
	return data

/// Resolve a ref only against authorized candidates, never locate() an arbitrary browser ref.
/datum/tactical_command/proc/find_recruit(id)
	for(var/mob/living/carbon/human/human AS in GLOB.alive_human_list)
		if(REF(human) == id && human.faction == plan.faction && human.z == commander.z && get_dist(commander, human) <= 7 && !human.client && human.stat == CONSCIOUS)
			return human
	return null

/datum/tactical_command/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	. = dispatch(action, params, usr)
	refresh_world_overlay()

/// All frontends enter here: permission, level and order validation cannot drift apart.
/datum/tactical_command/proc/dispatch(action, list/params, mob/user)
	if(ui_status(user) != UI_INTERACTIVE)
		return FALSE
	check_level()
	// Refuse delayed actions sent from another level rather than applying old geometry here.
	if(params["z"] != editor_z)
		return feedback("Your level changed. Select the target again on this map.", TRUE)
	var/datum/tactical_squad/squad = plan.find_squad(selected_squad)
	var/datum/tactical_zone/zone = plan.find_zone(selected_zone)
	var/datum/tactical_route/route = plan.find_route(selected_route)
	if(zone && zone.z != editor_z)
		zone = null
	if(route && route.z != editor_z)
		route = null
	switch(action)
		if("deselect")
			// Also clear the world designator's off-screen highlight; this never alters AI orders.
			var/datum/action/ability/activable/build_designator/designator = commander.actions_by_path[/datum/action/ability/activable/build_designator]
			if(designator && commander.selected_ability == designator)
				designator.deselect()
			else if(designator?.selected_mob)
				designator.unindicate_target(designator.selected_mob)
				designator.selected_mob = null
			selected_squad = null
			selected_zone = null
			selected_route = null
			tool = "inspect"
			world_target_order = null
			clear_draft()
			return feedback("Selection cleared. Every squad keeps its current orders.")
		if("tool")
			if(!(params["tool"] in list("inspect", "rectangle", "room", "route", "entrance", "choke")))
				return FALSE
			tool = params["tool"]
			world_target_order = null
			clear_draft()
			return feedback("[tool] tool selected. Click the terrain map.")
		if("clear_draft")
			clear_draft()
			world_target_order = null
			tool = "inspect"
			return feedback("Draft cleared. Saved zones and orders were not changed.")
		if("marker_facing")
			if(!(params["direction"] in list(NORTH, EAST, SOUTH, WEST)))
				return FALSE
			marker_direction = params["direction"]
			return feedback("Approach facing: [dir2text(marker_direction)].")
		if("map_click")
			var/turf/position = read_position(params)
			if(!position)
				return feedback("Invalid map coordinate.", TRUE)
			cursor = position
			switch(tool)
				if("rectangle")
					if(!anchor || length(preview))
						anchor = position
						preview = list()
						return feedback("First corner set. Click the opposite corner to preview.")
					if((abs(anchor.x - position.x) + 1) * (abs(anchor.y - position.y) + 1) > 1600)
						return feedback("Zone exceeds 1600 tiles. Choose a closer second corner.", TRUE)
					preview = block(anchor, position)
					return feedback("Rectangle ready: [length(preview)] tiles. Name it and save.")
				if("room")
					var/area/room = get_area(position)
					var/list/room_tiles = room.get_turfs_by_zlevel(editor_z)
					if(!length(room_tiles) || length(room_tiles) > 1600)
						preview = list()
						return feedback("This mapped area is too large for a room zone. Use Rectangle to select a local footprint.", TRUE)
					preview = room_tiles.Copy()
					return feedback("Room preview: [room.name], [length(preview)] tiles. Save to keep this exact footprint.")
				if("route")
					if(length(draft_route) >= 32)
						return feedback("A route may have at most 32 waypoints.", TRUE)
					if(length(draft_route) && draft_route[length(draft_route)] == position)
						return feedback("Choose a different next waypoint.", TRUE)
					draft_route += position
					return feedback("Waypoint [length(draft_route)] added. Save once the route is ready.")
				if("entrance", "choke")
					if(!zone)
						return feedback("Select a saved zone before marking its entrances or choke points.", TRUE)
					var/old_direction
					for(var/datum/tactical_marker/existing AS in zone.markers)
						if(existing.position == position && existing.kind == tool)
							old_direction = existing.direction
							break
					var/datum/tactical_marker/placed = zone.add_marker(tool, position, marker_direction)
					if(!placed)
						return feedback("Place markers in or directly beside the zone; maximum 16 per zone.", TRUE)
					marker_undo += list(list("zone" = zone.id, "marker" = placed.id, "old_direction" = old_direction, "direction" = marker_direction))
					if(length(marker_undo) > 32)
						marker_undo.Cut(1, 2)
					plan.touch()
					return feedback("[tool] marker saved on [zone.name]. Undo reverses the last marker; Cancel leaves saved markers intact.")
			return feedback("Map target: [position.x], [position.y]. Hold at target applies to the selected squad.")
		if("zone_save")
			if(!length(preview))
				return feedback("Preview a room or rectangle first.", TRUE)
			var/datum/tactical_zone/new_zone = plan.create_zone(params["name"], preview, params["purpose"])
			if(!new_zone)
				return feedback("Zone could not be saved. Limit: 32 zones, 1600 tiles, one level, valid purpose.", TRUE)
			selected_zone = new_zone.id
			clear_draft()
			tool = "inspect"
			return feedback("Saved [new_zone.name]. Its geometry can be reused for guard or fallback assignments.")
		if("zone_select")
			zone = plan.find_zone(params["id"])
			if(!zone || zone.z != editor_z)
				return feedback("That zone is no longer available.", TRUE)
			selected_zone = zone.id
			return feedback("Selected zone [zone.name]. Selection alone does not give orders.")
		if("zone_rename")
			if(!zone)
				return feedback("Select a zone first.", TRUE)
			zone.name = tactical_label(params["name"], zone.name)
			plan.touch()
			return feedback("Zone renamed. Existing assignments are preserved.")
		if("zone_purpose")
			if(!zone || !zone.set_purpose(params["purpose"]))
				return feedback("Select a zone and a valid purpose.", TRUE)
			plan.touch()
			return feedback("Zone reclassified without changing its footprint or assignments.")
		if("zone_delete")
			if(!zone || !plan.delete_zone(zone))
				return feedback("Cannot delete this zone while a squad uses it. Reassign guard and fallback orders first.", TRUE)
			selected_zone = null
			return feedback("Zone deleted.")
		if("marker_delete")
			if(!zone || !zone.remove_marker(params["id"]))
				return feedback("That marker is no longer available.", TRUE)
			plan.touch()
			return TRUE
		if("route_undo")
			if(length(draft_route))
				draft_route.Cut(length(draft_route))
			return feedback("Last draft waypoint removed. [length(draft_route)] remain.")
		if("draft_undo")
			if(tool == "entrance" || tool == "choke")
				if(!length(marker_undo))
					return feedback("No marker placement to undo in this drawing session.", TRUE)
				var/list/last = marker_undo[length(marker_undo)]
				marker_undo.Cut(length(marker_undo))
				var/datum/tactical_zone/marked_zone = plan.find_zone(last["zone"])
				for(var/datum/tactical_marker/marker AS in marked_zone?.markers)
					if(marker.id != last["marker"])
						continue
					if(marker.direction != last["direction"])
						return feedback("This marker was edited since your placement; leaving the newer change intact.", TRUE)
					if(isnull(last["old_direction"]))
						marked_zone.remove_marker(marker.id)
					else
						marker.direction = last["old_direction"]
						plan.touch()
					return feedback("Last marker placement undone.")
				return feedback("That marker is no longer available.", TRUE)
			if(tool == "route")
				if(length(draft_route))
					draft_route.Cut(length(draft_route))
			else if(length(preview))
				preview = list()
			else
				anchor = null
			return feedback("Last draft step undone. Saved geometry and orders were not changed.")
		if("route_save")
			var/datum/tactical_route/new_route = plan.create_route(params["name"], draft_route, params["loop"] == TRUE)
			if(!new_route)
				return feedback("Route needs 2–32 distinct consecutive waypoints; at most 32 routes per faction.", TRUE)
			selected_route = new_route.id
			clear_draft()
			tool = "inspect"
			return feedback("Saved ordered patrol route [new_route.name].")
		if("route_select")
			route = plan.find_route(params["id"])
			if(!route || route.z != editor_z)
				return feedback("That route is no longer available.", TRUE)
			selected_route = route.id
			return feedback("Selected route [route.name]. Selection alone does not give orders.")
		if("route_rename")
			if(!route)
				return FALSE
			route.name = tactical_label(params["name"], route.name)
			plan.touch()
			return TRUE
		if("route_delete")
			if(!route || !plan.delete_route(route))
				return feedback("Cannot delete a route assigned to a squad. Reassign it first.", TRUE)
			selected_route = null
			return feedback("Route deleted.")
		if("squad_create")
			if(length(plan.squads) >= 16)
				return feedback("This faction already has 16 tactical squads.", TRUE)
			var/datum/tactical_squad/new_squad = new(plan, params["name"])
			selected_squad = new_squad.id
			sync_legacy_selection(new_squad)
			return feedback("Created [new_squad.name]. Recruit AI within seven tiles using the roster.")
		if("squad_select")
			squad = plan.find_squad(params["id"])
			if(!squad)
				return feedback("That squad is no longer available.", TRUE)
			selected_squad = squad.id
			sync_legacy_selection(squad)
			return feedback("Selected [squad.name]: [squad.order].")
		if("squad_rename")
			if(!squad)
				return FALSE
			squad.name = tactical_label(params["name"], squad.name)
			plan.touch()
			return TRUE
		if("squad_delete")
			if(!squad || !plan.remove_squad(squad))
				return feedback("That squad is no longer available.", TRUE)
			selected_squad = null
			return feedback("Squad disbanded. Released AI return to autonomous behavior.")
		if("recruit", "transfer")
			var/mob/living/carbon/human/recruit = find_recruit(params["id"])
			if(!squad || !recruit || !squad.add_member(recruit, action == "transfer"))
				return feedback("Recruitment failed: select a squad and a conscious allied AI within seven tiles; use Transfer for an assigned marine.", TRUE)
			return feedback("[recruit.real_name] assigned to [squad.name].")
		if("release")
			if(!squad)
				return FALSE
			for(var/mob/living/carbon/human/member AS in squad.members)
				if(REF(member) != params["id"])
					continue
				squad.remove_member(member)
				return feedback("[member.real_name] released to autonomous behavior.")
			return feedback("That marine is no longer in the selected squad.", TRUE)
		if("fallback")
			var/datum/tactical_zone/fallback = plan.find_zone(params["id"])
			if(!squad || (params["id"] && (!fallback || fallback.z != editor_z)) || !squad.set_fallback(fallback))
				return feedback("Unable to update fallback. Select a squad and a valid zone on this level.", TRUE)
			return feedback(fallback ? "[squad.name] fallback: [fallback.name]. Retreat is a separate explicit order." : "Fallback cleared.")
		if("order")
			if(!squad || !(params["order"] in list("hold", "follow", "guard", "patrol", "retreat")))
				return feedback("Select a squad and an order first.", TRUE)
			for(var/mob/living/carbon/human/member AS in squad.members)
				if(member.z != editor_z)
					return feedback("Squad members are on another level. Join them before issuing a new map assignment.", TRUE)
			if(params["order"] == "retreat" && squad.fallback_zone?.z != editor_z)
				return feedback("Set a fallback on this level before ordering retreat.", TRUE)
			var/turf/hold_target = params["at_cursor"] ? cursor : get_turf(commander)
			if(params["at_cursor"] && !hold_target)
				return feedback("Click a location on the map first.", TRUE)
			var/mob/living/follow_target = commander
			if(params["follow_ref"])
				follow_target = null
				for(var/mob/living/candidate in view(9, commander))
					if(REF(candidate) == params["follow_ref"] && candidate.faction == plan.faction && candidate.stat == CONSCIOUS && world_target_visible(candidate))
						follow_target = candidate
						break
				if(!follow_target)
					return feedback("Choose a visible conscious ally on your level to follow.", TRUE)
			if(!squad.issue_order(params["order"], params["order"] == "guard" ? zone : null, params["order"] == "patrol" ? route : null, follow_target, hold_target))
				return feedback("Order rejected. Guard needs a zone; patrol needs a route; retreat needs a fallback on the squad's level.", TRUE)
			plan.touch()
			return feedback("[squad.name]: [squad.order]. This order persists until you change it.")
	return FALSE

/// A separate always-visible leadership button; selecting/deselecting a designator is not an order.
/datum/action/tactical_command
	name = "Tactical Command"
	desc = "Manage AI squads, persistent orders, guard zones, fallback areas, and patrol routes."
	action_icon = 'icons/mob/tactical_command.dmi'
	action_icon_state = "command"
	var/datum/tactical_command/command_ui

/datum/action/tactical_command/should_show()
	return ..() && (owner?.client?.holder || owner?.skills?.getRating(SKILL_LEADERSHIP) >= SKILL_LEAD_TRAINED)

/datum/action/tactical_command/can_use_action(silent, override_flags, selecting)
	return tactical_command_available(owner)

/datum/action/tactical_command/action_activate()
	if(!can_use_action())
		return
	var/datum/tactical_command/command = get_tactical_command(owner)
	command?.ui_interact(owner)

/datum/action/tactical_command/Destroy()
	QDEL_NULL(command_ui)
	return ..()

/// Optional admin-spawnable access item; it never grants command permission itself.
/obj/item/tactical_command_tablet
	name = "tactical command tablet"
	desc = "A command terminal for AI squad assignments, guard zones and patrol routes. Requires leadership training."
	icon = 'icons/obj/items/pda.dmi'
	icon_state = "pda_large_green"
	w_class = WEIGHT_CLASS_SMALL

/obj/item/tactical_command_tablet/attack_self(mob/user)
	if(!can_use_tactical_command(user))
		to_chat(user, span_warning("Leadership training and command access are required."))
		return
	var/datum/action/tactical_command/action = user.actions_by_path[/datum/action/tactical_command]
	action?.action_activate()
