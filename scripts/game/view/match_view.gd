## Draws a match: court art, crowd, goal-zone lights, players, the disc,
## effects, the HUD and the big overlays. It only reads the sim; every bit
## of state here (animation clocks, particles, trails) is cosmetic.
extends RefCounted

const MatchSim := preload("res://scripts/sim/match_sim.gd")
const UI := preload("res://scripts/game/ui/theme.gd")
const CourtProjection := preload("res://scripts/game/view/projection.gd")
const CharacterArt := preload("res://scripts/game/view/character_art.gd")
const PixelCrowd := preload("res://scripts/game/view/pixel_crowd.gd")

const SPRITE_SCALE := 0.72
const DISC_RADIUS := 21.0
## Flying discs are drawn at waist height with their shadow on the floor
## marking the real position, so a throw passing behind a player is seen to
## go behind them rather than through their body.
const FLY_HEIGHT := 30.0
const SPECIAL_COLORS := {
	"mick": Color("ff2e88"), "tiffany": Color("2de2e6"), "pete": Color("ffd23f"),
	"steve": Color("8ee6ad"), "vanessa": Color("2de2e6"), "keno": Color("ff4d2e"),
}
## One-shot animations and how long each holds, in ticks.
const ACTION_ANIMS := {
	MatchSim.Act.THROW: ["throw", 14], MatchSim.Act.SMASH: ["throw", 14], MatchSim.Act.LOB: ["lob", 16],
	MatchSim.Act.SLAP: ["slap", 12], MatchSim.Act.DROP: ["slap", 12], MatchSim.Act.BLOCK: ["block", 14],
	MatchSim.Act.POWER_TOSS: ["block", 16], MatchSim.Act.WHIFF: ["slap", 12],
	MatchSim.Act.SPECIAL: ["special", 24], MatchSim.Act.CATCH: ["catch", 10],
}

var sim: MatchSim
var proj: CourtProjection
var arts: Array = []
var names: Array[String] = ["P1", "CPU"]
var court_bg: Texture2D
var pixel_court := false
var pixel_spectators: PixelCrowd
var crowd: Array[Texture2D] = []

var frame := 0
var shake := 0.0
var effects: Array[Dictionary] = []
var trail: Array[Vector2] = []
var trail_color := Color.WHITE
var disc_spin := 0.0
var disc_art: Texture2D
var disc_region := Rect2()
var last_pos: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var moving: Array[bool] = [false, false]
var run_phase: Array[int] = [0, 0]
var cheer_ticks := 0
var zone_flash := {}  # "side:index" -> ticks left
var overlay := {}     # current big overlay: {kind, ticks, ...}
var cutin := {}       # special-move cut-in banner
var banner_text := ""
var banner_ticks := 0
var referee: CharacterArt
var ref_anim := "idle"
var ref_ticks := 0
var ref_facing_right := true


func _init(match_sim: MatchSim, character_ids: Array, player_names: Array[String]) -> void:
	sim = match_sim
	proj = CourtProjection.new(sim.court_width(), sim.court_height())
	for id in character_ids:
		arts.append(CharacterArt.new(id))
	names = player_names
	var cid: String = sim.court.id
	var pixel_path := "res://assets/art/courts/%s_pixel.png" % cid
	pixel_court = ResourceLoader.exists(pixel_path)
	court_bg = load(pixel_path if pixel_court else "res://assets/art/courts/%s.webp" % cid)
	if pixel_court:
		pixel_spectators = PixelCrowd.new(cid)
	crowd = [load("res://assets/art/courts/%s_crowd_a.webp" % cid),
		load("res://assets/art/courts/%s_crowd_b.webp" % cid)]
	for p in sim.players:
		last_pos[p.side] = p.pos
	referee = CharacterArt.new("referee")
	disc_art = load("res://assets/art/disc/hyperdisc.png")
	disc_region = Rect2(disc_art.get_image().get_used_rect())


# --- Per-tick updates ------------------------------------------------------

func tick() -> void:
	frame += 1
	if pixel_spectators != null:
		pixel_spectators.tick()
		pixel_spectators.rally_x = clampf(float(sim.disc.pos.x)/float(sim.court_width()),0.0,1.0)
	ref_ticks += 1
	if ref_anim != "idle" and ref_ticks > 70:
		ref_anim = "idle"
	shake = maxf(0.0, shake - 0.7)
	cheer_ticks = maxi(0, cheer_ticks - 1)
	banner_ticks = maxi(0, banner_ticks - 1)
	for k in zone_flash.keys():
		zone_flash[k] -= 1
		if zone_flash[k] <= 0:
			zone_flash.erase(k)
	if not overlay.is_empty():
		overlay.ticks -= 1
		if overlay.ticks <= 0:
			overlay = {}
	if not cutin.is_empty():
		cutin.ticks -= 1
		if cutin.ticks <= 0:
			cutin = {}
	for e in effects:
		e.age += 1
	effects = effects.filter(func(e): return e.age < e.life)
	for p in sim.players:
		moving[p.side] = p.pos.distance_to(last_pos[p.side]) > 0.5
		if moving[p.side]:
			var dx: float = p.pos.x - last_pos[p.side].x
			var backwards := dx < -0.1 if p.side == MatchSim.LEFT else dx > 0.1
			run_phase[p.side] += -1 if backwards else 1
		last_pos[p.side] = p.pos
		if p.dash_ticks > 0 and frame % 3 == 0 and Settings.high_effects():
			_dust(p.pos, 0.7)
	_update_trail()


