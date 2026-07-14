# Task 026 — DB 캐릭터 도메인 스키마 (V15~V17) + 캐릭터 2종 시드

- **Phase**: 7 (캐릭터 중심 전환)
- **구현 기능**: 캐릭터 도메인 토대 (F026~F033 공통)
- **상태**: ✅ 완료

## 개요

캐릭터·아이템·미션·보상의 전 구조를 담는 스키마를 3개 마이그레이션으로 나눠 구축하고, **캐릭터 2종**을 시드한다.
이 Task가 Phase 7 전체의 토대이며, 이후 백엔드(027·028)·앱(029~032)이 전부 여기에 의존한다.

### 핵심 설계 결정
- **★ group(소유·착용) ↔ variant(렌더) 2단 구조**: 원숭이와 레서판다는 체형이 달라(레서판다가 통통하고 팔이 짧음)
  **옷 PNG를 캐릭터별로 따로 그려야 한다**. 그래서 사용자는 `item_groups.code`("빨간 후드티")를 소유·착용하고,
  렌더할 때만 `(group_code + 캐릭터)`로 `character_items` variant를 해석한다.
  → **캐릭터를 바꿔도 옷장이 그대로 따라온다.**
- **★ 단일 멱등 관문**: `character_events(user_id, event_key) UNIQUE` 한 테이블이
  ① 멱등 관문 ② 코인 원장 ③ 리액션 페이로드 ④ 미확인 보상 알림함을 겸한다. 적립·해금·미션·구매가 전부 이 관문을 통과 → **중복 적립 불가**.
- **미션 rule은 JSONB + 순수 함수 판정**: DB 트리거 없이 `MissionEvaluator`(Task 028)가 판정한다. **감정 규칙은 없다**.
- **`user_progress`는 미션 판정 O(1) 캐시** — 매 확정마다 전체 기록을 세지 않는다.
- **캐릭터 2종으로 시작**: 캐릭터가 늘면 **옷 에셋이 곱셈으로 늘어난다**(셔츠 1종 = PNG N장). 추가는 신중히.

## 관련 파일

- `backend/src/main/resources/db/migration/V15__add_character_catalog.sql` — **신규**
- `backend/src/main/resources/db/migration/V16__add_missions.sql` — **신규**
- `backend/src/main/resources/db/migration/V17__add_user_character_state.sql` — **신규**
- `backend/src/test/java/com/recordapp/CharacterSchemaTest.java` — **신규**(Testcontainers, V15~V17 제약 검증)
- `docs/database.md` — ERD·DDL 정합 갱신(별도 작업)

## 구현 항목

### V15 — 카탈로그
- [x] `characters(code PK, name_ko, tagline, rive_artboard, thumbnail_url, sort_order, active)`
  - **2종 시드**: `MONKEY`(원숭이 — 여유롭고 느긋한), `RED_PANDA`(레서판다 — 부지런하고 애착 강한). 둘 다 온보딩 무료 선택
- [x] `item_groups(code PK, slot, name_ko, thumbnail_url, acquire_type, coin_price, sort_order, active)` — **상점·인벤토리가 다루는 단위**
  - `slot` ∈ `HAT` / `OUTFIT` / `GLASSES` / `PROP`(손) / `ROOM_PROP`(방 소품) / `BACKGROUND`
  - `acquire_type` ∈ `DEFAULT` / `MISSION` / `COIN`
- [x] `character_items(id, group_code FK, character_code FK nullable, image_url, rive_slot, render_meta JSONB)` — **렌더 단위(variant)**
  - `character_code` NOT NULL = 캐릭터 전용(HAT/OUTFIT/GLASSES/PROP — 체형·머리 크기 차이)
  - `character_code` NULL = 공용(ROOM_PROP/BACKGROUND — 캐릭터 옆·뒤라 체형 무관)
  - `uq_variant UNIQUE NULLS NOT DISTINCT (group_code, character_code)` — **일반 UNIQUE로는 공용(NULL) variant의 중복을 못 막는다**(하단 요약 참조)
  - `rive_slot` = Rive VM 이미지 프로퍼티명(`hat`/`outfit`/`glasses`/`prop`/`background`/`roomProp0..5`)
  - `render_meta` = `{"anchorX":0.5,"anchorY":0.18,"scale":0.42,"z":30}` — **플레이스홀더 렌더러 전용**(Task 029)
