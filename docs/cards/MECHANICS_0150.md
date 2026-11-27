# 0.15.0 新增机制

本页对应 GitHub issue #156 #157 #158 #160 #167 #168 #169 #170 #171 #172 #173。旧版本客户端不认识这些写法，使用它们的卡需要 0.15.0 及以上版本。

## 随机选定一个目标后分支（#156）

`select_units` 加 `"random": true`：不让玩家选，随机选出 `max` 个（`min` 须等于 `max`；场上不够时有几个选几个）。之后用 `selected_units` 作为目标，再用 `unit_filter` 分支：

```json
[{"op":"modify_kredit_slots","player":"owner","amount":3},
 {"op":"select_units","side":"enemy","min":1,"max":1,"random":true},
 {"op":"damage","target":"selected_units","amount":4,"unit_filter":{"unit_classes":["fighter","bomber"]}},
 {"op":"destroy","target":"selected_units","unit_filter":{"unit_classes":["infantry","tank","artillery"]}}]
```

这就是《恨意》：随机选中一个敌方单位，是空军就受 4 点伤害，是陆军就被消灭。

## 无法被压制（#157）

新内置词条 `core.unpinnable`「无法被压制」：不会受到压制；获得它时已有的压制立即解除。`grant_keyword` 可以授予。

要让手牌里的卡获得它，用 `modify_cards` 的 `grant_abilities` 加一个部署时授予自身的能力（`duration: match` 可随回手保留）：

```json
{"op":"modify_cards","player":"owner","zones":["hand"],"filter":{"card_name":"第四集团军驯鹿"},"duration":"match",
 "grant_abilities":[{"trigger":"on_play","effects":[{"op":"grant_keyword","target":"self","keyword_id":"core.unpinnable","keyword_version":1,"duration":"battle"}]}]}
```

## 持续光环读取词条（#158）

`while_active` 的前提现在可以读取单位的词条，例如“相邻有友方守护单位时”：

```json
{"test":"compare","left":{"count_units":{"side":"ally","keyword_id":"core.guard","adjacent_to":"self"}},"cmp":"gte","right":1}
```

读取时只看单位卡面自带的和效果赋予的词条，**不看其他光环赋予的词条**，这样两个光环不会互相依赖。

## 缴获 v2 与效果收缴（#167 #170 #171）

- **缴获 v2：** `core.salvage` 新增版本 2，收缴副本 1/1，费用至多 1，**没有罪孽**，保留原卡的词条与能力。
  - 版本 1 不变，费用至多 3。
  - 现有卡改用版本 2，需要提交改版：`{"id":"core.salvage","version":2}`。
- **`destroy` 加 `"salvage": true`：** 这个效果消灭的每个单位（双方都算），都把收缴副本（版本 2 规则）加入效果拥有者的手牌。被庇护挡下的不算。
- **新操作 `salvage_copy`（`player: owner | opponent`）：** 把本卡的收缴副本加入该玩家手牌。
- **“本回合内死亡就收缴”（《穿云破雾》）：** 给目标一个只到本回合结束的阵亡能力：

```json
[{"op":"damage","target":"chosen","amount":1},
 {"op":"grant_ability","target":"chosen","duration":"end_of_turn","ability":{"trigger":"on_death","effects":[{"op":"salvage_copy","player":"opponent"}]}}]
```

阵亡能力属于被打的单位，`opponent` 就是使用这张指令的玩家。多次使用会叠加。

## 攻击力最低 / 最高的单位（#171）

效果的 `unit_filter` 可以加 `"attack_rank": "lowest"` 或 `"highest"`：在这个效果原本会作用的单位里，只保留攻击力最低（或最高）的全部单位，并列的都算。《如日方升》写作：

```json
{"op":"destroy","target":"all_units","unit_filter":{"attack_rank":"lowest"},"salvage":true}
```

## 移除全部手牌（#169）

`remove_hand` 不写 `card_name` 时移除该玩家的全部手牌。“本局每次打出单位抽 1”用已有的整局监听：

```json
{"op":"schedule","trigger":"next_own_unit_deployed","repeat":"each_event","lifetime":"match","effects":[{"op":"draw","player":"owner","amount":1}]}
```

## 从敌方取牌（#168）

`transfer_card` 新增：

- `"from": "opponent"`：从**敌方**的手牌、牌组或弃牌区取牌，放进**己方**的手牌、牌组或场上（不能再写 `player: opponent`）。
- `"reveal": 2–5`：先从候选里随机展示 N 张，再从中手动选择（须 `selection: chosen`）。
- `"hand_cost_delta"`：进入手牌的这张牌费用变化（-5 到 5，不为 0）。

《独脚大盗》：

```json
{"op":"transfer_card","from":"opponent","source":"hand","destination":"hand","mode":"move","selection":"chosen","reveal":3,"amount":1}
```

《好高骛远》的“复制 1 张敌方手牌，使其费用 -1”：`mode: copy`，加 `"hand_cost_delta": -1`。

## 剧毒（#172）

新内置词条 `core.poisonous`「剧毒」：本单位对单位造成伤害后（普通攻击、反击和能力伤害），消灭受到伤害的单位。

- 伤害被减到 0、对总部造成伤害时都不触发。
- 一次伤害打到多个单位时，全部消灭。
- 被庇护挡下时扣 1 层庇护。

## 衍生卡继承罪孽（#173）

没有写罪孽的衍生卡（召唤、开发、研发出来的卡）沿用来源卡的罪孽；明确写了别的罪孽时保持不变。新收录或改版的卡，卡库里的衍生卡记录也同样继承。

## 试卡器（#160）

试卡任务的 `scenario` 新增：

| 字段 | 说明 |
| --- | --- |
| `my_units` / `enemy_units` | 场景单位可加 `keywords`、`abilities`，或用 `card` 给出完整卡牌 |
| `hand` / `enemy_hand` | 额外手牌（卡牌数组），动作 `play_hand:N` / `enemy_play:N` 打出 |
| `enemy_deck` | 放进对手牌组的卡牌（其余用填充牌） |
| `seed` | 随机种子，默认 20261109 |

步骤快照里的单位新增行动费、词条、层数、压制、抑制状态。