func _update_trail() -> void:
	var d := sim.disc
	if d.state == MatchSim.Disc.FLYING and sim.freeze_ticks == 0:
		disc_spin += d.vel.length() * 0.04 * signf(d.vel.x + 0.001)
		trail.push_front(proj.air_point(d.pos, FLY_HEIGHT))
		var length := 16 if d.pattern != MatchSim.Pattern.NONE else (12 if d.supersonic else 7)
		while trail.size() > length:
			trail.pop_back()
	elif d.state == MatchSim.Disc.AIR:
		disc_spin += 0.25
		trail.clear()
	else:
		trail.clear()


## Turns sim events into effects and overlays. Returns nothing; sounds and
## rumble are handled by the caller from the same events.
func handle(e: Dictionary) -> void:
	if pixel_spectators != null:
		pixel_spectators.handle(e)
	var s := Settings.shake_scale()
	match e.type:
		"ready":
			overlay = {"kind": "ready", "ticks": int(sim.cfg.match.ready_ticks), "set": e.set}
		"go":
			overlay = {"kind": "go", "ticks": 45}
			_referee("lob", sim.server == MatchSim.LEFT)
		"throw":
			trail_color = Color("ffb347") if e.supersonic else Color(1, 1, 1, 0.7)
			if e.smash:
				trail_color = Color("ff5a3c")
			if e.supersonic or e.smash:
				_burst(sim.disc.pos, Color("fff3b0"), 0.8)
		"slap":
			trail_color = UI.CYAN
			_burst(sim.disc.pos, Color.WHITE, 1.0)
			shake = maxf(shake, 4.0 * s)
		"special":
			var id: String = arts[e.side].id
			trail_color = SPECIAL_COLORS.get(id, UI.PINK)
			if e.ex:
				trail_color = Color.WHITE
			cutin = {"side": e.side, "name": e.name, "ex": e.ex, "ticks": 70}
			_burst(sim.disc.pos, trail_color, 1.8)
			shake = maxf(shake, 9.0 * s)
		"catch":
			var power: float = e.speed / float(sim.cfg.throw.base_speed)
			if e.special:
				_burst(sim.players[e.side].pos, Color.WHITE, 2.2)
				shake = maxf(shake, 12.0 * s)
			elif power > 1.2:
				_burst(sim.players[e.side].pos, Color.WHITE, 1.0 + power * 0.3)
				shake = maxf(shake, power * 3.0 * s)
			else:
				_ring(sim.players[e.side].pos, Color(1, 1, 1, 0.8), 0.6)
		"block", "power_toss":
			_burst(sim.disc.pos, UI.YELLOW, 1.1)
		"drop":
			_ring(sim.disc.pos, UI.CYAN, 0.8)
		"bounce", "barrier":
			_ring(sim.disc.pos, Color(1, 1, 1, 0.7), 0.45)
		"land":
			_dust(sim.players[e.side].pos, 1.0)
		"jump":
			_dust(sim.players[e.side].pos, 0.8)
		"charge_ready":
			_ring(sim.players[e.side].pos, UI.YELLOW, 1.4)
			banner(sim.players[e.side], "CHARGED!")
		"ex_ready":
			pass
		"buzzsaw":
			_burst(sim.disc.pos, UI.ORANGE, 1.2)
			trail_color = UI.ORANGE
		"point":
			cheer_ticks = 140
			shake = maxf(shake, 14.0 * s)
			var where: Vector2 = e.pos
			_burst(where, UI.ZONE_5 if e.points == 5 else UI.ZONE_3, 2.6)
			if e.reason == "goal" or e.reason == "carried":
				var defender := 1 - int(e.side)
				var zones := sim.zones_for(defender)
				var t := clampf(where.y / sim.court_height(), 0.0, 1.0)
				for i in zones.size():
					if t >= float(zones[i].from) and t <= float(zones[i].to):
						zone_flash["%d:%d" % [defender, i]] = 70
			_referee("win", e.side == MatchSim.LEFT)
			overlay = {"kind": "point", "ticks": int(sim.cfg.match.point_pause_ticks), "side": e.side,
				"points": e.points, "reason": e.reason, "scores": e.scores}
		"set_end":
			cheer_ticks = 200
			overlay = {"kind": "set", "ticks": int(sim.cfg.match.set_pause_ticks), "scores": e.scores,
				"sets": e.sets_won, "set": e.set}
		"match_over":
			cheer_ticks = 400


