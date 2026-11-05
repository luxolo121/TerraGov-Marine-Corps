/// Persistent player-authored orders. Combat is deliberately not an order.
/datum/tactical_squad
	var/id
	var/name
	var/datum/tactical_plan/plan
	var/faction
	var/list/members = list()
	var/order = "hold"
	var/datum/tactical_zone/zone
	var/datum/tactical_route/route
	var/datum/tactical_zone/fallback_zone
	var/mob/living/follow_target
	var/turf/hold_position
	var/waypoint_index = 1
	var/waypoint_direction = 1
	var/status = "Awaiting recruits"
	/// Stable, exclusive formation destinations, refreshed only when the anchor changes.
	var/list/formation_slots = list()
	var/turf/formation_anchor
	var/next_formation_update = 0
	var/last_patrol_update = -1
	var/patrol_ready_since = -1

/datum/tactical_squad/New(datum/tactical_plan/new_plan, new_name)
	. = ..()
	if(!istype(new_plan) || length(new_plan.squads) >= 16)
		qdel(src)
		return
	plan = new_plan
	faction = plan.faction
	id = plan.next_id("squad")
	name = tactical_label(new_name, "Team [length(plan.squads) + 1]")
	plan.squads += src
	plan.touch()

/datum/tactical_squad/Destroy()
	for(var/mob/living/carbon/human/member AS in members.Copy())
		remove_member(member)
	plan?.squads -= src
	plan?.touch()
	plan = null
	zone = null
	route = null
	fallback_zone = null
	follow_target = null
	hold_position = null
	formation_anchor = null
	formation_slots = null
	return ..()

/datum/tactical_squad/proc/can_accept_member(mob/living/carbon/human/member)
	if(!ishuman(member) || QDELETED(member) || member.client || member.stat == DEAD || member.faction != faction)
		return FALSE
	var/datum/component/ai_controller/controller = member.GetComponent(/datum/component/ai_controller)
	return istype(controller?.ai_behavior, /datum/ai_behavior/human)

/datum/tactical_squad/proc/add_member(mob/living/carbon/human/member, transfer = FALSE)
	if(!can_accept_member(member) || length(members) >= 24)
		return FALSE
	var/datum/component/ai_controller/controller = member.GetComponent(/datum/component/ai_controller)
	var/datum/ai_behavior/human/brain = controller.ai_behavior
	if(brain.tactical_squad == src)
		return TRUE
	if(brain.tactical_squad)
		if(!transfer)
			return FALSE
		brain.tactical_squad.remove_member(member, FALSE)
	members += member
	RegisterSignals(member, list(COMSIG_QDELETING, COMSIG_MOB_LOGIN, COMSIG_MOB_DEATH), PROC_REF(member_unavailable))
	if(!hold_position)
		hold_position = get_turf(member)
	brain.set_tactical_squad(src)
	formation_slots.Cut()
	status = "Forming up"
	plan.touch()
	return TRUE

/datum/tactical_squad/proc/remove_member(mob/living/carbon/human/member, resume_legacy = TRUE)
	if(!(member in members))
		return FALSE
	UnregisterSignal(member, list(COMSIG_QDELETING, COMSIG_MOB_LOGIN, COMSIG_MOB_DEATH))
	members -= member
	formation_slots -= member
	var/datum/component/ai_controller/controller = member.GetComponent(/datum/component/ai_controller)
	var/datum/ai_behavior/human/brain = controller?.ai_behavior
	if(istype(brain) && brain.tactical_squad == src)
		brain.set_tactical_squad(null, resume_legacy)
	formation_slots.Cut()
	if(!length(members))
		status = "No active members"
	plan?.touch()
	return TRUE

/datum/tactical_squad/proc/member_unavailable(mob/living/carbon/human/member)
	SIGNAL_HANDLER
	remove_member(member, FALSE)

/datum/tactical_squad/proc/set_fallback(datum/tactical_zone/new_fallback)
	if(new_fallback && !(new_fallback in plan.zones))
		return FALSE
	fallback_zone = new_fallback
	plan.touch()
	return TRUE

