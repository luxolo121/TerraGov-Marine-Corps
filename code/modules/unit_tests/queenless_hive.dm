/// Solo hives progress and communicate without a mapped queen, including after queen death.
/datum/unit_test/queenless_hive_progression/Run()
	var/mob/living/carbon/xenomorph/runner/xeno = allocate(/mob/living/carbon/xenomorph/runner)
	var/datum/hive_status/hive = xeno.hive
	var/previous_policy = hive.requires_living_ruler
	var/mob/living/carbon/xenomorph/previous_ruler = hive.living_xeno_ruler
	var/datum/game_mode/previous_mode = SSticker.mode
	var/datum/game_mode/infestation/nuclear_war/mode = allocate(/datum/game_mode/infestation/nuclear_war)
	SSticker.mode = mode
	hive.living_xeno_ruler = null
	xeno.evolution_stored = 0
	var/queenless_enabled = !hive.requires_living_ruler
	xeno.update_evolving(2)
	var/queenless_progress = xeno.evolution_stored
	var/queenless_announcements = hive.can_xeno_message()
	var/datum/xeno_caste/queen_caste = GLOB.xeno_caste_datums[/datum/xeno_caste/queen][XENO_UPGRADE_BASETYPE]
	var/previous_death_timer = hive.caste_death_timers[queen_caste]
	var/death_timer = addtimer(CALLBACK(hive, TYPE_PROC_REF(/datum/hive_status, end_caste_death_timer), queen_caste), hive.get_total_hivemind_conduit_time(), TIMER_STOPPABLE)
	hive.caste_death_timers[queen_caste] = death_timer
	var/queenless_speech = hive.can_use_hivemind()
	hive.requires_living_ruler = TRUE
	xeno.evolution_stored = 0
	xeno.update_evolving(2)
	var/required_progress = xeno.evolution_stored
	var/required_announcements = hive.can_xeno_message()
	var/required_speech = hive.can_use_hivemind()
	// A living ruler remains meaningful when a hive opts into the original policy.
	hive.living_xeno_ruler = xeno
	xeno.update_evolving(2)
	var/ruled_progress = xeno.evolution_stored
	deltimer(death_timer)
	hive.caste_death_timers[queen_caste] = previous_death_timer
	hive.requires_living_ruler = previous_policy
	hive.living_xeno_ruler = previous_ruler
	SSticker.mode = previous_mode
	TEST_ASSERT(queenless_enabled, "Normal SGS hives must not require a dummy queen")
	TEST_ASSERT(queenless_progress > 0, "A non-larva must actually gain evolution progress without a ruler")
	TEST_ASSERT(queenless_announcements && queenless_speech, "Queenless hives must retain announcements and speech during the queen death cooldown")
	TEST_ASSERT_EQUAL(required_progress, 0, "A hive opting into ruler dependence must still halt evolution without a ruler")
	TEST_ASSERT(!required_announcements && !required_speech, "The original ruler-dependent communication policy must remain available")
	TEST_ASSERT(ruled_progress > 0, "A ruler must still satisfy a ruler-dependent hive's evolution requirement")

