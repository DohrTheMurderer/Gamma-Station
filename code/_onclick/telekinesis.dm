/*
	Telekinesis

	This needs more thinking out, but I might as well.
*/

#define TELEKINETIC_BASIC 0
#define TELEKINETIC_MOB_CONTROL 1
#define TELEKINETIC_HARM_WEAKEN 2
#define TELEKINETIC_NO_VIEW_REQUIRED 4

/*
	Telekinetic attack:

	By default, emulate the user's unarmed attack
*/
/atom/proc/attack_tk(mob/user)
	if(user.stat)
		return
	user.UnarmedAttack(src, 0) // attack_hand, attack_paw, etc

/obj/attack_tk(mob/user)
	if(user.stat)
		return
	if(istype(loc, /mob))
		if(user.a_intent == I_HELP)
			var/mob/M = loc
			M.drop_from_inventory(src, M.loc)
			return
	else if(istype(loc, /obj/item/weapon/storage))
		var/obj/item/weapon/storage/S = loc
		S.remove_from_storage(src, get_turf(src))
		return

	switch(user.a_intent)
		if(I_HELP)
			if(istype(src, /obj/item) && Adjacent(user)) // Even telekinesis requires being near clothing to put it on.
				user.equip_to_appropriate_slot(src)
			else
				user.UnarmedAttack(src, 0)
		if(I_GRAB)
			var/obj/item/tk_grab/O = new(src)
			user.put_in_active_hand(O)
			O.host = user
			O.focus_object(src)
		else
			user.UnarmedAttack(src, 0)

/mob/living/attack_tk(mob/living/user)
	if(user.stat)
		return

	var/dist = get_dist(src, user)
	var/psy_resist_chance = 50 + (dist * 2) + getarmor(null, "telepathy", TRUE) +  user.getarmor(BP_HEAD, "telepathy") // A chance that our target will not be affected.

	if(get_species(user) != TYCHEON)
		psy_resist_chance += 10

	if(a_intent == I_HELP)
		psy_resist_chance = 0
	else if(stat)
		psy_resist_chance = 0
	else if(lying)
		psy_resist_chance = 0

	if(!prob(psy_resist_chance))
		switch(user.a_intent)
			if(I_DISARM)
				if(world.time <= next_click)
					return
				if(next_move > world.time)
					return
				if(!(user.tk_level & TELEKINETIC_HARM_WEAKEN))
					return
				SetNextClick(max(dist, CLICK_CD_MELEE))

				to_chat(user, "<span class='warning'>You disarm [src]!</span>")
				to_chat(src, "<span class='warning'>An immense force disarms you!</span>")
				user.attack_log += text("\[[time_stamp()]\] <font color='red'>Disarmed [name] ([ckey])</font>")
				attack_log += text("\[[time_stamp()]\] <font color='orange'>Has been disarmeded by [user.name] ([user.ckey])</font>")
				msg_admin_attack("[key_name(user)] disarmed [key_name(src)]")
				drop_item(loc)
			if(I_GRAB)
				if(!(user.tk_level & TELEKINETIC_MOB_CONTROL))
					to_chat(user, "<span class='notice'>You are too weak to control [src].</span>")
					return
				var/obj/item/tk_grab/O = new(src)
				user.put_in_active_hand(O)
				O.host = user
				O.focus_object(src)
			if(I_HURT)
				if(world.time <= next_click)
					return
				if(next_move > world.time)
					return
				if(!(user.tk_level & TELEKINETIC_HARM_WEAKEN))
					to_chat(user, "<span class='notice'>You are too weak to lock [src] in place.</span>")
					return
				SetNextClick(max(dist, CLICK_CD_MELEE))

				to_chat(user, "<span class='warning'>You lock [src] in place!</span>")
				to_chat(src, "<span class='warning'>An immense force seems to lock you in place, paralyzing!</span>")
				user.attack_log += text("\[[time_stamp()]\] <font color='red'>Paralyzed [name] ([ckey])</font>")
				attack_log += text("\[[time_stamp()]\] <font color='orange'>Has been paralyzed by [user.name] ([user.ckey])</font>")
				msg_admin_attack("[key_name(user)] paralyzed [key_name(src)]")
				apply_effect(3, WEAKEN)
	else
		to_chat(host, "<span class='notice'>[src] is resisting your efforts.</span>")

/*
	This is similar to item attack_self, but applies to anything
	that you can grab with a telekinetic grab.

	It is used for manipulating things at range, for example, opening and closing closets.
	There are not a lot of defaults at this time, add more where appropriate.
*/
/atom/proc/attack_self_tk(mob/user)
	return user.do_telekinesis(get_dist(src, user))

/obj/item/attack_self_tk(mob/user)
	. = ..()
	if(.)
		attack_self(user)

