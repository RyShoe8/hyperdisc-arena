## Shared look for every screen: the 80s Outrun palette, fonts, outlined
## text, slanted neon panels and the animated sunset-grid background.
## Everything draws onto whichever CanvasItem is passed in.
extends RefCounted

const INK := Color("1a0f2e")
const WHITE := Color("f4f1ff")
const PINK := Color("ff2e88")
const CYAN := Color("2de2e6")
const YELLOW := Color("ffd23f")
const ORANGE := Color("ff8c42")
const PURPLE := Color("7b2cbf")
const DEEP := Color("1b0b33")
const NIGHT := Color("0d0620")
const ZONE_3 := Color("ffd23f")
const ZONE_5 := Color("ff2e63")
const P1 := Color("ff2e88")
const P2 := Color("2de2e6")
const DIM := Color("b9a8d9")

static var display: Font
static var ui: Font
static var future: Font


static func load_fonts() -> void:
	if display != null:
		return
	display = load("res://assets/fonts/Bangers-Regular.ttf")
	ui = load("res://assets/fonts/RussoOne-Regular.ttf")
	future = load("res://assets/fonts/kenney_future.ttf")


## Text with a thick ink outline and optional drop shadow. With width < 0,
## `align` anchors the text at pos.x (left edge, centre or right edge);
## otherwise it is aligned inside a box of that width starting at pos.x.
static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, color: Color,
		font: Font = null, outline := 0, align := HORIZONTAL_ALIGNMENT_CENTER, width := -1.0,
		shadow := false) -> void:
	var f := font if font != null else ui
	var w := width
	var x := pos.x
	if w < 0.0:
		var tw := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if align == HORIZONTAL_ALIGNMENT_CENTER:
			x -= tw / 2.0
		elif align == HORIZONTAL_ALIGNMENT_RIGHT:
			x -= tw
		align = HORIZONTAL_ALIGNMENT_LEFT
		w = tw + 4.0
	var o := outline if outline > 0 else maxi(2, size / 9)
	if shadow:
		ci.draw_string_outline(f, Vector2(x + size * 0.06, pos.y + size * 0.08), s, align, w, size, o,
			Color(0, 0, 0, color.a * 0.55))
	ci.draw_string_outline(f, Vector2(x, pos.y), s, align, w, size, o, Color(INK, color.a))
	ci.draw_string(f, Vector2(x, pos.y), s, align, w, size, color)


static func text_width(s: String, size: int, font: Font = null) -> float:
	var f := font if font != null else ui
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## The largest size (up to `size`) at which `s` fits in `max_width`.
static func fit_size(s: String, size: int, max_width: float, font: Font = null) -> int:
	var w := text_width(s, size, font)
	if w <= max_width:
		return size
	return maxi(10, int(floor(size * max_width / w)))


## Parallelogram panel slanted like 80s sports graphics.
static func slant_panel(ci: CanvasItem, rect: Rect2, fill: Color, edge := Color.TRANSPARENT,
		slant := 18.0, border := 4.0) -> void:
	var p := rect.position
	var s := rect.size
	var pts := PackedVector2Array([
		p + Vector2(slant, 0), p + Vector2(s.x, 0), p + Vector2(s.x - slant, s.y), p + Vector2(0, s.y)])
	ci.draw_colored_polygon(pts, fill)
	if edge.a > 0.0:
		pts.append(pts[0])
		ci.draw_polyline(pts, edge, border, true)


## A menu button: slanted bar, neon edge when selected.
static func button(ci: CanvasItem, rect: Rect2, label: String, selected: bool, frame: int,
		size := 34, enabled := true) -> void:
	var pulse := 0.5 + 0.5 * sin(frame * 0.18)
	var fill := Color(PINK.lerp(Color("ff5aa5"), pulse * 0.4)) if selected else Color(DEEP, 0.92)
	if not enabled:
		fill = Color(0.2, 0.15, 0.3, 0.8)
	slant_panel(ci, Rect2(rect.position + Vector2(6, 6), rect.size), Color(0, 0, 0, 0.45))
	slant_panel(ci, rect, fill, CYAN if selected else Color(PURPLE, 0.9), 22.0, 4.0 if selected else 3.0)
	var c := WHITE if enabled else DIM
	text(ci, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + size * 0.36), label, size,
		c, ui, 0, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)


## Horizontal meter with segments (speed/power bars, EX gauge).
static func meter(ci: CanvasItem, rect: Rect2, value: float, color: Color, segments := 10,
		back := Color(0, 0, 0, 0.55)) -> void:
	ci.draw_rect(rect.grow(3), INK)
	ci.draw_rect(rect, back)
	var gap := 3.0
	var seg_w := (rect.size.x - gap * (segments - 1)) / segments
	var filled := value * segments
	for i in segments:
		var r := Rect2(rect.position + Vector2(i * (seg_w + gap), 0), Vector2(seg_w, rect.size.y))
		var amount := clampf(filled - i, 0.0, 1.0)
		if amount > 0.0:
			ci.draw_rect(Rect2(r.position, Vector2(r.size.x * amount, r.size.y)), color)


