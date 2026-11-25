# 0.14.0 新增机制

本页对应 GitHub issue #50 #155。旧版本客户端不认识这些写法，使用它们的卡需要 0.14.0 及以上版本。

## 排除所选单位

效果的 `unit_filter` 可以加 `"not_chosen": true`，把卡牌或能力选择的那个单位排除在外：

```json
{"op":"destroy","target":"all_friendly_units","unit_filter":{"not_chosen":true}}
```

- 需要有“所选单位”：卡牌的 `play_target`（部署 / 使用时），或能力自己的 `target`。
- 指令没有来源单位，`all_other_friendly_units` 在指令里等于全部友方单位；要表达“其余友方单位”，请用上面的写法。
- 卡面写作“消灭所选单位以外的友方单位”。

## 被消灭单位的攻防合计

数值来源：

| stat | 含义 |
| --- | --- |
| `destroyed_attack_total` | 本组效果到目前为止实际消灭的单位的**当前**攻击力合计 |
| `destroyed_health_total` | 同上，当前防御力合计 |

- 必须放在同组的 `destroy` 之后。
- 被庇护挡下的消灭不算。
- 按消灭时的当前数值计算，包括光环、受伤后的防御。

《残阳孤路》写作：

```json
{"trigger":"on_play","effects":[
  {"op":"destroy","target":"all_friendly_units","unit_filter":{"not_chosen":true}},
  {"op":"modify_stats","target":"chosen","attack_delta":{"stat":"destroyed_attack_total"},"health_delta":{"stat":"destroyed_health_total"},"duration":"battle"}
]}
```

配合 `"play_target": {"side":"ally","row":"any"}`。

## 卡牌自己声明大 / 小阵营类别（#50）

卡牌可以写 `"category": "large" | "normal" | "small"`：

- `large`（大阵营卡）不能计入副罪孽，`small`（小阵营卡）不能计入主罪孽，`normal` 不受限制。
- 组牌限制**先看卡牌自己的 category**；没写时沿用所属阵营登记的类别（旧卡不受影响）。
- 卡面边框花纹和悬停说明也按卡牌的类别显示。
- 阵营上的类别只作为旧卡的默认值保留；新卡请直接在卡牌上写。