- [x] `character_lines(id, character_code nullable(=공용), context, line_ko, rive_trigger, weight)`
  - **`context`는 감정이 아니라 맥락**: `CONFIRM` / `STREAK_3` / `STREAK_7` / `MISSION` / `LEVEL_UP` / `IDLE`
  - 원숭이는 느긋한 말투, 레서판다는 애쓰는 말투 — **캐릭터별 대사로 성격 대비 구현**

### V16 — 미션(유일한 해금 경로)
- [x] `missions(code PK, title, description, rule JSONB, coin_reward, item_group_reward FK, sort_order, active)`
  - `chk_missions_reward CHECK (coin_reward > 0 OR item_group_reward IS NOT NULL)` — 보상 없는 미션 금지
- [x] `user_missions(user_id, mission_code, achieved_at, PRIMARY KEY(user_id, mission_code))`
- [x] rule 타입(감정 규칙 없음): `DIARY_COUNT` / `CONSECUTIVE_DAYS` / `RESOLUTION_SUCCESS` / `RESOLUTION_STREAK`(기존 `resolutions.streak_seq` 재사용) / `LEVEL`
- [x] 초기 미션 시드(예: `DIARY_10`, `STREAK_7`, `RESOL_1`)

### V17 — 사용자 상태
- [x] `user_character_state(user_id PK, selected_character FK, level, exp)`
- [x] `user_item_groups(user_id, group_code)` — **소유는 group 단위**
- [x] `user_equipment(user_id, slot, slot_index, group_code)` + `CHECK(slot='ROOM_PROP' OR slot_index=0)` — 단일 슬롯 1개 / ROOM_PROP만 0~5 다중 진열
- [x] `user_progress(user_id PK, confirmed_diary_count, consecutive_days, last_confirmed_date, resolution_success_count, max_streak_seq)` — **미션 판정 O(1) 캐시**
- [x] `user_wallets(user_id PK, balance INT CHECK (balance >= 0))`
- [x] `character_events(id, user_id, event_key TEXT, event_type, coin_delta, balance_after, diary_id, payload JSONB, acked_at)` + **`uq_character_events_key UNIQUE(user_id, event_key)`**

## 수락 기준

- [x] V15~V17이 로컬 PostgreSQL 18(`recorme`)에 무오류 적용(기존 V1~V14 무손상)
- [x] 캐릭터 2종(`MONKEY`·`RED_PANDA`) 시드 존재 + 초기 미션 시드 존재
- [x] `uq_variant`·`uq_character_events_key`·잔액 CHECK·미션 보상 CHECK·slot_index CHECK 전부 동작
- [x] `./gradlew compileTestJava` 통과 + Testcontainers 스키마 테스트 전체 통과

## 구현 단계

1. [x] `V15__add_character_catalog.sql` 작성(+ 캐릭터 2종·대사 시드)
2. [x] `V16__add_missions.sql` 작성(+ 초기 미션 시드)
3. [x] `V17__add_user_character_state.sql` 작성
4. [x] 로컬 PostgreSQL 18 적용 실측(`bootRun` 기동 로그로 Flyway 적용 확인)
5. [x] `CharacterSchemaTest`(Testcontainers) 작성·실행 → **전 항목 통과 확인 후에만 완료 처리**

## 테스트 체크리스트 (JUnit5 + Testcontainers)

### 정상 경로
- [x] V15~V17 마이그레이션 무오류 적용, 전 테이블·인덱스 생성 확인
- [x] **캐릭터 2종 시드**(`MONKEY`·`RED_PANDA`) 조회 + `active=true` + `rive_artboard` 값 존재
- [x] `character_lines` context별(CONFIRM/STREAK_3/…) 대사 조회 — 캐릭터별·공용 모두
- [x] group 1개에 캐릭터별 variant 2행(`MONKEY`·`RED_PANDA`) 등록 성공

