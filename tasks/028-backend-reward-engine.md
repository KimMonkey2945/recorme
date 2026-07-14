# Task 028 — ★ 백엔드 보상 엔진 (이벤트 훅 + 멱등 게이트 + 미션 판정 + 코인 + 백스톱 폴러)

- **Phase**: 7 (캐릭터 중심 전환)
- **구현 기능**: F028(코인), F029(상점), F030(미션 해금)
- **상태**: 미착수
- **선행**: Task 026(스키마), Task 027(캐릭터 상태·소유 모델)

> ⚠️ **Phase 7 최대 리스크 지점.** 중복 적립·유실 적립·경합은 전부 여기서 발생한다.
> **여기만 정확하면 나머지는 CRUD다.** 테스트를 가장 두껍게 작성한다.

## 개요

기록 확정('오늘을 기억하기')과 작심삼일 완주를 트리거로 **코인 적립 · 진척도 갱신 · 미션 판정 · 리액션 대사 생성**을 수행하는
보상 엔진을 구현한다. 모든 부작용은 **단일 멱등 관문**을 통과해야만 발생한다.

### 설계 원칙
1. **단방향 훅킹** — `diary`·`resolution` 도메인은 `character`를 **모른다**. 기존 코드는 `publishEvent` **한 줄씩만** 추가한다.
   보상 로직이 터져도 **기록 저장은 롤백되지 않는다.**
2. **AFTER_COMMIT** — 기록이 실제로 커밋된 뒤에만 보상이 나간다. 롤백된 기록에 코인이 붙는 일은 없다.
3. **멱등 게이트가 유일한 진입 조건** — `character_events`에 `event_key`를 `INSERT … ON CONFLICT DO NOTHING`.
   **0행이면 즉시 no-op 반환.** 재전달·폴러 중복·사용자 더블탭이 전부 여기서 흡수된다.
4. **백스톱 폴러** — 비동기 리스너가 유실될 수 있으므로 `EmotionAnalysisPoller`와 동일 철학의 보정 폴러를 둔다.
   게이트가 멱등하므로 **폴러가 돌아도 중복 적립은 불가능**하다.
5. **경합 안전한 코인 소비** — `UPDATE … WHERE balance >= ?` → 0행이면 실패. DB CHECK가 최종 방어선.

## 관련 파일

```
backend/src/main/java/com/recordapp/
├── global/event/         DiaryConfirmedEvent, ResolutionSucceededEvent
├── global/config/        AsyncConfig  (characterExecutor 추가)
└── domain/character/
    ├── controller/       CharacterRewardController
    ├── service/          CharacterRewardService         ★ 멱등 보상 엔진
    │                     CharacterEventListener         ★ AFTER_COMMIT + @Async
    │                     CharacterRewardBackfillPoller  (백스톱)
    │                     MissionEvaluator (순수 함수), LineService
    └── mapper/           CharacterEventMapper(+XML)
```
- **수정(한 줄씩)**: `domain/diary/service/DiaryService.java`(확정=DONE 전이 시 publish), `domain/resolution/service/ResolutionService.java`(`markResolutionSuccessIfAllDone(id)==1` 블록, 기존 push 훅 옆)
- `backend/src/main/resources/application.yml` — `record.character.*` 설정
- `backend/src/main/java/com/recordapp/global/error/ErrorCode.java` — `COIN_INSUFFICIENT`(409)·`FEATURE_DISABLED`(403)
- `backend/src/test/java/com/recordapp/domain/character/CharacterRewardServiceTest.java` — **신규**(Testcontainers, 가장 두껍게)

## 구현 항목

### 이벤트 훅
- [ ] `global/event/DiaryConfirmedEvent(userId, diaryId, writtenDate)` · `ResolutionSucceededEvent(userId, resolutionId, streakSeq)`
- [ ] `DiaryService.upsert` — 확정(DONE 전이) 시 `publishEvent` 1줄
- [ ] `ResolutionService.completeToday` — 완주 확정 블록에서 `publishEvent` 1줄
- [ ] `CharacterEventListener` — `@TransactionalEventListener(AFTER_COMMIT)` + `@Async("characterExecutor")`
- [ ] `AsyncConfig`에 `characterExecutor`(core 2 / max 4 / queue 200 / CallerRunsPolicy)

### ★ 멱등 보상 엔진 (`CharacterRewardService`, `@Transactional(propagation = REQUIRES_NEW)`)
- [ ] ① **게이트**: `character_events`에 `event_key`(`DIARY_CONFIRM:{diaryId}`) `INSERT … ON CONFLICT DO NOTHING` → **0행이면 즉시 return**
- [ ] ② **코인 적립** + `balance_after` 원장 기록
- [ ] ③ `user_progress` **UPSERT + RETURNING**(확정 수·연속일·마지막 확정일·완주 수·최대 streak)
- [ ] ④ `MissionEvaluator`(**순수 함수**)로 미션 판정 — 미션도 `event_key='MISSION:{code}'` 게이트를 통과 → **보상 1회 보장**
- [ ] ⑤ `character_lines`에서 **캐릭터별·맥락별**(CONFIRM/STREAK_3/STREAK_7/MISSION/LEVEL_UP — **감정 아님**) 대사 1줄 선택
- [ ] ⑥ `payload` 갱신 → **앱 리액션의 단일 소스**

### 코인 소비 / 상점
- [ ] `POST /characters/items/{groupCode}/purchase` — `UPDATE user_wallets SET balance = balance - ? WHERE user_id = ? AND balance >= ?`
      → **0행이면 409 `COIN_INSUFFICIENT`**(CHECK 제약이 최종 방어선). 구매도 `event_key='PURCHASE:{groupCode}'` 게이트 통과
