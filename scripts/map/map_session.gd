class_name MapSession
extends RefCounted
## SESSION D'ÉDITION (Lot 11) : le document ouvert (plan, relief, historique Ctrl+Z) et son fichier d'enregistrement. Elle survit au
## passage éditeur → vue 3D → éditeur (le document est transmis tel quel, sans être recalculé) et protège les modifications non
## enregistrées : toute action qui les ferait perdre (quitter, ouvrir une autre carte, générer un nouveau plan) passe par `ask`.

static var current: MapSession = null

var doc: MapDoc
var path := ""                       # dernier fichier enregistré ou ouvert ("" = jamais enregistré)
var dir := "user://cartes/"
var tool := ""                       # outil actif de l'éditeur (repris au retour de la 3D)
var graine := 0                      # réglages du générateur (idem)
var largeur := 56.0
var longueur := 48.0

static func begin(p_doc: MapDoc, p_path := "") -> MapSession:
	var s := MapSession.new()
	s.doc = p_doc
	s.path = p_path
	current = s
	return s

static func clean_name(n: String) -> String:
	var c := n.strip_edges().to_lower().replace(" ", "_").replace("·", "").replace("×", "x").replace("__", "_").replace("/", "_").replace("\\", "_")
	return c if c != "" else "carte"

## Fichier d'enregistrement : le fichier courant, sinon un nom tiré du titre (jamais celui d'une autre carte : suffixe _2, _3…).
func target_file() -> String:
	if path != "":
		return path
	var base := clean_name(doc.plan.name)
	var f := dir + base + ".eclats-carte.json"
	var k := 2
	while FileAccess.file_exists(f):
		f = dir + "%s_%d.eclats-carte.json" % [base, k]
		k += 1
	return f

## Enregistre le document (écriture sûre). Échec : le document reste ouvert ET modifié, l'erreur est renvoyée telle quelle.
func save() -> Dictionary:
	var f := target_file()
	var r := doc.export_to(f)
	if bool(r["ok"]):
		path = f
	return r

func is_dirty() -> bool:
	return doc != null and doc.is_dirty()

## Applique un choix du dialogue de sortie. "save" : enregistre puis poursuit (si l'enregistrement échoue, rien n'est poursuivi et
## l'erreur est renvoyée) · "discard" : poursuit sans enregistrer · "cancel" : abandonne l'action.
func choose(choice: String, then: Callable) -> Dictionary:
	match choice:
		"save":
			var r := save()
			if not bool(r["ok"]):
				return {"ok": false, "done": false, "error": String(r["error"])}
			if then.is_valid():
				then.call()
			return {"ok": true, "done": true}
		"discard":
			if then.is_valid():
				then.call()
			return {"ok": true, "done": true}
	return {"ok": true, "done": false}

## Poursuit tout de suite si rien n'est à perdre ; sinon ouvre le dialogue (host : nœud qui le porte).
static func ask(host: Node, then: Callable) -> bool:
	var s := current
	if s == null or not s.is_dirty():
		then.call()
		return true
	if DisplayServer.get_name() == "headless":
		return false
	s._dialog(host, then)
	return false

func _dialog(host: Node, then: Callable) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.name = "DialogueSortie"
	host.add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(shade)
	var panel := MenuStyle.panel(Vector2(640, 340))
	layer.add_child(panel)
	var box := panel.get_child(0) as VBoxContainer
	box.add_child(MenuStyle.title("Modifications non enregistrées", 28))
	var msg := Label.new()
	msg.text = "La carte « %s » a été modifiée depuis son dernier enregistrement. Que faire ?" % doc.plan.name
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_font_size_override("font_size", 17)
	box.add_child(msg)
	var err := Label.new()
	err.name = "Erreur"
	err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	err.add_theme_font_size_override("font_size", 15)
	err.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	box.add_child(err)
	var b1 := MenuStyle.button("Enregistrer puis continuer")
	b1.name = "Enregistrer"
	b1.pressed.connect(func() -> void:
		var r := choose("save", then)
		if bool(r["ok"]):
			layer.queue_free()
		else:
			err.text = "Enregistrement impossible : %s La carte reste ouverte et inchangée." % r["error"])
	box.add_child(b1)
	var b2 := MenuStyle.button("Continuer sans enregistrer")
	b2.name = "SansEnregistrer"
	b2.pressed.connect(func() -> void:
		choose("discard", then)
		layer.queue_free())
	box.add_child(b2)
	var b3 := MenuStyle.button("Annuler")
	b3.name = "Annuler"
	b3.pressed.connect(func() -> void: layer.queue_free())
	box.add_child(b3)
