/// Recruitment is explicit, faction bounded, and cannot silently steal another squad's NPC.
/datum/unit_test/tactical_squad_recruitment/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/datum/tactical_squad/alpha = new(plan, "Alpha")
	var/datum/tactical_squad/bravo = new(plan, "Bravo")
	var/mob/living/carbon/human/member = allocate(/mob/living/carbon/human)
	member.faction = FACTION_TERRAGOV
	TEST_ASSERT(!alpha.add_member(member), "A human without an existing AI must not be recruited")
	var/datum/component/ai_controller/controller = member.AddComponent(/datum/component/ai_controller, /datum/ai_behavior/human)
	var/datum/ai_behavior/human/brain = controller.ai_behavior
	TEST_ASSERT(alpha.add_member(member), "An existing allied human AI should be recruitable")
	TEST_ASSERT_EQUAL(brain.tactical_squad, alpha, "Recruitment must opt the existing behavior into tactical policy")
	TEST_ASSERT(!bravo.add_member(member), "Recruitment must not silently transfer another squad member")
	TEST_ASSERT(bravo.add_member(member, TRUE), "Explicit transfer must be supported")
	TEST_ASSERT_EQUAL(length(alpha.members), 0, "Transfer must remove the previous roster entry")
	TEST_ASSERT_EQUAL(brain.tactical_squad, bravo, "Transfer must install the destination squad")
	member.faction = FACTION_SOM
	TEST_ASSERT(!alpha.add_member(member, TRUE), "Cross-faction transfers must be rejected")

/// Login/death signals remove ownership and stop outstanding movement, rather than moving a player.
/datum/unit_test/tactical_squad_takeover/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/datum/tactical_squad/squad = new(plan, "Alpha")
	var/mob/living/carbon/human/member = allocate(/mob/living/carbon/human)
	member.faction = FACTION_TERRAGOV
	var/datum/component/ai_controller/controller = member.AddComponent(/datum/component/ai_controller, /datum/ai_behavior/human)
	var/datum/ai_behavior/human/brain = controller.ai_behavior
	TEST_ASSERT(squad.add_member(member), "Recruitment fixture failed")
	// Exercise the two registered takeover handlers, not unrelated login UI subscribers
	// that require a real connected client (personal crafting, preferences, HUDs).
	controller.clean_up()
	squad.member_unavailable(member)
	TEST_ASSERT_NULL(brain.tactical_squad, "Player takeover must immediately relinquish tactical ownership")
	TEST_ASSERT_EQUAL(length(squad.members), 0, "Player takeover must remove the NPC roster entry")
	TEST_ASSERT_NULL(brain.next_move_timer, "Player takeover must cancel queued tactical movement")
	TEST_ASSERT_EQUAL(length(brain.tactical_path), 0, "Player takeover must discard pending movement paths")

/// A concave zone is a path boundary, not merely a test of the final destination.
/datum/unit_test/tactical_guard_path_boundary/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/turf/start = run_loc_floor_bottom_left
	var/turf/goal = locate(start.x + 2, start.y, start.z)
	var/list/footprint = list(start, get_step(start, NORTH), locate(start.x, start.y + 2, start.z), locate(start.x + 1, start.y + 2, start.z), locate(start.x + 2, start.y + 2, start.z), get_step(goal, NORTH), goal)
	var/datum/tactical_zone/zone = plan.create_zone("U-shaped perimeter", footprint)
	var/datum/tactical_squad/squad = new(plan, "Guard")
	var/mob/living/carbon/human/member = allocate(/mob/living/carbon/human, start)
	member.faction = FACTION_TERRAGOV
	var/datum/component/ai_controller/controller = member.AddComponent(/datum/component/ai_controller, /datum/ai_behavior/human)
	var/datum/ai_behavior/human/brain = controller.ai_behavior
	squad.add_member(member)
	TEST_ASSERT(squad.issue_order("guard", zone), "Guard fixture must accept its own plan's zone")
	var/list/path = brain.build_tactical_path(start, goal)
	TEST_ASSERT_EQUAL(length(path), 6, "Guard must walk around a concave perimeter, not cut across unassigned space")
	for(var/turf/step AS in path)
		TEST_ASSERT(zone.contains(step), "Every path tile, not only its endpoint, must be inside the guard zone")
	TEST_ASSERT(!squad.allows_step(start, get_step(start, EAST)), "An actual move across the guard boundary must be rejected")
	TEST_ASSERT(!brain.tactical_step_allowed(start, locate(start.x + 1, start.y + 1, start.z)), "Diagonal movement cannot cut an unassigned corner")

