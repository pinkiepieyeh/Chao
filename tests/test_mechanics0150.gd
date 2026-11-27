extends "res://tests/test_mechanics0140.gd"
## Run: godot --headless --path . --script tests/test_mechanics0150.gd
## Covers issues handled in 0.15.0: #156 #157 #158 #160 #167 #168 #169 #170 #171 #172 #173.

func _initialize() -> void:
	_random_then_branch()
	_unpinnable()
	_aura_reads_guard()
	_salvage_versions()
	_whole_hand()
	_salvage_on_death_and_lowest_attack()
	_poisonous()
	_token_sin()
	_opponent_hand()
	_trial_tool()
	print("MECHANICS 0150: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _kw(id: String, version := 1) -> Dictionary:
	return {"id": id, "version": version, "params": {}}

func _unit_with(name: String, unit_class: String, attack: int, health: int, keywords: Array = []) -> Dictionary:
	var spec := _base(name)
	spec.unit_class = unit_class
	spec.appearance.emblem = unit_class
	spec.attack = attack
	spec.health = health
	spec.keywords = keywords
	return _compile_with(spec)

func _order_with(name: String, effects: Array, play_target: Variant = null) -> Dictionary:
	var spec := _base(name, "order")
	spec.play_target = play_target
	spec.abilities = [{"trigger": "on_play", "effects": effects}]
	return spec

func _play_spec(g: RefCounted, seat: int, spec: Dictionary, target := -1) -> String:
	var id := _hand_card(g, seat, spec)
	var error: String = g.apply_action(seat, {"type": "play", "hand_id": id, "target_uid": target})
	var guard := 0
	while g.state.has("pending_choice") and guard < 8:
		var choice: Dictionary = g.state.pending_choice
		if choice.get("kind", "unit") != "unit": g.apply_action(int(choice.owner), {"type": "choose_card", "choice_id": choice.choice_id, "option_index": 0})
		else: g.apply_action(int(choice.owner), {"type": "choose_target", "choice_id": choice.choice_id, "target_uid": choice.targets[0]})
		guard += 1
	return error

func _random_then_branch() -> void:
	var spec := _order_with("恨意", [
		{"op": "select_units", "side": "enemy", "min": 1, "max": 1, "random": true},
		{"op": "damage", "target": "selected_units", "amount": 4, "unit_filter": {"unit_classes": ["fighter", "bomber"]}},
		{"op": "destroy", "target": "selected_units", "unit_filter": {"unit_classes": ["infantry", "tank", "artillery"]}}])
	_check(Runtime.rules_text(_compile_with(spec)).contains("随机选择1个敌方单位"), "random selection has rules text (#156)")
	var loose := _order_with("随机范围", [{"op": "select_units", "side": "enemy", "min": 1, "max": 2, "random": true}])
	_compile_with(loose, false)
	var g := _game()
	var seat := _rich(g)
	var land: Dictionary = g._new_unit(1 - seat, _unit_with("陆军", "tank", 2, 8))
	_check(_play_spec(g, seat, spec).is_empty(), "play 恨意")
	_check(g._unit(int(land.uid)).is_empty(), "a land unit picked at random is destroyed")
	var g2 := _game()
	var seat2 := _rich(g2)
	var air: Dictionary = g2._new_unit(1 - seat2, _unit_with("空军", "fighter", 2, 8))
	_play_spec(g2, seat2, spec)
	_check(not g2._unit(int(air.uid)).is_empty() and int(g2._unit(int(air.uid)).hp) == 4, "an air unit picked at random takes 4 damage instead")

func _unpinnable() -> void:
	var g := _game()
	var seat := _rich(g)
	var tough: Dictionary = g._new_unit(1 - seat, _unit_with("驯鹿", "artillery", 1, 3, [_kw("core.unpinnable")]))
	_run_effect(g, {"op": "pin", "target": "chosen", "turns": 1}, g._context(seat, -1, _compile(_base("压制者")), int(tough.uid)))
	_check(not g._pinned(tough), "无法被压制 ignores pin (#157)")
	var normal: Dictionary = g._new_unit(1 - seat, _unit_with("普通", "artillery", 1, 3))
	_run_effect(g, {"op": "pin", "target": "chosen", "turns": 1}, g._context(seat, -1, _compile(_base("压制者")), int(normal.uid)))
	_check(g._pinned(normal), "other units are still pinned")
	_run_effect(g, {"op": "grant_keyword", "target": "chosen", "keyword_id": "core.unpinnable", "keyword_version": 1, "duration": "battle"}, g._context(seat, -1, _compile(_base("解压")), int(normal.uid)))
	_check(not g._pinned(normal), "gaining it lifts an existing pin")
	var spec := _base("第四集团军驯鹿")
	spec.abilities = [{"trigger": "on_death", "effects": [{"op": "modify_cards", "player": "owner", "zones": ["hand"], "filter": {"card_name": "第四集团军驯鹿"}, "duration": "match", "grant_abilities": [{"trigger": "on_play", "effects": [{"op": "grant_keyword", "target": "self", "keyword_id": "core.unpinnable", "keyword_version": 1, "duration": "battle"}]}]}]}]
	_compile_with(spec)

func _aura_reads_guard() -> void:
	var spec := _base("脆弱花卉")
	spec.abilities = [{"trigger": "while_active", "premise": {"test": "compare", "left": {"count_units": {"side": "ally", "keyword_id": "core.guard", "adjacent_to": "self"}}, "cmp": "gte", "right": 1}, "effects": [{"op": "modify_stats", "target": "self", "attack_delta": 1, "health_delta": 0, "duration": "battle"}]}]
	var card := _compile_with(spec)
	var g := _game()
	var seat := _rich(g)
	var flower: Dictionary = g._new_unit(seat, card)
	var base_attack := int(flower.attack)
	var guard: Dictionary = g._new_unit(seat, _unit_with("守卫", "infantry", 1, 3, [_kw("core.guard", 2)]))
	g._remove_from_line(guard)
	g._position_unit(guard, g.line_order(seat, "support").find(int(flower.uid)) + 1)
	for unit in g.state.units: g._recompute(unit)
	_check(int(g._unit(int(flower.uid)).attack) == base_attack + 1, "a guarding neighbour switches the aura on (#158)")
	_run_effect(g, {"op": "destroy", "target": "chosen"}, g._context(1 - seat, -1, _compile(_base("清除")), int(guard.uid)))
	for unit in g.state.units: g._recompute(unit)
	_check(int(g._unit(int(flower.uid)).attack) == base_attack, "and off again when it leaves")

func _salvage_versions() -> void:
	for version in [1, 2]:
		var g := _game()
		var seat := _rich(g)
		var hunter: Dictionary = g._new_unit(seat, _unit_with("收缴者", "infantry", 5, 5, [_kw("core.salvage", version)]))
		hunter.born_turn = int(g.state.turn) - 1
		var prey_spec := _base("高费目标")
		prey_spec.cost = 6
		prey_spec.attack = 1
		prey_spec.health = 2
		prey_spec["sin"] = "wrath"
		var prey: Dictionary = g._new_unit(1 - seat, _compile_with(prey_spec))
		prey.row = "support"
		var hand := int(g.state.players[seat].hand.size())
		_run_effect(g, {"op": "damage", "target": "chosen", "amount": 9}, g._context(seat, int(hunter.uid), hunter.card, int(prey.uid)))
		var got: Array = g.state.players[seat].hand.slice(hand)
		_check(got.size() == 1, "缴获 v%d gives a copy" % version)
		if got.size() == 1:
			var copy: Dictionary = got[0].card.definition
			if version == 1: _check(int(copy.cost) == 3 and copy.get("sin") == "wrath", "v1 copies cost at most 3 (#167)")
			else: _check(int(copy.cost) == 1 and copy.get("sin") == null and int(copy.attack) == 1, "v2 copies cost at most 1 and have no sin (#167)")

func _whole_hand() -> void:
	var g := _game()
	var seat := _rich(g)
	_check(not g.state.players[seat].hand.is_empty(), "there is a hand to remove")
	_run_effect(g, {"op": "remove_hand", "player": "owner"}, g._context(seat, -1, _compile(_base("撤退"))))
	_check(g.state.players[seat].hand.is_empty(), "remove_hand without a name clears the hand (#169)")
	var spec := _order_with("假装撤退", [{"op": "remove_hand", "player": "owner"}, {"op": "schedule", "trigger": "next_own_unit_deployed", "repeat": "each_event", "lifetime": "match", "effects": [{"op": "draw", "player": "owner", "amount": 1}]}])
	_check(Runtime.rules_text(_compile_with(spec)).contains("全部手牌"), "and has rules text")

func _salvage_on_death_and_lowest_attack() -> void:
	var cloud := _order_with("穿云破雾", [{"op": "damage", "target": "chosen", "amount": 1}, {"op": "grant_ability", "target": "chosen", "duration": "end_of_turn", "ability": {"trigger": "on_death", "effects": [{"op": "salvage_copy", "player": "opponent"}]}}], {"side": "enemy", "row": "any"})
	_compile_with(cloud)
	var g := _game()
	var seat := _rich(g)
	var victim: Dictionary = g._new_unit(1 - seat, _unit_with("目标", "infantry", 2, 5))
	_check(_play_spec(g, seat, cloud, int(victim.uid)).is_empty(), "play 穿云破雾")
	var hand := int(g.state.players[seat].hand.size())
	_run_effect(g, {"op": "destroy", "target": "chosen"}, g._context(seat, -1, _compile(_base("后手")), int(victim.uid)))
	_check(int(g.state.players[seat].hand.size()) == hand + 1 and int(g.state.players[seat].hand.back().card.definition.attack) == 1, "a unit that dies later this turn yields a salvage copy (#170)")
	var rise := _order_with("如日方升", [{"op": "destroy", "target": "all_units", "unit_filter": {"attack_rank": "lowest"}, "salvage": true}])
	_check(Runtime.rules_text(_compile_with(rise)).contains("攻击力最低的"), "lowest attack has rules text (#171)")
	var g2 := _game()
	var seat2 := _rich(g2)
	var weak_mine: Dictionary = g2._new_unit(seat2, _unit_with("我方弱", "infantry", 1, 3))
	var weak_theirs: Dictionary = g2._new_unit(1 - seat2, _unit_with("敌方弱", "infantry", 1, 3))
	var strong: Dictionary = g2._new_unit(1 - seat2, _unit_with("敌方强", "tank", 4, 3))
	var before := int(g2.state.players[seat2].hand.size())
	_check(_play_spec(g2, seat2, rise).is_empty(), "play 如日方升")
	_check(g2._unit(int(weak_mine.uid)).is_empty() and g2._unit(int(weak_theirs.uid)).is_empty() and not g2._unit(int(strong.uid)).is_empty(), "every unit with the lowest attack, on both sides, is destroyed")
	_check(int(g2.state.players[seat2].hand.size()) == before + 2, "and each one is salvaged")

func _poisonous() -> void:
	var g := _game()
	var seat := _rich(g)
	var viper: Dictionary = g._new_unit(seat, _unit_with("剧毒单位", "infantry", 1, 5, [_kw("core.poisonous")]))
	viper.born_turn = int(g.state.turn) - 1
	g._remove_from_line(viper); viper.row = "front"; g._position_unit(viper)
	var big: Dictionary = g._new_unit(1 - seat, _unit_with("大块头", "tank", 1, 9))
	g.apply_action(seat, {"type": "attack", "uid": int(viper.uid), "target_uid": int(big.uid)})
	_check(g._unit(int(big.uid)).is_empty(), "剧毒 destroys a unit it damages in combat (#172)")
	var other: Dictionary = g._new_unit(1 - seat, _unit_with("另一个", "tank", 1, 9))
	_run_effect(g, {"op": "damage", "target": "chosen", "amount": 1}, g._context(seat, int(viper.uid), viper.card, int(other.uid)))
	_check(g._unit(int(other.uid)).is_empty(), "and with its abilities' damage")
	var shielded: Dictionary = g._new_unit(1 - seat, _unit_with("免疫者", "tank", 1, 9, [_kw("core.immune")]))
	_run_effect(g, {"op": "damage", "target": "chosen", "amount": 1}, g._context(seat, int(viper.uid), viper.card, int(shielded.uid)))
	_check(not g._unit(int(shielded.uid)).is_empty(), "damage reduced to 0 does not poison")

func _token_sin() -> void:
	var spec := _base("低空补给", "order")
	spec["sin"] = "sloth"
	spec.tokens = [_token("t", "温室")]
	spec.abilities = [{"trigger": "on_play", "effects": [{"op": "summon", "token_id": "t", "amount": 1, "row": "support"}]}]
	var card := _compile_with(spec)
	var g := _game()
	_check(g._generated_card(card, "t").definition.get("sin") == "sloth", "a token without a sin takes its source's sin (#173)")

func _opponent_hand() -> void:
	var spec := _order_with("独脚大盗", [{"op": "transfer_card", "from": "opponent", "source": "hand", "destination": "hand", "mode": "move", "selection": "chosen", "reveal": 3, "amount": 1, "hand_cost_delta": -1}])
	var text := Runtime.rules_text(_compile_with(spec))
	_check(text.contains("随机展示3张") and text.contains("敌方手牌"), "taking from the opponent has rules text (#168)")
	var both := spec.duplicate(true)
	both.abilities[0].effects[0]["player"] = "opponent"
	_compile_with(both, false)
	var g := _game()
	var seat := _rich(g)
	var theirs := int(g.state.players[1 - seat].hand.size())
	var mine := int(g.state.players[seat].hand.size())
	_check(_play_spec(g, seat, spec).is_empty(), "play 独脚大盗")
	_check(int(g.state.players[1 - seat].hand.size()) == theirs - 1 and int(g.state.players[seat].hand.size()) == mine + 1, "one card moves from their hand to mine")
	var taken: Dictionary = g.state.players[seat].hand.back().card
	_check(g.play_cost(seat, taken) == maxi(0, int(taken.definition.cost) - 1), "and costs one less")

func _trial_tool() -> void:
	var trial: RefCounted = load("res://scripts/core/card_trial.gd").new()
	trial.keywords = Runtime.builtin_keywords()
	var card := _base("试卡单位")
	var report: Dictionary = trial._trial(card, {"seed": 7, "my_units": [{"name": "守卫", "unit_class": "infantry", "attack": 1, "health": 3, "keywords": [_kw("core.guard", 2)]}], "hand": [_base("第二张")], "enemy_hand": [_order_with("敌方指令", [{"op": "draw", "player": "owner", "amount": 1}])], "actions": ["play", "play_hand:0", "end_turn", "enemy_play:0"]})
	_check(report.ok, "the trial runs with scenario cards (#160): " + str(report.get("error", "")))
	if report.ok:
		var guard: Array = report.initial.units.filter(func(u): return u.name == "守卫")
		_check(not guard.is_empty() and "core.guard" in guard[0].keywords and guard[0].has("operation_cost"), "scenario units keep their keywords and the snapshot shows them")
		_check(report.steps[1].status == "ok" and report.steps[3].status == "ok", "extra hand cards for both sides can be played")
