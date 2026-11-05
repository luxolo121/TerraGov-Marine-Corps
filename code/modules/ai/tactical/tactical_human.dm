/// Managed squads reuse the human controller's inventory, combat and movement clock,
/// but do not run its opportunistic escort/pursuit/task-selection policy.
/datum/ai_behavior/human
	var/datum/tactical_squad/tactical_squad
	var/tactical_status = "Holding"
	var/turf/tactical_destination
	var/list/tactical_path = list()
	var/tactical_path_pending = FALSE
	var/tactical_next_path = 0
	var/turf/tactical_last_position
	var/tactical_last_progress = 0
	var/list/tactical_blocked_tiles = list()
	var/tactical_next_support = 0

/datum/ai_behavior/human/proc/set_tactical_squad(datum/tactical_squad/new_squad, resume_legacy = TRUE)
	// Suppress inherited reacquisition while removing stale movement and escort targets.
	tactical_squad = new_squad || tactical_squad
	cleanup_current_action()
	deltimer(next_move_timer)
	next_move_timer = null
	SSadvanced_pathfinding.node_pathfinding_to_do -= src
	registered_for_node_pathfinding = FALSE
	reset_tactical_path()
	stop_fire()
	if(escorted_atom)
		do_unset_target(escorted_atom, FALSE, FALSE)
	if(atom_to_walk_to)
		do_unset_target(atom_to_walk_to, FALSE, FALSE)
	if(combat_target)
		do_unset_target(combat_target, FALSE, FALSE)
	if(interact_target)
		do_unset_target(interact_target, FALSE, FALSE)
	if(goal_node)
		UnregisterSignal(goal_node, COMSIG_QDELETING)
	goal_node = null
	goal_nodes = list()
	set_current_node(null)
	current_action = IDLE
	tactical_squad = new_squad
	tactical_destination = null
	tactical_last_position = get_turf(mob_parent)
	tactical_last_progress = world.time
	if(QDELETED(mob_parent))
		return
	mob_parent.a_intent = INTENT_HELP
	if(new_squad)
		tactical_status = "Forming up"
		prepare_move()
	else if(resume_legacy && !mob_parent.client && mob_parent.stat != DEAD)
		late_initialize()

/datum/ai_behavior/human/proc/reset_tactical_path()
	tactical_destination = null
	tactical_path.Cut()
	tactical_blocked_tiles.Cut()
	tactical_path_pending = FALSE
	tactical_next_path = 0
	SSadvanced_pathfinding.tile_pathfinding_to_do -= src
	tactical_last_progress = world.time

/datum/ai_behavior/human/proc/tactical_process()
	if(QDELETED(mob_parent) || mob_parent.client || mob_parent.stat == DEAD)
		tactical_squad.remove_member(mob_parent, FALSE)
		return
	if(mob_parent.faction != tactical_squad.faction)
		tactical_squad.remove_member(mob_parent)
		return
	mob_parent.a_intent = INTENT_HELP
	var/mob/living/carbon/human/human_parent = mob_parent
	if(human_parent.incapacitated() || human_parent.notransform)
		tactical_status = "Incapacitated"
		stop_fire()
		return
	if(human_parent.lying_angle)
		tactical_status = "Getting up"
		INVOKE_ASYNC(human_parent, TYPE_PROC_REF(/mob/living/carbon/human, get_up))
		return
	if(human_parent.buckled && !human_parent.buckled.ai_should_stay_buckled(human_parent))
		human_parent.buckled.unbuckle_mob(human_parent)
	var/turf/new_destination = tactical_squad.get_member_destination(human_parent)
	if(new_destination != tactical_destination)
		tactical_destination = new_destination
		tactical_path.Cut()
	if(!tactical_target_allowed(combat_target))
		if(combat_target)
			do_unset_target(combat_target, FALSE, FALSE)
		var/atom/visible_target = get_nearest_target(mob_parent, target_distance, TARGET_HOSTILE, mob_parent.faction, mob_parent.get_xeno_hivenumber(), TRUE)
		if(tactical_target_allowed(visible_target))
			set_combat_target(visible_target)
	if(should_hold())
		tactical_status = "Supporting / reloading"
		return
	if(human_ai_behavior_flags & HUMAN_AI_USE_WEAPONS)
		weapon_process()
		if(combat_target && get_dist(mob_parent, combat_target) <= 1)
			INVOKE_ASYNC(src, PROC_REF(melee_interact), null, combat_target)
	if(!tactical_destination)
		tactical_status = "No valid rally position"
		return
	if(mob_parent.z != tactical_destination.z)
		tactical_status = "Blocked: assignment is on another level"
		return
	var/distance = get_dist(mob_parent, tactical_destination)
	if(distance > 1 && world.time - tactical_last_progress >= 6 SECONDS)
		tactical_status = "Blocked: route obstructed; retrying"
	else if(combat_target)
		tactical_status = distance > 2 ? "Fighting while regrouping" : "Fighting from assigned position"
	else if(distance > 1)
		tactical_status = tactical_squad.order == "retreat" ? "Falling back" : "Rejoining formation"
	else
		tactical_status = tactical_squad.order == "retreat" ? "Holding fallback (awaiting orders)" : "Holding assigned position"
	if(!combat_target && distance <= 1 && tactical_squad.zone)
		var/member_index = tactical_squad.members.Find(mob_parent)
		if(member_index && member_index <= length(tactical_squad.zone.markers))
			var/datum/tactical_marker/marker = tactical_squad.zone.markers[member_index]
			mob_parent.setDir(marker.direction)
	if(!combat_target && distance <= 2 && world.time >= tactical_next_support)
		tactical_support()
	if(!next_move_timer)
		prepare_move()

