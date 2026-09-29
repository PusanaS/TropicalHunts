extends RefCounted
# Shared helpers for fruit enemies other than the minion (the boss and its shockwave).
# They use the minion's stand-in attack table and share its "player was just hurt" cooldown,
# so the boss and the minions can't hit the player back to back.

const FruitMinion := preload("res://code/design/fruit_minion.gd")


# the player's attack that is hitting `box` right now, as {"damage", "push"}; empty if none
static func player_attack_hitting(player: CharacterBody2D, state_names: Array, box: Rect2) -> Dictionary:
	var hit = FruitMinion.PLAYER_HITS.get(state_names[player.state])
	var pt: float = player.state_time
	if hit == null or pt < hit["active"].x or pt > hit["active"].y:
		return {}
	var pf: int = player.facing
	var r: Rect2 = hit["rect"]
	if pf < 0:
		r.position.x = -r.position.x - r.size.x
	r.position += player.global_position
	if not r.intersects(box):
		return {}
	var dir := float(pf)
	if hit.get("all_around", false):
		dir = signf(box.get_center().x - player.global_position.x)
		if dir == 0.0:
			dir = pf
	return {"damage": hit["damage"], "push": Vector2(dir * hit["push"].x, hit["push"].y)}


# hurts the player if `box` touches them: red flash + push away from from_x. False if it didn't.
static func hurt_player(player: CharacterBody2D, box: Rect2, from_x: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now < FruitMinion._player_safe_until:
		return false
	if not box.intersects(Rect2(player.global_position + FruitMinion.PLAYER_BOX.position, FruitMinion.PLAYER_BOX.size)):
		return false
	FruitMinion._player_safe_until = now + FruitMinion.PLAYER_SAFE_TIME
	var dir := signf(player.global_position.x - from_x)
	if dir == 0.0:
		dir = 1.0
	player.velocity = Vector2(dir * FruitMinion.PLAYER_PUSH.x, FruitMinion.PLAYER_PUSH.y)
	# no player health yet: flash red instead
	player.modulate = Color(1, 0.35, 0.35)
	player.create_tween().tween_property(player, "modulate", Color.WHITE, FruitMinion.PLAYER_SAFE_TIME)
	return true


# nothing can hurt the player for this long (e.g. during a cinematic)
static func protect_player(seconds: float):
	var until := Time.get_ticks_msec() / 1000.0 + seconds
	FruitMinion._player_safe_until = maxf(FruitMinion._player_safe_until, until)


# tiny freeze on impact. The reset is bound to Engine, so it still runs if the enemy is freed.
static func hitstop(tree: SceneTree, time: float):
	Engine.time_scale = 0.05
	var t := tree.create_timer(time, true, false, true)
	t.timeout.connect(Callable(Engine, "set").bind("time_scale", 1.0))