func _referee(anim: String, facing_right: bool) -> void:
	ref_anim = anim
	ref_ticks = 0
	ref_facing_right = facing_right


func banner(p: MatchSim.PlayerState, text: String) -> void:
	banner_text = text
	banner_ticks = 50
	_float_text(p.pos, text, UI.YELLOW)


func _burst(pos: Vector2, color: Color, size: float) -> void:
	effects.append({"type": "burst", "pos": pos, "age": 0, "life": 16, "color": color, "size": size,
		"rot": randf() * TAU})


func _ring(pos: Vector2, color: Color, size: float) -> void:
	effects.append({"type": "ring", "pos": pos, "age": 0, "life": 18, "color": color, "size": size})


func _dust(pos: Vector2, size: float) -> void:
	for i in 3 if Settings.high_effects() else 1:
		effects.append({"type": "dust", "pos": pos + Vector2(randf_range(-14, 14), randf_range(-6, 6)),
			"age": 0, "life": 22, "size": size * randf_range(0.7, 1.2), "drift": randf_range(-0.6, 0.6)})


func _float_text(pos: Vector2, text: String, color: Color) -> void:
	effects.append({"type": "text", "pos": pos, "age": 0, "life": 50, "text": text, "color": color})


# --- Drawing ---------------------------------------------------------------

func draw(ci: CanvasItem) -> void:
	var off := Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) * 0.6
	_current_offset = off
	ci.draw_set_transform(off)
	if pixel_spectators == null:
		ci.draw_texture_rect(court_bg, Rect2(Vector2.ZERO, proj.screen), false)
	_draw_crowd(ci)
	_draw_goal_lights(ci)
	_draw_markers(ci)
	_draw_shadows(ci)
	_draw_world(ci, off)
	_draw_referee(ci)
	_draw_trail(ci)
	_draw_effects(ci, off)
	ci.draw_set_transform(Vector2.ZERO)
	_draw_hud(ci)
	_draw_overlays(ci)


func _draw_crowd(ci: CanvasItem) -> void:
	# Pixel spectators belong to the new environment; the old 3D crowd
	# overlay would obscure its terraces and lighting.
	if pixel_court:
		pixel_spectators.draw(ci,_current_offset)
		return
	var cheering := cheer_ticks > 0
	var tex := crowd[1] if cheering and (frame / 7) % 2 == 0 else crowd[0]
	var bob := sin(frame * (0.5 if cheering else 0.06)) * (5.0 if cheering else 1.5)
	ci.draw_texture(tex, Vector2(0, bob))


func _draw_goal_lights(ci: CanvasItem) -> void:
	var pulse := 0.75 + 0.25 * sin(frame * 0.12)
	for side in [0, 1]:
		var zones := sim.zones_for(side)
		for i in zones.size():
			var z: Dictionary = zones[i]
			var h := sim.court_height()
			var strip := proj.goal_strip(side, float(z.from) * h + 6.0, float(z.to) * h - 6.0)
			var base := UI.ZONE_5 if int(z.points) == 5 else UI.ZONE_3
			var key := "%d:%d" % [side, i]
			var color := Color(base, pulse)
			if zone_flash.has(key) and (zone_flash[key] / 4) % 2 == 0:
				color = Color.WHITE
			ci.draw_colored_polygon(strip, Color(color, 0.35))
			var inner := proj.goal_strip(side, float(z.from) * h + 14.0, float(z.to) * h - 14.0, 0.3)
			ci.draw_colored_polygon(inner, color)
			var mid := (inner[0] + inner[2]) / 2.0
			UI.text(ci, mid + Vector2(0, 14), str(int(z.points)), 38, Color.WHITE, UI.display)


func _draw_markers(ci: CanvasItem) -> void:
	var d := sim.disc
	if d.state != MatchSim.Disc.AIR or sim.phase == MatchSim.Phase.MATCH_OVER:
		return
	var target := proj.floor_point(d.air_to)
	var t := float(d.air_tick) / float(d.air_flight)
	var pulse := 1.0 + sin(frame * 0.4) * 0.08
	var color := UI.ZONE_5 if d.air_kind != MatchSim.Air.REF else UI.CYAN
	# Light column where it will land, fading in as it falls (charge spot).
	var col_h := 260.0 * (0.4 + t * 0.6)
	var col := PackedVector2Array([target + Vector2(-30, 0), target + Vector2(30, 0),
		target + Vector2(18, -col_h), target + Vector2(-18, -col_h)])
	ci.draw_colored_polygon(col, Color(color, 0.12 + 0.12 * t))
	ci.draw_set_transform(target + _current_offset, 0.0, Vector2(1.0, proj.floor_y / proj.scale))
	ci.draw_arc(Vector2.ZERO, 40 * pulse, 0, TAU, 40, color, 5.0)
	ci.draw_arc(Vector2.ZERO, 24 * pulse, 0, TAU, 32, Color(color, 0.7), 3.0)
	for p in sim.players:
		if p.charge > 0:
			var need := float(sim.cfg.charge.ticks_needed)
			var amount := clampf(p.charge / need, 0.0, 1.0)
			ci.draw_arc(Vector2.ZERO, 52, -PI / 2, -PI / 2 + TAU * amount, 48, UI.YELLOW, 8.0)
	ci.draw_set_transform(_current_offset)


