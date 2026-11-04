/// RL-222 impact callbacks must not delete the shared ammo datum or the projectile
/// before do_projectile_hit finishes applying the direct hit's damage.
/datum/unit_test/autorocket_hit_lifecycle/Run()
	var/datum/ammo/ammo = GLOB.ammo_list[/datum/ammo/bullet/autorocket]
	TEST_ASSERT(ammo && !QDELETED(ammo), "RL-222 AP ammo must be available before firing.")
	var/mob/living/carbon/human/shooter = allocate(/mob/living/carbon/human)

	for(var/shot in 1 to 2)
		var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human)
		var/atom/movable/projectile/projectile = allocate(/atom/movable/projectile)
		projectile.generate_bullet(/datum/ammo/bullet/autorocket)
		projectile.firer = shooter
		projectile.shot_from = shooter
		projectile.dir_angle = 0
		var/health_before = victim.health

		victim.do_projectile_hit(projectile)

		TEST_ASSERT(!QDELETED(ammo), "RL-222 shot [shot] deleted the shared ammo datum, breaking later shots.")
		TEST_ASSERT(!QDELETED(projectile), "RL-222 shot [shot] deleted the projectile before hit processing could finish.")
		TEST_ASSERT(victim.health < health_before, "RL-222 shot [shot] did not apply its direct hit damage.")
		TEST_ASSERT_EQUAL(projectile.ammo, ammo, "Each shot must retain the same usable ammo datum.")
		TEST_ASSERT_EQUAL(projectile.proj_max_range, 0, "AP shells must stop travelling after a living hit.")