### 제약/예외 (핵심)
- [x] **`uq_variant(group_code, character_code)` 중복 INSERT → 23505**
- [x] **`uq_character_events_key(user_id, event_key)` 중복 INSERT → 23505**(멱등 관문의 물리적 근거)
- [x] `user_wallets.balance`를 **음수로 UPDATE → CHECK 위반 거부**
- [x] `chk_missions_reward` — `coin_reward=0` + `item_group_reward=NULL` INSERT 거부
- [x] `user_equipment` — slot이 `ROOM_PROP`이 아닌데 `slot_index=1` INSERT 거부
- [x] FK 무결성 — 존재하지 않는 `group_code` 소유(`user_item_groups`) INSERT 거부
- [x] 존재하지 않는 `character_code`로 `user_character_state.selected_character` 설정 거부

### 엣지
- [x] `character_items.character_code` **NULL 허용**(공용 ROOM_PROP/BACKGROUND) + `uq_variant`가 NULL 행에도 의도대로 동작
- [x] `user_equipment` ROOM_PROP **0~5 다중 진열** 정상 + 단일 슬롯(HAT 등)은 1개만
- [x] `character_events.payload` JSONB 저장·조회(리액션 페이로드 왕복)
- [x] `render_meta` JSONB(anchorX/anchorY/scale/z) 저장·조회

## 변경 사항 요약

### ⚠️ 마이그레이션 번호 변경 — V16~V18 → **V15~V17**

원안은 Task 024(감정 수동 입력)가 V15를 쓰고 이 Task가 V16~V18을 쓰는 순서였다.
그러나 **Task 024를 건너뛰고 이 Task를 먼저 착수**하면서 V15가 **빈 번호로 남게** 됐고,
나중에 V15를 채우면 Flyway가 **out-of-order**(이미 V17까지 적용된 DB에 뒤늦게 V15 등장)로 **기동을 거부**한다.
→ 이 Task가 **V15~V17을 선점**하고, **Task 024의 감정 마이그레이션을 V18로 미뤘다.**

### 산출물

| 마이그레이션 | 내용 |
|---|---|
| `V15__add_character_catalog.sql` | `characters` · `item_groups` · `character_items` · `character_lines` + **시드**: 캐릭터 **2종**(`MONKEY`·`RED_PANDA`), 대사 **33행**, item_group **5종**, variant **8행** |
| `V16__add_missions.sql` | `missions` · `user_missions` + **미션 5종** 시드 |
| `V17__add_user_character_state.sql` | `user_character_state` · `user_item_groups` · `user_equipment` · `user_progress` · `user_wallets` · `character_events` |

### 설계상 짚어둘 것 — `uq_variant`는 일반 UNIQUE로는 성립하지 않는다

```sql
CONSTRAINT uq_variant UNIQUE NULLS NOT DISTINCT (group_code, character_code)
```

`character_items.character_code`는 **공용 아이템(ROOM_PROP·BACKGROUND)에서 NULL**이다.
SQL 표준 UNIQUE는 NULL을 서로 다른 값으로 취급하므로, 일반 UNIQUE면 **같은 group의 공용 variant가 무제한 중복 INSERT**된다.
PostgreSQL 15+의 `NULLS NOT DISTINCT`로 NULL도 같은 값으로 보게 해야 공용 variant의 중복이 실제로 막힌다.

### 검증

- `CharacterSchemaTest`(Testcontainers) **통과** — `uq_variant`·`uq_character_events_key` 중복 차단(23505), 잔액 음수 CHECK, `chk_missions_reward`, `slot_index` CHECK, FK 무결성, JSONB(`render_meta`·`payload`) 왕복까지 전 항목.
- 로컬 PostgreSQL 18(`recorme`)에 **실제 적용 완료**(Flyway 스키마 버전 **17**, 기존 V1~V14 무손상).
