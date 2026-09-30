class_name ShellsView
extends Control

## Draws the last cowry throw: open-up shells show their slit mouth,
## face-down shells show the domed back.

const SHELL_SIZE := Vector2(26, 38)
const GAP := 14.0
const OPEN_COLOR := Color(0.97, 0.94, 0.86)
const BACK_COLOR := Color(0.62, 0.47, 0.32)
const OUTLINE_COLOR := Color(0.2, 0.15, 0.1)

var shells: Array[bool] = []:
	set(value):
		shells = value
		queue_redraw()

func _ready() -> void:
	custom_minimum_size = Vector2(4 * SHELL_SIZE.x + 3 * GAP, SHELL_SIZE.y + 4)

func _draw() -> void:
	for i in 4:
		var center := Vector2(SHELL_SIZE.x / 2.0 + i * (SHELL_SIZE.x + GAP), size.y / 2.0)
		var points := _ellipse(center, SHELL_SIZE / 2.0)
		if i >= shells.size():
			# Not thrown yet: faint placeholder
			draw_polyline(points, Color(1, 1, 1, 0.25), 1.5, true)
			continue
		if shells[i]:
			draw_colored_polygon(points, OPEN_COLOR)
			# The toothed slit along the shell's mouth
			var top := center + Vector2(0, -SHELL_SIZE.y * 0.36)
			var bottom := center + Vector2(0, SHELL_SIZE.y * 0.36)
			draw_line(top, bottom, OUTLINE_COLOR, 2.5, true)
			for t in range(1, 6):
				var y := lerpf(top.y, bottom.y, t / 6.0)
				draw_line(Vector2(center.x - 4, y), Vector2(center.x + 4, y), OUTLINE_COLOR, 1.0, true)
		else:
			draw_colored_polygon(points, BACK_COLOR)
			draw_circle(center + Vector2(-4, -7), 4.0, Color(1, 1, 1, 0.25))
		draw_polyline(points, OUTLINE_COLOR, 1.5, true)

func _ellipse(center: Vector2, radius: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for s in 33:
		var a := TAU * s / 32.0
		points.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	return points
