/// Round-local command plans. Factions share geometry internally, never enemy contacts.
GLOBAL_LIST_EMPTY(tactical_plans)

/// The plan is deliberately separate from map areas and from individual NPC brains.
/proc/get_tactical_plan(faction)
	if(!istext(faction) || !length(faction))
		return null
	var/datum/tactical_plan/plan = GLOB.tactical_plans[faction]
	if(QDELETED(plan))
		plan = new(faction)
		GLOB.tactical_plans[faction] = plan
	return plan

/// Use the existing designator leadership threshold; possession of a tablet is not authority.
/proc/can_use_tactical_command(mob/user)
	if(!ishuman(user) || !user.client || user.incapacitated() || !user.faction)
		return FALSE
	if(user.client.holder)
		return TRUE
	if(user.skills?.getRating(SKILL_LEADERSHIP) < SKILL_LEAD_TRAINED)
		return FALSE
	return !is_banned_from(user.ckey, GLOB.roles_allowed_minimap_draw)

/// Shared validation for player-facing labels, including names supplied by forged UI messages.
/proc/tactical_label(value, default_name = "Unnamed")
	if(!istext(value))
		return default_name
	var/clean_name = trim(strip_html(value, 40))
	return length(clean_name) ? clean_name : default_name

/datum/tactical_plan
	var/faction
	var/list/zones = list()
	var/list/routes = list()
	var/list/squads = list()
	var/revision = 0
	var/id_counter = 0

/datum/tactical_plan/New(new_faction)
	. = ..()
	faction = new_faction

/datum/tactical_plan/Destroy()
	if(GLOB.tactical_plans[faction] == src)
		GLOB.tactical_plans -= faction
	// Squads release their members before the geometry they reference disappears.
	for(var/datum/tactical_squad/squad AS in squads.Copy())
		qdel(squad)
	QDEL_LIST(zones)
	QDEL_LIST(routes)
	squads = null
	return ..()

/datum/tactical_plan/proc/next_id(prefix)
	return "[prefix]-[++id_counter]"

/datum/tactical_plan/proc/touch()
	revision++

/datum/tactical_plan/proc/find_zone(id)
	for(var/datum/tactical_zone/zone AS in zones)
		if(zone.id == id)
			return zone
	return null

/datum/tactical_plan/proc/find_route(id)
	for(var/datum/tactical_route/route AS in routes)
		if(route.id == id)
			return route
	return null

/datum/tactical_plan/proc/find_squad(id)
	for(var/datum/tactical_squad/squad AS in squads)
		if(squad.id == id)
			return squad
	return null

/// Validate before allocating; reject mixed levels rather than silently clipping the instruction.
/datum/tactical_plan/proc/create_zone(name, list/turfs, purpose = "guard")
	if(length(zones) >= 32 || !islist(turfs) || !length(turfs) || length(turfs) > 1600)
		return null
	if(!(purpose in list("guard", "fallback", "staging")))
		return null
	var/zone_z
	var/has_walkable_tile = FALSE
	var/list/unique_turfs = list()
	for(var/candidate in turfs)
		if(!isturf(candidate))
			return null
		var/turf/tile = candidate
		if(zone_z && tile.z != zone_z)
			return null
		zone_z = tile.z
		if(!tile.density && !isspaceturf(tile))
			has_walkable_tile = TRUE
		unique_turfs |= tile
	if(!has_walkable_tile)
		return null
	var/datum/tactical_zone/zone = new(src, tactical_label(name, "Zone [length(zones) + 1]"), unique_turfs, purpose)
	zones += zone
	touch()
	return zone

/datum/tactical_plan/proc/create_rectangle(name, turf/a, turf/b, purpose = "guard")
	if(!isturf(a) || !isturf(b) || a.z != b.z)
		return null
	// Cap the work before calling block(), not after allocating an arbitrary map-sized list.
	if((abs(a.x - b.x) + 1) * (abs(a.y - b.y) + 1) > 1600)
		return null
	return create_zone(name, block(a, b), purpose)

/datum/tactical_plan/proc/create_room(name, turf/at, purpose = "guard")
	if(!isturf(at))
		return null
	var/area/room = get_area(at)
	return create_zone(name || room.name, room.get_turfs_by_zlevel(at.z), purpose)

/// Deleting a referenced assignment is an explicit error, never a silent order cancellation.
/datum/tactical_plan/proc/delete_zone(datum/tactical_zone/zone)
	if(!(zone in zones))
		return FALSE
	for(var/datum/tactical_squad/squad AS in squads)
		if(squad.zone == zone || squad.fallback_zone == zone)
			return FALSE
	zones -= zone
	qdel(zone)
	touch()
	return TRUE

/datum/tactical_plan/proc/create_route(name, list/waypoints, loop = TRUE)
	if(length(routes) >= 32 || !islist(waypoints) || length(waypoints) < 2 || length(waypoints) > 32)
		return null
	var/route_z
	var/turf/previous
	for(var/candidate in waypoints)
		if(!isturf(candidate))
			return null
		var/turf/tile = candidate
		if(route_z && tile.z != route_z)
			return null
		if(tile.density || isspaceturf(tile))
			return null
		if(tile == previous)
			return null
		route_z = tile.z
		previous = tile
	var/datum/tactical_route/route = new(src, tactical_label(name, "Route [length(routes) + 1]"), waypoints, loop)
	routes += route
	touch()
	return route

