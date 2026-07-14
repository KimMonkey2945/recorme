# Task 030 — 앱 옷장 · 상점 · 미션 · 보상함 UI

- **Phase**: 7 (캐릭터 중심 전환)
- **구현 기능**: F027(코스튬·옷장), F029(상점), F030(미션 해금)
- **상태**: 미착수
- **선행**: Task 027(착용 API), Task 028(코인·구매·미션·보상함 API), Task 029(데이터 계층·홈)

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

- [ ] **옷장** `wardrobe_page.dart`: slot 탭(`HAT`/`OUTFIT`/`GLASSES`/`PROP`/`ROOM_PROP`/`BACKGROUND`) +
      `item_grid_tile`(보유/미보유·착용중 표시) → 착용/해제 → **`PUT /characters/me/equipment` 배치 교체**(`group_code` 단위).
      `ROOM_PROP`은 **0~5 다중 진열 슬롯 UI**
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

- (작성 예정) 검증 완료 후 기재
