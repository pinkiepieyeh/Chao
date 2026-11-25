extends "res://tests/test_mechanics0130.gd"
## Run: godot --headless --path . --script tests/test_mechanics0140.gd
## Covers issues handled in 0.14.0: #155 (every other friendly unit, the destroyed units' attack and health) and
## #50 (a card declares its own large / normal / small category).

func _initialize() -> void:
	_last_road()
	_rules()
	_card_category()
	print("MECHANICS 0140: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _last_road_spec() -> Dictionary:
	var spec := _base("残阳孤路", "order")
	spec.cost = 4
	spec.play_target = {"side": "ally", "row": "any"}
	spec.abilities = [{"trigger": "on_play", "effects": [
		{"op": "destroy", "target": "all_friendly_units", "unit_filter": {"not_chosen": true}},
		{"op": "modify_stats", "target": "chosen", "attack_delta": {"stat": "destroyed_attack_total"}, "health_delta": {"stat": "destroyed_health_total"}, "duration": "battle"}]}]
	return spec

func _last_road() -> void:
	var spec := _last_road_spec()
	var card := _compile_with(spec)
	var text := Runtime.rules_text(card)
	_check(text.contains("所选单位以外的") and text.contains("本组消灭单位的攻击力合计"), "rules text names the exclusion and the totals (#155)")
	var g := _game()
	var seat := _rich(g)
	var kept := _veteran_unit(g, seat, "孤军")
	var first := _veteran_unit(g, seat, "甲")
	var second := _veteran_unit(g, seat, "乙")
	second.damage_taken = 1
	g._recompute(second)
	var enemy := _veteran_unit(g, 1 - seat, "敌军")
	var before_attack := int(kept.attack)
	var before_health := int(kept.hp)
	var expected_attack := int(first.attack) + int(second.attack)
	var expected_health := int(first.hp) + int(second.hp)
	var id := _hand_card(g, seat, spec)
	_check(g.apply_action(seat, {"type": "play", "hand_id": id, "target_uid": int(kept.uid)}).is_empty(), "play 残阳孤路 on one friendly unit")
	_check(g._unit(int(first.uid)).is_empty() and g._unit(int(second.uid)).is_empty(), "every other friendly unit is destroyed")
	_check(not g._unit(int(kept.uid)).is_empty() and not g._unit(int(enemy.uid)).is_empty(), "the chosen unit and enemies stay")
	var now: Dictionary = g._unit(int(kept.uid))
	_check(int(now.attack) == before_attack + expected_attack and int(now.hp) == before_health + expected_health, "it gains their current attack and health")

func _rules() -> void:
	var loose := _base("无选择", "order")
	loose.abilities = [{"trigger": "on_play", "effects": [{"op": "destroy", "target": "all_friendly_units", "unit_filter": {"not_chosen": true}}]}]
	_compile_with(loose, false)
	var early := _base("先加后消", "order")
	early.play_target = {"side": "ally", "row": "any"}
	early.abilities = [{"trigger": "on_play", "effects": [{"op": "modify_stats", "target": "chosen", "attack_delta": {"stat": "destroyed_attack_total"}, "health_delta": 0, "duration": "battle"}, {"op": "destroy", "target": "all_enemy_units"}]}]
	_compile_with(early, false)
	var shelter: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/registered/standard_shelter.json"))
	var guarded := _base("被庇护")
	guarded.keywords = [{"id": "standard.shelter", "version": 1, "params": {"n": 1}}]
	var compiled := Runtime.compile_card(guarded, Runtime.builtin_keywords() + [shelter])
	var g := _game()
	var seat := _rich(g)
	var kept := _veteran_unit(g, seat, "孤军")
	var safe: Dictionary = g._new_unit(seat, compiled)
	g._initialize_innate_rules(safe)
	var before := int(kept.attack)
	var id := _hand_card(g, seat, _last_road_spec())
	g.apply_action(seat, {"type": "play", "hand_id": id, "target_uid": int(kept.uid)})
	_check(not g._unit(int(safe.uid)).is_empty() and int(g._unit(int(kept.uid)).attack) == before, "a destroy cancelled by 庇护 adds nothing")

func _card_category() -> void:
	var registry := {"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa": {"name": "大阵营", "role": "major", "color": "#335577", "category": "large"}, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb": {"name": "普通阵营", "role": "major", "color": "#557733", "category": "normal"}}
	var small := _base("小型卡")
	small["category"] = "small"
	_compile_with(small)
	var bad := _base("无效类别")
	bad["category"] = "huge"
	_compile_with(bad, false)
	var plain := {"name": "旧卡", "faction_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}
	_check(DeckRules.card_category(plain, registry) == "large", "without its own category a card follows its faction (#50)")
	_check(DeckRules.card_category({"name": "改为普通", "faction_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "category": "normal"}, registry) == "normal", "the card's own category wins")
	var deck: Array = []
	for i in 30: deck.append({"definition": {"name": "主%d" % i, "kind": "unit", "sin": "wrath", "faction_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}})
	for i in 10: deck.append({"definition": {"name": "副%d" % i, "kind": "unit", "sin": "gloom", "faction_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}})
	_check(DeckRules.composition(deck, registry, "wrath", "gloom").error.is_empty(), "a plain deck is legal")
	deck[0] = {"definition": {"name": "小型主卡", "kind": "unit", "sin": "wrath", "faction_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "category": "small"}}
	_check(DeckRules.composition(deck, registry, "wrath", "gloom").error.contains("小阵营"), "a small card cannot count for the main sin, whatever its faction")
	deck[0] = {"definition": {"name": "大阵营旧卡", "kind": "unit", "sin": "gloom", "faction_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}}
	deck[39] = {"definition": {"name": "主补", "kind": "unit", "sin": "wrath", "faction_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}}
	_check(DeckRules.composition(deck, registry, "wrath", "gloom").error.contains("大阵营"), "older cards keep their faction's limit")
	deck[0].definition["category"] = "normal"
	_check(DeckRules.composition(deck, registry, "wrath", "gloom").error.is_empty(), "a card set to normal is free of its faction's limit")
