# Task 024 — 백엔드 LLM 비활성화 flag + 감정 사용자 입력 전환 (V18)

- **Phase**: 7 (캐릭터 중심 전환)
- **구현 기능**: F018·F019 축소 (감정 분석 비활성화 + 사용자 직접 입력 전환)
- **상태**: 미착수

> ⚠️ **마이그레이션 번호가 V15 → V18로 바뀌었다.**
> Task 026(캐릭터 스키마)을 먼저 착수하면서 **V15~V17을 선점**했다. 이 Task가 V15를 그대로 쓰면
> 이미 V17까지 적용된 DB에 뒤늦게 V15가 등장해 Flyway가 **out-of-order로 기동을 거부**한다.
> → 감정 마이그레이션은 **`V18__diary_manual_emotion.sql`**이다(본문 반영 완료).
>
> ⚠️ **감정 LLM 분석은 지금도 활성 상태다.** 이 Task가 미착수이므로 `record.analysis.enabled` flag 자체가 아직 없고,
> 확정 시 기존 `PENDING` → 비동기 LLM 분석 → `DONE` 경로가 **그대로 동작한다**. 비활성화는 이 Task에서 수행한다.

## 개요

제품 중심을 캐릭터로 옮기기 위해, LLM 감정 분석 파이프라인을 **삭제하지 않고 flag로 비활성화**한다.
감정은 **사용자가 직접 입력**(프리셋 6종 또는 자유 텍스트 ≤20자)하는 **순수 기록 메타데이터**가 되며,
캐릭터 리액션·미션 판정·해금 어디에도 관여하지 않는다(달력 표시·회고 통계 전용).

### 설계 결정
- **코드·테이블 보존**: `domain.emotion`·`infra.llm`·`emotion_types` 마스터·`diaries` 감정/테마 컬럼을 유지하고
  `@ConditionalOnProperty`로 빈만 미등록 → `ANALYSIS_ENABLED=true` **한 줄로 복구 가능**.
- **확정 시 즉시 DONE**: flag off면 확정('오늘을 기억하기') 시 `analysis_status='DONE'`으로 **즉시 전이**.
  분석 대기가 없으므로 앱은 폴링 없이 **리액션 지연 0**으로 캐릭터를 띄울 수 있다(Task 032 전제).
- **스키마 변경 최소**: 프리셋은 기존 `diaries.primary_emotion`(FK) 재사용, 직접 입력만 신규 `emotion_label`.
  FK를 자유 텍스트로 오염시키지 않는다.
- **감정은 선택 사항**: 미입력 확정도 정상 동작해야 하므로 `chk_diaries_done_has_emotion`을 제거한다.

## 관련 파일

- `backend/src/main/resources/db/migration/V18__diary_manual_emotion.sql` — **신규**: `diaries.emotion_label VARCHAR(20)` 추가 + `chk_diaries_done_has_emotion` DROP
- `backend/src/main/resources/application.yml` — `record.analysis.enabled: ${ANALYSIS_ENABLED:false}` 추가
- `backend/src/main/java/com/recordapp/domain/emotion/EmotionAnalysisService.java` — `@ConditionalOnProperty` 부착(보존)
- `backend/src/main/java/com/recordapp/domain/emotion/EmotionAnalysisPoller.java` — `@ConditionalOnProperty` 부착(보존)
- `backend/src/main/java/com/recordapp/domain/emotion/LlmEmotionAnalyzer.java`, `infra/llm/LlmConfig.java` — `@ConditionalOnProperty` 부착(보존)
- `backend/src/main/java/com/recordapp/domain/diary/dto/SaveDiaryRequest.java` — `emotion`(프리셋 코드) + `emotionLabel`(`@Size(max=20)`) 추가
- `backend/src/main/java/com/recordapp/domain/diary/service/DiaryService.java` — flag 분기(off=즉시 DONE + 사용자 감정 / on=기존 PENDING 경로)
- `backend/src/main/java/com/recordapp/domain/diary/mapper/DiaryMapper.xml` — upsert에 `emotion_label`·`primary_emotion` 반영, `findRecentEmotionLabels` 추가
- `backend/src/main/java/com/recordapp/domain/diary/controller/DiaryController.java` — `GET /diaries/me/emotions/recent`
- `backend/src/main/java/com/recordapp/global/exception/ErrorCode.java` — `EMOTION_CONFLICT`(400) 추가
  (※ 실제 경로는 `global/exception/` — 설계 시 적어둔 `global/error/`가 아니다)
