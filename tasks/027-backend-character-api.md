# Task 027 — 백엔드 캐릭터·미션 조회/선택/착용 API (group↔variant 해석)

- **Phase**: 7 (캐릭터 중심 전환)
- **구현 기능**: F026(캐릭터 선택), F027(코스튬·옷장), F033(캐릭터 홈·소품 진열)
- **상태**: ✅ 완료
- **선행**: Task 026(**V15~V17** 스키마 + 캐릭터 2종 시드) — 완료

## 개요

`com.recordapp.domain.character` 패키지를 신설하고 캐릭터 조회·선택·아이템 조회·착용(배치 교체)·미션 조회 API를 구현한다.
보상 적립(코인·미션 달성·구매)은 **Task 028**이 담당하며, 이 Task는 **읽기 + 선택/착용 상태 변경**까지다.

### ★ 이 Task의 핵심 = group↔variant 해석
- 소유(`user_item_groups`)·착용(`user_equipment`)은 **`group_code`로만** 저장한다.
- 응답의 렌더 정보는 `(group_code + 선택된 캐릭터)`로 `character_items`를 조인해
  `image_url` / `rive_slot` / `render_meta`를 **해석해서 내려준다**.
- 따라서 **캐릭터를 교체해도 착용 상태는 유지되고 variant만 재해석**된다. 이것이 옷장이 캐릭터를 따라오는 이유다.
- 해당 캐릭터용 variant가 아직 제작되지 않았다면 409 `ITEM_VARIANT_MISSING`.

## 관련 파일

```
backend/src/main/java/com/recordapp/domain/character/
├── controller/  CharacterController, WardrobeController, MissionController
├── service/     CharacterService, WardrobeService, MissionService, CatalogCache
├── mapper/      CharacterCatalogMapper(+XML), UserCharacterMapper(+XML), MissionMapper(+XML)
└── dto/ vo/     CharacterResponse, MyCharacterResponse, ItemGroupResponse,
                 EquipmentRequest(배치), MissionResponse
```
- `backend/src/main/java/com/recordapp/global/exception/ErrorCode.java` — `CHARACTER_NOT_OWNED`(409)·`ITEM_NOT_OWNED`(409)·`ITEM_SLOT_MISMATCH`(400)·`ITEM_VARIANT_MISSING`(409) 추가
  (※ 실제 경로는 `global/exception/` — 설계 시 적어둔 `global/error/`가 아니다)
- `backend/src/test/java/com/recordapp/domain/character/CharacterServiceTest.java` — **신규**(Testcontainers)
- `backend/src/test/java/com/recordapp/domain/character/CharacterControllerTest.java` — **신규**(@WebMvcTest)
- `docs/api-contract.md` — 캐릭터·미션 절 추가(별도 작업)

## 구현 항목

- [x] **기본 상태 JIT 생성**: 최초 접근 시 `user_character_state`·`user_wallets`·`user_progress`를 자동 생성(`ON CONFLICT DO NOTHING` → **멱등**). `UserProvisioningService`와 동일 철학
- [x] `GET /characters` — 캐릭터 2종 목록 + 소유/선택 여부
- [x] `GET /characters/me` — 선택 캐릭터·착용 상태(해석된 variant 포함)·level/exp·코인 잔액·미확인 보상 수
- [x] `PUT /characters/me/selection` — 캐릭터 교체(**착용 유지 + variant 재해석**)
- [x] `PUT /characters/me/equipment` — **배치 교체**(`group_code` 단위, 원자적). 단일 슬롯 1개 / `ROOM_PROP` 0~5 다중
- [x] `GET /characters/items?slot=` — group 목록 + 소유 여부 + **내 캐릭터 기준 variant 이미지**
- [x] `GET /missions` — 미션 목록 + 달성 여부 + **진행률**(`user_progress` 기반 O(1) 산출)
- [x] `CatalogCache` — `characters`·`item_groups`·`character_items`·`missions`는 변경 빈도가 낮으므로 메모리 캐시
- [x] 소유권은 **SecurityContext의 내부 `userId`로만** 결정 → IDOR 구조적 차단(기존 컨벤션)

## 수락 기준

- [x] JIT 기본 상태 생성이 **멱등**(동시 호출에도 1행)
- [x] 미보유 group 착용 시도 → 409 `ITEM_NOT_OWNED`
- [x] slot 불일치 착용(HAT 슬롯에 OUTFIT group) → 400 `ITEM_SLOT_MISMATCH`
- [x] **캐릭터 교체 시 착용 유지 + variant만 재해석**(핵심 시나리오)
- [x] 해당 캐릭터용 variant 미제작 → 409 `ITEM_VARIANT_MISSING`
- [x] 배치 교체가 **원자적**(일부 실패 시 전체 롤백)
- [x] 타인 상태 조회·수정 불가(IDOR)
- [x] `./gradlew compileTestJava` 통과 + @WebMvcTest·Testcontainers 전체 통과

## 구현 단계