## Synthwave sunset: gradient sky, striped sun, scrolling neon grid, palms.
static func outrun_background(ci: CanvasItem, size: Vector2, t: float, dim := 0.0) -> void:
	var horizon := size.y * 0.58
	var sky := [Color("12052b"), Color("3d0f5e"), Color("a3207a"), Color("ff6b6b"), Color("ffb347")]
	var bands := 48
	for i in bands:
		var f := float(i) / bands
		var idx := f * (sky.size() - 1)
		var c: Color = sky[int(idx)].lerp(sky[mini(int(idx) + 1, sky.size() - 1)], idx - int(idx))
		ci.draw_rect(Rect2(0, horizon * f, size.x, horizon / bands + 1), c)
	# Sun with horizontal cut-outs.
	var sun_c := Vector2(size.x * 0.5, horizon - 30)
	var sun_r := size.y * 0.23
	ci.draw_circle(sun_c, sun_r + 18, Color(1.0, 0.45, 0.6, 0.25))
	ci.draw_circle(sun_c, sun_r, Color("ffd23f"))
	ci.draw_circle(sun_c + Vector2(0, sun_r * 0.35), sun_r * 0.8, Color("ff7a59"))
	var cuts := 7
	for i in cuts:
		var y := sun_c.y + sun_r * (0.05 + i * 0.14)
		ci.draw_rect(Rect2(sun_c.x - sun_r - 2, y, sun_r * 2 + 4, 4 + i * 2.2), sky[3].lerp(sky[4], 0.4))
	# Distant mountains.
	var m := PackedVector2Array([Vector2(0, horizon)])
	var steps := 24
	for i in steps + 1:
		var x := size.x * i / steps
		var hgt := 40.0 + 55.0 * absf(sin(i * 1.7)) + 30.0 * absf(sin(i * 0.6 + 1.0))
		m.append(Vector2(x, horizon - hgt))
	m.append(Vector2(size.x, horizon))
	ci.draw_colored_polygon(m, Color("2a0f4f"))
	# Ground and grid.
	ci.draw_rect(Rect2(0, horizon, size.x, size.y - horizon), Color("12052b"))
	var grid := Color(1.0, 0.18, 0.6, 0.85)
	var vp := Vector2(size.x * 0.5, horizon)
	for i in range(-16, 17):
		var bottom := Vector2(size.x * 0.5 + i * size.x * 0.14, size.y)
		ci.draw_line(vp.lerp(bottom, 0.0), bottom, grid, 2.0)
	var scroll := fposmod(t * 0.6, 1.0)
	for i in 14:
		var d := (i + scroll) / 14.0
		var y := horizon + (size.y - horizon) * d * d
		ci.draw_line(Vector2(0, y), Vector2(size.x, y), Color(grid, 0.35 + 0.65 * d), 2.0)
	ci.draw_line(Vector2(0, horizon), Vector2(size.x, horizon), Color(CYAN, 0.9), 3.0)
	# Palm silhouettes either side.
	for side in [-1, 1]:
		_palm_silhouette(ci, Vector2(size.x * 0.5 + side * size.x * 0.42, size.y + 20), side, size.y * 0.75)
	if dim > 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, dim))


static func _palm_silhouette(ci: CanvasItem, base: Vector2, side: int, height: float) -> void:
	var col := Color("0a0418")
	var top := base + Vector2(-side * height * 0.18, -height)
	var trunk := PackedVector2Array()
	var segs := 12
	for i in segs + 1:
		var t := float(i) / segs
		var p := base.lerp(top, t) + Vector2(-side * sin(t * PI) * 40.0, 0)
		trunk.append(p + Vector2(-14 + t * 6, 0))
	for i in range(segs, -1, -1):
		var t := float(i) / segs
		var p := base.lerp(top, t) + Vector2(-side * sin(t * PI) * 40.0, 0)
		trunk.append(p + Vector2(14 - t * 6, 0))
	ci.draw_colored_polygon(trunk, col)
	for i in 7:
		var a := -PI * 0.5 + (i - 3) * 0.48
		var dir := Vector2(cos(a), sin(a) + 0.35)
		var leaf := PackedVector2Array()
		var length := height * 0.38
		for k in 9:
			var t := float(k) / 8.0
			var droop := Vector2(0, t * t * length * 0.45)
			leaf.append(top + dir * length * t + droop + dir.orthogonal() * sin(t * PI) * 22.0)
		for k in range(8, -1, -1):
			var t := float(k) / 8.0
			var droop := Vector2(0, t * t * length * 0.45)
			leaf.append(top + dir * length * t + droop - dir.orthogonal() * sin(t * PI) * 6.0)
		ci.draw_colored_polygon(leaf, col)


## Spiky comic starburst (impacts, VS screen, specials).
static func starburst(ci: CanvasItem, centre: Vector2, inner: float, outer: float, points: int,
		color: Color, rotation := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in points * 2:
		var r := outer if i % 2 == 0 else inner
		var a := rotation + i * PI / points
		pts.append(centre + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(pts, color)


## CRT scanlines, an optional retro filter from the graphics settings.
static func scanlines(ci: CanvasItem, size: Vector2) -> void:
	var y := 0.0
	while y < size.y:
		ci.draw_rect(Rect2(0, y, size.x, 2), Color(0, 0, 0, 0.18))
		y += 4.0