func _draw_shadows(ci: CanvasItem) -> void:
	for p in sim.players:
		var g := proj.floor_point(p.pos)
		var s := 1.0 - clampf(p.z / 200.0, 0.0, 0.5)
		_ellipse(ci, g, 34 * s, 12 * s, Color(0.1, 0.0, 0.2, 0.35))
		if Settings.show_catch_zones:
			_catch_zone(ci, p)
	var d := sim.disc
	if sim.phase != MatchSim.Phase.MATCH_OVER and d.state != MatchSim.Disc.HELD:
		var g := proj.floor_point(d.pos)
		var s := 1.0 - clampf(d.z / 400.0, 0.0, 0.6)
		_ellipse(ci, g, DISC_RADIUS * s, DISC_RADIUS * 0.45 * s, Color(0.1, 0.0, 0.2, 0.4))


## The catch circle drawn on the floor (Options > Graphics > Show catch zones).
func _catch_zone(ci: CanvasItem, p: MatchSim.PlayerState) -> void:
	var g := proj.floor_point(p.pos)
	var r := float(sim.cfg.player.catch_radius) * proj.scale
	var c := UI.P1 if p.side == MatchSim.LEFT else UI.P2
	ci.draw_set_transform(g + _current_offset, 0.0, Vector2(1.0, proj.floor_y / proj.scale))
	ci.draw_circle(Vector2.ZERO, r, Color(c, 0.18))
	ci.draw_arc(Vector2.ZERO, r, 0, TAU, 48, Color(c, 0.9), 3.0)
	ci.draw_set_transform(_current_offset)


func _ellipse(ci: CanvasItem, centre: Vector2, rx: float, ry: float, color: Color) -> void:
	ci.draw_set_transform(centre + _current_offset, 0.0, Vector2(1.0, ry / rx))
	ci.draw_circle(Vector2.ZERO, rx, color)
	ci.draw_set_transform(_current_offset)


var _current_offset := Vector2.ZERO


func _draw_world(ci: CanvasItem, off: Vector2) -> void:
	_current_offset = off
	# Depth-sort players, barriers and the airborne/flying disc by floor y.
	var items: Array = []
	for p in sim.players:
		items.append({"y": p.pos.y, "kind": "player", "p": p})
	for b in sim.barriers:
		items.append({"y": b.y, "kind": "barrier", "b": b})
	var d := sim.disc
	if sim.phase != MatchSim.Phase.MATCH_OVER and sim.phase != MatchSim.Phase.READY \
			and d.state != MatchSim.Disc.HELD:
		items.append({"y": d.pos.y + 0.1, "kind": "disc"})
	items.sort_custom(func(a, b): return a.y < b.y)
	for it in items:
		match it.kind:
			"player":
				_draw_player(ci, it.p)
			"barrier":
				_draw_barrier(ci, it.b)
			"disc":
				var lift := FLY_HEIGHT if d.state == MatchSim.Disc.FLYING else d.z
				_draw_disc(ci, proj.air_point(d.pos, lift), d.z)


func _draw_referee(ci: CanvasItem) -> void:
	var ground := proj.floor_point(Vector2(sim.net_x() + 4.0, sim.court_height() + 58.0))
	var f := referee.frame_for(ref_anim, ref_ticks if ref_anim != "idle" else frame)
	_ellipse(ci, ground, 30, 10, Color(0.1, 0.0, 0.2, 0.35))
	referee.draw(ci, f, ground, ref_facing_right, SPRITE_SCALE * 0.9)


func _anim_for(p: MatchSim.PlayerState) -> Array:
	if sim.phase == MatchSim.Phase.MATCH_OVER:
		return ["win" if sim.winner == p.side else "lose", frame]
	if p.knock_ticks > 0:
		return ["knock", frame]
	if ACTION_ANIMS.has(p.action) and p.action_ticks < ACTION_ANIMS[p.action][1]:
		var a: Array = ACTION_ANIMS[p.action]
		if not (p.action == MatchSim.Act.CATCH and not p.holding):
			return [a[0], p.action_ticks]
	if p.z > 0.0:
		# Follow physical flight progress; don't snap from a frozen takeoff to landing.
		var flight := clampf((float(sim.cfg.player.jump_velocity) - p.vz) \
			/ (2.0 * float(sim.cfg.player.jump_velocity)), 0.0, 1.0)
		return ["jump", mini(19, int(flight * 20.0))]
	if p.recovery_ticks > 0 and p.action == MatchSim.Act.JUMP:
		return ["jump", 19]
	if p.dash_ticks > 0:
		return ["dash", int(sim.cfg.player.dash_ticks) - p.dash_ticks + 4]
	if p.holding:
		return ["hold", frame]
	if p.charge > 0:
		return ["charge", frame]
	if moving[p.side]:
		return ["run", run_phase[p.side]]
	return ["idle", frame]


