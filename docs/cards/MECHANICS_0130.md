# 0.13.0 新增机制

本页对应 GitHub issue #137 #144 #151 #152。旧版本客户端不认识这些写法，使用它们的卡需要 0.13.0 及以上版本。

## 一张反制卡挂多个触发时机（#137）

```json
"counter_trigger": ["enemy_unit_deployed", "enemy_order_played"]
```

- `counter_trigger` 仍可写单个时机；写成数组时为 2–8 个不重复的时机，任一时机发生就触发。
- 反制触发后照常扣费并离开伏置区，所以一张卡只结算一次。
- 校验要求数组里**每个**时机都支持所用的效果：
  - `cancel_action` 只能用在打出指令、攻击总部、攻击友方单位这三种时机。
  - `redirect_attack` 只能用在攻击总部、攻击友方单位。
  - `attack_target` 只能用在攻击友方单位。
  - `trigger_unit` 不能和“对方打出指令时”同时出现，因为那个时机没有触发单位。
- `counter_filter` 要求数组里含 `unit_attack_changed`。
- 卡面写作“伏置：对方部署单位后或对方打出指令时触发一次……”。

## 按消灭数量分档强化（#151）

```json
[
  {"op":"select_units","side":"ally","min":1,"max":5},
  {"op":"destroy","target":"selected_units"},
  {"op":"summon","token_id":"giant","amount":1,"row":"support"},
  {"op":"if_destroyed","tiers":[
    {"min":1,"effects":[{"op":"modify_stats","target":"summoned","attack_delta":4,"health_delta":4,"duration":"battle"}]},
    {"min":2,"effects":[{"op":"grant_keyword","target":"summoned","keyword_id":"core.fury","keyword_version":1,"duration":"battle"}]},
    {"min":3,"effects":[{"op":"grant_unit_class","target":"summoned","unit_class":"bomber","duration":"battle"}]}
  ]}
]
```

- **多选上限：** `select_units` 的 `min` / `max` 上限放宽到 5。
- **`if_destroyed`：** 有 1–5 档，`min` 为 1–5，必须从小到大且不重复，每档最多 4 个效果。
  - 必须放在同组 `destroy`（`target: selected_units`）之后。
  - 满足的档位全部按顺序结算，是**叠加**的：消灭 3 个时，第 1、2、3 档都生效。
  - 被庇护挡下的消灭不计数。
- **`target: "summoned"`：** `modify_stats`、`grant_keyword`、`grant_unit_class` 现在可以用它，指同一能力中刚召唤的单位；用之前同一能力里必须先有 `summon`。

## 资源槽可以超过 12（#144）

- **回合开始：** 资源槽每回合 +1，到 12 为止，这一点不变。
- **效果加槽：** `modify_kredit_slots`（单次 -3..3）可以把资源槽加到 **24**。
  - 回合开始不会把超过 12 的资源槽降回去，并且会补满。
  - `gain_kredits` 照常填充到当前资源槽。
- **时机与数值：** 资源槽实际增加时，仍然触发 `own_kredit_slot_gained` / `enemy_kredit_slot_gained`。`friendly_kredit_slots` 可以读到 24。

## 庇护（#152）

新的模板词条 `standard.shelter`，卡面写作“庇护 N”（N 为 1–10）：

```json
"keywords": [{"id":"standard.shelter","version":1,"params":{"n":2}}]
```

- **层数：** 单位入场时获得 N 层“庇护”，存在层数“庇护”里。别的卡可以用 `modify_stacks`（`stack: "庇护"`）增减，用 `stack_count` 读取。
- **挡消灭：** 单位被 `destroy` 时，扣 1 层并取消这次消灭，视为没有被消灭：
  - 不结算阵亡能力和亡计，不触发阵亡监听，不进弃牌堆。
  - 不计入 `selected_destroyed_count`。
  - 来源包括己方效果。
  - 群体消灭时每个单位各扣 1 层。
- **不挡的：** 伤害和战斗致死、降低防御力、移除、回手、洗入牌库、`trigger_death`。
- **清除：** 单位被抑制或离场时清除。
- **显示：** 场上单位的状态栏显示庇护图标和剩余层数。
