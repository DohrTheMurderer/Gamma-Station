/*
	Click code cleanup
	~Sayu
*/

// 1 decisecond click delay (above and beyond mob/next_move)
/mob/var/next_click	= 0

/*
	Before anything else, defer these calls to a per-mobtype handler.  This allows us to
	remove istype() spaghetti code, but requires the addition of other handler procs to simplify it.

	Alternately, you could hardcode every mob's variation in a flat ClickOn() proc; however,
	that's a lot of code duplication and is hard to maintain.

	Note that this proc can be overridden, and is in the case of screen objects.
*/
/atom/Click(location,control,params)
	if(src)
		usr.ClickOn(src, params)

/atom/DblClick(location,control,params)
	if(src)
		usr.DblClickOn(src,params)

/*
	Standard mob ClickOn()
	Handles exceptions: Buildmode, middle click, modified clicks, mech actions

	After that, mostly just check your state, check whether you're holding an item,
	check whether you're adjacent to the target, then pass off the click to whoever
	is recieving it.
	The most common are:
	* mob/UnarmedAttack(atom,adjacent) - used here only when adjacent, with no item in hand; in the case of humans, checks gloves
	* atom/attackby(item,user,params) - used only when adjacent
	* item/afterattack(atom,user,adjacent,params) - used both ranged and adjacent
	* mob/RangedAttack(atom,params) - used only ranged, only used for tk and laser eyes but could be changed
*/
/mob/var/next_move_modifier = 0 // for now just used for species


/mob/proc/SetNextMove(num)
	next_move = world.time + num + next_move_modifier

/mob/proc/SetNextClick(num) // next_click is checked before even modified(Shift/Ctrl) clicks, that's the difference.
	next_click = world.time + num

/mob/proc/ClickOn(atom/A, params)
	if(world.time <= next_click)
		return
	next_click = world.time + 1

	if(client.buildmode)
		build_click(src, client.buildmode, params, A)
		return

	var/list/modifiers = params2list(params)

	if(client.cob && client.cob.in_building_mode)
		cob_click(client, modifiers)
		return

	if(modifiers["shift"] && modifiers["ctrl"])
		CtrlShiftClickOn(A, params)
		return
	if(modifiers["middle"])
		MiddleClickOn(A)
		return
	if(modifiers["shift"])
		ShiftClickOn(A)
		return
	if(modifiers["alt"]) // alt and alt-gr (rightalt)
		AltClickOn(A)
		return
	if(modifiers["ctrl"])
		CtrlClickOn(A)
		return

	if(stat || paralysis || stunned || weakened)
		return

	face_atom(A) // change direction to face what you clicked on

	if(next_move > world.time) // in the year 2000...
		return

	if(istype(loc,/obj/mecha))
		if(!locate(/turf) in list(A, A.loc)) // Prevents inventory from being drilled
			return
		var/obj/mecha/M = loc
		return M.click_action(A, src)

	if(istype(loc,/obj/spacepod))
		if(!locate(/turf) in list(A, A.loc))
			return
		var/obj/spacepod/M = loc
		return M.click_action(A, src)

	if(restrained())
		RestrainedClickOn(A)
		return

	if(in_throw_mode)
		throw_item(A)
		return

	if(!istype(A,/obj/item/weapon/gun) && !isturf(A) && !istype(A,/obj/screen))
		last_target_click = world.time

	// additional_checks is a parameter that determines whether we get ACTUAL hand item,
	// or something else. per say, TK grabs with the checks return what is in TK focus, not
	// the TK item itself.
	var/obj/item/W = get_active_hand(additional_checks = FALSE)

	if(W == A)
		W.attack_self(src)
		if(hand)
			update_inv_l_hand()
		else
			update_inv_r_hand()
		return

	// operate two STORAGE levels deep here (item in backpack in src; NOT item in box in backpack in src)
	var/sdepth = A.storage_depth(src)
	if(A == loc || (A in loc) || (sdepth != -1 && sdepth <= 1))

		// No adjacency needed
		if(W)

			var/resolved = A.attackby(W, src, params)
			if(!resolved && A && W)
				W.afterattack(A, src, 1, params) // 1 indicates adjacency
		else
			UnarmedAttack(A)
		return

	if(!isturf(loc)) // This is going to stop you from telekinesing from inside a closet, but I don't shed many tears for that
		return

	// Allows you to click on a box's contents, if that box is on the ground, but no deeper than that
	sdepth = A.storage_depth_turf()
	if(isturf(A) || isturf(A.loc) || (sdepth != -1 && sdepth <= 1))

		if(A.Adjacent(src)) // see adjacent.dm
			if(W)
				// Return 1 in attackby() to prevent afterattack() effects (when safely moving items for example)
				var/resolved = A.attackby(W, src, params)
				if(!resolved && A && W)
					W.afterattack(A, src, 1, params) // 1: clicking something Adjacent
			else
				UnarmedAttack(A)
		else // non-adjacent click
			if(W)
				W.afterattack(A, src, 0, params) // 0: not Adjacent
			else
				RangedAttack(A, params)

// Default behavior: ignore double clicks, consider them normal clicks instead
/mob/proc/DblClickOn(atom/A, params)
	ClickOn(A,params)


// Translates into attack_hand, etc.

/mob/proc/UnarmedAttack(atom/A)
	if(ismob(A))
		SetNextMove(CLICK_CD_MELEE)