/// Combat reacquisition and legacy state initialization cannot replace a deliberate fallback.
/datum/unit_test/tactical_persistent_orders/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/turf/start = run_loc_floor_bottom_left
	var/datum/tactical_zone/fallback = plan.create_rectangle("Aid station", start, locate(start.x + 2, start.y + 2, start.z), "fallback")
	var/datum/tactical_squad/squad = new(plan, "Alpha")
	var/mob/living/carbon/human/member = allocate(/mob/living/carbon/human)
	member.faction = FACTION_TERRAGOV
	var/datum/component/ai_controller/controller = member.AddComponent(/datum/component/ai_controller, /datum/ai_behavior/human)
	var/datum/ai_behavior/human/brain = controller.ai_behavior
	squad.add_member(member)
	TEST_ASSERT(!squad.issue_order("retreat"), "Retreat without a fallback must fail, not invent a destination")
	TEST_ASSERT(squad.set_fallback(fallback), "Saved fallback must be accepted")
	TEST_ASSERT(squad.issue_order("retreat"), "Manual fallback must be assignable")
	brain.look_for_new_state()
	brain.late_initialize()
	TEST_ASSERT_EQUAL(squad.order, "retreat", "Retreat remains until an explicit replacement order")
	TEST_ASSERT_EQUAL(squad.zone, fallback, "Retreat must keep the actual squad fallback geometry")
	TEST_ASSERT(!brain.change_action(MOVING_TO_SAFETY, start), "Legacy reactive movement must not replace squad orders")
	TEST_ASSERT_EQUAL(squad.order, "retreat", "A rejected inherited state change must not clear fallback")
	var/datum/tactical_plan/foreign_plan = allocate(/datum/tactical_plan, FACTION_SOM)
	var/datum/tactical_zone/foreign_zone = foreign_plan.create_zone("Foreign", list(start))
	TEST_ASSERT(!squad.issue_order("guard", foreign_zone), "A foreign plan's geometry must not be accepted")
	TEST_ASSERT_EQUAL(squad.order, "retreat", "Invalid assignments must leave the previous order intact")

/// Adjacent waypoints still require exact arrival and a dwell; a five-tile proximity bubble is not arrival.
/datum/unit_test/tactical_patrol_arrival/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/turf/start = run_loc_floor_bottom_left
	var/turf/end = locate(start.x + 2, start.y, start.z)
	var/datum/tactical_route/route = plan.create_route("Short patrol", list(start, end), FALSE)
	var/datum/tactical_squad/squad = new(plan, "Alpha")
	var/mob/living/carbon/human/member = allocate(/mob/living/carbon/human, get_step(start, EAST))
	member.faction = FACTION_TERRAGOV
	member.AddComponent(/datum/component/ai_controller, /datum/ai_behavior/human)
	squad.add_member(member)
	squad.issue_order("patrol", route = route)
	squad.update_patrol()
	TEST_ASSERT_EQUAL(squad.waypoint_index, 1, "Being near both short-route waypoints must not advance the route")
	member.forceMove(start)
	squad.last_patrol_update = -1
	squad.update_patrol()
	TEST_ASSERT_EQUAL(squad.waypoint_index, 1, "Arrival must begin a dwell rather than immediately cycling the route")
	TEST_ASSERT_EQUAL(squad.patrol_ready_since, world.time, "Patrol arrival must record its dwell start")
	squad.waypoint_index = 2
	squad.last_patrol_update = -1
	squad.update_patrol()
	TEST_ASSERT_EQUAL(squad.waypoint_index, 2, "The next nearby waypoint still requires real movement to reach it")
	TEST_ASSERT_EQUAL(squad.patrol_ready_since, -1, "Moving to another waypoint must clear the previous arrival dwell")

