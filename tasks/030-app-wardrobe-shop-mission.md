# Task 030 — 앱 옷장 · 상점 · 미션 · 보상함 UI

- **Phase**: 7 (캐릭터 중심 전환)
- **구현 기능**: F027(코스튬·옷장), F029(상점), F030(미션 해금)
- **상태**: **부분 구현 — 옷장 완료** (상점·미션·보상함은 Task 028 보상 엔진 선행 필요로 잔여)
- **선행**: Task 027(착용 API) ✅, Task 028(코인·구매·미션·보상함 API) ⏳, Task 029(데이터 계층·홈) ⏳

## 옷장 구현 노트 (완료분)

- **렌더 방식(확정)**: 착용형(HAT/OUTFIT/GLASSES/PROP) 아이템 PNG는 **캐릭터와 동일 프레임의 풀프레임
  투명 PNG**로 제작하고, `IdleCharacterView`가 **같은 메시 워프 정점 배열에 z 오름차순으로 겹쳐 그린다**
  (`overlayAssetPaths`) — 아이템이 캐릭터와 함께 숨쉬고 흔들리며, 앵커 계산이 필요 없다.
  `render_meta`의 anchor/scale은 **BACKGROUND(카드 cover)·ROOM_PROP(스테이지 정적 배치)에만** 쓴다(z는 공통).
- **커밋 모델**: 타일 탭 = 로컬 미리보기(`_provisional`)만 변경 → 하단 저장 바 "저장"에서
  `PUT /characters/me/equipment` 배치 커밋, "취소"는 서버 상태 롤백.
- **진입점**: 캐릭터 홈(Task 029) 전까지 **프로필의 "옷장" 버튼**(임시) → `/wardrobe`(셸 밖 풀스크린).
- ⚠️ `app/assets/items/*`는 **코드 생성 플레이스홀더**(도형)다. 실제 에셋은 캐릭터 원본 위에
  인페인팅으로 아이템을 입혀 생성 → 원본과 diff로 아이템만 추출 → 동일 프레임 투명 PNG로 교체한다
  (Task 031의 교훈: 따로 생성된 이미지는 서로 맞지 않는다).

## 개요

캐릭터 홈 하단 액션에서 진입하는 **옷장 · 상점 · 미션 · 보상함** 화면을 구현한다.
사용자는 `group_code` 단위로 소유·착용하고, 렌더 이미지는 백엔드가 **내 캐릭터 기준 variant**로 해석해 내려준다
(앱은 variant를 몰라도 된다 — Task 027 설계).

**해금은 미션(누적 업적) 단일 경로**임을 UI에서도 명확히 드러낸다.

## 관련 파일

```
app/lib/features/character/presentation/
├── wardrobe_page.dart      (slot 탭 + 착용/해제 → 배치 교체)
├── shop_page.dart          (COIN 아이템 + 잔액 + 구매)
├── mission_page.dart       (미션 목록 + 진행률 + 보상)
├── reward_box_page.dart    (미확인 보상함 + ack)
└── widgets/ item_grid_tile.dart, mission_tile.dart, unlock_progress_bar.dart
```
- `app/lib/features/character/data/api_character_repository.dart` — 착용 배치·구매·미션·보상함 메서드 추가
- `app/test/features/character/wardrobe_test.dart`, `shop_test.dart`, `mission_test.dart`, `reward_box_test.dart` — **신규**

## 구현 항목

- [x] **옷장** `wardrobe_page.dart`: slot 탭(`HAT`/`OUTFIT`/`GLASSES`/`PROP`/`ROOM_PROP`/`BACKGROUND`) +
      `item_grid_tile`(보유/미보유·착용중 표시) → 착용/해제 → **`PUT /characters/me/equipment` 배치 교체**(`group_code` 단위).
      `ROOM_PROP`은 **0~5 다중 진열 슬롯 UI** ✅ (+ `wardrobe_slot_tabs`·`wardrobe_save_bar`, 착용 오버레이 렌더 포함)
- [ ] **상점** `shop_page.dart`: `acquire_type=COIN` group 목록 + 가격·잔액 표시 → 구매 확인 다이얼로그 →
      `POST /characters/items/{groupCode}/purchase`. 성공 시 잔액 차감·소유 반영·옷장 invalidate
- [ ] **상점 에러 UI**: 잔액 부족 → `COIN_INSUFFICIENT` 안내 / `coin-enabled=false` → **`FEATURE_DISABLED`(준비 중) 안내**
- [ ] **미션** `mission_page.dart`: `mission_tile` + **`unlock_progress_bar`**(진행률 — "10개 중 7개 기록") + 달성 시 보상(코인·아이템) 표시.
      **해금은 미션 단일 경로**임을 UI 카피로 명확히
