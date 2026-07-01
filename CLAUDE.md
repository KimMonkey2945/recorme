# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 언어 및 커뮤니케이션 규칙

- **기본 응답 언어**: 한국어
- **코드 주석**: 한국어로 작성
- **커밋 메시지**: 한국어로 작성
- **문서화**: 한국어로 작성
- **변수명/함수명**: 영어 (코드 표준 준수)

## 프로젝트 개요

`record`(앱 표기 **`recorme`**)는 하루를 글로 기록하는 **개인 모바일 기록장**이다. 작성한 글을 확정하면 **감정을 외부 LLM으로 분석**하여, 기분에 맞는 **동적 테마(감정 배경·글자·강조색)와 마스코트/시네마틱 영상 연출**을 자동으로 입히는 것이 핵심이다. (감정 기반 **음악**·공유·피드·친구·공감은 **MVP 이후** 범위.)

**모노레포** 구조로, 단일 저장소에서 모바일 앱(`app/`)과 백엔드(`backend/`)를 함께 관리한다.

| 구분 | 스택 |
|---|---|
| 모바일 | Dart / Flutter (SDK `^3.10.x`, Feature-first, Riverpod ^3, go_router ^17, Dio, flutter_quill, supabase_flutter, firebase_messaging) |
| 백엔드 | Java 21, Spring Boot 3.5.x, MyBatis |
| DB | PostgreSQL 18 (Flyway V1~V10) |
| 감정 분석 | 멀티모달 외부 LLM API (`LlmClient` 추상화: Claude/Gemini/Ollama/Stub) |
| 인증 | Supabase Auth(소셜: 카카오/구글, 이메일; 애플 추후) + 백엔드 Supabase JWT(JWKS ES256) 검증 |
| 푸시 | FCM (작심삼일 리마인더/완주, firebase-admin) |

## 현재 상태 (중요)

MVP 핵심 기능이 **구현 완료** 단계다. Phase 1~5(골격·UI·인증·기록 CRUD·작심삼일) + **감정 분석·동적 테마**까지 코드·설정 레벨로 완성됐다. 작업 전 다음을 인지할 것:

- `backend/`: Spring Boot 3.5.x 스캐폴드 완성. 패키지 `com.recordapp` 아래 `domain.{auth,user,diary,emotion,resolution,device}` + `infra.{llm,push,storage}` + `global.*`(보안/예외/표준 응답)이 실제 구현돼 있다. Flyway `V1~V10` 마이그레이션 실재. 로컬은 네이티브 PostgreSQL 18(`recorme` DB)로 `bootRun` 실측됨.
- `app/`: Flutter feature-first 앱 완성. `lib/features/{auth,diary,profile,resolution}` + `lib/core/*` + `lib/shared/*`. 기본 카운터 스캐폴드는 제거됨. flutter_quill 리치 에디터·감정 동적 테마·마스코트/영상 연출·FCM 연동 포함.
- 그래도 **`docs/`가 설계의 단일 진실 공급원(source of truth)**이다. 구현·수정 시 항상 `docs/`와 정합을 맞추고, 신규 기능은 로드맵 순서를 따른다.
- **남은 검증**: ① 백엔드 Testcontainers 통합 테스트 **Docker 일괄 실행**(테스트 코드는 작성 완료, 실행 보류), ② 작심삼일 **FCM 실기기(Z Flip3) 라이브 검증**(딥링크·팬아웃).
- **MVP 이후(미구현)**: 감정 기반 **음악**, 공유·피드·친구·공감, 성능 최적화·배포, 애플 로그인.

## 설계 문서 (구현의 기준)

| 문서 | 내용 |
|---|---|
| `docs/PRD.md` | MVP 제품 요구사항(사용자 여정, 기능 명세 F001~, 페이지·데이터 모델·기술 스택) |
| `docs/ROADMAP.md` | 개발 로드맵(Phase·Task 분해, 기능 ID 추적, 스택 네이티브 테스트 원칙) |
| `docs/architecture.md` | 전체 아키텍처, 확정 결정사항, 트레이드오프, 구현 로드맵 |
| `docs/database.md` | PostgreSQL ERD + 전체 DDL (Flyway `V1~V10` 마이그레이션의 설계 원본) |
| `docs/backend.md` | 패키지 구조, 계층, 표준 응답, MyBatis 매퍼 예시, JWT/LLM 설계 |
| `docs/mobile.md` | Feature-first 구조, Riverpod, Dio 통신, 테마 동적 적용 |
| `docs/api-contract.md` | REST API 계약 (`/api/v1`), 표준 응답·커서 페이징 |

## 핵심 아키텍처 결정 (반드시 준수)