/// Formation slots must be distinct; support work cannot escape those assignments.
/datum/unit_test/tactical_formation_and_support/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/turf/start = run_loc_floor_bottom_left
	var/datum/tactical_zone/zone = plan.create_rectangle("Guard", start, locate(start.x + 4, start.y + 4, start.z))
	var/datum/tactical_squad/squad = new(plan, "Alpha")
	var/list/assigned = list()
	for(var/index in 1 to 3)
		var/mob/living/carbon/human/member = allocate(/mob/living/carbon/human, start)
		member.faction = FACTION_TERRAGOV
		member.AddComponent(/datum/component/ai_controller, /datum/ai_behavior/human)
		squad.add_member(member)
	squad.issue_order("guard", zone)
	squad.refresh_formation(zone.center)
	for(var/mob/living/carbon/human/member AS in squad.members)
		var/turf/slot = squad.formation_slots[member]
		TEST_ASSERT(slot && zone.contains(slot), "Each member must receive an actual in-zone formation slot")
		TEST_ASSERT(!(slot in assigned), "Squad members must not all converge on one tile")
		assigned += slot
		var/datum/component/ai_controller/controller = member.GetComponent(/datum/component/ai_controller)
		var/datum/ai_behavior/human/brain = controller.ai_behavior
		brain.tactical_destination = slot
		TEST_ASSERT(!brain.tactical_support_allowed(locate(start.x + 8, start.y, start.z)), "Distant medical/engineering tasks must not pull members out of formation")

/// Visible hostiles do not turn a follow assignment into pursuit, even during real target acquisition.
/datum/unit_test/tactical_follow_during_combat/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/turf/start = run_loc_floor_bottom_left
	var/mob/living/carbon/human/member = allocate(/mob/living/carbon/human, start)
	var/mob/living/carbon/human/leader = allocate(/mob/living/carbon/human, locate(start.x + 4, start.y, start.z))
	var/mob/living/carbon/human/hostile = allocate(/mob/living/carbon/human, locate(start.x, start.y + 4, start.z))
	member.faction = FACTION_TERRAGOV
	leader.faction = FACTION_TERRAGOV
	leader.setDir(NORTH)
	hostile.faction = FACTION_SOM
	var/datum/component/ai_controller/controller = member.AddComponent(/datum/component/ai_controller, /datum/ai_behavior/human)
	var/datum/ai_behavior/human/brain = controller.ai_behavior
	var/datum/tactical_squad/squad = new(plan, "Escort")
	squad.add_member(member)
	TEST_ASSERT(squad.issue_order("follow", follow_target = leader), "Follow fixture must accept the friendly leader")
	TEST_ASSERT(brain.set_combat_target(hostile), "The hostile must be a real visible combat contact")
	brain.tactical_process()
	TEST_ASSERT_EQUAL(brain.combat_target, hostile, "Managed AI must retain the visible hostile as a firing target")
	TEST_ASSERT_EQUAL(squad.order, "follow", "Combat acquisition must not replace the persistent follow assignment")
	TEST_ASSERT_EQUAL(squad.follow_target, leader, "A visible hostile must not replace the ordered leader")
	TEST_ASSERT(brain.tactical_destination != get_turf(hostile), "The combat target must never become the movement destination")
	TEST_ASSERT_EQUAL(brain.tactical_destination, squad.formation_slots[member], "Combat movement must still use the member's formation slot")
	var/list/path = brain.build_tactical_path(get_turf(member), brain.tactical_destination)
	TEST_ASSERT(length(path), "The escort should retain an actual path back to formation during combat")
	TEST_ASSERT_EQUAL(path[1], brain.tactical_destination, "The path endpoint must remain formation, not the hostile")
	brain.look_for_new_state(hostile)
	TEST_ASSERT_EQUAL(brain.current_action, IDLE, "Inherited pursuit state must remain suppressed")