func _draw_player(ci: CanvasItem, p: MatchSim.PlayerState) -> void:
	var art = arts[p.side]
	var anim := _anim_for(p)
	var f: int = art.frame_for(anim[0], anim[1])
	var ground := proj.air_point(p.pos, p.z)
	var facing_right := p.side == MatchSim.LEFT
	var tint := Color.WHITE
	if p.charged or (p.holding and sim.ex_full(p.side)):
		var glow := 0.5 + 0.5 * sin(frame * 0.35)
		var aura := UI.YELLOW if p.charged else Color.WHITE
		ci.draw_circle(ground - Vector2(0, 70), 70 + glow * 10, Color(aura, 0.18 + glow * 0.12))
	if p.knock_ticks > 0 and (frame / 2) % 2 == 0:
		tint = Color(1.5, 1.5, 1.5)
	art.draw(ci, f, ground, facing_right, SPRITE_SCALE, tint)
	if p.holding and sim.disc.owner == p.side and sim.phase != MatchSim.Phase.MATCH_OVER \
			and sim.phase != MatchSim.Phase.POINT_PAUSE and sim.phase != MatchSim.Phase.SET_PAUSE:
		var hand: Vector2 = art.point(f, "hand") * SPRITE_SCALE
		if not facing_right:
			hand.x = -hand.x
		_draw_disc(ci, ground + hand, 0.0, 0.75)
		_draw_hold_timer(ci, p, ground + art.point(f, "head") * SPRITE_SCALE)
	# Player tag over the head.
	var head: Vector2 = art.point(f, "head") * SPRITE_SCALE
	var tip := ground + Vector2(0, head.y - (44 if p.holding else 26))
	var c := UI.P1 if p.side == 0 else UI.P2
	ci.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-11, -15), tip + Vector2(11, -15)]), c)
	UI.text(ci, tip + Vector2(0, -20), names[p.side], 20, c, UI.ui, 4)


func _draw_hold_timer(ci: CanvasItem, p: MatchSim.PlayerState, head: Vector2) -> void:
	var limit := float(sim.cfg.player.serve_hold_limit_ticks if p.serving else sim.cfg.player.hold_limit_ticks)
	var left := clampf(1.0 - p.hold_ticks / limit, 0.0, 1.0)
	var r := Rect2(head + Vector2(-34, -30), Vector2(68, 8))
	ci.draw_rect(r.grow(2), UI.INK)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x * left, r.size.y)), UI.YELLOW if left > 0.3 else UI.ZONE_5)


func _draw_disc(ci: CanvasItem, centre: Vector2, z: float, scale := 1.0) -> void:
	var d := sim.disc
	var grow := scale * (1.0 + clampf(z, 0.0, 400.0) / 230.0)
	var r := DISC_RADIUS * grow
	var squash := 0.55 + clampf(z / 300.0, 0.0, 0.4)
	var rim := Color.WHITE
	var core := UI.PINK
	if d.pattern != MatchSim.Pattern.NONE:
		rim = trail_color.lightened(0.4)
		core = trail_color
	elif d.supersonic and d.state == MatchSim.Disc.FLYING:
		core = UI.ORANGE
	if disc_art != null:
		var tint := Color.WHITE
		if d.pattern != MatchSim.Pattern.NONE or (d.supersonic and d.state == MatchSim.Disc.FLYING):
			tint = core.lerp(Color.WHITE, 0.55)
		# Extrude the rim toward the camera. Depth is in screen pixels, so
		# spinning the face never rotates the sidewall or its lighting.
		var depth := maxf(2.0, 4.0 * grow * (1.0 - squash * 0.45))
		var face_rect := Rect2(Vector2(-r-4,-r-4),Vector2.ONE*(r+4)*2)
		var transform := Transform2D(disc_spin, Vector2.ZERO)
		for layer in [1.0, 0.65, 0.3]:
			var side_tint := Color("302044").lerp(Color("a692bc"), 1.0-layer)
			ci.draw_set_transform_matrix(Transform2D(0.0, Vector2(1.0,squash),0.0,centre+_current_offset+Vector2(0,depth*layer)) * transform)
			ci.draw_texture_rect_region(disc_art,face_rect,disc_region,side_tint)
		# Rotate the markings inside the squashed plane.
		ci.draw_set_transform_matrix(Transform2D(0.0, Vector2(1.0,squash),0.0,centre+_current_offset) * transform)
		ci.draw_texture_rect_region(disc_art,face_rect,disc_region,tint)
		# A short upper-left bevel glint stays aligned with arena light.
		ci.draw_set_transform(centre+_current_offset,0.0,Vector2(1.0,squash))
		ci.draw_arc(Vector2.ZERO,r-2,PI*1.20,PI*1.40,5,Color(1.0,0.98,0.88,0.75),maxf(1.0,1.0*grow),false)
		ci.draw_set_transform(_current_offset)
		return
	ci.draw_set_transform(centre + _current_offset, 0.0, Vector2(1.0, squash))
	ci.draw_circle(Vector2.ZERO, r + 4, UI.INK)
	ci.draw_circle(Vector2.ZERO, r, rim)
	ci.draw_circle(Vector2.ZERO, r * 0.62, core)
	ci.draw_circle(Vector2.ZERO, r * 0.36, rim)
	var a := disc_spin
	ci.draw_line(Vector2(cos(a), sin(a)) * r * 0.1, Vector2(cos(a), sin(a)) * r * 0.85, Color(1, 1, 1, 0.9), 3.0)
	ci.draw_set_transform(_current_offset)


