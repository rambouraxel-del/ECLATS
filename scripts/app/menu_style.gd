class_name MenuStyle
extends RefCounted
## Éléments d'interface communs au menu principal, au menu de pause et aux outils (style provisoire sobre).

const BG := Color(0.07, 0.09, 0.12)
const PANEL := Color(0.11, 0.14, 0.19, 0.96)
const ACCENT := Color(0.40, 0.82, 0.95)
const TEXT := Color(0.92, 0.95, 0.98)
const MUTED := Color(0.62, 0.70, 0.78)

static func box(color: Color, border := Color(0, 0, 0, 0), radius := 8, bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

## Panneau centré (conteneur vertical dans un PanelContainer).
static func panel(size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(PANEL, Color(0.30, 0.42, 0.55, 0.9), 14, 2))
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = size
	p.offset_left = -size.x * 0.5
	p.offset_right = size.x * 0.5
	p.offset_top = -size.y * 0.5
	p.offset_bottom = size.y * 0.5
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	return p

static func button(text: String, width := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 54)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_focus_color", Color(1, 1, 1))
	b.add_theme_stylebox_override("normal", box(Color(0.17, 0.22, 0.30), Color(0.28, 0.38, 0.50), 8, 1))
	b.add_theme_stylebox_override("hover", box(Color(0.22, 0.34, 0.46), ACCENT, 8, 2))
	b.add_theme_stylebox_override("focus", box(Color(0.22, 0.34, 0.46), ACCENT, 8, 2))
	b.add_theme_stylebox_override("pressed", box(Color(0.14, 0.45, 0.58), ACCENT, 8, 2))
	return b

static func title(text: String, size := 34) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TEXT)
	return l

static func note(text: String, size := 15) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", MUTED)
	return l

static func spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