/// Real diagonal steps must not permanently accumulate a movement penalty.
/datum/unit_test/tactical_movement_clock/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/datum/tactical_squad/squad = new(plan, "March")
	var/turf/start = run_loc_floor_bottom_left
	var/mob/living/carbon/human/member = allocate(/mob/living/carbon/human, start)
	member.faction = FACTION_TERRAGOV
	var/datum/component/ai_controller/controller = member.AddComponent(/datum/component/ai_controller, /datum/ai_behavior/human)
	var/datum/ai_behavior/human/brain = controller.ai_behavior
	squad.add_member(member)
	var/diagonal_delay
	for(var/direction in list(NORTHEAST, NORTHEAST, EAST))
		var/turf/destination = get_step(member, direction)
		brain.tactical_destination = destination
		brain.tactical_path = list(destination)
		brain.next_move_time = 0
		brain.tactical_move()
		TEST_ASSERT_EQUAL(get_turf(member), destination, "The clock regression must exercise an actual successful movement")
		if(ISDIAGONALDIR(direction))
			if(isnull(diagonal_delay))
				diagonal_delay = member.next_move_slowdown
			TEST_ASSERT_EQUAL(member.next_move_slowdown, diagonal_delay, "Consecutive diagonal moves must have equal per-step slowdown")
		else
			TEST_ASSERT_EQUAL(member.next_move_slowdown, 0, "A straight move must not inherit earlier diagonal slowdown")

/// Separate squads sharing a room must leave parked allies' formation slots available to their owners.
/datum/unit_test/tactical_cross_squad_formation/Run()
	var/datum/tactical_plan/plan = allocate(/datum/tactical_plan, FACTION_TERRAGOV)
	var/turf/start = run_loc_floor_bottom_left
	var/datum/tactical_zone/zone = plan.create_rectangle("Shared guard room", start, locate(start.x + 4, start.y + 4, start.z))
	var/datum/tactical_squad/alpha = new(plan, "Alpha")
	var/datum/tactical_squad/bravo = new(plan, "Bravo")
	var/list/parked = list()
	for(var/datum/tactical_squad/squad AS in list(alpha, bravo))
		for(var/index in 1 to 2)
			var/mob/living/carbon/human/member = allocate(/mob/living/carbon/human, start)
			member.faction = FACTION_TERRAGOV
			member.AddComponent(/datum/component/ai_controller, /datum/ai_behavior/human)
			squad.add_member(member)
		TEST_ASSERT(squad.issue_order("guard", zone), "Both squads must accept the shared zone")
		squad.refresh_formation(zone.center)
		for(var/mob/living/carbon/human/member AS in squad.members)
			var/turf/slot = squad.formation_slots[member]
			TEST_ASSERT(slot && zone.contains(slot), "Every member must receive a usable in-zone destination")
			TEST_ASSERT(!(slot in parked), "A later squad must not choose a standing ally's occupied formation slot")
			member.forceMove(slot)
			parked += slot
	bravo.refresh_formation(zone.center)
	for(var/mob/living/carbon/human/member AS in bravo.members)
		TEST_ASSERT_EQUAL(bravo.formation_slots[member], get_turf(member), "Own squad reservations must remain stable on refresh")

/// A temporarily opened defence is restored only once living traffic has cleared it.
/datum/unit_test/tactical_barricade_restoration/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/obj/structure/barricade/folding/barricade = allocate(/obj/structure/barricade/folding, start)
	var/mob/living/carbon/human/member = allocate(/mob/living/carbon/human, start)
	var/datum/tactical_barricade_passage/passage = new(barricade)
	TEST_ASSERT_EQUAL(barricade.tactical_passage, passage, "An initially raised defence should be tracked")
	barricade.toggle_open(TRUE)
	passage.restore_after = world.time
	passage.process()
	TEST_ASSERT(barricade.barricade_flags & BARRICADE_OPEN, "Restoration must not raise a barricade underneath a person")
	member.forceMove(locate(start.x + 4, start.y + 4, start.z))
	passage.process()
	TEST_ASSERT(!(barricade.barricade_flags & BARRICADE_OPEN), "A clear aperture must be restored to its original raised state")
	TEST_ASSERT_NULL(barricade.tactical_passage, "Completed restoration must release the tracked object")
	barricade.toggle_open(TRUE)
	new /datum/tactical_barricade_passage(barricade)
	TEST_ASSERT_NULL(barricade.tactical_passage, "A pre-existing opening must never be claimed for automatic closure")
