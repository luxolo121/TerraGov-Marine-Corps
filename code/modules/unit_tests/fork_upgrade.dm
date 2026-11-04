/// The low-pop timings belong to nuclear disks, not the new generic code-generator parent.
/datum/unit_test/fork_nuclear_disk_segments/Run()
	var/obj/machinery/computer/code_generator/nuke/red/generator = allocate(/obj/machinery/computer/code_generator/nuke/red)
	TEST_ASSERT_EQUAL(generator.segment_time, 1 MINUTES, "Custom nuclear disk segment time was lost during parent extraction")
	TEST_ASSERT_EQUAL(initial(/obj/machinery/computer/code_generator::segment_time), 1.5 MINUTES, "Nuclear custom timing leaked into other generator types")
	for(var/segment in 1 to 3)
		generator.complete_segment()
	var/list/ui_state = generator.ui_data(null)
	TEST_ASSERT(ui_state["completed"], "Low-pop nuclear disk must be printable after three completed segments")
	TEST_ASSERT_EQUAL(initial(/obj/machinery/computer/code_generator::total_segments), 5, "Generic generators must retain upstream segment count")

/// The fixed heavy season must expose both custom rockets and newly added upstream remote gear.
/datum/unit_test/fork_heavy_season_availability/Run()
	var/datum/season_datum/weapons/guns/KABOOM/all_heavy = allocate(/datum/season_datum/weapons/guns/KABOOM)
	var/datum/season_datum/weapons/guns/heavy_remote/upstream_remote = allocate(/datum/season_datum/weapons/guns/heavy_remote)
	for(var/item_type in upstream_remote.item_list)
		TEST_ASSERT(item_type in all_heavy.item_list, "Upstream remote equipment [item_type] is missing from fixed heavy availability")
	TEST_ASSERT_EQUAL(all_heavy.item_list[/obj/item/storage/holster/backholster/rpg/auto/full], 2, "Custom RL-222 acquisition route missing")
	TEST_ASSERT_EQUAL(all_heavy.item_list[/obj/item/ammo_magazine/handful/autorocket], 3, "Custom RL-222 ammunition acquisition route missing")

/// Exercise the relocated barricade smoke handler and its custom armor together.
/datum/unit_test/fork_barricade_acid_smoke/Run()
	var/obj/structure/barricade/solid/barricade = allocate(/obj/structure/barricade/solid)
	var/obj/effect/particle_effect/smoke/smoke = allocate(/obj/effect/particle_effect/smoke)
	smoke.smoke_traits = SMOKE_XENO_ACID
	smoke.strength = 1
	smoke.lifetime = 10
	var/integrity_before = barricade.obj_integrity
	barricade.effect_smoke(smoke)
	TEST_ASSERT(abs((integrity_before - barricade.obj_integrity) - 6.4) < 0.01, "Custom 8-point acid smoke with 20% metal acid armor did not survive the barricade split")

/// A real equip pass catches renamed or removed gear in the custom guardsman outfit.
/datum/unit_test/fork_guardsman_loadout/Run()
	var/mob/living/carbon/human/guardsman = allocate(/mob/living/carbon/human)
	guardsman.equipOutfit(/datum/outfit/job/volksturm/guardsman)
	TEST_ASSERT(istype(guardsman.get_item_by_slot(SLOT_S_STORE), /obj/item/weapon/gun/rifle/standard_smarttargetrifle/cadia), "Custom guardsman no longer equips its Cadian rifle")

/// Unrestricted selection must not turn an ID-less purchase into a null dereference.
/datum/unit_test/fork_vendor_without_id/Run()
	var/mob/living/carbon/human/customer = allocate(/mob/living/carbon/human)
	var/obj/machinery/marine_selector/vendor = allocate(/obj/machinery/marine_selector)
	TEST_ASSERT_EQUAL(vendor.on_vend(customer, list("vend" = "/obj/item/weapon/gun/rifle/standard_smarttargetrifle/cadia")), FALSE, "ID-less purchasing must return safely")
