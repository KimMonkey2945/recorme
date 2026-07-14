# Task 032 — 앱 리액션 오버레이 + 월간 회고 카드 (락인 완성)

- **Phase**: 7 (캐릭터 중심 전환)
- **구현 기능**: F031(기록 리액션), F032(월간 회고·성장)
- **상태**: 미착수
- **선행**: Task 025(상세 화면 연출 제거), Task 028(리액션 페이로드·보상함 API), Task 029(캐릭터 렌더러)

## 개요

Phase 7의 **완성 지점**. 두 축을 붙인다.

1. **리액션(1단계 — 애착 기반 7일 리텐션)**: 기록을 확정하면 **대기 없이 즉시** 내 캐릭터가 등장해 반응한다.
   Task 024로 확정 응답이 곧 `DONE`이므로 **분석 대기·폴링이 구조적으로 없다** → 리액션 지연 0.
2. **월간 회고(2단계 — 락인)**: 이달의 기록·연속일·감정 분포·획득 아이템·캐릭터 성장을 한 장으로 보여준다.
   **데이터가 쌓일수록 떠나기 어려워지는 구조**를 가시화한다.

### 리액션 접점
`diary_detail_view.dart`에서 **인트로·러닝 영상·PENDING 폴링을 제거한 자리**(Task 025)에 `ReactionOverlay`가 들어간다.
페이로드 소스는 `GET /characters/me/reaction?diaryId=` — **`character_events.payload` 단일 소스**(Task 028).
**획득이 없어도 대사 1줄은 항상** 표시한다(빈손 리액션 금지).

> 대사는 **감정이 아니라 맥락**(CONFIRM / STREAK_3 / STREAK_7 / MISSION / LEVEL_UP) 기반이며,
> 원숭이는 느긋한 말투, 레서판다는 애쓰는 말투로 **성격 대비**가 드러난다.

## 관련 파일

- `app/lib/features/character/presentation/widgets/reaction_overlay.dart` — **신규**
- `app/lib/features/character/presentation/widgets/character_speech_bubble.dart` — **신규**
- `app/lib/features/character/presentation/retrospect_page.dart` — **신규**(월간 회고 카드)
- `app/lib/features/diary/presentation/diary_detail_view.dart` — 확정 직후 `ReactionOverlay` 표시
- `app/lib/features/character/data/api_character_repository.dart` — `getReaction(diaryId)`·`getRetrospect(yearMonth)`·`ackReward` 추가
- `backend/src/main/java/com/recordapp/domain/character/service/RetrospectService.java` — **신규**
- `backend/src/main/java/com/recordapp/domain/character/controller/CharacterController.java` — `GET /characters/me/retrospect?yearMonth=`
- `app/test/features/character/reaction_overlay_test.dart`, `retrospect_test.dart` — **신규**
- `app/integration_test/character_journey_test.dart` — **신규**(전 구간 관통 E2E)

## 구현 항목

### 리액션 오버레이 (F031)
- [ ] 확정 직후 상세 진입 → `GET /characters/me/reaction?diaryId=` → **대기 없이 즉시** 캐릭터 등장
- [ ] `character_speech_bubble` — 맥락 기반 대사 1줄(**획득이 없어도 항상 표시**)
- [ ] 코인/미션 획득 카드 렌더(획득 시)
- [ ] 탭하면 `POST /characters/me/rewards/ack` → 홈 상태바 배지 감소(`invalidate`)
- [ ] `CharacterStage` 재사용(플레이스홀더/Rive 스위치 동일) — Rive면 `react` 트리거 발사

### 월간 회고 카드 (F032 — ★ 락인)
- [ ] 백엔드 `RetrospectService` + `GET /characters/me/retrospect?yearMonth=`
- [ ] `retrospect_page.dart` — 이달의 **기록 수 · 연속일 · 감정 분포**(사용자 입력 감정 통계 — 프리셋 + 커스텀 라벨 혼재) ·
      **획득 아이템 · 레벨 성장 · 캐릭터 성장 요약**
- [ ] 진입 동선: 캐릭터 홈 또는 프로필에서 진입

## 수락 기준

- [ ] 확정 직후 **폴링 없이 즉시** 리액션 오버레이 표시(로딩 스피너·영상 없음)
- [ ] 획득이 없어도 **대사 1줄은 항상** 표시
- [ ] ack 후 배지 감소 + 같은 기록으로 재진입 시 오버레이 재표시 안 됨
- [ ] 회고 카드가 기록 수·연속일·감정 분포·획득 아이템·레벨 성장을 정확히 렌더
- [ ] 빈 달(기록 0건)도 깨지지 않음
- [ ] `flutter analyze` 무경고 + `flutter test` + **`integration_test` 전 구간 관통 통과**

## 구현 단계

1. [ ] 백엔드 `RetrospectService` + `GET /characters/me/retrospect` 구현(+ Testcontainers 집계 테스트)
2. [ ] Repository에 `getReaction`·`getRetrospect`·`ackReward` 추가(Api/Fake)
3. [ ] `character_speech_bubble` + `reaction_overlay` 구현
4. [ ] `diary_detail_view`에 리액션 접점 연결(Task 025가 비운 자리)
5. [ ] `retrospect_page` 구현
6. [ ] `flutter test` → `integration_test` 실행 → **전 항목 통과 확인 후에만 완료 처리**

## 테스트 체크리스트

### `flutter test` — 리액션
- [ ] 확정 직후 오버레이 표시 / dismiss 동작
- [ ] **획득 없어도 대사 1줄 표시**(빈손 리액션 금지)
- [ ] 코인 획득 카드 · 미션 달성 카드 렌더
- [ ] 탭 → `ack` 호출 → **배지 감소 + 재표시 안 됨**
- [ ] 캐릭터별 대사 차이 렌더(원숭이 느긋 / 레서판다 애쓰는 말투)
- [ ] 리액션 API 오류 시 상세 화면은 정상(오버레이만 생략 — 기록 조회를 막지 않음)

### `flutter test` — 월간 회고
- [ ] 기록 수·연속일·획득 아이템·레벨 성장 렌더
- [ ] **감정 분포 집계 렌더 — 프리셋 + 커스텀 라벨 혼재**
- [ ] 감정 미입력 기록이 섞여도 집계가 깨지지 않음
- [ ] **빈 달(기록 0건)** 처리(빈 상태 UI)
- [ ] 월 이동(이전/다음), 미래 달 차단
- [ ] 로딩/에러 상태

### `integration_test` — 전 구간 관통 E2E (★)
- [ ] **가입 → 캐릭터 선택(온보딩) → 기록 작성 → 감정 입력 → 확정 → 리액션 즉시 등장 → 코인 반영 → 상점 구매 → 착용 → 홈 반영**
- [ ] 같은 기록으로 재진입 시 **코인 중복 적립 없음**(Task 028 멱등 게이트의 앱 레벨 확인)
- [ ] 확정 → 회고 카드에 즉시 반영

### 백엔드 (Testcontainers)
- [ ] `GET /characters/me/retrospect?yearMonth=` — 기록 수·연속일·감정 분포·획득 아이템 집계 정확
- [ ] 기록 0건인 달 → 빈 집계 반환(에러 아님)
- [ ] 잘못된 `yearMonth` 형식 → 400
- [ ] 타인 회고 조회 불가(IDOR)

## 변경 사항 요약

- (작성 예정) 검증 완료 후 기재
