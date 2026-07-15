# Task 024 — 백엔드 LLM 비활성화 flag + 감정 사용자 입력 전환 (V19)

- **Phase**: 7 (캐릭터 중심 전환)
- **구현 기능**: F018·F019 축소 (감정 분석 비활성화 + 사용자 직접 입력 전환)
- **상태**: ✅ 구현 완료 (2026-07-16)

> ✅ **마이그레이션 번호는 최종 `V19`다.**
> Task 026(캐릭터 스키마)이 V15~V17을, 보상 재설계가 V18(`drop_level_exp`)을 선점해 감정 마이그레이션은
> **`V19__diary_manual_emotion.sql`**로 확정됐다(본문의 옛 "V18" 표기는 정정).
>
> ✅ **감정 LLM 분석은 flag(`record.analysis.enabled`, 기본 false)로 꺼졌다.** 확정 시 즉시 `DONE` + 사용자 감정 저장이
> 기본 동작이며, `ANALYSIS_ENABLED=true` 한 줄이면 기존 `PENDING`→비동기 LLM 분석→`DONE` 경로가 무손상 복구된다.

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

## 변경 사항 요약 (2026-07-16 구현 완료)

- **DB**: `V19__diary_manual_emotion.sql` 신규 — `diaries.emotion_label VARCHAR(20)` 추가 + `chk_diaries_done_has_emotion` DROP(감정 미입력 확정 허용).
- **설정**: `application.yml` `record.analysis.enabled: ${ANALYSIS_ENABLED:false}` 추가. `application-test.yml`은 `enabled: true`로 고정(기존 on-경로 테스트 회귀 보존).
- **빈 게이팅**: `EmotionAnalysisService`·`EmotionAnalysisPoller`·`LlmEmotionAnalyzer`·`LlmConfig.llmClient`에 `@ConditionalOnProperty(name="record.analysis.enabled", havingValue="true")`(삭제 아닌 미등록, 코드베이스 최초 도입). `DiaryService`는 `EmotionAnalysisService`를 `ObjectProvider`로 주입해 빈 부재를 흡수.
- **요청/검증**: `SaveDiaryRequest`에 `emotion`(프리셋 코드) + `emotionLabel`(≤20자) 추가(5-arg 호환 보조 생성자로 기존 호출부 무손상). 프리셋은 `Emotion` enum 엄격 검증(미존재 400), 프리셋+자유텍스트 동시 지정 400 `EMOTION_CONFLICT`(신규 ErrorCode).
- **확정 분기**: `DiaryService.upsert`가 `analysisEnabled ? "PENDING" : "DONE"`으로 확정 상태 결정 → `DiaryMapper.xml upsert`가 `primary_emotion`·`emotion_label`·상태를 반영. off면 즉시 DONE + 감정 저장, AI 필드 NULL.
- **라운드트립**: `DiaryRow`·`DiaryResponse`에 `emotionLabel` 추가(상세·by-date 응답 반환) + `GET /diaries/me/emotions/recent`(최근 커스텀 라벨 중복제거·최신순) 엔드포인트·매퍼 신설.
- **테스트**: `ManualEmotionTest`(off 컨텍스트) + `EmotionAnalysisEnabledTest`(on 회귀) 신규. `FlywayMigrationTest`의 `doneStatusCheck`를 CHECK 제거 반영(감정 없는 DONE 허용) + `emotion_label` 컬럼 존재 검증 추가. **`./gradlew test` 전체 통과**.
- **문서**: `database.md`·`api-contract.md`·`backend.md`·`CLAUDE.md`를 V19 적용·flag 기본 off 기준으로 갱신.

### 남은 연동
- **Task 025(앱)**: 감정 시각 연출 제거 + 작성기 감정 입력 위젯. 백엔드가 `emotionLabel`을 저장·상세응답·recent로 라운드트립하므로 앱이 이를 소비하면 된다.