- `backend/src/test/java/com/recordapp/domain/diary/ManualEmotionTest.java` — **신규**(Testcontainers)

## 수락 기준

- [ ] `V18__diary_manual_emotion.sql` 적용 — `emotion_label` 추가, `chk_diaries_done_has_emotion` 제거, 기존 확정 기록 무손상
- [ ] `record.analysis.enabled` 기본값 **false**, flag off 시 LLM 관련 빈 **미등록**(컨텍스트에 존재하지 않음)
- [ ] `SaveDiaryRequest.emotion` / `emotionLabel` 둘 다 **선택**, 동시 지정 시 400 `EMOTION_CONFLICT`
- [ ] flag off 확정 → `analysis_status='DONE'` 즉시 전이 + 사용자 감정 저장 + AI 필드(색상·코멘트·제목·이모지·점수) NULL
- [ ] flag on 복구 시 기존 `PENDING` + 비동기 분석 경로 **무손상 동작**(회귀 방지)
- [ ] `GET /diaries/me/emotions/recent` — 최근 사용 커스텀 감정 목록 반환
- [ ] `./gradlew compileTestJava` 통과 + Testcontainers 시나리오 전체 통과

## 구현 단계

1. [ ] `V18__diary_manual_emotion.sql` 작성 및 로컬 PostgreSQL 18(`recorme`) 적용 실측
2. [ ] `application.yml`에 `record.analysis.enabled` 추가 + LLM/emotion 빈에 `@ConditionalOnProperty` 부착(삭제 금지)
3. [ ] `SaveDiaryRequest` 필드 추가 + 상호 배타 검증 → `EMOTION_CONFLICT` ErrorCode 신설
4. [ ] `DiaryService.upsert` flag 분기(off = 즉시 DONE / on = 기존 PENDING 경로 그대로)
5. [ ] `DiaryMapper.xml` upsert에 감정 컬럼 반영 + `findRecentEmotionLabels` 쿼리 추가
6. [ ] `GET /diaries/me/emotions/recent` 엔드포인트 추가
7. [ ] Testcontainers 테스트 작성 및 실행 → **전 항목 통과 확인 후에만 완료 처리**

## 테스트 체크리스트 (JUnit5 + Testcontainers)

### 정상 경로
- [ ] flag off + 프리셋 감정(`JOY`)으로 확정 → `analysis_status='DONE'`, `primary_emotion='JOY'`, `emotion_label` NULL, AI 필드 전부 NULL
- [ ] flag off + 직접 입력(`emotionLabel="설렘"`)으로 확정 → `DONE`, `emotion_label='설렘'`, `primary_emotion` NULL
- [ ] **감정 미입력 확정도 성공**(CHECK 해제 확인) — 두 필드 모두 NULL이어도 `DONE`
- [ ] `GET /diaries/me/emotions/recent` — 최근 사용한 커스텀 라벨이 중복 제거·최신순으로 반환

### 에러/예외
- [ ] 프리셋 + 커스텀 **동시 지정** → 400 `EMOTION_CONFLICT`
- [ ] `emotionLabel` **21자** → 400 `VALIDATION_ERROR`
- [ ] 존재하지 않는 프리셋 코드 → 400(FK 위반이 아니라 검증 단계에서 차단)
- [ ] 확정된 기록 재upsert → 기존 409 `DIARY_ALREADY_CONFIRMED` 유지(라이프사이클 무손상)

### 엣지/회귀 (가장 중요)
- [ ] **flag on 복구 시 기존 분석 경로 정상**: 확정 → `PENDING` → 비동기 분석 → `DONE` + AI 필드 채워짐
- [ ] flag off 상태에서 `EmotionAnalysisService`·`EmotionAnalysisPoller`·`LlmClient` 빈 **미등록** 확인(`ApplicationContext` 조회 실패)
- [ ] flag off 상태에서 **LLM 외부 호출 0회**(Stub 호출 카운터로 검증)
- [ ] `emotionLabel` 20자 **경계값** 정상 저장
- [ ] V18 적용 후 기존 DONE 기록(LLM 분석 결과 보유)이 그대로 조회됨(데이터 손실 없음)

## 변경 사항 요약

- (작성 예정) 검증 완료 후 기재