/// Removing the dependency cancels old orphan timers but does not remove ordinary silo defeat.
/datum/unit_test/queenless_hive_orphan_collapse/Run()
	var/mob/living/carbon/previous_direction_leader = SSdirection.leader_mapping[XENO_HIVE_NORMAL]
	var/datum/hive_status/normal/hive = allocate(/datum/hive_status/normal)
	SSdirection.set_leader(XENO_HIVE_NORMAL, previous_direction_leader)
	var/datum/hive_status/previous_hive = GLOB.hive_datums[XENO_HIVE_NORMAL]
	var/datum/game_mode/previous_mode = SSticker.mode
	var/previous_gamestate = SSmonitor.gamestate
	var/datum/game_mode/infestation/nuclear_war/nuclear = allocate(/datum/game_mode/infestation/nuclear_war)
	var/datum/game_mode/infestation/sovl_war/sovl = allocate(/datum/game_mode/infestation/sovl_war)
	GLOB.hive_datums[XENO_HIVE_NORMAL] = hive
	SSticker.mode = nuclear
	SSmonitor.gamestate = SHIPSIDE
	hive.handle_ruler_timer()
	var/no_new_timer = !nuclear.orphan_hive_timer && !hive.orphan_hud_timer
	hive.requires_living_ruler = TRUE
	hive.handle_ruler_timer()
	var/old_timer = nuclear.orphan_hive_timer
	var/atom/movable/screen/text/screen_timer/old_hud = hive.orphan_hud_timer
	var/required_timer_started = old_timer && old_hud
	hive.requires_living_ruler = FALSE
	// Cancellation must not be skipped just because the round has changed phase.
	SSmonitor.gamestate = 0
	hive.handle_ruler_timer()
	var/stale_timer_cancelled = !nuclear.orphan_hive_timer && !hive.orphan_hud_timer && QDELETED(old_hud)
	nuclear.round_stage = INFESTATION_MARINE_CRASHING
	nuclear.orphan_hivemind_collapse()
	sovl.round_stage = INFESTATION_MARINE_DEPLOYMENT
	sovl.orphan_hivemind_collapse()
	var/no_orphan_defeat = !nuclear.round_finished && !sovl.round_finished
	nuclear.round_stage = INFESTATION_MARINE_DEPLOYMENT
	nuclear.siloless_hive_collapse()
	var/silo_defeat_preserved = nuclear.round_finished == MODE_INFESTATION_M_MAJOR
	// Always restore globals before an assertion may return early.
	GLOB.hive_datums[XENO_HIVE_NORMAL] = previous_hive
	SSticker.mode = previous_mode
	SSmonitor.gamestate = previous_gamestate
	if(nuclear.orphan_hive_timer)
		deltimer(nuclear.orphan_hive_timer)
		nuclear.orphan_hive_timer = null
	QDEL_NULL(hive.orphan_hud_timer)
	TEST_ASSERT(no_new_timer, "Queenless shipside play must not start an orphan timer or HUD")
	TEST_ASSERT(required_timer_started, "The original ruler-dependent timer must still work as a positive control")
	TEST_ASSERT(stale_timer_cancelled, "Disabling ruler dependence must cancel an armed timer and remove its HUD outside shipside too")
	TEST_ASSERT(no_orphan_defeat, "Neither Nuclear War nor Sovl War may declare an orphan defeat for a queenless hive")
	TEST_ASSERT(silo_defeat_preserved, "Queenless play must not bypass the independent siloless defeat condition")

/// Healing without a ruler must not silently retain the half-strength penalty in other modes.
/datum/unit_test/queenless_hive_healing/Run()
	var/mob/living/carbon/xenomorph/runner/xeno = allocate(/mob/living/carbon/xenomorph/runner)
	var/datum/hive_status/hive = xeno.hive
	var/previous_policy = hive.requires_living_ruler
	var/mob/living/carbon/xenomorph/previous_ruler = hive.living_xeno_ruler
	var/datum/game_mode/previous_mode = SSticker.mode
	var/datum/game_mode/mode = allocate(/datum/game_mode)
	mode.round_type_flags = NONE
	SSticker.mode = mode
	hive.living_xeno_ruler = null
	xeno.loc_weeds_type = /obj/alien/weeds
	xeno.resting = FALSE
	xeno.lying_angle = 0
	xeno.adjustBruteLoss(100, TRUE)
	xeno.regen_power = 1
	var/health_before = xeno.health
	hive.requires_living_ruler = FALSE
	xeno.handle_living_health_updates(2)
	var/queenless_healing = xeno.health - health_before
	xeno.adjustBruteLoss(queenless_healing, TRUE)
	xeno.regen_power = 1
	health_before = xeno.health
	hive.requires_living_ruler = TRUE
	xeno.handle_living_health_updates(2)
	var/required_healing = xeno.health - health_before
	hive.requires_living_ruler = previous_policy
	hive.living_xeno_ruler = previous_ruler
	SSticker.mode = previous_mode
	TEST_ASSERT(queenless_healing > 0, "A queenless xeno on weeds must actually heal")
	TEST_ASSERT(abs(queenless_healing - required_healing * 2) < 0.01, "Queenless healing must avoid the old half-strength ruler penalty")
