/// The four castes explicitly granted access by the custom fork must get one visible action.
/datum/unit_test/xeno_blessings_custom_castes/Run()
	for(var/xeno_type in list(/mob/living/carbon/xenomorph/drone, /mob/living/carbon/xenomorph/hivelord, /mob/living/carbon/xenomorph/hivemind, /mob/living/carbon/xenomorph/larva))
		var/mob/living/carbon/xenomorph/xeno = allocate(xeno_type)
		var/datum/action/ability/xeno_action/blessing_menu/blessings = xeno.actions_by_path[/datum/action/ability/xeno_action/blessing_menu]
		TEST_ASSERT(blessings, "[xeno_type] must retain the fork's innate Mother's Blessings")
		TEST_ASSERT(blessings.should_show(), "[xeno_type] must expose a game-window action button, not only a hidden keybind")
		var/count = 0
		for(var/datum/action/ability/xeno_action/blessing_menu/action in xeno.mob_abilities)
			count++
		TEST_ASSERT_EQUAL(count, 1, "[xeno_type] must not create duplicate Blessings actions")
		var/list/hive_data = xeno.hive.ui_static_data(xeno)
		TEST_ASSERT(hive_data["user_purchase_perms"], "[xeno_type] must also retain the Hive Status purchase entry")

/// Maturing replaces the caste action list: the actual upgrade must not delete this menu.
/datum/unit_test/xeno_blessings_maturation/Run()
	for(var/xeno_type in list(/mob/living/carbon/xenomorph/drone, /mob/living/carbon/xenomorph/hivelord))
		var/mob/living/carbon/xenomorph/xeno = allocate(xeno_type)
		var/datum/action/ability/xeno_action/blessing_menu/blessings = xeno.actions_by_path[/datum/action/ability/xeno_action/blessing_menu]
		TEST_ASSERT(blessings, "Normal builder must have Blessings before maturation")
		TEST_ASSERT(xeno.upgrade_xeno(XENO_UPGRADE_PRIMO, TRUE), "Builder maturation fixture failed")
		TEST_ASSERT_EQUAL(xeno.actions_by_path[/datum/action/ability/xeno_action/blessing_menu], blessings, "[xeno_type] must preserve its existing Blessings action after primordial maturation")
		TEST_ASSERT(blessings.should_show(), "Maturation must not hide the retained menu")
		TEST_ASSERT(xeno.actions_by_path[/datum/action/ability/xeno_action/sow], "The primordial builder must still receive its upstream Sow ability")

/// Losing hive leadership must preserve innate access but remove temporary ruler-only grants.
/datum/unit_test/xeno_blessings_ruler_cleanup/Run()
	var/mob/living/carbon/xenomorph/drone/builder = allocate(/mob/living/carbon/xenomorph/drone)
	var/datum/action/ability/xeno_action/blessing_menu/innate = builder.actions_by_path[/datum/action/ability/xeno_action/blessing_menu]
	builder.give_ruler_abilities()
	builder.remove_ruler_abilities()
	TEST_ASSERT_EQUAL(builder.actions_by_path[/datum/action/ability/xeno_action/blessing_menu], innate, "Ruler cleanup must use type-path membership to preserve an innate menu")
	TEST_ASSERT_NULL(builder.actions_by_path[/datum/action/ability/xeno_action/set_xeno_lead], "A builder must still lose temporary leadership powers")
	var/mob/living/carbon/xenomorph/runner/runner = allocate(/mob/living/carbon/xenomorph/runner)
	TEST_ASSERT_NULL(runner.actions_by_path[/datum/action/ability/xeno_action/blessing_menu], "The fix must not grant Blessings to every caste")
	runner.give_ruler_abilities()
	TEST_ASSERT(runner.actions_by_path[/datum/action/ability/xeno_action/blessing_menu], "Ruler grant fixture failed")
	runner.remove_ruler_abilities()
	TEST_ASSERT_NULL(runner.actions_by_path[/datum/action/ability/xeno_action/blessing_menu], "Non-innate Blessings must be removed when temporary ruler powers are revoked")

