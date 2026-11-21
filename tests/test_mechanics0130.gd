extends "res://tests/test_mechanics0120.gd"
## Run: godot --headless --path . --script tests/test_mechanics0130.gd
## Covers issues handled in 0.13.0: #137 #144 #151 #152.

func _initialize() -> void:
	_kredit_slots_above_twelve()
	_multi_trigger_counters()
	_tiers_by_destroyed_count()
	_shelter()
	print("MECHANICS 0130: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _kredit_slots_above_twelve() -> void:
	var g := _game()
	var seat: int = g.state.active_player
	var context: Dictionary = g._context(seat, -1, _compile(_base("跳费")))
	g.state.players[seat].max_credits = 12
	g.state.players[seat].credits = 0
	_run_effect(g, {"op": "modify_kredit_slots", "player": "owner", "amount": 3}, context)
	_check(int(g.state.players[seat].max_credits) == 15, "effects raise slots past 12 (#144)")
	_run_effect(g, {"op": "gain_kredits", "player": "owner", "amount": 20}, context)
	_check(int(g.state.players[seat].credits) == 15, "kredits fill the extra slots")
	for i in 4: _run_effect(g, {"op": "modify_kredit_slots", "player": "owner", "amount": 3}, context)
	_check(int(g.state.players[seat].max_credits) == 24, "the hard cap is 24")
	g.apply_action(seat, {"type": "end_turn"})
	g.apply_action(1 - seat, {"type": "end_turn"})
	_check(int(g.state.players[seat].max_credits) == 24 and int(g.state.players[seat].credits) == 24, "turn start keeps slots above 12 and refills them")
	var low := _game()
	var other: int = low.state.active_player
	low.state.players[1 - other].max_credits = 11
	low.apply_action(other, {"type": "end_turn"})
	_check(int(low.state.players[1 - other].max_credits) == 12, "normal growth still stops at 12")
	low.apply_action(1 - other, {"type": "end_turn"})
	low.apply_action(other, {"type": "end_turn"})
	_check(int(low.state.players[1 - other].max_credits) == 12, "and does not pass it")

func _multi_trigger_counters() -> void:
	var spec := _counter("多重警戒", "enemy_unit_deployed", [{"op": "gain_hq_defense", "player": "owner", "amount": 2}])
	spec.counter_trigger = ["enemy_unit_deployed", "enemy_order_played"]
	var card := _compile_with(spec)
	_check(Runtime.rules_text(card).contains("对方部署单位后或对方打出指令时"), "several triggers are joined in the rules text (#137)")
	var cancel := _counter("多重取消", "enemy_order_played", [{"op": "cancel_action"}])
	cancel.counter_trigger = ["enemy_order_played", "enemy_hq_attacked"]
	_compile_with(cancel)
	cancel.counter_trigger = ["enemy_order_played", "enemy_unit_deployed"]
	_compile_with(cancel, false)
	var duplicated := _counter("重复时机", "enemy_order_played", [{"op": "gain_hq_defense", "player": "owner", "amount": 1}])
	duplicated.counter_trigger = ["enemy_order_played", "enemy_order_played"]
	_compile_with(duplicated, false)
	var g := _game()
	var seat := _rich(g)
	var enemy := 1 - seat
	_arm(g, enemy, spec)
	var before := int(g.state.players[enemy].max_hp)
	var order := _base("触发指令", "order")
	order.abilities = [{"trigger": "on_play", "effects": [{"op": "draw", "player": "owner", "amount": 1}]}]
	_play(g, order)
	_check(int(g.state.players[enemy].max_hp) == before + 2, "the second listed trigger springs the counter")
	_check(g.state.players[enemy].counters.is_empty(), "the counter resolves once and leaves")

func _tiers_by_destroyed_count() -> void:
	var spec := _base("献祭召唤", "order")
	spec.tokens = [_token("giant", "巨像", 2, 2)]
	spec.abilities = [{"trigger": "on_play", "effects": [
		{"op": "select_units", "side": "ally", "min": 1, "max": 5},
		{"op": "destroy", "target": "selected_units"},
		{"op": "summon", "token_id": "giant", "amount": 1, "row": "support"},
		{"op": "if_destroyed", "tiers": [
			{"min": 1, "effects": [{"op": "modify_stats", "target": "summoned", "attack_delta": 4, "health_delta": 4, "duration": "battle"}]},
			{"min": 2, "effects": [{"op": "grant_keyword", "target": "summoned", "keyword_id": "core.fury", "keyword_version": 1, "duration": "battle"}]},
			{"min": 3, "effects": [{"op": "grant_unit_class", "target": "summoned", "unit_class": "bomber", "duration": "battle"}]}]}]}]
	var card := _compile_with(spec)
	_check(Runtime.rules_text(card).contains("消灭至少2个时"), "tiers have rules text (#151)")
	var early := spec.duplicate(true)
	early.abilities[0].effects = [early.abilities[0].effects[0], early.abilities[0].effects[3], early.abilities[0].effects[1], early.abilities[0].effects[2]]
	_compile_with(early, false)
	var unordered := spec.duplicate(true)
	unordered.abilities[0].effects[3].tiers[1].min = 1
	_compile_with(unordered, false)
	var g := _game()
	var seat := _rich(g)
	for i in 2: _veteran_unit(g, seat, "祭品%d" % i)
	var id := _hand_card(g, seat, spec)
	_check(g.apply_action(seat, {"type": "play", "hand_id": id, "target_uid": -1}).is_empty(), "play the order")
	var picks := 0
	while g.state.has("pending_choice") and picks < 6:
		var choice: Dictionary = g.state.pending_choice
		var real: Array = choice.targets.filter(func(t): return int(t) > 0)
		var pick: int = real[0] if not real.is_empty() else -1000
		g.apply_action(seat, {"type": "choose_target", "choice_id": choice.choice_id, "target_uid": pick})
		picks += 1
	var giants: Array = g.state.units.filter(func(u): return g._unit_definition(u).name == "巨像")
	_check(giants.size() == 1, "the token is summoned")
	if giants.size() == 1:
		var giant: Dictionary = giants[0]
		_check(int(giant.attack) == 6 and int(giant.hp) == 6, "first tier: +4/+4 for one or more destroyed")
		_check(g._has_keyword(giant, "core.fury"), "second tier: fury for two destroyed")
		_check(not "bomber" in g._unit_classes(giant), "third tier is not reached with two")
	var five := spec.duplicate(true)
	five.abilities[0].effects[0].max = 6
	_compile_with(five, false)

func _shelter() -> void:
	var shelter: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/cards/registered/standard_shelter.json"))
	var spec := _base("玉玄武")
	spec.keywords = [{"id": "standard.shelter", "version": 1, "params": {"n": 2}}]
	spec.abilities = [{"trigger": "on_death", "effects": [{"op": "gain_hq_defense", "player": "owner", "amount": 3}]}]
	var compiled := Runtime.compile_card(spec, Runtime.builtin_keywords() + [shelter])
	_check(compiled.ok, "庇护 compiles as a template keyword (#152): " + str(compiled.get("error", "")))
	if not compiled.ok: return
	var g := _game()
	var seat := _rich(g)
	var enemy := 1 - seat
	var unit: Dictionary = g._new_unit(enemy, compiled)
	g._initialize_innate_rules(unit)
	_check(g.stack_count(unit, "庇护") == 2, "庇护 N starts with N layers")
	var hq := int(g.state.players[enemy].max_hp)
	var order_spec := _base("消灭", "order")
	order_spec.abilities = [{"trigger": "on_play", "effects": [{"op": "draw", "player": "owner", "amount": 1}]}]
	var order := _compile(order_spec)
	var context: Dictionary = g._context(seat, -1, order, int(unit.uid))
	_run_effect(g, {"op": "destroy", "target": "chosen"}, context)
	_check(not g._unit(int(unit.uid)).is_empty() and g.stack_count(unit, "庇护") == 1, "a destroy spends one layer and is cancelled")
	_check(int(g.state.players[enemy].max_hp) == hq, "a cancelled destroy starts no death ability")
	_run_effect(g, {"op": "destroy", "target": "chosen"}, context)
	_check(not g._unit(int(unit.uid)).is_empty() and g.stack_count(unit, "庇护") == 0, "the second layer stops the second destroy")
	_run_effect(g, {"op": "destroy", "target": "chosen"}, context)
	_check(g._unit(int(unit.uid)).is_empty() and int(g.state.players[enemy].max_hp) == hq + 3, "with no layers left it is destroyed and its death ability runs")
	var tough: Dictionary = g._new_unit(enemy, compiled)
	g._initialize_innate_rules(tough)
	_run_effect(g, {"op": "damage", "target": "chosen", "amount": 10}, g._context(seat, -1, order, int(tough.uid)))
	_check(g._unit(int(tough.uid)).is_empty(), "庇护 does not stop lethal damage")
	var shielded: Dictionary = g._new_unit(enemy, compiled)
	g._initialize_innate_rules(shielded)
	g._suppress(shielded)
	_run_effect(g, {"op": "destroy", "target": "chosen"}, g._context(seat, -1, order, int(shielded.uid)))
	_check(g._unit(int(shielded.uid)).is_empty(), "suppression clears 庇护")
	var plain := _compile(_base("普通单位"))
	var counted: Dictionary = g._new_unit(enemy, compiled)
	g._initialize_innate_rules(counted)
	var other: Dictionary = g._new_unit(enemy, plain)
	var multi: Dictionary = g._context(seat, -1, order)
	multi["selected_units"] = [int(counted.uid), int(other.uid)]
	_run_effect(g, {"op": "destroy", "target": "selected_units"}, multi)
	_check(int(multi.get("selected_destroyed_count", 0)) == 1, "a cancelled destroy is not counted as destroyed")
