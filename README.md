# 아르카나 듀얼 (가제) — 알파 v0.1

공용 시장에서 카드를 사서 덱을 키우며, 유닛으로 싸워 상대 영웅을 쓰러뜨리는 **1:1 덱빌딩 결투** 카드게임.

- 엔진: Godot 4.7 (GDScript, Compatibility 렌더러)
- 플랫폼: Windows `.exe`, Android `.apk`
- 기획서: [`docs/design_v0.1.md`](docs/design_v0.1.md)

## 지금 들어간 것 (알파 v0.1)
- 1:1 결투 vs AI (쉬움/보통)
- 튜토리얼 (18단계, 눌러야 할 곳을 화살표로 안내) + 게임 중 상황별 도움말 팁
- 영웅 4명, 시장 카드 40장 + 스타터 4종 + 토큰 3종
- 유닛 / 주문 / 함정 / 공용 필드 / 영웅 카드
- 마나(자동 증가) + 골드(카드 버리기), 시장 구매·갱신·정리
- 시작 손패 교체, 붕괴(13턴부터), 승패 화면
- AI끼리 자동 대전 시뮬레이터 (밸런스 통계), 규칙 단위 테스트, 화면 자동 점검

## 실행하기
### 빌드된 파일로
GitHub의 **Releases**에서 최신 `알파 빌드`를 받으세요.
- Windows: `ArcanaDuel.exe` 실행. "Windows의 PC 보호" 창이 뜨면 **추가 정보 → 실행**을 누르세요 (서명이 없어서 뜨는 경고입니다).
- Android: 폰에서 `ArcanaDuel.apk`를 받아 설치하세요. **출처를 알 수 없는 앱** 설치를 허용해야 합니다.

### Godot 에디터로
1. [Godot 4.7](https://godotengine.org/download)을 설치합니다 (무료, 표준 버전).
2. Godot에서 이 폴더의 `project.godot`을 엽니다.
3. F5를 누르면 실행됩니다.

## 카드 수정하기
카드는 전부 [`data/cards.json`](data/cards.json)에 있습니다. 숫자나 문구를 바꾸면 바로 반영됩니다.
효과를 적는 방법은 [`docs/card_format.md`](docs/card_format.md)를 보세요.

## 밸런스 시뮬레이션
```bash
godot --headless --path . -s res://tests/sim.gd -- 500
```
선공 승률, 영웅별 승률, 평균 게임 길이, 카드별 승률이 출력됩니다.

## 폴더 구조
| 폴더 | 내용 |
|---|---|
| `core/` | 규칙 엔진 (화면과 분리) |
| `ai/` | AI 상대 |
| `ui/` | 화면 (메뉴, 대전, 카드 그리기) |
| `data/` | 카드·영웅·아이콘 데이터 |
| `tests/` | AI끼리 자동 대전 |
| `assets/` | 글꼴 |
| `tools/` | 안드로이드 디버그 서명 키 (개발용) |
| `docs/` | 기획서 |

## 크레딧
[CREDITS.md](CREDITS.md)
