/// Map-placed xenos can update their hive before the ticker chooses a mode.
/datum/unit_test/hive_tier_limits_before_mode/Run()
	// Construct a detached hive without disturbing normal-hive direction tracking.
	var/mob/living/carbon/previous_leader = SSdirection.leader_mapping[XENO_HIVE_NORMAL]
	var/datum/hive_status/hive = allocate(/datum/hive_status)
	SSdirection.set_leader(XENO_HIVE_NORMAL, previous_leader)
	var/list/tier_ones = hive.xenos_by_tier[XENO_TIER_ONE]
	var/list/tier_fours = hive.xenos_by_tier[XENO_TIER_FOUR]
	tier_ones.len = 4
	tier_fours.len = 1

	hive.update_tier_limits(null)
	TEST_ASSERT_EQUAL(hive.tier3_xeno_limit, 1, "Pre-mode hive initialization must safely use the existing four-to-one tier ratio.")
	TEST_ASSERT_EQUAL(hive.tier2_xeno_limit, 6, "Pre-mode initialization must still calculate tier-two availability.")

	var/list/tier_threes = hive.xenos_by_tier[XENO_TIER_THREE]
	tier_threes.len = 3
	hive.update_tier_limits(null)
	TEST_ASSERT_EQUAL(hive.tier3_xeno_limit, 3, "Pre-mode limits must not fall below already present tier-three xenos.")

	var/datum/game_mode/mode = allocate(/datum/game_mode)
	mode.roundstart_players = 12
	mode.tier_three_inclusion = TRUE
	mode.tier_three_penalty = 1
	hive.update_tier_limits(mode)
	TEST_ASSERT_EQUAL(hive.tier3_xeno_limit, 5, "A selected mode must retain the low-pop marine-count bonus, inclusion and penalty.")
	TEST_ASSERT_EQUAL(hive.tier2_xeno_limit, 3, "Selecting a mode must not change the established tier-two calculation.")