/// A target may be shot, never used as a movement destination. No omniscient reacquisition.
/datum/ai_behavior/human/proc/tactical_target_allowed(atom/target)
	if(!tactical_squad || QDELETED(target) || !ismovable(target) || !mob_parent || mob_parent.client)
		return FALSE
	var/atom/movable/movable_target = target
	if(movable_target.faction == mob_parent.faction || target.z != mob_parent.z || get_dist(mob_parent, target) > target_distance)
		return FALSE
	if(isliving(target))
		var/mob/living/living_target = target
		if(living_target.stat == DEAD)
			return FALSE
	if(!line_of_sight(mob_parent, target, target_distance))
		return FALSE
	return TRUE

/// Signals may nominate nearby support work, but cannot dispatch members across the map.
/datum/ai_behavior/human/set_interact_target(atom/new_target)
	if(tactical_squad && !tactical_support_allowed(new_target))
		return FALSE
	return ..()

/datum/ai_behavior/human/proc/tactical_support_allowed(atom/target)
	if(QDELETED(target) || !mob_parent || mob_parent.client || combat_target || !tactical_destination)
		return FALSE
	if(tactical_squad.order == "retreat" && get_dist(mob_parent, tactical_destination) > 1)
		return FALSE
	if(target.z != mob_parent.z || get_dist(mob_parent, target) > 1 || get_dist(mob_parent, tactical_destination) > 2 || !mob_parent.CanReach(target))
		return FALSE
	if((tactical_squad.order == "guard" || tactical_squad.order == "retreat") && !tactical_squad.zone?.contains(target))
		return FALSE
	return TRUE

/// Adjacent medical/engineering work is bounded by the assignment, never a competing destination.
/datum/ai_behavior/human/proc/tactical_support()
	tactical_next_support = world.time + 3 SECONDS
	if(!check_hazards())
		return
	if((human_ai_behavior_flags & HUMAN_AI_SELF_HEAL) && mob_parent.health < mob_parent.maxHealth * 0.7)
		INVOKE_ASYNC(src, PROC_REF(try_heal))
		return
	if(interact_target)
		var/atom/target = interact_target
		do_unset_target(target, FALSE, FALSE)
		if(tactical_support_allowed(target))
			try_interact(target)
			return
	if(medical_rating >= AI_MED_MEDIC)
		for(var/mob/living/carbon/human/patient AS in heal_list)
			if(!tactical_support_allowed(patient))
				continue
			INVOKE_ASYNC(src, PROC_REF(try_heal_other), patient)
			return
	if(engineer_rating >= AI_ENGIE_STANDARD)
		for(var/atom/project AS in engineering_list)
			if(!tactical_support_allowed(project))
				continue
			try_interact(project)
			return

