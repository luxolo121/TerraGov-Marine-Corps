///Build designation mode
#define BUILD_DESIGNATOR_MODE "build_designator_mode"
///Interact designation mode
#define INTERACT_DESIGNATOR_MODE "interact_designator_mode"
///World tactical drawing shares the existing designator and ability binding.
#define TACTICAL_DESIGNATOR_MODE "tactical_designator_mode"

GLOBAL_LIST_INIT(designator_mode_image_list, list(
	INTERACT_DESIGNATOR_MODE = image('icons/mob/actions.dmi', icon_state = "interact_designator"),
	BUILD_DESIGNATOR_MODE = image('icons/mob/actions.dmi', icon_state = "build_designator"),
))

/datum/action/ability/activable/build_designator
	name = "Interact Designator"
	desc = "Click a friendly to select; click again to deselect without cancelling orders. Selecting a recruited AI commands its whole tactical squad: click a tile to hold or a living ally to follow. Right-click this button (Select Buildtype key, default I) for tactical orders, drawing tools, overlays and deselect."
	action_icon_state = "interact_designator"
	action_icon = 'icons/mob/actions.dmi'
	use_state_flags = ABILITY_TARGET_SELF
	keybinding_signals = list(
		KEYBINDING_NORMAL = COMSIG_ABILITY_PLACE_HOLOGRAM,
		KEYBINDING_ALTERNATE = COMSIG_ABILITY_SELECT_BUILDTYPE,
	)
	///What function this action is currently on
	var/designator_mode = INTERACT_DESIGNATOR_MODE

/datum/action/ability/activable/build_designator/Destroy()
	cleanup_hologram()
	if(selected_mob)
		unindicate_target(selected_mob)
	selected_mob = null
	return ..()

/datum/action/ability/activable/build_designator/should_show()
	. = ..()
	if(!.)
		return
	return owner?.client?.holder || owner.skills.getRating(SKILL_LEADERSHIP) >= SKILL_LEAD_TRAINED

/datum/action/ability/activable/build_designator/can_use_action(silent, override_flags, selecting)
	if(designator_mode == TACTICAL_DESIGNATOR_MODE)
		return tactical_command_available(owner)
	return owner?.client?.holder || owner.skills.getRating(SKILL_LEADERSHIP) >= SKILL_LEAD_TRAINED

/datum/action/ability/activable/build_designator/on_selection()
	activate_mode(designator_mode)
	if(designator_mode == TACTICAL_DESIGNATOR_MODE)
		var/datum/tactical_command/command = get_tactical_command(owner)
		command?.set_world_overlay(TRUE)

/datum/action/ability/activable/build_designator/on_deselection()
	deactivate_mode(designator_mode)
	var/datum/action/tactical_command/action = owner?.actions_by_path[/datum/action/tactical_command]
	if(action?.command_ui)
		action.command_ui.world_target_order = null
		action.command_ui.disable_world_overlay()

/datum/action/ability/activable/build_designator/action_activate()
	var/mob/living/carbon/carbon_owner = owner
	if(carbon_owner.selected_ability == src)
		deselect()
		return
	return ..()

/datum/action/ability/activable/build_designator/use_ability(atom/A)
	if(!can_use_action())
		return
	if(!A)
		return FALSE
	switch(designator_mode)
		if(BUILD_DESIGNATOR_MODE)
			return use_build_ability(A)

		if(INTERACT_DESIGNATOR_MODE)
			return use_interact_ability(A)
		if(TACTICAL_DESIGNATOR_MODE)
			var/datum/tactical_command/command = get_tactical_command(owner)
			return command?.world_click(A)

/datum/action/ability/activable/build_designator/alternate_action_activate()
	if(!can_use_action())
		return
	switch(designator_mode)
		if(BUILD_DESIGNATOR_MODE)
			INVOKE_ASYNC(src, PROC_REF(select_structure))
		if(INTERACT_DESIGNATOR_MODE, TACTICAL_DESIGNATOR_MODE)
			INVOKE_ASYNC(src, PROC_REF(select_mode))

///Tells overwatch we're overriding the radial selection
/datum/action/ability/activable/build_designator/proc/override_cic_radial(datum/source)
	SIGNAL_HANDLER
	return OVERWATCH_RADIAL_HIDE