/*
	Ranged unarmed attack:

	This currently is just a default for all mobs, involving
	laser eyes and telekinesis.  You could easily add exceptions
	for things like ranged glove touches, spitting alien acid/neurotoxin,
	animals lunging, etc.
*/
/mob/proc/RangedAttack(atom/A, params)
	if(!mutations.len)
		return
	var/dist = get_dist(src, A)
	if(a_intent == I_HURT && (LASEREYES in mutations))
		LaserEyes(A) // moved into a proc below
	else if((TK in mutations) && do_telekinesis(dist))
		A.attack_tk(src)

/*
	Restrained ClickOn

	Used when you are handcuffed and click things.
	Not currently used by anything but could easily be.
*/
/mob/proc/RestrainedClickOn(atom/A) // for now it's overriding only in monkey.
	return

/*
	Middle click
	Only used for swapping hands
*/
/mob/proc/MiddleClickOn(atom/A)
	return
/mob/living/carbon/MiddleClickOn(atom/A)
	swap_hand()

// In case of use break glass
/*
/atom/proc/MiddleClick(mob/M)
	return
*/

/*
	Shift click
	For most mobs, examine.
	This is overridden in ai.dm
*/
/mob/proc/ShiftClickOn(atom/A)
	A.ShiftClick(src)
	return
/atom/proc/ShiftClick(mob/user)
	if(user.client && user.client.eye == user)
		user.examinate(src)
	return

/*
	Ctrl click
	For most objects, pull
*/
/mob/proc/CtrlClickOn(atom/A)
	A.CtrlClick(src)
	return

/atom/proc/CtrlClick(mob/user)
	return

/atom/movable/CtrlClick(mob/user)
	if(Adjacent(user))
		user.start_pulling(src)

/*
	Alt click
	Unused except for AI
*/
/mob/proc/AltClickOn(atom/A)
	A.AltClick(src)
	return

/atom/proc/AltClick(mob/user)
	var/turf/T = get_turf(src)
	if(T && user.TurfAdjacent(T))
		if(user.listed_turf == T)
			user.listed_turf = null
		else
			user.listed_turf = T
			user.client.statpanel = T.name
	return

/mob/proc/TurfAdjacent(turf/T)
	return T.AdjacentQuick(src)

/*
	Control+Shift click
	Unused except for AI
*/
/mob/proc/CtrlShiftClickOn(atom/A, params)
	A.CtrlShiftClick(src, params)
	return

/atom/proc/CtrlShiftClick(mob/user, params)
	// if(!incapacitated) This proc also checks for restrained. But we do want to be able to do telekinesis while restrained.
	if(user.stat || user.paralysis || user.stunned || user.weakened)
		return
	var/dist = get_dist(src, user)
	if((TK in user.mutations) && user.do_telekinesis(dist))
		var/obj/item/item = user.get_active_hand(additional_checks = FALSE)
		if(istype(item, /obj/item/tk_grab))
			item.afterattack(src, user, Adjacent(user), params)
		else
			attack_tk(user)

/*
	Misc helpers

	Laser Eyes: as the name implies, handles this since nothing else does currently
	face_atom: turns the mob towards what you clicked on
	cob_click: handles hotkeys for "craft or build"
*/
/mob/proc/LaserEyes(atom/A)
	return

/mob/living/carbon/human/LaserEyes(atom/A)
	if(nutrition > 300)
		..()
		SetNextMove(CLICK_CD_MELEE)
		var/obj/item/projectile/beam/LE = new (loc)
		LE.damage = 20
		playsound(usr.loc, 'sound/weapons/taser2.ogg', 75, 1)
		LE.Fire(A, src)
		nutrition = max(nutrition - rand(10, 40), 0)
	else
		to_chat(src, "<span class='red'> You're out of energy!  You need food!</span>")

// Simple helper to face what you clicked on, in case it should be needed in more than one place
/mob/proc/face_atom(atom/A)
	if( stat || buckled || !A || !x || !y || !A.x || !A.y ) return
	var/dx = A.x - x
	var/dy = A.y - y
	if(!dx && !dy) return

	if(abs(dx) < abs(dy))
		if(dy > 0)	usr.dir = NORTH
		else		usr.dir = SOUTH
	else
		if(dx > 0)	usr.dir = EAST
		else		usr.dir = WEST

// Craft or Build helper (main file can be found here: code/datums/cob_highlight.dm)
/mob/proc/cob_click(client/C, list/modifiers)
	if(C.cob.busy)
		//do nothing
	else if(modifiers["left"])
		if(modifiers["alt"])
			C.cob.rotate_object()
		else
			C.cob.try_to_build(src)
	else if(modifiers["right"])
		C.cob.remove_build_overlay(C)

/obj/screen/click_catcher
	icon = 'icons/mob/screen_gen.dmi'
	icon_state = "click_catcher"
	plane = CLICKCATCHER_PLANE
	mouse_opacity = 2
	screen_loc = "CENTER"

/obj/screen/click_catcher/atom_init()
	. = ..()
	transform = matrix(200, 0, 0, 0, 200, 0)

/obj/screen/click_catcher/Click(location, control, params)
	var/list/modifiers = params2list(params)
	if(modifiers["middle"] && istype(usr, /mob/living/carbon))
		var/mob/living/carbon/C = usr
		C.swap_hand()
	else
		var/turf/T = params2turf(modifiers["screen-loc"], get_turf(usr))
		if(T)
			T.Click(location, control, params)
	. = 1