/datum/ai_behavior/human/proc/tactical_move()
	if(!tactical_squad || QDELETED(mob_parent) || mob_parent.client || mob_parent.incapacitated() || !mob_parent.canmove || mob_parent.notransform || should_hold() || world.time < next_move_time)
		return
	var/turf/current = get_turf(mob_parent)
	if(current != tactical_last_position)
		tactical_last_progress = world.time
		tactical_last_position = current
	if(!tactical_destination || tactical_destination.z != current.z)
		return
	// Get off an immediate hazard without violating the assigned boundary.
	if(!check_hazards())
		var/best_hazard_score = tactical_hazard_score(current)
		var/best_direction
		for(var/direction in GLOB.alldirs)
			var/turf/escape = get_step(current, direction)
			if(!tactical_step_allowed(current, escape) || tactical_occupied(escape))
				continue
			var/score = tactical_hazard_score(escape)
			if(score >= best_hazard_score)
				continue
			best_hazard_score = score
			best_direction = direction
		if(best_direction)
			mob_parent.next_move_slowdown = 0
			ai_complete_move(best_direction, FALSE)
			tactical_path.Cut()
			return
	if(current == tactical_destination)
		return
	if(length(tactical_path))
		var/turf/next_tile = tactical_path[length(tactical_path)]
		if(next_tile == current)
			tactical_path.len--
			if(!length(tactical_path))
				return
			next_tile = tactical_path[length(tactical_path)]
		if(get_dist(current, next_tile) > 1 || !tactical_step_allowed(current, next_tile))
			tactical_path.Cut()
		else if(tactical_occupied(next_tile))
			// Never shove a player or push another squad member out of their slot.
			if(world.time - tactical_last_progress >= 2 SECONDS)
				tactical_blocked_tiles[next_tile] = world.time + 3 SECONDS
				tactical_path.Cut()
		else
			// ai_complete_move adds this step's diagonal delay; do not carry old steps forward.
			mob_parent.next_move_slowdown = 0
			ai_complete_move(get_dir(current, next_tile), FALSE)
			if(world.time - tactical_last_progress >= 3 SECONDS)
				tactical_blocked_tiles[next_tile] = world.time + 5 SECONDS
				tactical_path.Cut()
	if(!length(tactical_path) && !tactical_path_pending && world.time >= tactical_next_path)
		tactical_path_pending = TRUE
		tactical_next_path = world.time + 2 SECONDS
		SSadvanced_pathfinding.tile_pathfinding_to_do |= src

/datum/ai_behavior/human/proc/tactical_occupied(turf/tile)
	for(var/mob/living/occupant in tile)
		if(occupant != mob_parent && occupant.density && !occupant.lying_angle)
			return TRUE
	return FALSE

/datum/ai_behavior/human/proc/tactical_hazard_score(turf/tile)
	var/score = 0
	for(var/atom/hazard AS in hazard_list)
		if(QDELETED(hazard) || hazard.z != tile.z || !isturf(hazard.loc))
			continue
		score += max(0, hazard_list[hazard] + 1 - get_dist(tile, hazard))
	return score

/datum/ai_behavior/human/proc/tactical_step_allowed(turf/origin, turf/destination)
	if(!tactical_squad?.allows_step(origin, destination) || !tactical_walkable_turf(destination))
		return FALSE
	var/direction = get_dir(origin, destination)
	if(ISDIAGONALDIR(direction))
		var/turf/vertical = get_step(origin, direction & (NORTH|SOUTH))
		var/turf/horizontal = get_step(origin, direction & (EAST|WEST))
		if(!tactical_squad.allows_step(origin, vertical) || !tactical_squad.allows_step(origin, horizontal) || !tactical_walkable_turf(vertical) || !tactical_walkable_turf(horizontal))
			return FALSE
	return TRUE

/// Final gate also covers the inherited obstacle handler's asynchronous jump move.
/datum/ai_behavior/human/ai_complete_move(move_dir, try_sidestep = TRUE)
	if(QDELETED(mob_parent) || mob_parent.client || mob_parent.stat == DEAD)
		return
	if(tactical_squad)
		var/turf/next_tile = get_step(mob_parent, move_dir)
		if(!tactical_step_allowed(get_turf(mob_parent), next_tile) || tactical_occupied(next_tile))
			return
		mob_parent.a_intent = INTENT_HELP
		return ..(move_dir, FALSE)
	return ..()