/mob/attack_self_tk(mob/user)
	. = ..()
	if(.)
		var/obj/item/I
		if(user.hand)
			I = l_hand
		else
			I = r_hand

		if(I)
			I.attack_self(user)

/*
	TK Grab Item (the workhorse of old TK)

	* If you have not grabbed something, do a normal tk attack
	* If you have something, throw it at the target.  If it is already adjacent, do a normal attackby()
	* If you click what you are holding, or attack_self(), do an attack_self_tk() on it.
	* Deletes itself if it is ever not in your hand, or if you should have no access to TK.
*/
/obj/item/tk_grab
	name = "Telekinetic Grab"
	desc = "Magic."
	icon = 'icons/obj/magic.dmi'//Needs sprites
	icon_state = "2"
	flags = NOBLUDGEON | ABSTRACT | DROPDEL
	//item_state = null
	w_class = 10.0
	layer = ABOVE_HUD_LAYER
	plane = ABOVE_HUD_PLANE

	var/last_throw = 0
	var/atom/movable/focus = null
	var/mob/living/host = null

/obj/item/tk_grab/Destroy()
	focus.focused_by -= src
	return ..()

	//stops TK grabs being equipped anywhere but into hands
/obj/item/tk_grab/equipped(mob/user, slot)
	if((slot == slot_l_hand) || (slot == slot_r_hand))
		return
	qdel(src)

/obj/item/tk_grab/attack_self(mob/user)
	if(focus && !QDELING(focus))
		focus.attack_self_tk(user)
		apply_focus_overlay()

/obj/item/tk_grab/attack_hand(mob/user)
	if(focus && !QDELING(focus))
		if(ismob(focus) && user.a_intent != I_HELP)
			return
		user.SetNextMove(CLICK_CD_MELEE)
		focus.attack_hand(user)
		apply_focus_overlay()

// Since we ourselves can telekinetically do this, this is useless.
/*
/obj/item/tk_grab/MouseDrop_T(atom/A)
	if(istype(A, /obj/item/tk_grab))
		var/obj/item/tk_grab/T = A
		if(focus && T.focus)
			focus.MouseDrop_T(T.focus, host)
	else if(focus)
		focus.MouseDrop_T(A, host)
*/

/obj/item/tk_grab/afterattack(atom/target, mob/living/user, proximity, params)//TODO: go over this
	if(last_throw > world.time)
		return
	if(!host || host != user)
		qdel(src)
		return
	if(!(TK in host.mutations))
		qdel(src)
		return
	if(!(host.tk_level & TELEKINETIC_NO_VIEW_REQUIRED) && !(focus in view(host)))
		qdel(src)
		return

	var/d = get_dist(user, target)
	if(focus)
		d = max(d, get_dist(user, focus) + get_dist(target, focus)) // whichever is further

	if(d > user.tk_maxrange)
		to_chat(host, "<span class='notice'>Your mind won't reach that far.</span>")
		return
	else if(d > (user.tk_maxrange * 0.6))
		host.SetNextClick(10)
	else if(d > (user.tk_maxrange * 0.3))
		host.SetNextClick(5)
	else if(d > 0 && !proximity) // not adjacent may mean blocked by window
		host.SetNextClick(2)

	if(!host.do_telekinesis(d))
		return

	if(!focus)
		focus_object(target, user)
		return

	apply_focus_overlay()

	if(isliving(focus))
		var/mob/living/M = focus
		user.nutrition -= d * 2 // Manipulating living beings is TOUGH!

		var/psy_resist_chance = 50 + (d * 2) + M.getarmor(null, "telepathy", TRUE) +  host.getarmor(BP_HEAD, "telepathy") // A chance that our poor mob might resist our efforts to make him beat something up.

		if(user.get_species() != TYCHEON)
			psy_resist_chance += 10

		if(target == M)
			psy_resist_chance += 30 // Resisting yourself being beaten up is kinda easier.
		if(M.a_intent == I_HELP)
			psy_resist_chance = 0
		else if(M.stat)
			psy_resist_chance = 0
		else if(M == host) // Tis' a feature.
			psy_resist_chance = 0
		else if(M.lying)
			psy_resist_chance = 0

		if(prob(psy_resist_chance))
			to_chat(host, "<span class='notice'>[M] is resisting our efforts.</span>")
			return

		switch(host.a_intent)
			if(I_DISARM)
				if(world.time <= M.next_click)
					return
				if(M.next_move > world.time)
					return
				M.drop_item()

			if(I_GRAB)
				step_towards(M, target)

			if(I_HURT)
				var/obj/item/I
				if(host.hand)
					I = M.l_hand
				else
					I = M.r_hand

				var/old_zone_sel = M.zone_sel
				M.zone_sel = host.zone_sel

				if(world.time <= M.next_click)
					return
				if(M.next_move > world.time)
					return

				if(target.Adjacent(M))
					if(I)
						if(ismob(target))
							var/mob/log_M = target
							host.attack_log += text("\[[time_stamp()]\] <font color='red'>Forced [M.name] ([M.ckey]) to hit [log_M.name] ([log_M.ckey]) with [I.name]</font>")
							log_M.attack_log += text("\[[time_stamp()]\] <font color='orange'>Has been hit with [I.name] by [user.name] ([user.ckey]), who was forcing [M.name] ([M.ckey])</font>")
							msg_admin_attack("[key_name(host)] forced [key_name(M)] to hit [key_name(log_M)] with [I.name]")
						var/resolved = target.attackby(I, M, params)
						if(!resolved && target && I)
							I.afterattack(target, M, 1)
					else
						if(ismob(target))
							var/mob/log_M = target
							host.attack_log += text("\[[time_stamp()]\] <font color='red'>Forced [M.name] ([M.ckey]) to punch [log_M.name] ([log_M.ckey])</font>")
							log_M.attack_log += text("\[[time_stamp()]\] <font color='orange'>Has been punched by [user.name] ([user.ckey]), who was forcing [M.name] ([M.ckey])</font>")
							msg_admin_attack("[key_name(host)] forced [key_name(M)] to punch [key_name(log_M)]")
						M.UnarmedAttack(target, 0)
				else
					if(I)
						I.afterattack(target, M, 0)
				M.zone_sel = old_zone_sel
		last_throw = world.time + 5// So we don't allow them to spam.
		apply_focus_overlay()
		return

	else if(istype(focus, /obj/item))
		if(!istype(target, /turf) || host.a_intent == I_HURT)
			var/obj/item/I = focus
			if(target.Adjacent(focus))
				var/resolved = target.attackby(I, user, params)
				if(!resolved && target && I)
					I.afterattack(target, user, 1)
			else
				I.afterattack(target, user, 0)
			last_throw = world.time + 5 // So we don't allow them to spam.
			apply_focus_overlay()
			return

	apply_focus_overlay()

	if(!focus.anchored)
		focus.throw_at(target, 10, 1, user)
		last_throw = world.time + 1 SECOND

