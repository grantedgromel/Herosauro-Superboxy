class_name Banter
extends Control
## Lightweight comic banter — a single styled line that pops in at key beats
## (fight start, phase 2) and fades out. Purely cosmetic; ignores mouse.

const INTRO := [
	"ADAMASTOR: \"Turn back, little ones — this bridge is MINE!\"",
	"HEROSAURO: \"Not today, you overgrown pebble!\"",
	"SUPER BOXY: \"Let's bonk this big rock, brother!\"",
	"ADAMASTOR: \"The Douro will swallow your city!\"",
]
const PHASE2 := [
	"ADAMASTOR: \"ENOUGH! Feel the fury of the Douro!\"",
	"ADAMASTOR: \"You only make me ANGRIER!\"",
	"ADAMASTOR: \"Now you face my TRUE strength!\"",
]

var _label: Label
var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_label = UIStyle.label("", 26, UIStyle.GOLD, true)
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_label.offset_top = 196.0
	_label.offset_bottom = 280.0
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.modulate.a = 0.0
	add_child(_label)

	GameManager.game_started.connect(_on_game_started)
	GameManager.boss_phase_changed.connect(_on_phase_changed)


func _on_game_started() -> void:
	say(INTRO[randi() % INTRO.size()])


func _on_phase_changed(phase: int) -> void:
	if phase >= 2:
		say(PHASE2[randi() % PHASE2.size()])


func say(text: String) -> void:
	_label.text = text
	if _tween and _tween.is_valid():
		_tween.kill()
	_label.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_label, "modulate:a", 1.0, 0.3)
	_tween.tween_interval(2.8)
	_tween.tween_property(_label, "modulate:a", 0.0, 0.6)