func _draw_trail(ci: CanvasItem) -> void:
	if trail.size() < 2:
		return
	var d := sim.disc
	var special := d.pattern != MatchSim.Pattern.NONE
	var width := 34.0 if special else (22.0 if d.supersonic else 10.0)
	for i in range(trail.size() - 1, 0, -1):
		var t := 1.0 - float(i) / trail.size()
		var w := width * t
		ci.draw_line(trail[i], trail[i - 1], Color(trail_color, 0.25 * t), w * 1.8)
		ci.draw_line(trail[i], trail[i - 1], Color(trail_color, 0.8 * t), w)
		if special or d.supersonic:
			ci.draw_line(trail[i], trail[i - 1], Color(1, 1, 1, 0.9 * t), w * 0.35)


func _draw_barrier(ci: CanvasItem, b: Vector3) -> void:
	var base := proj.floor_point(Vector2(b.x, b.y))
	var top := proj.scenery_point(Vector2(b.x, b.y), 46.0)
	var rx := b.z * proj.scale
	var ry := rx * (proj.floor_y / proj.scale) * 0.55
	var cid: String = sim.court.id
	var body := Color("c9c2d6") if cid == "concrete" else Color("d0683a")
	var stripe := UI.YELLOW if cid == "concrete" else Color("2e9e4f")
	ci.draw_rect(Rect2(Vector2(base.x - rx, top.y), Vector2(rx * 2, base.y - top.y)), body)
	_ellipse_abs(ci, base, rx, ry, body.darkened(0.25))
	for k in 3:
		var y := lerpf(top.y, base.y, (k + 0.5) / 3.0)
		ci.draw_rect(Rect2(base.x - rx, y - 4, rx * 2, 8), stripe)
	ci.draw_rect(Rect2(Vector2(base.x - rx, top.y), Vector2(rx * 2, base.y - top.y)), UI.INK, false, 3.0)
	_ellipse_abs(ci, top, rx, ry, body.lightened(0.15))
	if cid == "clay":
		_ellipse_abs(ci, top - Vector2(0, 10), rx * 0.9, ry * 1.4, Color("37a85a"))


func _ellipse_abs(ci: CanvasItem, centre: Vector2, rx: float, ry: float, color: Color) -> void:
	ci.draw_set_transform(centre + _current_offset, 0.0, Vector2(1.0, ry / rx))
	ci.draw_circle(Vector2.ZERO, rx + 2.5, UI.INK)
	ci.draw_circle(Vector2.ZERO, rx, color)
	ci.draw_set_transform(_current_offset)


func _draw_effects(ci: CanvasItem, off: Vector2) -> void:
	for e in effects:
		var t: float = float(e.age) / float(e.life)
		match e.type:
			"burst":
				var c := proj.air_point(e.pos, 20)
				var r: float = (30.0 + 70.0 * t) * e.size
				UI.starburst(ci, c, r * 0.45, r, 10, Color(e.color, 1.0 - t), e.rot)
				UI.starburst(ci, c, r * 0.25, r * 0.6, 10, Color(1, 1, 1, 1.0 - t), e.rot + 0.3)
			"ring":
				var c := proj.floor_point(e.pos)
				ci.draw_set_transform(c + off, 0.0, Vector2(1.0, 0.5))
				ci.draw_arc(Vector2.ZERO, (20 + 70 * t) * e.size, 0, TAU, 36, Color(e.color, 1.0 - t), 5.0 * (1.0 - t) + 1.0)
				ci.draw_set_transform(off)
			"dust":
				var c := proj.floor_point(e.pos) + Vector2(e.drift * e.age * 2.0, -t * 26.0)
				ci.draw_circle(c, (8 + 16 * t) * e.size, Color(1, 0.95, 0.9, 0.5 * (1.0 - t)))
			"text":
				var c := proj.air_point(e.pos, 150 + t * 60)
				UI.text(ci, c, e.text, 34, Color(e.color, 1.0 - t * t), UI.display)