- [ ] `record.character.coin-enabled=false`(기본)이면 **403 `FEATURE_DISABLED`** — **적립은 항상 동작, 상점 소비만 게이팅**

### 백스톱 폴러
- [ ] `CharacterRewardBackfillPoller` — 확정됐으나 `character_events`에 게이트가 없는 기록을 주기 스캔·보정

### API
- [ ] `GET /characters/me/wallet` · `GET /characters/me/rewards`(커서 — 미확인 보상함) · `POST /characters/me/rewards/ack`
- [ ] `GET /characters/me/reaction?diaryId=` — **확정 즉시 생성되므로 폴링 불필요**

### 설정
- [ ] `record.character.{coin-enabled: false, coin-per-diary: 10, coin-per-resolution-success: 30, exp-per-diary: 10}`

## 수락 기준

- [ ] 확정 1회 → 코인·진척도·`character_events` **정확히 1행**
- [ ] 같은 이벤트 재전달·폴러 중복 → **잔액·진척도·미션 전부 불변**
- [ ] 미션 임계값 도달 시 **보상 1회만** 지급
- [ ] 기록 저장 트랜잭션 롤백 시 **미적립**(AFTER_COMMIT)
- [ ] 구매 동시 요청 경합에도 **잔액 음수 불가**
- [ ] `diary`·`resolution` 서비스가 `character` 패키지를 **import 하지 않음**(단방향 확인)
- [ ] Testcontainers 시나리오 ①~⑨ 전체 통과

## 구현 단계

1. [ ] `global/event/*` + `AsyncConfig.characterExecutor` 추가
2. [ ] `DiaryService`·`ResolutionService`에 `publishEvent` 한 줄씩(단방향 유지 — character import 금지)
3. [ ] `CharacterEventMapper`(게이트 INSERT·코인 UPDATE·progress UPSERT RETURNING·payload UPDATE) + XML
4. [ ] `MissionEvaluator`(순수 함수) + `LineService`(맥락 기반 대사 선택)
5. [ ] `CharacterRewardService` 구현 — **게이트 → 코인 → 진척도 → 미션 → 대사 → payload** 순서 고정
6. [ ] `CharacterEventListener`(AFTER_COMMIT + @Async) 연결
7. [ ] 구매 API(경합 안전 UPDATE) + `coin-enabled` 게이팅 + ErrorCode 2종
8. [ ] `CharacterRewardBackfillPoller` 구현
9. [ ] 보상함·지갑·리액션 API
10. [ ] Testcontainers 테스트 작성·실행 → **①~⑨ 전 항목 통과 확인 후에만 완료 처리**

## 테스트 체크리스트 (JUnit5 + Testcontainers — 가장 두껍게)

### 정상 경로
- [ ] **①** 기록 확정 1회 → 코인 `coin-per-diary` 적립 + `user_progress.confirmed_diary_count=1` + `character_events` **정확히 1행**(payload에 대사 포함)
- [ ] **④** 작심삼일 완주 → `coin-per-resolution-success` 적립 + `resolution_success_count` 증가 + `RESOLUTION_STREAK` 미션 판정 수행
- [ ] `GET /characters/me/reaction?diaryId=` — 확정 직후 **즉시** 페이로드 반환(폴링 불필요)
- [ ] 획득이 없어도 **대사 1줄은 항상** payload에 존재
- [ ] 보상함 조회(커서) → `POST /rewards/ack` → 미확인 수 감소

### 멱등/중복 (★ 핵심)
- [ ] **②** 같은 `DiaryConfirmedEvent`를 **3회 재전달** → 잔액·진척도·미션·이벤트 행 수 **전부 불변**(게이트 0행 → no-op)
- [ ] **③** 미션 임계값 도달 후 **재판정해도 재지급 없음**(`MISSION:{code}` 게이트) — `user_missions` 1행, 코인 1회
- [ ] **⑥** **백스톱 폴러가 유실분 보정** — 리스너 미실행 상황 시뮬레이션 → 폴러 실행 → **1회만** 적립
- [ ] 폴러와 리스너가 **동시 실행**되어도 중복 적립 없음(게이트 UNIQUE)
- [ ] 구매 `event_key` 게이트 — 더블탭 구매 요청 → 1회만 차감

### 트랜잭션/경합
- [ ] **⑤** 기록 저장 트랜잭션 **롤백 시 미적립**(AFTER_COMMIT 보장 — 기록은 없는데 코인만 들어오면 안 됨)
- [ ] 보상 엔진 예외 발생 시 **기록 저장은 롤백되지 않음**(REQUIRES_NEW 격리)
- [ ] **⑦** 잔액 100, 가격 100인 구매를 **동시 2요청** → 1건 성공 / 1건 **409 `COIN_INSUFFICIENT`**, 잔액 **음수 불가**(CHECK 미발동 = 애플리케이션 레벨에서 이미 차단)

### 엣지/경계값
- [ ] **⑧** **연속일 계산** — 연속 확정 시 +1 / **하루 건너뛰면 1로 리셋** / **같은 날 재확정은 불변**
- [ ] **⑨** `coin-enabled=false` → 구매 **403 `FEATURE_DISABLED`**, 단 **적립은 정상 동작**
- [ ] 미션 임계값 **경계**(9개 → 미달성 / 10개 → 달성)
- [ ] 잔액 0에서 구매 → 409 `COIN_INSUFFICIENT`
- [ ] 미보유 group 구매 후 **소유 반영**(`user_item_groups` 1행) / 이미 보유한 group 재구매 시 차감 없음
- [ ] `diary`·`resolution` 패키지에 `domain.character` **import 0건**(단방향 아키텍처 정적 검증)

## 변경 사항 요약

- (작성 예정) 검증 완료 후 기재