/obj/item/tk_grab/attack(mob/living/M, mob/living/user, def_zone)
	return

/obj/item/tk_grab/proc/focus_object(atom/movable/target, mob/living/user)
	if(!istype(target, /atom/movable))
		return
	if(focus)
		focus.focused_by -= src
	focus = target
	focus.focused_by |= src
	apply_focus_overlay()

/obj/item/tk_grab/proc/apply_focus_overlay()
	if(!focus || QDELING(focus))
		qdel(src)
		return
	update_icon()
	var/obj/effect/overlay/O = new /obj/effect/overlay(get_turf(focus))
	O.name = "sparkles"
	O.pixel_x = focus.pixel_x
	O.pixel_y = focus.pixel_y
	O.anchored = TRUE
	O.density = FALSE
	O.layer = FLY_LAYER
	O.dir = pick(cardinal)
	O.icon = 'icons/effects/effects.dmi'
	O.icon_state = "nothing"
	flick("empdisable", O)
	QDEL_IN(O, 5)
	var/obj/effect/overlay/O2 = new /obj/effect/overlay(get_turf(host))
	O2.name = "sparkles"
	O2.pixel_x = host.pixel_x
	O2.pixel_y = host.pixel_y
	O2.anchored = TRUE
	O2.density = FALSE
	O2.layer = FLY_LAYER
	O2.dir = pick(cardinal)
	O2.icon = 'icons/effects/effects.dmi'
	O2.icon_state = "nothing"
	flick("empdisable", O2)
	QDEL_IN(O2, 5)

/obj/item/tk_grab/update_icon()
	overlays.Cut()
	if(focus)
		for(var/un in focus.underlays)
			overlays += un
		overlays += icon(focus.icon, focus.icon_state)
		for(var/ov in focus.overlays)
			overlays += ov

/*Not quite done likely needs to use something thats not get_step_to
	proc/check_path()
		var/turf/ref = get_turf(src.loc)
		var/turf/target = get_turf(focus.loc)
		if(!ref || !target)	return 0
		var/distance = get_dist(ref, target)
		if(distance >= 10)	return 0
		for(var/i = 1 to distance)
			ref = get_step_to(ref, target, 0)
		if(ref != target)	return 0
		return 1
*/

//equip_to_slot_or_del(obj/item/W, slot, del_on_fail = 1)
/*
		if(istype(user, /mob/living/carbon))
			if(user:mutations & TK && get_dist(source, user) <= 7)
				if(user:get_active_hand())	return 0
				var/X = source:x
				var/Y = source:y
				var/Z = source:z

*/

