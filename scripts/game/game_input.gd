class_name GameInput
extends RefCounted
## Actions de jeu (Lot 5), déclarées par POSITION physique des touches : ZQSD sur un clavier AZERTY et WASD sur
## un clavier QWERTY désignent les mêmes touches. Les flèches marchent aussi. Les libellés affichés (« E · … »)
## sont lus sur la disposition réelle du clavier.

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"interact": [KEY_E],
}

static func ensure() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)

## Libellé de la touche réellement assignée à une action (première touche), sur la disposition courante.
static func key_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for ev in InputMap.action_get_events(action):
		var k := ev as InputEventKey
		if k == null:
			continue
		var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
		var shown := code
		if k.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless":
			var lab := DisplayServer.keyboard_get_label_from_physical(k.physical_keycode)
			if lab != KEY_NONE:
				shown = lab
		var s := OS.get_keycode_string(shown)
		if s == "Space":
			return "Espace"
		if s == "Shift":
			return "Maj"
		return s.to_upper() if s.length() == 1 else s
	return "?"

## « ZQSD » ou « WASD » selon le clavier.
static func move_keys_label() -> String:
	return key_label("move_forward") + key_label("move_left") + key_label("move_back") + key_label("move_right")
