# 카드 데이터 형식 (`data/cards.json`)

## 기본 항목
| 항목 | 설명 | 예 |
|---|---|---|
| `id` | 고유 번호 | `"F7"` |
| `name` | 이름 | `"화염의 군주"` |
| `faction` | 진영: `fire` `steel` `shadow` `forest` `neutral` | `"fire"` |
| `rarity` | 희귀도: `common` `rare` `epic` `legendary` `mythic` `ultimate` | `"legendary"` |
| `type` | 종류: `unit` `spell` `trap` `field` `hero` | `"unit"` |
| `cost` | 마나 비용 | `7` |
| `attack`, `health` | 유닛 공격력/체력 | `6`, `6` |
| `keywords` | `taunt`(도발) `charge`(돌진) `shield`(보호막) `poison`(독) `lifesteal`(흡혈) `plunder`(약탈: 공격할 때마다 골드 +1) | `["charge"]` |
| `tags` | 시리즈: `dragon`(드래곤) `lord`(군주) `wolf`(늑대) `knight`(기사). 조합 조건에 쓰임 | `["dragon"]` |
| `upgrade_of` | 이 카드가 상위 호환인 일반 카드 id (설명에 표시) | `"F1"` |
| `target` | 낼 때 대상을 고르는 카드만: `any` `enemy` `enemy_unit` `friendly` `friendly_unit` | `"any"` |
| `trigger` | 함정만: 발동 조건 (아래) | `"enemy_spell"` |
| `text` | 카드에 보이는 설명 | `"등장: 적 영웅에게 3 피해"` |
| `icon` | game-icons 아이콘 이름 (`data/icons.json`에 있어야 함) | `"dragon-breath"` |
| `effects` | 실제 효과 목록 (아래) | |

시장 가격과 등장 확률은 희귀도로 정해집니다 (`core/card_db.gd`의 `RARITY_PRICE`, `RARITY_WEIGHT`).

## effects
```json
{"when": "play", "do": "damage", "target": "chosen", "amount": 4}
```

### when (언제)
| 값 | 뜻 |
|---|---|
| `play` | 낼 때 (유닛의 등장, 주문 효과) |
| `death` | 죽을 때 (유언) |
| `turn_start` / `turn_end` | 내 턴 시작/종료 시 (필드 위 유닛) |
| `trap` | 함정이 발동할 때 |
| `field_turn_start` / `field_turn_end` | 필드 주인의 턴 시작/종료 시 |
| `field_trap_fired` | 필드 주인의 함정이 발동할 때 |

`"ally": true`를 붙이면 **동맹**(이번 턴에 같은 진영 카드를 먼저 썼을 때)일 때만, `"ally": false`면 동맹이 아닐 때만 발동합니다.

조건 / 배수:
- `"if_tag": "dragon"` — 내 필드에 (이 카드 말고) 그 시리즈 유닛이 있을 때만
- `"if_no_tag": "lord"` — 그 시리즈 유닛이 없을 때만
- `"per_tag": "lord"` — `amount` × (이 카드 말고 내 필드의 그 시리즈 유닛 수)

### do (무엇을)
| 값 | 추가 항목 | 뜻 |
|---|---|---|
| `damage` | `target`, `amount` | 피해 |
| `heal` | `target`, `amount` | 회복 |
| `gold` | `amount` | 골드 획득 |
| `draw` | `amount` | 카드 뽑기 |
| `armor` | `amount` | 내 영웅 방어도 |
| `summon` | `token`, `count` | 토큰 소환 (`T_SAPLING` `T_WOLF` `T_SPIRIT`) |
| `buff` | `target`, `atk`, `hp`, `keyword`(선택) | 능력치 강화 |
| `ramp` | `amount` | 최대 마나 증가 (한도까지) |
| `cap_up` | `amount` | 최대 마나 한도 증가 (10 → 최대 15) + 최대 마나 증가 |
| `mana` | `amount` | 이번 턴에만 마나 증가 |
| `steal_gold` | `amount` | 상대 골드 빼앗기 |
| `destroy` | `target` | 처치 |
| `destroy_enemy_traps` | | 상대 함정 전부 파괴 |
| `buy_discount` | `amount` | 이번 턴 다음 구매 할인 |
| `become_hero` | `power`, `armor` | 영웅 교체 (영웅 카드) |
| `counter` | | (함정) 상대 주문 무효 |
| `cancel_attack_freeze` | | (함정) 공격 취소 + 다음 턴 공격 불가 |

### target (누구에게)
`chosen`(낼 때 고른 대상) · `self`(이 카드) · `enemy_hero` · `my_hero` · `all_enemy_units` · `all_enemies`(적 영웅 + 적 유닛) · `my_units` · `my_other_units` · `all_other_units` · `trigger_unit`(함정을 발동시킨 유닛) · `random_enemy`(무작위 적 영웅·유닛, `"times"`번 반복) · `my_tag_units`(내 다른 유닛 중 `"tag"` 시리즈) · `combo_units`(조합에 든 유닛, 조합 효과에서만)

### 함정 trigger
`enemy_attack_hero`(적 유닛이 내 영웅 공격) · `enemy_attack`(적 유닛 공격) · `enemy_spell`(상대 주문) · `enemy_unit_played`(상대 유닛 소환) · `enemy_buy`(상대 시장 구매)

## 조합 (`data/combos.json`)
내 필드에 조건(`need`)에 맞는 유닛이 모이면 **결성**되어 `on_form` 효과가 1번 발동하고,
결성되어 있는 동안 공동 스킬(`skill`)을 턴마다 1번 쓸 수 있습니다. 조건이 깨지면 풀리고, 다시 모이면 다시 결성됩니다.

| 항목 | 설명 |
|---|---|
| `need` | 조건 목록 (모두 만족해야 함). `{"tag": "dragon", "count": 2}` · `{"faction": "fire", "count": 3}` · `{"kw": "taunt", "count": 3}` · `{"all_ids": ["F7", "DR3"]}`(모두 있어야) · `{"any_ids": ["D1", "RD1"], "count": 2}` |
| `cond`, `form_text` | 화면에 보이는 조건 / 결성 효과 설명 |
| `on_form` | 결성될 때 효과 (`when` 없이 `do` 부터) |
| `skill` | `name`, `cost`(마나), `text`, `target`(선택), `effects` |
| `color` | 연출 색 |

## 영웅 (`data/heroes.json`)
- `rarity`: `basic`(처음부터 보유) · `rare` · `epic` · `legendary` (뽑기 확률은 `gacha.weights`)
- `starter: true`면 처음부터 가진 영웅. 나머지는 영웅 뽑기로 얻습니다.
- `bonus_cards`: 시작 덱에 추가되는 전용 카드 id
- `gacha`: `cost`(1회 마석), `weights`(희귀도별 확률), `start_crystals`(처음 주는 마석)
