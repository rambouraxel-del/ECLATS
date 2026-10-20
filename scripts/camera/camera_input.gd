class_name CameraInput
extends RefCounted
## Déclare les actions clavier de la caméra (touches physiques = AZERTY et QWERTY).

const BINDINGS := {
	"camera_forward": [KEY_W, KEY_UP],
	"camera_back": [KEY_S, KEY_DOWN],
	"camera_left": [KEY_A, KEY_LEFT],
	"camera_right": [KEY_D, KEY_RIGHT],
	"camera_up": [KEY_SPACE, KEY_PAGEUP],
	"camera_down": [KEY_CTRL, KEY_PAGEDOWN],
	"camera_fast": [KEY_SHIFT],
	"camera_release_mouse": [KEY_ESCAPE],
	"camera_toggle_mode": [KEY_TAB],
}

static func ensure_actions() -> void:
	for action in BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