- [ ] **보상함** `reward_box_page.dart`: 미확인 `character_events` 목록(커서 페이징) → 확인 시 `POST /characters/me/rewards/ack`
      → 홈 상태바 배지 감소(`invalidate`)
- [ ] 코인 표시는 `AppColors.currency`(골드) 토큰 사용, `accent`(AI 전용)는 미사용

## 수락 기준

- [ ] 착용/해제 시 배치 payload가 **`group_code` 단위**로 정확히 구성됨
- [ ] 미보유 아이템은 착용 불가(비활성 + 안내)
- [ ] 구매 성공 → 잔액 차감·소유 반영 / 구매 실패 → **에러 UI + 잔액 불변**
- [ ] `FEATURE_DISABLED`(coin-enabled=false) 안내 노출
- [ ] 미션 진행률 바가 `user_progress` 기반 값으로 정확히 렌더
- [ ] 보상함 ack 후 배지 감소 및 목록에서 제거
- [ ] `flutter analyze` 무경고 + `flutter test` 전체 통과

## 구현 단계

1. [ ] Repository에 착용 배치·구매·미션·보상함 메서드 추가(Api/Fake 양쪽)
2. [ ] `item_grid_tile`·`mission_tile`·`unlock_progress_bar` 공통 위젯
3. [ ] `wardrobe_page`(slot 탭·배치 교체·ROOM_PROP 다중 진열)
4. [ ] `shop_page`(가격·잔액·구매 확인·에러 UI)
5. [ ] `mission_page`(진행률·보상 표시)
6. [ ] `reward_box_page`(커서 페이징·ack·배지 동기화)
7. [ ] `flutter analyze` → `flutter test` 실행 → **전 항목 통과 확인 후에만 완료 처리**

## 테스트 체크리스트 (`flutter test`)

### 정상 경로 (옷장)
- [ ] slot 탭 전환 시 해당 slot의 group 목록 렌더(보유/미보유 구분)
- [ ] 착용 → **배치 payload가 `group_code` 단위**로 정확히 구성되어 전송됨
- [ ] 해제 → 해당 슬롯이 payload에서 제거됨
- [ ] `ROOM_PROP` **0~5 다중 진열** 선택·해제
- [ ] 착용 성공 후 홈 캐릭터 렌더 갱신(`invalidate`)

### 정상 경로 (상점·미션·보상함)
- [ ] 상점 목록에 가격·현재 잔액 표시, 구매 확인 다이얼로그 노출
- [ ] **구매 성공 → 잔액 차감 + 소유 반영 + 옷장에 등장**
- [ ] 미션 진행률 바 렌더 + 달성 미션은 보상(코인·아이템) 표시
- [ ] 보상함 커서 페이징 + ack 후 **목록에서 제거 + 홈 배지 감소**

### 에러/예외
- [ ] **구매 실패(잔액 부족) → `COIN_INSUFFICIENT` 에러 UI + 잔액 불변**(낙관적 갱신 롤백)
- [ ] `coin-enabled=false` → **`FEATURE_DISABLED`("준비 중") 안내**, 구매 버튼 비활성
- [ ] 미보유 아이템 착용 시도 불가(타일 비활성) / 서버 409 `ITEM_NOT_OWNED` 방어 UI
- [ ] `ITEM_VARIANT_MISSING`(해당 캐릭터용 variant 미제작) → 안내 후 착용 취소
- [ ] 네트워크 오류 시 에러 상태 + 재시도

### 엣지/경계값
- [ ] 미션 진행률 **0% · 99% · 100%** 경계 렌더
- [ ] 잔액 0 / 가격과 잔액이 정확히 같을 때(구매 성공, 잔액 0)
- [ ] 이미 보유한 아이템은 상점에서 "보유 중"으로 표시(재구매 불가)
- [ ] 보상함 빈 상태 / 미션 0건 / 옷장 slot 빈 상태 렌더

## 변경 사항 요약

### 2026-07-14 — 옷장(F027) 구현 완료

- **렌더러**: `idle_character_view.dart`에 `overlayAssetPaths`(다층 레이어) 추가 — 같은 정점 배열에
  아이템 텍스처만 바꿔 `drawVertices` 반복(레이어 로드 실패는 조용히 스킵).
  `character_stage.dart`에 `equipment` 주입 — 착용형은 z 정렬 오버레이, BACKGROUND는 카드 cover,
  ROOM_PROP은 `render_meta` anchor/scale 정적 배치.
- **데이터**: `ItemGroup`/`MissionLock`/`EquipmentSelection` 도메인 + `fetchItems`/`replaceEquipment`
  (Api/Fake 양쪽, Fake는 V15 시드 미러 + variant 해석 시뮬레이션) + `wardrobeItemsProvider`/
  `ReplaceEquipmentController`.
