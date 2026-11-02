class_name GanjifaCard
extends Control

## A round Ganjifa card for a CardData: gold rim, lacquer field with a dotted border, the
## avatar's painting in a medallion (a placeholder symbol for now), the card's short tag
## across the top and its avatar + title across the bottom. Face down it shows the back.
## Drawn at any size: callers scale it with `scale` (pivot is the centre) for tweens.

const DIAMETER := 132.0
const BACK_COLOR := Color(0.45, 0.1, 0.1)

var card: CardData
var face_up := true:
	set(value):
		face_up = value
		queue_redraw()
## 0..1: a glowing ring (hovered, selected, offered and picked...).
var glow := 0.0:
	set(value):
		glow = value
		queue_redraw()
var glow_color := Color(1.0, 0.85, 0.4)

func _init(card_data: CardData = null, up: bool = true) -> void:
	card = card_data
	face_up = up
	custom_minimum_size = Vector2.ONE * DIAMETER
	size = Vector2.ONE * DIAMETER
	pivot_offset = size / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP

func _draw() -> void:
	var c := size / 2.0
	var r := DIAMETER / 2.0
	draw_circle(c + Vector2(3, 5), r, Color(0, 0, 0, 0.35))
	if glow > 0.0:
		var g := glow_color
		g.a = 0.55 * glow
		draw_circle(c, r + 9.0 * glow, g)
	draw_circle(c, r, Ganjifa.GOLD)
	draw_arc(c, r - 2.0, 0, TAU, 48, Ganjifa.GOLD.darkened(0.35), 2.0, true)
	var font := GameFonts.title()
	if not face_up or card == null:
		draw_circle(c, r * 0.9, BACK_COLOR)
		for i in 8:
			var a := TAU * i / 8.0
			draw_circle(c + Vector2.from_angle(a) * r * 0.42, r * 0.16, Ganjifa.GOLD.darkened(0.15))
		draw_circle(c, r * 0.24, Ganjifa.GOLD)
		draw_circle(c, r * 0.12, BACK_COLOR)
		return
	var look := Ganjifa.look(card)
	var field := card.color.darkened(0.3)
	draw_circle(c, r * 0.9, field)
	for i in 28:
		draw_circle(c + Vector2.from_angle(TAU * i / 28.0) * r * 0.8, r * 0.025, Ganjifa.IVORY)
	draw_circle(c + Vector2(0, r * 0.06), r * 0.47, card.color.lightened(0.55))
	draw_arc(c + Vector2(0, r * 0.06), r * 0.47, 0, TAU, 40, Ganjifa.GOLD, 2.5, true)
	Ganjifa.draw_symbol(self, look["symbol"], c + Vector2(0, r * 0.06), r * 0.42, Ganjifa.INK)
	# The tag (what it does), readable while only the top of the card shows
	var tag_size := int(r * 0.2)
	_text_centered(font, look["tag"], c + Vector2(0, -r * 0.55), tag_size, Ganjifa.IVORY)
	# Yatra for the name too: Laila drawn straight onto a card comes out as solid bars
	_text_centered(font, card.title, c + Vector2(0, r * 0.74), int(r * 0.17), Ganjifa.IVORY, 3)

## outline 0 = a drop shadow instead.
func _text_centered(font: Font, text: String, at: Vector2, font_size: int, color: Color, outline: int = 4) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := at + Vector2(-width / 2.0, font_size * 0.35)
	if outline > 0:
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Ganjifa.INK)
	else:
		draw_string(font, pos + Vector2(1, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Ganjifa.INK)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## Circle-shaped hit area (Controls are rectangles).
func _has_point(point: Vector2) -> bool:
	return point.distance_to(size / 2.0) <= DIAMETER / 2.0