/// A real primordial purchase works without a queen; one-time and currency checks still apply.
/datum/unit_test/xeno_blessings_queenless_purchase/Run()
	var/mob/living/carbon/xenomorph/drone/buyer = allocate(/mob/living/carbon/xenomorph/drone)
	var/datum/hive_upgrade/primordial/tier_one/upgrade = allocate(/datum/hive_upgrade/primordial/tier_one)
	var/datum/hive_status/hive = buyer.hive
	var/mob/living/carbon/xenomorph/previous_ruler = hive.living_xeno_ruler
	var/previous_points = SSpoints.xeno_strategic_points_by_hive[buyer.hivenumber]
	hive.living_xeno_ruler = null
	SSpoints.xeno_strategic_points_by_hive[buyer.hivenumber] = upgrade.psypoint_cost * 2
	// Exercise the same can_buy -> on_buy pipeline used by the BlessingMenu buy action.
	var/allowed = upgrade.can_buy(buyer)
	var/purchased = allowed && upgrade.on_buy(buyer)
	var/points_after = SSpoints.xeno_strategic_points_by_hive[buyer.hivenumber]
	var/repeat_allowed = upgrade.can_buy(buyer)
	upgrade.times_bought = 0
	SSpoints.xeno_strategic_points_by_hive[buyer.hivenumber] = 0
	var/unfunded_allowed = upgrade.can_buy(buyer)
	// Restore shared state before any assertion can return early.
	SSpoints.xeno_strategic_points_by_hive[buyer.hivenumber] = previous_points
	hive.living_xeno_ruler = previous_ruler
	TEST_ASSERT(purchased, "A non-ruler builder with points must be able to buy primordial unlocks without a queen")
	TEST_ASSERT_EQUAL(points_after, upgrade.psypoint_cost, "A successful purchase must charge the hive exactly once")
	TEST_ASSERT(!repeat_allowed, "Queenless access must not bypass the one-time purchase rule")
	TEST_ASSERT(!unfunded_allowed, "Queenless access must not bypass the psychic point cost")

/// Primordial maturation schedules Enhancement setup; removing it before that tick must be safe.
/datum/unit_test/xeno_blessings_drone_action_lifetime/Run()
	var/mob/living/carbon/xenomorph/drone/live_drone = allocate(/mob/living/carbon/xenomorph/drone)
	TEST_ASSERT(live_drone.upgrade_xeno(XENO_UPGRADE_PRIMO, TRUE), "Live primordial Drone fixture failed")
	var/datum/action/ability/xeno_action/enhancement/live_action = live_drone.actions_by_path[/datum/action/ability/xeno_action/enhancement]
	TEST_ASSERT(live_action, "Primordial Drone must retain Enhancement")
	live_action.link_essence_action()
	TEST_ASSERT_EQUAL(live_action.essence_link_action, live_drone.actions_by_path[/datum/action/ability/activable/xeno/essence_link], "An attached action must still link to its owner's Essence Link")
	var/mob/living/carbon/xenomorph/drone/removed_drone = allocate(/mob/living/carbon/xenomorph/drone)
	TEST_ASSERT(removed_drone.upgrade_xeno(XENO_UPGRADE_PRIMO, TRUE), "Removed primordial Drone fixture failed")
	var/datum/action/ability/xeno_action/enhancement/removed_action = removed_drone.actions_by_path[/datum/action/ability/xeno_action/enhancement]
	TEST_ASSERT(removed_action, "Deferred Enhancement fixture missing")
	removed_action.remove_action(removed_drone)
	TEST_ASSERT_NULL(removed_action.xeno_owner, "Removal must clear the owner before deferred setup")
	removed_action.link_essence_action()
	TEST_ASSERT_NULL(removed_action.essence_link_action, "An ownerless deferred action must not acquire a stale Essence Link")
	qdel(removed_action)