/datum/tactical_squad/proc/issue_order(new_order, datum/tactical_zone/zone = null, datum/tactical_route/route = null, mob/follow_target = null, turf/position = null)
	if(!(new_order in list("hold", "follow", "guard", "patrol", "retreat")))
		return FALSE
	if(zone && !(zone in plan.zones))
		return FALSE
	if(route && !(route in plan.routes))
		return FALSE
	switch(new_order)
		if("guard")
			if(!zone)
				return FALSE
		if("retreat")
			zone = zone || fallback_zone
			if(!zone)
				return FALSE
		if("patrol")
			if(!route || !length(route.waypoints))
				return FALSE
		if("follow")
			if(!isliving(follow_target) || QDELETED(follow_target) || follow_target.stat == DEAD || follow_target.faction != faction || (follow_target in members))
				return FALSE
		if("hold")
			position = position || get_anchor() || hold_position
			if(!isturf(position) || position.density || (position.atom_flags & AI_BLOCKED))
				return FALSE
	order = new_order
	src.zone = (order == "guard" || order == "retreat") ? zone : null
	src.route = order == "patrol" ? route : null
	src.follow_target = order == "follow" ? follow_target : null
	if(position)
		hold_position = position
	if(order == "follow")
		hold_position = get_turf(follow_target)
	waypoint_index = 1
	waypoint_direction = 1
	patrol_ready_since = -1
	formation_slots.Cut()
	formation_anchor = null
	next_formation_update = 0
	status = "[capitalize(order)] assigned"
	for(var/mob/living/carbon/human/member AS in members)
		var/datum/component/ai_controller/controller = member.GetComponent(/datum/component/ai_controller)
		var/datum/ai_behavior/human/brain = controller?.ai_behavior
		brain?.reset_tactical_path()
	plan.touch()
	return TRUE

/// A missing/dead leader leaves a persistent follow order at the last known rally point.
/datum/tactical_squad/proc/get_anchor()
	switch(order)
		if("guard", "retreat")
			return zone?.center
		if("follow")
			if(!QDELETED(follow_target) && follow_target.stat != DEAD && follow_target.faction == faction)
				hold_position = get_turf(follow_target)
			else
				follow_target = null
				status = "Leader unavailable; holding last position"
			return hold_position
		if("patrol")
			if(route && length(route.waypoints))
				return route.waypoints[clamp(waypoint_index, 1, length(route.waypoints))]
	return hold_position

/// No waypoint advance until the whole mobile squad has regrouped. A blocked member is reported, not abandoned.
/datum/tactical_squad/proc/update_patrol()
	if(order != "patrol" || last_patrol_update == world.time || !length(members))
		return
	last_patrol_update = world.time
	var/turf/anchor = get_anchor()
	if(!anchor)
		return
	for(var/mob/living/carbon/human/member AS in members)
		if(member.stat == DEAD || member.client)
			continue
		if(member.z != anchor.z || get_dist(member, anchor) > 5)
			status = "Regrouping at waypoint [waypoint_index]"
			patrol_ready_since = -1
			return
	var/mob/living/carbon/human/point_member = members[1]
	if(get_turf(point_member) != anchor)
		patrol_ready_since = -1
		return
	if(patrol_ready_since < 0)
		patrol_ready_since = world.time
		return
	if(world.time - patrol_ready_since < 2 SECONDS)
		return
	patrol_ready_since = -1
	if(length(route.waypoints) > 1)
		waypoint_index += waypoint_direction
		if(waypoint_index > length(route.waypoints) || waypoint_index < 1)
			if(route.loop)
				waypoint_index = 1
			else
				waypoint_direction *= -1
				waypoint_index = clamp(waypoint_index + 2 * waypoint_direction, 1, length(route.waypoints))
		formation_slots.Cut()
	status = "Patrolling waypoint [waypoint_index]"