///Selects a mode
/datum/action/ability/activable/build_designator/proc/select_mode()
	var/list/options = list(
		"Interact" = image('icons/mob/actions.dmi', icon_state = "interact_designator"),
		"Construction" = image('icons/mob/actions.dmi', icon_state = "build_designator"),
	)
	var/datum/tactical_command/command = get_tactical_command(owner)
	if(command)
		options["Tactical orders"] = image('icons/mob/tactical_command.dmi', icon_state = "orders")
		options["Tactical tools"] = image('icons/mob/tactical_command.dmi', icon_state = "designate")
		options["Deselect — keep orders"] = image('icons/mob/tactical_command.dmi', icon_state = "selected")
		options["Toggle tactical overlays"] = image('icons/mob/tactical_command.dmi', icon_state = "overlay")
	var/mode_choice = command ? command.show_world_radial(options) : show_radial_menu(owner, owner?.client?.eye, options, tooltips = TRUE)
	if(!mode_choice)
		return
	if(mode_choice == "Interact" || mode_choice == "Construction")
		var/new_mode = mode_choice == "Interact" ? INTERACT_DESIGNATOR_MODE : BUILD_DESIGNATOR_MODE
		if(new_mode != designator_mode)
			swap_mode(new_mode)
		return
	if(!command || command.ui_status(owner) != UI_INTERACTIVE)
		return
	switch(mode_choice)
		if("Tactical orders")
			command.world_orders_menu()
		if("Tactical tools")
			command.world_tool_menu()
		if("Deselect — keep orders")
			command.world_execute("deselect")
		if("Toggle tactical overlays")
			command.set_world_overlay(!command.world_overlay_enabled)
			to_chat(owner, span_notice("Local tactical overlays [command.world_overlay_enabled ? "shown" : "hidden"]. Orders are unchanged."))

///Swaps our mode to a new one
/datum/action/ability/activable/build_designator/proc/swap_mode(new_mode)
	deactivate_mode(designator_mode)
	designator_mode = new_mode
	activate_mode(new_mode)

///Toggles off the current mode
/datum/action/ability/activable/build_designator/proc/deactivate_mode(old_mode)
	UnregisterSignal(owner, COMSIG_DO_OVERWATCH_RADIAL)
	switch(old_mode)
		if(BUILD_DESIGNATOR_MODE)
			cleanup_hologram()
			UnregisterSignal(owner, list(COMSIG_ATOM_MOUSE_ENTERED, COMSIG_ATOM_DIR_CHANGE))
		if(INTERACT_DESIGNATOR_MODE)
			if(selected_mob)
				unindicate_target(selected_mob)
				selected_mob = null

///Toggles on the new mode
/datum/action/ability/activable/build_designator/proc/activate_mode(new_mode)
	var/mob/living/carbon/carbon_owner = owner
	if(carbon_owner.selected_ability == src)
		RegisterSignal(owner, COMSIG_DO_OVERWATCH_RADIAL, PROC_REF(override_cic_radial))
	switch(new_mode)
		if(BUILD_DESIGNATOR_MODE)
			if(carbon_owner.selected_ability == src)
				RegisterSignal(owner, COMSIG_ATOM_MOUSE_ENTERED, PROC_REF(show_hologram_call))
				RegisterSignal(owner, COMSIG_ATOM_DIR_CHANGE, PROC_REF(on_owner_rotate))
			target_flags = ABILITY_TURF_TARGET
			use_state_flags = NONE
			action_icon = 'icons/mob/actions.dmi'
			action_icon_state = "build_designator"
			name = "Construction Designator"
			desc = "Place a designator for construction."
		if(INTERACT_DESIGNATOR_MODE)
			target_flags = NONE
			use_state_flags = ABILITY_TARGET_SELF
			action_icon = 'icons/mob/actions.dmi'
			action_icon_state = "interact_designator"
			name = "Interact Designator"
			desc = "Click a friendly to select; click again to deselect without cancelling orders. Selecting a recruited AI commands its whole tactical squad: click a tile to hold or a living ally to follow. Right-click this button (Select Buildtype key, default I) for tactical orders, drawing tools, overlays and deselect."
		if(TACTICAL_DESIGNATOR_MODE)
			target_flags = NONE
			use_state_flags = ABILITY_TARGET_SELF
			action_icon = 'icons/mob/tactical_command.dmi'
			action_icon_state = "designate"
			name = "Tactical Designator"
			desc = "Middle/shift-click to use the selected tool on visible terrain. Right-click (Select Buildtype key, default I): tactical orders and tools, Save / Undo / Cancel, overlays and deselect."
	update_button_icon()
	var/datum/action/tactical_command/action = owner?.actions_by_path[/datum/action/tactical_command]
	action?.command_ui?.update_world_controls()