/// Uses the existing advanced-pathfinding work queue; paths are bounded A* over allowed edges.
/datum/ai_behavior/human/look_for_tile_path()
	if(!tactical_squad)
		return ..()
	tactical_path_pending = FALSE
	tactical_path = build_tactical_path(get_turf(mob_parent), tactical_destination)

/datum/ai_behavior/human/proc/build_tactical_path(turf/start, turf/goal)
	var/list/result = list()
	if(!start || !goal || start == goal || start.z != goal.z || !tactical_squad || mob_parent.client)
		return result
	var/list/open = list(start)
	var/list/closed = list()
	var/list/costs = list()
	var/list/previous = list()
	costs[start] = 0
	var/iterations = 0
	while(length(open) && iterations++ < 600)
		var/turf/current
		var/best_score = INFINITY
		for(var/turf/option AS in open)
			var/score = costs[option] + get_dist(option, goal) * 10
			if(score >= best_score)
				continue
			current = option
			best_score = score
		if(current == goal)
			while(current != start)
				result += current
				current = previous[current]
			return result
		open -= current
		closed[current] = TRUE
		for(var/direction in GLOB.alldirs)
			var/turf/neighbor = get_step(current, direction)
			if(!neighbor || closed[neighbor] || tactical_blocked_tiles[neighbor] > world.time || !tactical_step_allowed(current, neighbor))
				continue
			var/new_cost = costs[current] + (ISDIAGONALDIR(direction) ? 14 : 10) + tactical_hazard_score(neighbor) * 30
			if(!isnull(costs[neighbor]) && new_cost >= costs[neighbor])
				continue
			costs[neighbor] = new_cost
			previous[neighbor] = current
			open |= neighbor
	return result

/obj/structure/barricade/folding
	/// Only raised defences opened by a managed squad are restored automatically.
	var/datum/tactical_barricade_passage/tactical_passage

/// Restores the original raised state after a squad has cleared a folding defence.
/// Linked groups are treated together; a pre-existing opening is never closed by this service.
/datum/tactical_barricade_passage
	var/list/barricades = list()
	var/restore_after
	var/can_restore = TRUE

/datum/tactical_barricade_passage/New(obj/structure/barricade/folding/first)
	. = ..()
	var/list/pending = list(first)
	while(length(pending) && length(barricades) < 128)
		var/obj/structure/barricade/folding/current = pending[1]
		pending.Cut(1, 2)
		if(current in barricades)
			continue
		barricades += current
		if(current.barricade_flags & BARRICADE_OPEN)
			can_restore = FALSE
		if(!current.linked || !current.linkable)
			continue
		for(var/direction in LeftAndRightOfDir(current.dir))
			for(var/obj/structure/barricade/folding/neighbor in get_step(current, direction))
				if(neighbor.dir == current.dir && neighbor.linked && !(neighbor in barricades))
					pending |= neighbor
	if(length(pending))
		can_restore = FALSE
	if(!can_restore)
		qdel(src)
		return
	for(var/obj/structure/barricade/folding/barricade AS in barricades)
		barricade.tactical_passage = src
	restore_after = world.time + 4 SECONDS
	START_PROCESSING(SSprocessing, src)

/datum/tactical_barricade_passage/process()
	if(world.time < restore_after)
		return
	for(var/obj/structure/barricade/folding/barricade AS in barricades.Copy())
		if(QDELETED(barricade))
			barricades -= barricade
			continue
		// Do not raise underneath a person, or into a squad still passing this aperture.
		for(var/mob/living/person in range(1, barricade))
			if(person.stat != DEAD)
				return
	for(var/obj/structure/barricade/folding/barricade AS in barricades)
		if(barricade.barricade_flags & BARRICADE_OPEN)
			barricade.toggle_open(FALSE)
	qdel(src)

/datum/tactical_barricade_passage/Destroy()
	STOP_PROCESSING(SSprocessing, src)
	for(var/obj/structure/barricade/folding/barricade AS in barricades)
		if(!QDELETED(barricade) && barricade.tactical_passage == src)
			barricade.tactical_passage = null
	barricades = null
	return ..()