# --- HUD -------------------------------------------------------------------

func _draw_hud(ci: CanvasItem) -> void:
	# Scoreboard, top centre: P1 score | time | P2 score.
	var board := Rect2(Vector2(690, 10), Vector2(540, 118))
	UI.slant_panel(ci, Rect2(board.position + Vector2(6, 6), board.size), Color(0, 0, 0, 0.5), Color.TRANSPARENT, 26)
	UI.slant_panel(ci, board, Color("120826"), UI.CYAN, 26, 4)
	UI.text(ci, Vector2(960, 40), "SET %d" % sim.set_number if not sim.sudden_death else "SUDDEN DEATH",
		22, UI.CYAN, UI.ui, 3)
	for side in [0, 1]:
		var x := 820.0 if side == 0 else 1100.0
		UI.text(ci, Vector2(x, 112), "%02d" % sim.scores[side], 84, UI.YELLOW, UI.ui, 6)
		for i in int(sim.cfg.match.sets_to_win):
			var dot := Vector2(x - 18 + i * 36, 136)
			ci.draw_circle(dot, 11, UI.INK)
			ci.draw_circle(dot, 8, UI.P1 if sim.sets_won[side] > i else Color(0.25, 0.2, 0.35))
	var seconds := ceili(maxi(sim.set_ticks_left, 0) / 60.0)
	var time_text := "--" if sim.sudden_death else "%02d" % seconds
	var tcol := UI.ZONE_5 if not sim.sudden_death and seconds <= 10 and (frame / 15) % 2 == 0 else Color.WHITE
	UI.text(ci, Vector2(960, 76), "TIME", 18, UI.DIM, UI.ui, 3)
	UI.text(ci, Vector2(960, 114), time_text, 50, tcol, UI.ui, 5)

	# Portraits and names in the top corners.
	for side in [0, 1]:
		var art = arts[side]
		var left: bool = side == 0
		var frame_rect := Rect2(Vector2(18 if left else 1902 - 300, 12), Vector2(300, 116))
		var c := UI.P1 if left else UI.P2
		UI.slant_panel(ci, frame_rect, Color("120826"), c, 24, 4)
		var face := Rect2(frame_rect.position + Vector2(10 if left else 300 - 130, 6), Vector2(120, 104))
		ci.draw_texture_rect_region(art.portrait, face, art.portrait_face)
		# Text box between the portrait and the panel's slanted edge.
		var name_x := frame_rect.position.x + (140.0 if left else 30.0)
		var room := 128.0
		var tag: String = names[side]
		var tag_size := UI.fit_size(tag, 34, room, UI.display)
		UI.text(ci, Vector2(name_x, frame_rect.position.y + 46), tag, tag_size, c, UI.display, 4,
			HORIZONTAL_ALIGNMENT_LEFT)
		var who: Dictionary = sim.players[side].character
		var who_name := str(who.name).to_upper()
		UI.text(ci, Vector2(name_x, frame_rect.position.y + 88), who_name, UI.fit_size(who_name, 20, room, UI.ui),
			Color.WHITE, UI.ui, 3, HORIZONTAL_ALIGNMENT_LEFT)

	# Power throw meters along the bottom.
	for side in [0, 1]:
		var left: bool = side == 0
		var r := Rect2(Vector2(40 if left else 1880 - 420, 1032), Vector2(420, 26))
		var amount := float(sim.players[side].ex) / float(sim.cfg.ex.max)
		var full: bool = amount >= 1.0
		var col := UI.YELLOW if not full else (Color.WHITE if (frame / 6) % 2 == 0 else UI.PINK)
		UI.meter(ci, r, amount, col, 10)
		var label := "POWER THROW READY!" if full else "POWER THROW"
		UI.text(ci, Vector2(r.position.x + (0.0 if left else r.size.x), r.position.y - 8), label, 28,
			col if full else Color.WHITE, UI.display, 4,
			HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_overlays(ci: CanvasItem) -> void:
	if not cutin.is_empty():
		_draw_cutin(ci)
	if overlay.is_empty():
		return
	match overlay.kind:
		"ready":
			var total := float(sim.cfg.match.ready_ticks)
			var elapsed: float = total - float(overlay.ticks)
			var text := ("SET %d" % overlay.set) if elapsed < total * 0.55 else "READY"
			if sim.sudden_death:
				text = "SUDDEN DEATH" if elapsed < total * 0.55 else "READY"
			_big_banner(ci, text, UI.CYAN, elapsed)
		"go":
			_big_banner(ci, "GO!", UI.YELLOW, 45 - overlay.ticks)
		"point":
			_draw_score_overlay(ci)
		"set":
			_draw_set_overlay(ci)


func _big_banner(ci: CanvasItem, text: String, color: Color, age: float) -> void:
	var pop := 1.0 + maxf(0.0, 1.0 - age / 8.0) * 0.5
	ci.draw_rect(Rect2(0, 470, 1920, 140), Color(0.05, 0.0, 0.12, 0.55))
	ci.draw_rect(Rect2(0, 470, 1920, 6), color)
	ci.draw_rect(Rect2(0, 604, 1920, 6), color)
	UI.text(ci, Vector2(960, 590), text, int(130 * pop), color, UI.display, 10, HORIZONTAL_ALIGNMENT_CENTER,
		-1.0, true)


func _draw_score_overlay(ci: CanvasItem) -> void:
	var total := float(sim.cfg.match.point_pause_ticks)
	var age: float = total - float(overlay.ticks)
	if age < 18:
		var label := "GOAL!" if overlay.reason == "goal" else ("MISS!" if overlay.reason == "miss" else "PUSHED IN!")
		_big_banner(ci, label, UI.YELLOW if overlay.reason == "goal" else UI.PINK, age)
		return
	var s: Array = overlay.scores
	var pop := 1.0 + maxf(0.0, 1.0 - (age - 18) / 6.0) * 0.4
	var size := int(220 * pop)
	ci.draw_rect(Rect2(0, 0, 1920, 1080), Color(0.05, 0.0, 0.12, 0.25))
	UI.text(ci, Vector2(960, 640), "%02d - %02d" % [s[0], s[1]], size, UI.YELLOW, UI.ui, 14,
		HORIZONTAL_ALIGNMENT_CENTER, -1.0, true)
	var badge_x := 560.0 if overlay.side == 0 else 1360.0
	UI.starburst(ci, Vector2(badge_x, 760), 60, 96, 12, UI.ZONE_5 if overlay.points == 5 else UI.ZONE_3,
		frame * 0.02)
	UI.text(ci, Vector2(badge_x, 778), "+%d" % overlay.points, 64, Color.WHITE, UI.display, 6)
	UI.text(ci, Vector2(badge_x, 822), "PTS", 30, Color.WHITE, UI.display, 4)


func _draw_set_overlay(ci: CanvasItem) -> void:
	var s: Array = overlay.scores
	var sets: Array = overlay.sets
	ci.draw_rect(Rect2(0, 0, 1920, 1080), Color(0.05, 0.0, 0.12, 0.45))
	UI.text(ci, Vector2(960, 330), "SET %d" % overlay.set, 90, UI.CYAN, UI.display, 8)
	UI.text(ci, Vector2(960, 560), "%02d - %02d" % [s[0], s[1]], 200, UI.YELLOW, UI.ui, 14,
		HORIZONTAL_ALIGNMENT_CENTER, -1.0, true)
	UI.text(ci, Vector2(960, 700), "SET COUNTS", 50, Color.WHITE, UI.display, 6)
	UI.text(ci, Vector2(760, 860), str(sets[0]), 160, UI.P1, UI.ui, 12)
	UI.text(ci, Vector2(1160, 860), str(sets[1]), 160, UI.P2, UI.ui, 12)


func _draw_cutin(ci: CanvasItem) -> void:
	var age := 70 - int(cutin.ticks)
	var slide := clampf(age / 8.0, 0.0, 1.0)
	var out := clampf((cutin.ticks - 0) / 10.0, 0.0, 1.0)
	var left: bool = cutin.side == 0
	var c: Color = Color.WHITE if cutin.ex else SPECIAL_COLORS.get(arts[cutin.side].id, UI.PINK)
	var y := 330.0
	var w := 1920.0 * slide
	var x0 := 0.0 if left else 1920.0 - w
	var band := PackedVector2Array([Vector2(x0, y + 40), Vector2(x0 + w, y), Vector2(x0 + w, y + 190),
		Vector2(x0, y + 230)])
	ci.draw_colored_polygon(band, Color(0.06, 0.0, 0.14, 0.82 * out))
	ci.draw_polyline(PackedVector2Array([band[0], band[1]]), Color(c, out), 6)
	ci.draw_polyline(PackedVector2Array([band[3], band[2]]), Color(c, out), 6)
	if slide >= 1.0:
		var art = arts[cutin.side]
		var px := 220.0 if left else 1700.0
		var face := Rect2(Vector2(px - 150, y - 20), Vector2(300, 260))
		ci.draw_texture_rect_region(art.portrait, face, art.portrait_bust, Color(1, 1, 1, out))
		var label: String = ("POWER " if cutin.ex else "") + str(cutin.name) + "!"
		UI.text(ci, Vector2(1030 if left else 890, y + 150), label, 110, Color(c, out), UI.display, 9,
			HORIZONTAL_ALIGNMENT_CENTER, -1.0, true)