- **패키지 베이스는 `com.recordapp`** — Java `record` 키워드 혼동 회피.
- **백엔드 계층**: Controller → Service(`@Transactional`) → Mapper(MyBatis) → DB. **외부 LLM 호출은 트랜잭션 밖**에서 비동기로 수행.
- **인증은 Supabase Auth**: 앱이 Supabase SDK로 이메일/소셜 로그인(이메일: `signUp`(닉네임→`user_metadata`)·`signInWithPassword`, 확인 메일 필수 / 구글: `signInWithIdToken` / 카카오: `signInWithOAuth`) → Supabase 세션(access JWT + refresh, **SDK가 저장·자동 갱신**). 백엔드는 앱이 보낸 **Supabase access token(Bearer)을 검증**(JWT secret/JWKS)하고 `sub`(uuid)로 `users`를 **JIT(최초 요청 시 자동) 프로비저닝**. **자체 JWT 발급·`refresh_tokens`·`social_accounts`·`SocialVerifier`는 미사용.** Supabase는 **Auth만** 사용(소셜 검증·세션·JWT). **앱 데이터는 Supabase와 무관한 별도 PostgreSQL**(로컬: 네이티브 PostgreSQL 18 `recorme` DB, 배포: Docker/관리형)에 저장하며 **Flyway 단일 진실원**(기능별 마이그레이션 분할: `V1=users`, `V2=diaries`, `V3~V6=사진 인라인화·리치 본문(Delta)·content_text`, `V7=감정 분석(emotion_types + diaries 감정·테마 컬럼)`, `V8=draft→확정 라이프사이클`, `V9=작심삼일`, `V10=device_tokens(FCM)`). PostgREST/RLS/Edge Functions/`profiles` 테이블·트리거 미사용. 인증과 데이터는 물리적으로 분리되므로 `auth.users` FK 없이 `users.supabase_uid` 컬럼으로만 매핑한다. **이메일·소셜은 provider 무관 동일 JIT 경로**이며, 프로필(닉네임·프로필 이미지·자기소개 `bio`)은 `GET/PUT /users/me`로 조회·수정한다.
- **감정 분석은 비동기 + draft→확정 라이프사이클**: 기록은 `analysis_status=DRAFT`(미확정·수정가능·미분석)로 저장 → **'오늘을 기억하기' 확정 시 `PENDING`** 전이 후, **커밋 밖**에서 `@Async`(전용 풀 `emotionAnalysisExecutor`)로 멀티모달 LLM 분석·감정/테마 매핑 후 `DONE` 갱신. 실패 시 `NEUTRAL` 폴백. **확정 시 1회만 분석**(확정 후 수정 불가 → `DIARY_ALREADY_CONFIRMED`, 재분석은 삭제 후 재작성). 누락분은 `EmotionAnalysisPoller`(PENDING 백스톱)가 보완. (음악 매핑은 MVP 이후.)
- **하루 1기록 + 수정**: 사용자·날짜당 일기 1개(`uq_diary_user_day` 부분 유니크). 같은 날짜 재작성은 INSERT가 아닌 **UPDATE**.
- **PK 전략**: 내부 PK는 `BIGINT IDENTITY`, 외부 노출(회원/공유)은 별도 `UUID`(`users.uuid`, `diaries.share_token`).
- **확장 포인트는 인터페이스로 격리**: `EmotionAnalyzer`/`LlmClient`(LLM provider 교체 — **구현됨**: Claude/Gemini/Ollama/Stub), `PushService`(FCM/Stub 폴백), `StorageService`(로컬 디스크, 향후 S3 교체). `MusicSource` + `tracks.source_type`(음악 소스 미정 흡수)는 **MVP 이후**. (소셜 provider 검증은 Supabase Auth가 담당 — 백엔드 `SocialVerifier` 없음.)
- **API 표준 응답**: `{ success, data, error }` 래퍼 + 목록은 커서 페이징(OFFSET 미사용).
- **소셜 상호작용은 공감(리액션)만** — 댓글 기능은 범위 외.

## 자주 쓰는 명령어

### 모바일 (Flutter) — `app/` 디렉터리에서 실행
```bash
cd app
flutter pub get                 # 의존성 설치 (이전 직후 1회 필수: .dart_tool 재생성)
flutter run                     # 앱 실행
flutter analyze                 # 정적 분석 (lint)
flutter test                    # 전체 테스트
flutter test test/widget_test.dart   # 단일 테스트 파일 실행
```

### 백엔드 (Spring Boot) — `backend/` 디렉터리에서 실행
> 로컬은 네이티브 PostgreSQL 18(`recorme` DB, 도커 미사용)에 연결한다. 시크릿(DB 비밀번호·`supabase.url`·LLM 키·`FCM_CREDENTIALS`)은 환경변수로 주입한다.
```bash
cd backend
./gradlew bootRun               # 애플리케이션 실행
./gradlew test                  # 전체 테스트(Testcontainers는 Docker 필요)
./gradlew test --tests "com.recordapp.<클래스명>"   # 단일 테스트
```

## 주의사항

- Flutter 작업은 IDE에서 **`app/`를 프로젝트 루트로 열어야** 정상 인식된다(모노레포 이전 결과).
- 로컬 개발: 백엔드는 네이티브 PostgreSQL 18(`recorme`) 연결, 실기기 테스트는 `adb reverse tcp:8080 tcp:8080`으로 앱→백엔드를 잇는다. FCM 발송은 `FCM_CREDENTIALS`(Firebase 서비스계정 키) 주입 시 활성화되고, 무키면 `StubPushService`로 폴백한다.
- LLM API 키, Supabase JWT secret(백엔드 검증용)·Google OAuth client secret, DB 비밀번호는 환경변수/시크릿으로 주입한다(코드·git 금지). Supabase anon 키는 공개돼도 안전. 루트 `.gitignore`에 `*.env`, `application-secret.yml` 등이 제외되어 있다.