/datum/tactical_plan/proc/delete_route(datum/tactical_route/route)
	if(!(route in routes))
		return FALSE
	for(var/datum/tactical_squad/squad AS in squads)
		if(squad.route == route)
			return FALSE
	routes -= route
	qdel(route)
	touch()
	return TRUE

/datum/tactical_plan/proc/remove_squad(datum/tactical_squad/squad)
	if(!(squad in squads))
		return FALSE
	qdel(squad)
	touch()
	return TRUE

/// Immutable footprint with a mutable human label and purpose. No engine area metadata is changed.
/datum/tactical_zone
	var/id
	var/name
	var/purpose
	var/z
	var/list/turfs = list()
	var/list/markers = list()
	var/min_x
	var/max_x
	var/min_y
	var/max_y
	var/turf/center
	var/datum/tactical_plan/plan
	/// Coordinate membership survives ordinary ChangeTurf replacements.
	var/list/coordinates = list()

/datum/tactical_zone/New(datum/tactical_plan/new_plan, new_name, list/new_turfs, new_purpose)
	. = ..()
	plan = new_plan
	id = plan.next_id("zone")
	name = new_name
	purpose = new_purpose
	turfs = new_turfs.Copy()
	var/turf/first = turfs[1]
	z = first.z
	min_x = max_x = first.x
	min_y = max_y = first.y
	for(var/turf/tile AS in turfs)
		coordinates["[tile.x],[tile.y]"] = TRUE
		min_x = min(min_x, tile.x)
		max_x = max(max_x, tile.x)
		min_y = min(min_y, tile.y)
		max_y = max(max_y, tile.y)
	center = nearest_turf(locate(round((min_x + max_x) / 2), round((min_y + max_y) / 2), z))

/datum/tactical_zone/Destroy()
	QDEL_LIST(markers)
	plan = null
	center = null
	turfs = null
	coordinates = null
	return ..()

/datum/tactical_zone/proc/contains(atom/location)
	var/turf/tile = get_turf(location)
	return tile && tile.z == z && coordinates["[tile.x],[tile.y]"]

/// Prefer a floor tile; the exact footprint (including walls) is still retained for display.
/datum/tactical_zone/proc/nearest_turf(atom/location)
	var/turf/origin = get_turf(location)
	if(!origin || origin.z != z)
		return null
	var/turf/best
	var/best_distance = INFINITY
	for(var/turf/tile AS in turfs)
		if(tile.density || isspaceturf(tile))
			continue
		var/distance = get_dist(origin, tile)
		if(distance < best_distance)
			best = tile
			best_distance = distance
	return best

/datum/tactical_zone/proc/set_purpose(new_purpose)
	if(!(new_purpose in list("guard", "fallback", "staging")))
		return FALSE
	purpose = new_purpose
	plan?.touch()
	return TRUE

/// Entrances/frontages are attached to a zone and used as a positioning preference by its squads.
/datum/tactical_zone/proc/add_marker(kind, turf/position, direction = NORTH)
	if(!(kind in list("entrance", "choke")) || !isturf(position) || position.z != z || length(markers) >= 16)
		return null
	if(!(direction in GLOB.cardinals))
		return null
	var/on_boundary = contains(position)
	if(!on_boundary)
		for(var/turf/neighbor AS in RANGE_TURFS(1, position))
			if(contains(neighbor))
				on_boundary = TRUE
				break
	if(!on_boundary)
		return null
	for(var/datum/tactical_marker/existing AS in markers)
		if(existing.position == position && existing.kind == kind)
			existing.direction = direction
			plan?.touch()
			return existing
	var/datum/tactical_marker/marker = new
	marker.id = plan.next_id("marker")
	marker.kind = kind
	marker.position = position
	marker.direction = direction
	markers += marker
	plan?.touch()
	return marker

/datum/tactical_zone/proc/remove_marker(marker_id)
	for(var/datum/tactical_marker/marker AS in markers)
		if(marker.id != marker_id)
			continue
		markers -= marker
		qdel(marker)
		plan?.touch()
		return TRUE
	return FALSE

/datum/tactical_marker
	var/id
	var/kind
	var/turf/position
	var/direction = NORTH

/datum/tactical_marker/Destroy()
	position = null
	return ..()

/datum/tactical_route
	var/id
	var/name
	var/z
	var/list/waypoints = list()
	var/loop = TRUE

/datum/tactical_route/New(datum/tactical_plan/plan, new_name, list/new_waypoints, should_loop)
	. = ..()
	id = plan.next_id("route")
	name = new_name
	waypoints = new_waypoints.Copy()
	var/turf/first = waypoints[1]
	z = first.z
	loop = !!should_loop

/datum/tactical_route/Destroy()
	waypoints = null
	return ..()
