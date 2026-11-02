class_name Ganjifa
extends RefCounted

## The look of each card as a round Ganjifa card: the Dashavatara avatar it's painted
## with (chosen to echo what the card does), a short tag printed at the top so it reads
## even while the card peeks out of the hand, and a placeholder symbol for the painting
## until real art exists. The rules text always comes from the CardData itself.

const LOOKS := {
	&"sprint": {"avatar": "Vamana", "tag": "MOVE 2", "symbol": "umbrella"},
	&"tailwind": {"avatar": "Matsya", "tag": "+1 MOVES", "symbol": "fish"},
	&"aegis": {"avatar": "Kurma", "tag": "SHIELD", "symbol": "tortoise"},
	&"master_key": {"avatar": "Varaha", "tag": "UNLOCK", "symbol": "boar"},
	&"loaded_shells": {"avatar": "Narasimha", "tag": "THROW 4", "symbol": "lion"},
	&"banish": {"avatar": "Parashurama", "tag": "SEND HOME", "symbol": "axe"},
	&"sanctuary": {"avatar": "Rama", "tag": "SAFE SQUARE", "symbol": "bow"},
	&"switcheroo": {"avatar": "Krishna", "tag": "SWAP", "symbol": "flute"},
	&"stall": {"avatar": "Buddha", "tag": "SKIP TURN", "symbol": "lotus"},
	&"lucky_charm": {"avatar": "Kalki", "tag": "LUCKY", "symbol": "sword"},
}

const INK := Color(0.12, 0.07, 0.05)
const GOLD := Color(0.86, 0.68, 0.28)
const IVORY := Color(0.96, 0.9, 0.76)

static func look(card: CardData) -> Dictionary:
	return LOOKS.get(card.id, {"avatar": card.title, "tag": card.title.to_upper(), "symbol": ""})

## The placeholder painting: a simple emblem for the avatar, centred at c, about r across.
static func draw_symbol(ci: CanvasItem, symbol: String, c: Vector2, r: float, color: Color) -> void:
	var w := maxf(2.0, r * 0.09)
	match symbol:
		"umbrella": # Vamana's parasol
			ci.draw_arc(c + Vector2(0, -r * 0.1), r * 0.6, PI, TAU, 24, color, w * 1.4)
			ci.draw_line(c + Vector2(-r * 0.6, -r * 0.1), c + Vector2(r * 0.6, -r * 0.1), color, w)
			ci.draw_line(c + Vector2(0, -r * 0.7), c + Vector2(0, r * 0.65), color, w)
			ci.draw_arc(c + Vector2(r * 0.1, r * 0.65), r * 0.1, 0, PI, 8, color, w)
		"fish":
			_ellipse(ci, c + Vector2(-r * 0.1, 0), Vector2(r * 0.55, r * 0.28), color)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.35, 0), c + Vector2(r * 0.75, -r * 0.3), c + Vector2(r * 0.75, r * 0.3)]), color)
			ci.draw_circle(c + Vector2(-r * 0.4, -r * 0.05), r * 0.06, IVORY)
		"tortoise":
			ci.draw_circle(c, r * 0.45, color)
			ci.draw_arc(c, r * 0.3, 0, TAU, 6, IVORY, w * 0.7)
			for a in [0.6, 2.5, 3.8, 5.6]:
				ci.draw_circle(c + Vector2.from_angle(a) * r * 0.5, r * 0.12, color)
			ci.draw_circle(c + Vector2(0, -r * 0.62), r * 0.15, color)
		"boar": # Varaha lifting the earth on his tusk
			ci.draw_circle(c + Vector2(0, -r * 0.25), r * 0.3, color)
			ci.draw_arc(c + Vector2(0, r * 0.25), r * 0.4, PI * 1.15, PI * 1.85, 16, IVORY, w * 1.8)
			ci.draw_arc(c + Vector2(0, r * 0.3), r * 0.55, PI * 0.1, PI * 0.9, 16, color, w * 1.5)
		"lion": # Narasimha: a face with a mane
			for i in 12:
				var a := TAU * i / 12.0
				ci.draw_line(c + Vector2.from_angle(a) * r * 0.35, c + Vector2.from_angle(a) * r * 0.7, color, w * 1.6)
			ci.draw_circle(c, r * 0.38, color)
			ci.draw_circle(c + Vector2(-r * 0.13, -r * 0.08), r * 0.06, IVORY)
			ci.draw_circle(c + Vector2(r * 0.13, -r * 0.08), r * 0.06, IVORY)
		"axe":
			ci.draw_line(c + Vector2(-r * 0.45, r * 0.6), c + Vector2(r * 0.3, -r * 0.55), color, w * 1.3)
			ci.draw_arc(c + Vector2(r * 0.15, -r * 0.35), r * 0.35, -PI * 0.15, PI * 0.85, 16, color, w * 3.0)
		"bow":
			ci.draw_arc(c + Vector2(-r * 0.35, 0), r * 0.75, -PI * 0.38, PI * 0.38, 20, color, w * 1.6)
			var top := c + Vector2(-r * 0.35, 0) + Vector2.from_angle(-PI * 0.38) * r * 0.75
			var bottom := c + Vector2(-r * 0.35, 0) + Vector2.from_angle(PI * 0.38) * r * 0.75
			ci.draw_line(top, bottom, color, w * 0.6)
			ci.draw_line(c + Vector2(-r * 0.2, 0), c + Vector2(r * 0.65, 0), color, w)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.7, 0), c + Vector2(r * 0.5, -r * 0.1), c + Vector2(r * 0.5, r * 0.1)]), color)
		"flute": # Krishna's flute with a peacock feather
			ci.draw_line(c + Vector2(-r * 0.65, r * 0.35), c + Vector2(r * 0.65, -r * 0.2), color, w * 2.2)
			for i in 4:
				ci.draw_circle(c + Vector2(-r * 0.2 + i * r * 0.18, r * 0.15 - i * r * 0.08), r * 0.035, IVORY)
			_ellipse(ci, c + Vector2(r * 0.05, -r * 0.42), Vector2(r * 0.16, r * 0.26), color)
			ci.draw_circle(c + Vector2(r * 0.05, -r * 0.45), r * 0.08, IVORY)
		"lotus":
			for i in 5:
				var a := PI + PI * (i + 0.5) / 5.0
				_ellipse(ci, c + Vector2.from_angle(a) * r * 0.32 + Vector2(0, r * 0.1), Vector2(r * 0.12, r * 0.32), color, a + PI / 2.0)
			ci.draw_line(c + Vector2(-r * 0.55, r * 0.25), c + Vector2(r * 0.55, r * 0.25), color, w)
		"sword":
			ci.draw_line(c + Vector2(0, r * 0.45), c + Vector2(0, -r * 0.7), color, w * 2.0)
			ci.draw_line(c + Vector2(-r * 0.25, r * 0.4), c + Vector2(r * 0.25, r * 0.4), color, w * 1.6)
			ci.draw_line(c + Vector2(0, r * 0.4), c + Vector2(0, r * 0.7), color, w * 1.6)
		_:
			ci.draw_circle(c, r * 0.3, color)

static func _ellipse(ci: CanvasItem, c: Vector2, radii: Vector2, color: Color, angle: float = 0.0) -> void:
	var points := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		points.append(c + Vector2(cos(a) * radii.x, sin(a) * radii.y).rotated(angle))
	ci.draw_colored_polygon(points, color)
