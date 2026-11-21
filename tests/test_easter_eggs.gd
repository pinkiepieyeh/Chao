extends SceneTree
## Run: godot --headless --path . --script tests/test_easter_eggs.gd
## The meow egg: switch parsing, Beijing dates, punctuation, and which card faces it marks.
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func _run() -> void:
	EasterEggs.configure(null)
	check(not EasterEggs.meow_active(), "no switch file, no egg")
	EasterEggs.configure({"meow": {"enabled": true, "date": "2026-11-21", "until_unix": 1795795200}})
	check(EasterEggs.meow_active(1795795199.0) and not EasterEggs.meow_active(1795795200.0), "active until the end of the week")
	EasterEggs.configure({"meow": {"enabled": false, "date": "2026-11-21", "until_unix": 1795795200}})
	check(not EasterEggs.meow_active(1795190400.0), "turned off by hand")
	EasterEggs.configure({"meow": {"enabled": true, "date": "21-11", "until_unix": 1795795200}})
	check(not EasterEggs.meow_active(1795190400.0), "a malformed date switches nothing on")
	check(EasterEggs.beijing_date("2026-11-20T16:00:00.000Z") == "2026-11-21" and EasterEggs.beijing_date("2026-11-21T15:59:59Z") == "2026-11-21" and EasterEggs.beijing_date("2026-11-21T16:00:00Z") == "2026-11-22", "dates are counted in Beijing time")
	check(EasterEggs.record_date({"created_at": "2026-11-01T00:00:00Z", "submitted_at": "2026-11-21T08:00:00Z"}) == "2026-11-21", "a revision's submission time wins over the first registration")
	check(EasterEggs.meow("部署：抽1张牌，然后造成1.5点伤害。") == "部署喵：抽1张牌喵，然后造成1.5点伤害喵。", "喵 before each punctuation mark, not inside decimals")
	check(EasterEggs.meow(EasterEggs.meow("甲，乙")) == "甲喵，乙", "meowing twice adds nothing")

	var until := int(Time.get_unix_time_from_system()) + 3600
	EasterEggs.configure({"meow": {"enabled": true, "date": "2026-11-21", "until_unix": until}})
	var spec := {"schema_version": "1.0.0", "ruleset_version": "frontline-1", "name": "啥子，比！？", "flavor_text": "", "kind": "unit", "unit_class": "tank", "cost": 1, "operation_cost": 1, "attack": 3, "health": 4, "keywords": [], "play_target": null, "abilities": [{"trigger": "on_play", "effects": [{"op": "draw", "player": "owner", "amount": 1}]}], "tokens": [], "appearance": {"emblem": "tank"}}
	var card := CardRuntime.compile_card(spec, CardRuntime.builtin_keywords())
	check(card.ok, "fixture compiles")
	var today := card.duplicate(true); today["submitted_on"] = "2026-11-21"
	var other := card.duplicate(true); other["submitted_on"] = "2026-11-20"
	var marked := CardRuntime.display_definition(today)
	check(marked.get("_meow", false) and marked.name == "啥子喵，比喵！喵？", "a card submitted that day shows a meowing name")
	check(not CardRuntime.display_definition(other).get("_meow", false) and CardRuntime.display_definition(other).name == "啥子，比！？", "other days are untouched")
	check(card.definition.name == "啥子，比！？" and today.definition.name == "啥子，比！？", "the card itself never changes")
	var face := CardFace.new()
	face.spec = marked
	root.add_child(face)
	check(face._rules_text().contains("喵"), "the card face meows its rules text")
	EasterEggs.configure({"meow": {"enabled": false, "date": "2026-11-21", "until_unix": until}})
	check(not CardRuntime.display_definition(today).get("_meow", false), "switching it off removes the meow")
	face.queue_free()
	print("EASTER EGGS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