- **UI**: `wardrobe_page.dart` + `item_grid_tile`(3상태·미션 진행률/코인 가격 캡션)·
  `wardrobe_slot_tabs`·`wardrobe_save_bar`(dirty 시 슬라이드 인). 라우트 `/wardrobe` + 프로필 임시 진입 버튼.
- **에셋**: `app/assets/items/` 11개 플레이스홀더 PNG(풀프레임 모자 2종×2캐릭터·투명 티셔츠·화분·배경·썸네일 3종)
  — V15 시드 `image_url`과 1:1. pubspec 등록.
- **검증**: `flutter analyze` 무경고 · `flutter test` **127개 전체 통과**
  (신규: `character_stage_test.dart` 5개 — z 정렬·슬롯 분리·폴백, `wardrobe_test.dart` 10개 — 미리보기/커밋/롤백/실패).
- **잔여**: 상점·미션·보상함 UI(Task 028 선행), 캐릭터 홈 진입점(Task 029).

### 2026-07-15 — 실사 에셋 파이프라인 검증 + 캐릭터 몸 통일

- **캐릭터 에셋 교체**: 두 캐릭터의 몸 템플릿을 통일한 신규 원본(`docs/recormeImo/chImg/ch_paper_*.png`,
  1600×2604)을 투명화·워터마크 제거 후 표준 프레임(원숭이 848×1400, 판다 803×1400)으로 정규화해
  `app/assets/characters/` 교체. 몸이 같아져 **의상은 한 장으로 두 캐릭터를 커버**한다.
- **에셋 제작 방식 확정** (`docs/recormeImo/item/PROMPT_GUIDE.md`가 단일 기준):
  - 모자·안경 = **단독 제품샷** → 누끼 → 캐릭터별 위치 합성 (성공: 검정 볼캡·둥근 뿔테 안경)
  - 의상·신발 = **캐릭터에 입힌 인페인팅 완성샷** → 원본 bbox 변환으로 동일 프레임 정착.
    사람 옷 제품샷을 얹는 방식은 체형 불일치로 **기각**(실측).
  - **풀룩 세트**: 완성샷에 모자·안경까지 포함되면 머리를 지우지 않고 통째로 세트 오버레이로 쓴다
    (`러브 후드 세트` = 캡+안경+후드+카고+신발) — 완성샷과 픽셀 동일한 착장, 베이스 삐져나옴 없음.
- **Fake 시드에 3개 그룹 추가**(HAT_CAP_BLACK·GLASSES_ROUND·OUTFIT_LOVE_SET, 기본 보유) — 실서비스 반영 시
  V15 시드에도 동일 행 필요. 빈 슬롯 테스트는 GLASSES→PROP으로 이동. **테스트 127개 통과 유지**.
- **프레임 통일 + 부위별 슬롯 확장** (같은 날 3차):
  - 두 캐릭터 캔버스를 **848×1400으로 통일**(몸 중심·발선 정렬) — 몸에 붙는 의류(상의·하의·신발)를
    **공용 variant 1장**으로 쓰기 위한 전제. 캐릭터 N이 늘어도 의류 이미지는 안 늘어난다(모자·안경만 캐릭터별).
  - 옷장 슬롯에 **BOTTOM(하의)·SHOES(신발)** 추가, OUTFIT 라벨을 "상의"로. z 겹침: SHOES 26 < BOTTOM 28
    < OUTFIT 30 < GLASSES 35 < HAT 40. ⚠️ 백엔드 V15 슬롯은 미변경 — 실서비스 반영 시 V18 필요.
  - 부위별 아이템 방식 확정(실측 반복 끝 결론):
    - **의류(상의·하의·신발) = 착용샷 diff 추출** + 후처리(구멍 채움·털색 게이트·경계 침식).
      ⚠️ 공용 1장 공유는 **기각**(원숭이 픽셀 조각이 판다에 노출) — 캐릭터별 착용샷 필요.
    - **모자·안경 = 하이브리드**: 깨끗한 단독 제품샷 누끼를 **착용샷에서 실측한 좌표**(진검정 픽셀 침식 실측)에
      합성 — diff는 얼굴 재렌더 조각(눈썹·눈매)이 섞여 기각. 좌표는 캐릭터당 1회 실측 후 재사용 가능.
    - 생성 도구가 전체 재렌더링을 하는 한 diff 잔여물은 후처리로 관리(원본 보존형 부분 편집 도구면 근본 해소).
  - **원숭이·판다 각 5종(볼캡·뿔테·러브후드·샌드카고·맥스95) 옷장 착용 확인 완료** — 개별 선택·조합·저장 동작.