1. [x] 패키지·DTO·VO 골격 생성(`domain/character/*`)
2. [x] Mapper + XML 작성 — **group↔variant 조인 SQL이 핵심**(선택 캐릭터 기준 variant 해석)
3. [x] `CharacterService`(JIT 기본 상태·선택 교체) / `WardrobeService`(소유 검증·배치 착용) / `MissionService`(진행률)
4. [x] Controller + ErrorCode 4종 추가
5. [x] `CatalogCache` 적용
6. [x] @WebMvcTest(슬라이스) → Testcontainers(통합) 실행 → **전 항목 통과 확인 후에만 완료 처리**

## 테스트 체크리스트 (JUnit5 + @WebMvcTest + Testcontainers)

### 정상 경로
- [x] `GET /characters` — 2종 반환(`MONKEY`·`RED_PANDA`), 선택 전에는 `selected=false`
- [x] `PUT /characters/me/selection` — 선택 저장 후 `GET /characters/me`에 반영
- [x] `GET /characters/items?slot=HAT` — group 목록 + 소유 여부 + **내 캐릭터 기준 variant 이미지** 반환
- [x] `PUT /characters/me/equipment` — 배치 착용 후 `GET /characters/me`의 착용 목록·variant 정합
- [x] `GET /missions` — 미션별 달성 여부 + 진행률(예: 10개 중 7개 → 70%)

### 에러/예외
- [x] 미보유 group 착용 → **409 `ITEM_NOT_OWNED`**
- [x] slot 불일치 group 착용 → **400 `ITEM_SLOT_MISMATCH`**
- [x] 선택 캐릭터용 variant 미제작 group 착용 → **409 `ITEM_VARIANT_MISSING`**
- [x] 존재하지 않는 캐릭터 코드 선택 → 404/409(`CHARACTER_NOT_OWNED`)
- [x] 미인증 요청 → 401
- [x] **IDOR** — 타인 `userId`를 흉내 낸 요청이 본인 상태만 조작(경로/바디의 사용자 식별자 무시)

### 엣지/회귀 (핵심)
- [x] **★ 캐릭터 교체 시 착용 유지 + variant 재해석**: `MONKEY`로 "빨간 후드티" 착용 → `RED_PANDA`로 교체 →
      착용 목록에 **같은 group_code가 그대로 남고**, `image_url`만 `RED_PANDA` variant로 바뀜
- [x] JIT 기본 상태 생성 **멱등** — 동시 2회 호출에도 `user_character_state`/`user_wallets`/`user_progress` 각 1행
- [x] `ROOM_PROP` **0~5 다중 진열** 정상 / 단일 슬롯에 2개 착용 시도 거부
- [x] 배치 교체 **원자성** — 5개 중 3번째가 미보유면 **전체 롤백**(1·2번도 반영 안 됨)
- [x] 착용 해제(빈 배치 전송) → 전 슬롯 비움 정상
- [x] 공용 variant(`character_code IS NULL`, ROOM_PROP/BACKGROUND)는 **캐릭터 무관하게 해석**됨

## 변경 사항 요약

### 산출물

`com.recordapp.domain.character` 패키지 신설 — controller 3(`Character`·`Wardrobe`·`Mission`) / service 4(`CharacterService`·`WardrobeService`·`MissionService`·`CatalogCache`) / mapper 3(+ XML 3) / dto·vo.

| 엔드포인트 | 비고 |
|---|---|
| `GET /characters` | 캐릭터 2종 + 선택 여부 |
| `GET /characters/me` | **미선택자도 200 + `character: null`** — 온보딩 리다이렉트 판정을 앱이 에러가 아닌 정상 응답으로 하게 하려고 404를 쓰지 않았다 |
| `PUT /characters/me/selection` | 착용 유지 + variant 재해석 |
| `PUT /characters/me/equipment` | **전체 스냅샷 PUT**(배치 교체, 원자적) |
| `GET /characters/items?slot=` | group 목록 + 소유 여부 + 내 캐릭터 기준 variant |
| `GET /missions` | 달성 여부 + `user_progress` 기반 O(1) 진행률 |

ErrorCode 4종 추가(`global/exception/ErrorCode.java`).

### 문서와 의도적으로 다르게 간 것

- **없는 캐릭터 코드 선택 → 404가 아니라 409 `CHARACTER_NOT_OWNED`.**
  "존재하지 않는 코드"와 "존재하지만 내가 못 쓰는 코드"를 앱이 구분할 이유가 없고, 구분해서 내려주면 **카탈로그 존재 여부를 캐내는 열거 신호**가 된다. 하나로 통일했다.
- **DEFAULT 아이템 기본 지급을 JIT 프로비저닝에 포함**(027 원안에 없던 항목).
  `acquire_type='DEFAULT'` 그룹은 미션·구매 어느 경로로도 지급되지 않으므로, 그대로 두면 **아무도 소유하지 못하는 구멍**이 된다. JIT에서 baseline으로 함께 지급한다.
  보상 **적립**이 아니라 초기 상태 구성이므로 Task 028(보상 엔진)의 영역을 침범하지 않는다.

### 검증

- 백엔드 **전체 202개 테스트 통과**(Docker 실기동 — Testcontainers 포함).
- **선행 결함 수정**: `FlywayMigrationTest`·`CharacterSchemaTest`의 `insertUser` 픽스처가 `users.friend_code`(V11에서 NOT NULL + UNIQUE로 추가됨)를 누락해, Docker로 실제 실행하면 **21개가 전부 실패**하던 상태였다. 이 Task에서 함께 고쳤다.
