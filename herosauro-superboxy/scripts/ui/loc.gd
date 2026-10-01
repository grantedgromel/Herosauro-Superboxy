class_name Loc
extends RefCounted
## Every UI string the storybook frame shows, in European Portuguese and
## English, keyed by id. Story text (pages, beats, objectives, titles) is not
## here: it lives in StoryData and is picked with `pick()`.
##
## The language is GameManager.language, read live, so a screen that rebuilds
## its labels on `GameManager.settings_changed` switches language mid-session
## without keeping any state of its own.
##
## Strings are short on purpose. Most of the audience cannot read yet; every
## string that matters is also spoken (see Narrator) and sits next to an icon.

const S := {
	# Title
	"tap_to_start": {"pt": "Toca para começar", "en": "Tap to start"},
	"strapline": {"pt": "OS IRMÃOS GUARDIÕES DO PORTO", "en": "THE GUARDIAN BROTHERS OF PORTO"},
	# Bookshelf
	"shelf_title": {"pt": "As minhas histórias", "en": "My storybooks"},
	"shelf_prompt": {"pt": "Escolhe uma história!", "en": "Pick a story!"},
	"chapter_n": {"pt": "História %d", "en": "Story %d"},
	"read_again": {"pt": "Ler outra vez", "en": "Read again"},
	"new_story": {"pt": "Nova!", "en": "New!"},
	# Who's playing
	"who_title": {"pt": "Quem vai jogar?", "en": "Who's playing?"},
	"one_player": {"pt": "1 jogador", "en": "1 player"},
	"two_players": {"pt": "2 jogadores", "en": "2 players"},
	"pick_hero": {"pt": "Escolhe o teu herói!", "en": "Pick your hero!"},
	"helper_note": {"pt": "O outro irmão ajuda-te!", "en": "Your brother helps you!"},
	"helper": {"pt": "Ajudante", "en": "Helper"},
	# Reader
	"next": {"pt": "Seguinte", "en": "Next"},
	"back": {"pt": "Voltar", "en": "Back"},
	"skip": {"pt": "Saltar", "en": "Skip"},
	"play": {"pt": "Jogar!", "en": "Play!"},
	"the_end": {"pt": "Fim", "en": "The End"},
	"listen": {"pt": "Ouvir", "en": "Listen"},
	# End of chapter
	"well_done": {"pt": "Muito bem!", "en": "Well done!"},
	"sticker_won": {"pt": "Ganhaste um autocolante!", "en": "You won a sticker!"},
	"continue": {"pt": "Continuar", "en": "Continue"},
	"try_again_title": {"pt": "Vamos tentar outra vez!", "en": "Let's try again!"},
	"try_again_body": {"pt": "Os heróis estão prontos para mais uma aventura.", "en": "The heroes are ready for another go."},
	"try_again": {"pt": "Outra vez", "en": "Try again"},
	"back_to_book": {"pt": "Voltar ao livro", "en": "Back to the book"},
	# Pause
	"paused": {"pt": "Pausa", "en": "Paused"},
	"resume": {"pt": "Continuar", "en": "Continue"},
	# Settings
	"settings": {"pt": "Definições", "en": "Settings"},
	"language": {"pt": "Língua", "en": "Language"},
	"lang_pt": {"pt": "Português", "en": "Português"},
	"lang_en": {"pt": "English", "en": "English"},
	"assists": {"pt": "Ajudas", "en": "Assists"},
	"assists_hint": {"pt": "Nunca perdes", "en": "You never lose"},
	"narration": {"pt": "Narração", "en": "Narration"},
	"narration_hint": {"pt": "Lê-me a história", "en": "Read to me"},
	"reduce_motion": {"pt": "Menos movimento", "en": "Less motion"},
	"reduce_motion_hint": {"pt": "Ecrã mais calmo", "en": "A calmer screen"},
	"music": {"pt": "Música", "en": "Music"},
	"sounds": {"pt": "Sons", "en": "Sounds"},
	"credits": {"pt": "Créditos", "en": "Credits"},
	"close": {"pt": "Fechar", "en": "Close"},
	"on": {"pt": "Sim", "en": "On"},
	"off": {"pt": "Não", "en": "Off"},
	# HUD
	"boss_epithet": {"pt": "O GIGANTE DO DOURO", "en": "THE GIANT OF THE DOURO"},
	"phase": {"pt": "FASE %d", "en": "PHASE %d"},
	"pause": {"pt": "Pausa", "en": "Pause"},
	"move": {"pt": "ANDAR", "en": "MOVE"},
	"jump": {"pt": "SALTAR", "en": "JUMP"},
	"hit": {"pt": "SOCO", "en": "HIT"},
	"special": {"pt": "PODER", "en": "POWER"},
}


## The active language. Falls back to Portuguese when GameManager is not up
## (a --script tool, a probe that builds a widget before the tree is ready).
static func lang() -> String:
	var gm := _gm()
	if gm == null:
		return StoryData.DEFAULT_LANG
	var l := str(gm.get("language"))
	return l if l in StoryData.LANGS else StoryData.DEFAULT_LANG


## A UI string. An unknown id returns the id itself, loudly ugly on screen,
## so a typo is found by looking rather than by a crash.
static func t(id: String, lang_override: String = "") -> String:
	var entry: Dictionary = S.get(id, {})
	if entry.is_empty():
		push_warning("Loc: no string '%s'" % id)
		return id
	return StoryData.text(entry, lang_override if not lang_override.is_empty() else lang())


## t() with printf arguments, e.g. Loc.f("chapter_n", [2]).
static func f(id: String, args: Array) -> String:
	return t(id) % args


## Pick the current language out of a StoryData {pt, en} entry (a page, a
## beat, a title, an objective label).
static func pick(entry: Dictionary, lang_override: String = "") -> String:
	if entry.is_empty():
		return ""
	return StoryData.text(entry, lang_override if not lang_override.is_empty() else lang())


static func has(id: String) -> bool:
	return S.has(id)


static func _gm() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("GameManager")