/datum/tactical_squad/proc/get_member_status(mob/living/carbon/human/member)
	if(!(member in members))
		return "Not assigned"
	if(member.client)
		return "Player controlled"
	if(member.stat == DEAD)
		return "Dead"
	var/datum/component/ai_controller/controller = member.GetComponent(/datum/component/ai_controller)
	var/datum/ai_behavior/human/brain = controller?.ai_behavior
	return brain?.tactical_status || "Unavailable"

/// Guard boundaries are checked for every edge, including sidesteps and obstacle jumps.
/datum/tactical_squad/proc/allows_step(turf/origin, turf/destination)
	if(!origin || !destination || origin.z != destination.z)
		return FALSE
	if((order == "guard" || order == "retreat") && zone?.contains(origin) && !zone.contains(destination))
		return FALSE
	return TRUE

/datum/tactical_squad/proc/get_member_destination(mob/living/carbon/human/member)
	update_patrol()
	var/turf/anchor = get_anchor()
	if(!anchor)
		return
	if(anchor != formation_anchor || !formation_slots[member] || world.time >= next_formation_update)
		refresh_formation(anchor)
	return formation_slots[member] || anchor

/// Two-tile spacing where room permits, unique nearby slots in cramped rooms, medics towards the rear.
/datum/tactical_squad/proc/refresh_formation(turf/anchor)
	formation_anchor = anchor
	next_formation_update = world.time + 3 SECONDS
	formation_slots.Cut()
	var/list/candidates = list()
	if((order == "guard" || order == "retreat") && zone)
		candidates = zone.turfs.Copy()
	else
		candidates = RANGE_TURFS(6, anchor)
	var/list/claimed = list()
	var/index = 0
	for(var/mob/living/carbon/human/member AS in members)
		index++
		var/column = ((index - 1) % 3) - 1
		var/row = round((index - 1) / 3) + 1
		var/datum/component/ai_controller/controller = member.GetComponent(/datum/component/ai_controller)
		var/datum/ai_behavior/human/brain = controller?.ai_behavior
		if(istype(brain) && brain.medical_rating >= AI_MED_MEDIC)
			row += 2
		var/facing = follow_target?.dir || NORTH
		var/turf/desired = anchor
		if(order == "follow")
			for(var/step in 1 to row)
				desired = get_step(desired, REVERSE_DIR(facing)) || desired
			for(var/step in 1 to abs(column) * 2)
				desired = get_step(desired, turn(facing, column < 0 ? 90 : -90)) || desired
		else if(order == "patrol" && index == 1)
			desired = anchor
		else if(zone && index <= length(zone.markers))
			var/datum/tactical_marker/marker = zone.markers[index]
			desired = zone.nearest_turf(marker.position) || anchor
		else
			desired = locate(anchor.x + column * 2, anchor.y + (row - 2) * 2, anchor.z) || anchor
		var/turf/best
		var/best_score = INFINITY
		for(var/turf/candidate AS in candidates)
			if(candidate in claimed)
				continue
			if(!tactical_walkable_turf(candidate) || candidate == get_turf(follow_target))
				continue
			var/occupied = FALSE
			for(var/mob/living/occupant in candidate)
				if(occupant.client || occupant.faction != faction || (occupant.density && !occupant.lying_angle && !(occupant in members)))
					occupied = TRUE
					break
			if(occupied)
				continue
			var/score = get_dist(candidate, desired) * 10 + get_dist(candidate, anchor)
			for(var/turf/reserved AS in claimed)
				if(get_dist(candidate, reserved) < 2)
					score += 25
			if(score >= best_score)
				continue
			best = candidate
			best_score = score
		if(best)
			formation_slots[member] = best
			claimed += best

/// Cheap static tile test; doors/cades are handled by the existing movement obstacle service.
/proc/tactical_walkable_turf(turf/tile)
	if(!tile || tile.density || isspaceturf(tile) || (tile.atom_flags & AI_BLOCKED) || !can_cross_lava_turf(tile))
		return FALSE
	for(var/obj/blocker in tile)
		if(!blocker.density || (blocker.atom_flags & ON_BORDER))
			continue
		if(istype(blocker, /obj/machinery/door) || istype(blocker, /obj/structure/barricade))
			continue
		return FALSE
	return TRUE
