

/obj/item/odm_gear
	name = "ODM Gear"
	desc = "You know it bbg"
	icon = 'icons/obj/clothing/belts.dmi'
	icon_state = "utilitybelt"
	worn_icon_state = "utility"
	item_state_worn = TRUE
	equip_slot_flags = ITEM_SLOT_BELT
	w_class = WEIGHT_CLASS_BULKY
	///Time between uses
	var/cooldown_time = 0.5 SECONDS
	///maximum amount of fuel in the ODM gear
	var/fuel_max = 75
	///current amount of fuel in the ODM gear
	var/fuel_left = 75
	///How quick you will fly (warning, it rounds up to the nearest integer)
	var/speed = 1
	///Controlling action
	var/datum/action/ability/activable/item_toggle/odm_gear/toggle_action

/obj/item/odm_gear/Initialize(mapload)
	. = ..()
	toggle_action = new(src)
	update_icon()

/obj/item/odm_gear/examine(mob/user, distance, infix, suffix)
	. = ..()
	if(!ishuman(user))
		return
	if(fuel_left == 0)
		. += "The fuel gauge is empty, it has no fuel left!"
	else
		. += "The fuel gauge meter indicates it has [fuel_left/FUEL_USE] uses left."

/obj/item/odm_gear/equipped(mob/user, slot)
	. = ..()
	if(slot == SLOT_BELT)
		toggle_action.give_action(user)

/obj/item/odm_gear/dropped(mob/user)
	. = ..()
	toggle_action.remove_action(user)

/obj/item/odm_gear/ui_action_click(mob/user, datum/action/item_action/action, target)
	return toggle_action.odm_grapple(target, user)

/********************************************/
/**************** ODM grapple ***************/
/********************************************/

/datum/action/ability/activable/item_toggle/odm_gear
	name = "Use jetpack"
	action_icon_state = "axe_sweep"
	desc = "Briefly fly using your jetpack."
	use_state_flags = ABILITY_USE_STAGGERED|ABILITY_USE_BUSY
	keybinding_signals = list(KEYBINDING_NORMAL = COMSIG_ITEM_TOGGLE_JETPACK)

		//beam ref
	var/datum/beam/odm_beam



/datum/action/ability/activable/item_toggle/odm_gear/New(Target, obj/item/holder)
	. = ..()
	var/obj/item/odm_gear/odm = Target
	cooldown_duration = odm.cooldown_time

/datum/action/ability/activable/item_toggle/odm_gear/proc/odm_grapple(atom/A, mob/living/carbon/human/human_user)
	var/atom/movable/odm_hook/web_hook = new (get_turf(owner))
	odm_beam = owner.beam(web_hook,"1-full",'icons/effects/beam.dmi')
	RegisterSignals(web_hook, list(COMSIG_MOVABLE_POST_THROW, COMSIG_MOVABLE_IMPACT), PROC_REF(drag_user), TRUE)
	web_hook.throw_at(A, WIDOW_WEB_HOOK_RANGE, 3, owner, FALSE)

/datum/action/ability/activable/item_toggle/odm_gear/proc/drag_user(datum/source, turf/target_turf)
	SIGNAL_HANDLER
	QDEL_NULL(odm_beam)
	if(target_turf)
		owner.throw_at(target_turf, WIDOW_WEB_HOOK_RANGE, WIDOW_WEB_HOOK_SPEED, owner, FALSE, TRUE)
	else
		owner.throw_at(get_turf(source), WIDOW_WEB_HOOK_RANGE / 2, WIDOW_WEB_HOOK_SPEED, owner, FALSE, TRUE)
	qdel(source)
	RegisterSignal(owner, COMSIG_MOVABLE_POST_THROW, PROC_REF(delete_beam))

/datum/action/ability/activable/item_toggle/odm_gear/proc/delete_beam(datum/source)
	SIGNAL_HANDLER
	UnregisterSignal(source, COMSIG_MOVABLE_POST_THROW)
	QDEL_NULL(odm_beam)



/atom/movable/odm_hook
	name = "You can't see this"
	invisibility = INVISIBILITY_ABSTRACT
