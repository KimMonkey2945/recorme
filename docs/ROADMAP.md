# record 개발 로드맵

날짜별로 하루를 글로 기록하고 언제든 다시 꺼내볼 수 있는 개인 모바일 기록장 — Flutter 앱과 Spring Boot 백엔드를 단일 저장소에서 함께 관리하는 모노레포 프로젝트.

## 개요

`record`는 매일 짧은 글쓰기로 하루를 정리하고 싶은 모바일 사용자를 위한 **날짜 기반 개인 기록장**으로, MVP에서 다음 핵심 기능을 제공합니다:

- **소셜 로그인 (Supabase Auth, F001/F010)**: Supabase Auth로 소셜 로그인(카카오/구글) → Supabase 세션(JWT). 백엔드는 Supabase JWT를 검증하고 최초 요청 시 자동 가입(JIT 프로비저닝). 세션 발급·갱신은 Supabase SDK가 담당
- **캘린더 기반 작성·조회 (F002/F003/F005)**: 월별 캘린더에서 작성 여부를 점(dot)으로 표시하고, 날짜 탭으로 신규 작성 또는 단건 조회로 분기
- **하루 1기록 upsert (F003/F006)**: `(user_id, written_date)` 부분 유니크 기반 upsert로 같은 날짜 재작성은 INSERT가 아닌 UPDATE 처리. 클라이언트는 기록 id 없이 날짜+내용만으로 저장
- **목록 탐색 + 소프트 삭제 (F004/F007)**: 커서 기반 무한 스크롤로 과거 기록을 역순 탐색하고, `deleted_at` 기록으로 소프트 삭제(삭제 후 같은 날짜 재작성 허용)

> 아키텍처·DB·API 계약의 단일 진실 공급원은 `docs/`다. 모든 구현은 `docs/PRD.md`, `docs/architecture.md`, `docs/database.md`, `docs/backend.md`, `docs/mobile.md`, `docs/api-contract.md`를 기준으로 한다.

## 기술 스택

| 구분 | 스택 |
|---|---|
| 모바일(`app/`) | Flutter / Dart(SDK `^3.10.x`), feature-first 구조, **flutter_riverpod ^3.x**, **go_router ^17.x**, Dio(Supabase 토큰 첨부 인터셉터), **flutter_secure_storage ^10.x**, supabase_flutter(Supabase Auth) / google_sign_in ^7.x, image_picker, **flutter_quill ^11.x(리치 텍스트 에디터, Delta JSON) + flutter_quill_extensions + flutter_localizations**, **video_player(감정 마스코트·러닝 로딩·로그인 영상 연출)**, firebase_core/firebase_messaging ^16.x + flutter_local_notifications ^22.x(FCM), **캐릭터 렌더는 `IdleCharacterView`(통짜 PNG 12×16 메시 워프 — `drawVertices` + `ImageShader`, 추가 의존성 0). `rive`는 미도입 — Rive·파츠 조립을 둘 다 검토·시도했다가 되돌렸다(Task 031)**. ※ 모델은 freezed 미도입·손 작성(Task 004 비고). ※ Phase 7에서 `flutter_shaders`·감정 mp4/셰이더 연출 제거(로그인 마스코트 영상·`video_player`는 유지) |
| 백엔드(`backend/`) | Java 21 / Spring Boot 3.5.x, 도메인 기반 패키지 `com.recordapp.domain.*`(`auth`·`user`·`diary`·`emotion`·`resolution`·`device`) + `infra.*`(`llm`·`push`·`storage`), Controller → Service(@Transactional) → Mapper(MyBatis) → PostgreSQL, **Supabase JWT 검증(JWKS ES256 비대칭, `spring-boot-starter-oauth2-resource-server`, 자체 발급 없음)**, **멀티모달 감정 분석(`infra.llm` LlmClient 추상화: Claude(`anthropic-java`)·Gemini·Ollama·Stub / `@Async` 전용 풀 + Poller 백스톱)**, firebase-admin(FCM) |
| DB | PostgreSQL 18.x(로컬 네이티브), Flyway 11.x, **기능별 마이그레이션 분할**(`V1=users`, `V2=diaries`, `V3=diary_images(→V5에서 제거)`, `V4=리치 본문(content=Delta JSON·content_text)`, `V5=diary_images 제거`, `V6=content_text NOT NULL`, `V7=감정 분석(emotion_types 마스터 + diaries 감정·테마 컬럼)`, `V8=draft→확정 라이프사이클(analysis_status 기본값 DRAFT·CHECK)`, `V9=resolutions+resolution_checks(작심삼일)`, `V10=device_tokens(FCM)`, `V11~V14=소셜(friendships·visibility·피드 인덱스·diary_reactions)`, **`V15=diary_manual_emotion(감정 사용자 입력 — emotion_label 추가·done-has-emotion CHECK 해제)`**, **`V16=add_character_catalog(characters·item_groups·character_items(variant)·character_lines)`**, **`V17=add_missions(missions·user_missions)`**, **`V18=add_user_character_state(user_character_state·user_item_groups·user_equipment·user_progress·user_wallets·character_events)`**) |
| 테스트(앱) | `flutter test`(위젯/유닛) + `integration_test`(E2E) |
| 테스트(백엔드) | JUnit5 + Spring Boot Test(@WebMvcTest/@SpringBootTest) + Testcontainers(PostgreSQL) |

## 개발 워크플로우

1. **작업 계획**

- 기존 코드베이스(`app/`, `backend/`)와 `docs/`를 학습하고 현재 상태를 파악
- 새로운 작업을 포함하도록 `docs/ROADMAP.md` 업데이트
- 우선순위 작업은 마지막 완료된 작업 다음에 삽입

2. **작업 생성**

- `docs/` 설계 문서를 기준으로 현재 상태를 파악
- `/tasks` 디렉토리에 새 작업 파일 생성
- 명명 형식: `XXX-description.md` (예: `001-backend-skeleton.md`)
- 고수준 명세서, 관련 파일(`app/` 또는 `backend/` 경로), 수락 기준, 구현 단계 포함
- **API 연동/비즈니스 로직 작업 시 "## 테스트 체크리스트" 섹션 필수 포함** (앱은 `integration_test`/`flutter test`, 백엔드는 JUnit5 + Testcontainers 시나리오 작성)
- 예시를 위해 `/tasks` 디렉토리의 마지막 완료된 작업 참조. 현재 작업이 `008`이라면 `007`과 `006`을 예시로 참조
- 완료된 작업 파일은 체크된 박스와 변경 사항 요약을 포함함. 새 작업은 빈 박스이며 변경 사항 요약이 없어야 함. 초기 상태 샘플은 `000-sample.md` 참조

3. **작업 구현**

- 작업 파일의 명세서를 따라 `app/`/`backend/` 기능 구현
- **구현이 끝나면 반드시 스택 네이티브 테스트 수행** (앱: `flutter test` + `integration_test`, 백엔드: JUnit5 + Testcontainers) — 테스트는 선택이 아닌 필수 단계
- **API 연동 및 비즈니스 로직은 정상 경로 + 에러/예외(401·404·유효성·만료) + 엣지(경계값·중복 날짜 upsert·소프트 삭제 후 재작성)를 모두 포함해 꼼꼼히 검증**
- 각 단계 후 작업 파일 내 단계 진행 상황 업데이트
- 구현 완료 후 E2E/통합 테스트 실행 → **통과를 확인한 후에만** 다음 단계로 진행
- 테스트 실패 시 원인을 수정하고 재테스트하며, 통과 전에는 해당 Task를 완료로 표시하지 않음
- 각 단계 완료 후 중단하고 추가 지시를 기다림

4. **로드맵 업데이트**

- 로드맵에서 완료된 작업을 ✅로 표시 (테스트 통과 확인 후에만)

## 개발 단계

### Phase 1: 애플리케이션 골격 구축

전체 라우트/패키지 구조와 빈 화면, 스키마, 표준 응답·JWT 골격을 먼저 완성한다. 실제 비즈니스 로직 없이 앱과 백엔드가 독립적으로 빌드·실행되는 상태가 목표.

- **Task 001: 백엔드 스캐폴딩 및 DB 스키마 구축** - 구현 완료(Docker 검증 보류) · See: `/tasks/001-backend-skeleton.md`
  - 구현 기능: 인프라 기반 (전 기능 공통 토대)
  - ✅ 스캐폴드/Flyway V1/설정/Testcontainers 테스트 코드 작성, `compileTestJava` 통과. Testcontainers 실행은 프로젝트 완성 후 Docker로 일괄 검증 예정(사용자 결정).
  - Spring Initializr로 `backend/` 스캐폴드 생성 (Gradle, Java 21, Spring Boot 3.3.x, MyBatis, PostgreSQL, Flyway)
  - 패키지 베이스 `com.recordapp`, 도메인 기반 패키지 골격 `domain.{auth,user,diary}` 생성 (`.gitkeep` 제거)
  - Flyway `V1__init.sql` 작성: `users`, `social_accounts`, `diaries`, `refresh_tokens` 테이블 + `uq_diary_user_day` 부분 유니크(`WHERE deleted_at IS NULL`)
  - `application.yml` 환경변수 주입 구조 (DB 비밀번호·JWT 시크릿·LLM 키는 시크릿으로)
  - Testcontainers(PostgreSQL)로 Flyway 마이그레이션이 정상 적용되고 부분 유니크 제약이 동작하는지 검증
  - ⚠️ **Supabase Auth 전환**: `social_accounts`·`refresh_tokens` 제거 + `users.supabase_uid`(UNIQUE) 추가는 Task 007에서 V1 수정으로 반영(운영 DB 미배포 상태).

- **Task 002: 백엔드 공통 인프라 골격 (표준 응답·예외·JWT)** - 구현 완료(단위 테스트 통과) · See: `/tasks/002-backend-common-infra.md`
  - 구현 기능: F001/F010 토대
  - ✅ 표준 응답/예외/JWT/커서 페이징/SocialVerifier 골격 + JwtProvider·HashUtil 단위 테스트 통과. `@SpringBootTest` 컨텍스트 로드(Docker)는 프로젝트 완성 후 검증.
  - 표준 응답 래퍼 `{ success, data, error }` + 공통 응답 빌더
  - 전역 예외 핸들러(`@RestControllerAdvice`) + 에러 코드 enum (`DIARY_NOT_FOUND`, `UNAUTHORIZED` 등)
  - JWT 발급/검증 유틸 골격(access 단기 + refresh 회전), 인증 필터/`SecurityConfig` 골격 (실제 로그인 로직은 Phase 3)
  - 확장 포인트 인터페이스 격리: `SocialVerifier`(provider별 검증)
  - 커서 페이징 공통 응답 구조(`items`, `nextCursor`, `hasNext`) 정의
  - ⚠️ **Supabase Auth 전환**: 위 JWT 발급/검증 골격·`SocialVerifier`·`HashUtil`·refresh 회전은 Task 007에서 제거하고 `SupabaseJwtFilter`로 대체한다(완료 기록은 보존).

- **Task 003: 앱 feature-first 골격 및 라우팅 구성** ✅ - 완료 · See: `/tasks/003-app-skeleton-routing.md`
  - 구현 기능: 전 화면 골격
  - ✅ feature-first 구조, go_router 5화면 + 하단 탭 셸 + 인증 가드, 카운터 제거. `flutter analyze` 무경고.
  - `lib/core/`, `lib/features/`, `lib/shared/` 폴더 구조 확립 (`.gitkeep` 제거), 카운터 스캐폴드 정리
  - 의존성 추가: flutter_riverpod, go_router, dio, freezed, json_serializable, flutter_secure_storage, google_sign_in (※ 인증 Supabase Auth 전환으로 kakao SDK 제거·`supabase_flutter` 추가됨 — Task 010)
  - go_router 라우트 5개 화면 빈 껍데기: 로그인 / 메인(캘린더) / 글 에디터 / 글 목록 / 글 상세
  - 인증 상태 기반 리디렉션 가드 골격(토큰 유무 → 로그인/메인 분기)
  - 하단 내비게이션 바(캘린더 탭 / 목록 탭) ShellRoute 골격

- **Task 004: 앱 모델·DTO 및 네트워크 골격** ✅ - 완료 · See: `/tasks/004-app-models-network.md`
  - 구현 기능: F001~F007 공통 토대
  - ✅ 모델/DTO, Dio+AuthInterceptor, secure storage, Riverpod provider. `flutter analyze` 무경고 + 모델 테스트 3/3. ⚠️ freezed 코드 생성 보류(손 작성 모델로 대체) — 아래 비고 참조.
  - freezed + json_serializable 모델: `User`, `Diary`, `DiarySummary`, 표준 응답 래퍼, 커서 페이지 모델, 토큰 응답 DTO
  - Dio 클라이언트 골격 + `AuthInterceptor` 골격(Authorization 헤더 주입, 401 → refresh 자동 갱신 자리, `QueuedInterceptorsWrapper`)
  - `flutter_secure_storage` 기반 토큰 저장소 추상화 골격
  - Riverpod provider 골격(인증 상태, Dio 인스턴스) 배치
  - `flutter analyze` 통과 및 코드 생성(build_runner) 정상 동작 확인

### Phase 2: UI/UX 완성 (더미 데이터 활용) ✅

5개 화면 UI와 내비게이션을 더미 데이터로 완성해 전체 사용자 플로우를 체험 가능하게 만든다. 백엔드 연동 없이 앱 단독으로 동작.

> 구현 방식: "조용한 기록장" 디자인 컨셉(중립 캔버스 + 더스크 바이올렛 accent) + 화사한 웜 그라데이션 배경(Foodu 톤 참고). 더미 데이터는 `DiaryRepository` 추상 + `FakeDiaryRepository`로 격리(Phase 3에서 구현체만 교체). 앱명 `record` → `recorme`로 정합화. `flutter analyze` 무경고 + `flutter test` 17개 통과.

- **Task 005: 로그인·캘린더 화면 UI 구현 (더미)** ✅ - 완료
  - 구현 기능: F001, F002 (UI)
  - ✅ 디자인 토큰·공통 위젯 토대(테마/spacing/Empty·Error·Loading·ConfirmDialog·SnackBar), 더미 `DiaryRepository`+`FakeDiaryRepository`+Riverpod provider, 로그인 UI(recorme 브랜딩·카카오 말풍선/구글 멀티컬러 G 아이콘), 캘린더 UI(월 스와이프·작성일 dot·오늘 강조·날짜 탭 분기). `flutter analyze` 무경고.
  - 로그인 페이지: 카카오/구글 소셜 로그인 버튼, 에러 토스트 자리 (실제 SDK 호출은 Phase 3)
  - 메인 페이지: 월별 캘린더 위젯, 좌우 스와이프 월 이동, 작성된 날짜 dot 표시(더미 summary), 오늘 날짜 하이라이트
  - 날짜 탭 분기 로직(더미 기준: 기록 있음 → 상세, 없음 → 에디터)
  - 상단 앱 바 로그아웃 버튼 배치(F010 자리)
  - 반응형/접근성 기준 적용, 더미 데이터 유틸 작성

- **Task 006: 에디터·목록·상세 화면 UI 구현 (더미)** ✅ - 완료
  - 구현 기능: F003, F004, F005, F006, F007 (UI)
  - ✅ 에디터(날짜 읽기전용·멀티라인·upsert 저장·수정모드 프리필), 목록(날짜 역순·2줄 미리보기·커서 무한스크롤·당겨서 새로고침·빈/에러 상태), 상세(분석상태 배지·수정 이동·삭제 확인 다이얼로그→소프트 삭제→메인 복귀). 전체 플로우 점검 + 단위/위젯/페이지 테스트 17개 통과(`flutter analyze` 무경고). 웹(release) 전 화면 렌더 확인.
  - 글 에디터 페이지: 선택 날짜 표시(변경 불가), 멀티라인 입력 필드, 저장/취소 버튼, 수정 모드 시 기존 내용 로드(더미)
  - 글 목록 페이지: 날짜 역순 목록, 날짜 헤더 + 내용 2줄 미리보기(말줄임), 무한 스크롤 골격(더미 페이지네이션)
  - 글 상세 페이지: 날짜 헤더 + 전체 내용 스크롤, 수정 버튼, 삭제 버튼 + 삭제 확인 다이얼로그
  - 전체 내비게이션 플로우 검증(로그인 → 캘린더 → 작성 → 목록 → 상세 → 수정/삭제)
  - 반응형 디자인 및 모바일 최적화

### Phase 3: 핵심 기능 구현

백엔드 인증·기록 CRUD를 실제로 구현하고, 앱의 더미 데이터를 실제 API 호출로 교체한다. 인증은 소셜(카카오/구글)에 더해 **이메일 가입/로그인**(확인 메일 필수)을 지원하고, 가입 정보는 별도 PostgreSQL `users`에 JIT 저장되며 **프로필 조회·수정(F011)**을 제공한다. 인증 검증은 **JWKS(ES256 비대칭)**, 로그인 즉시 JIT 저장(워밍업), **웹 구글 OAuth·중복가입 안내·비밀번호 재설정**까지 포함한다. DB는 **기능별 마이그레이션 분할**(`V1=users`, `V2=diaries`)로 구성한다. 모든 API/로직 Task는 구현 직후 스택 네이티브 테스트로 검증한다.

> **진행 현황(2026-06-26)**: 인증·프로필 토대(Task 007 계열·010 계열) + **기록 CRUD·사진 첨부·글자수 제한(Task 008·009·011·011-1) 구현 완료**. 백엔드: `V2 diaries`(content CHECK 1~500)·`V3 diary_images`(1:N, 경로만 저장), DiaryController/Service/Mapper(upsert ON CONFLICT 201/200·커서 페이징·소유권 IDOR 차단), 사진 업로드/삭제(StorageService 재사용, 파일 IO 트랜잭션 밖+보상삭제, **삭제 시 디스크 파일 즉시 회수**), `IMAGE_LIMIT_EXCEEDED`(409)·multipart 26MB. 컴파일·@WebMvcTest 통과, Testcontainers(DiaryServiceTest·DiaryIntegrationTest) 작성 완료(실행은 배포 전 Docker 일괄). 앱: 에디터 사진 썸네일·글자수 카운터(하드 500)·`ApiDiaryRepository` 실연동, `flutter test` 63개 + `integration_test` 4개 통과, `flutter analyze` 무경고. 확정 정책: **글자수 500자 하드 제한**(앱 maxLength+백엔드 @Size+DB CHECK 동일 상수), **사진 기록당 5장·장당 5MB**(디스크 저장·DB 경로만·삭제 시 디스크 회수). MVP 스코프상 theme/track·피드는 Phase 4. **남은 검증: Testcontainers Docker 일괄 실행**.
> **추가 고도화(Task 011-2, 2026-06-26)**: 본문을 **리치 텍스트(flutter_quill, Delta JSON)**로 전환하고 **사진을 본문 인라인으로 통합** → `diary_images` 테이블 제거(`V4`=리치 본문/`content_text`, `V5`=테이블 드롭), 글자수 500자는 **순수 텍스트 기준**. **목록 실시간 갱신**(provider invalidate)·**미래 날짜 선택 차단** 적용. 웹 한글 IME는 flutter_quill 한계로 모바일에서 검증(수용).

- **Task 007: 백엔드 Supabase JWT 검증 + 사용자 JIT 프로비저닝** ✅ - 구현 완료(통합테스트 Docker 대기)
  - 구현 기능: F001, F010
  - ✅ JWKS(ES256) 검증·JIT 프로비저닝·V1(users) 재구성·레거시 제거 완료. 컴파일·`SupabaseJwtVerifierTest` 6/6 통과 + **로컬 PostgreSQL 18(`recorme`)에 bootRun 실측**(Flyway V1 적용·기동·`users` 스키마 확인). JIT/Flyway Testcontainers 통합테스트는 작성 완료, 실행은 Docker 가용 시(사용자 방침: 배포 전 일괄).
  - ⚠️ **인프라 방침(최종 확정)**: 인증만 Supabase Auth, **앱 데이터는 별도 PostgreSQL**(Supabase 미사용). 인증↔데이터는 `users.supabase_uid` 컬럼 매핑으로만 연결 — `auth.users` FK·RLS·DB 트리거 **금지**(물리적으로 다른 DB).
  - 레거시 정리: 자체 `JwtProvider`/`JwtProperties`/`HashUtil`, `domain/auth/social/*`(SocialVerifier·Router·Provider·SocialUserInfo)와 관련 단위 테스트(JwtProviderTest·HashUtilTest) 제거
  - **Supabase profiles 경로 폐기**: `supabase/migrations/0001_init_profiles.sql`(profiles 테이블·RLS 정책·`handle_new_user` 트리거)는 제거함(데이터를 Supabase에 두지 않으므로 불필요). 사용자 마스터는 Flyway `users` 단일 출처.
  - DB(기능별 마이그레이션 분할): `V1__init.sql`을 **`users` 전용**으로 재구성 — `social_accounts`·`refresh_tokens` 제거, `diaries`는 `V2__add_diaries.sql`로 분리(Task 008), `users.supabase_uid`(UNIQUE) + **`bio VARCHAR(300)`** + `uq_users_email_active`(이메일 부분 유니크) 추가(운영 DB 미배포라 V1 직접 재작성). 로컬은 네이티브 PostgreSQL 18(`recorme` DB/롤, 도커 미사용).
  - **이메일 provider 흡수**: Supabase Email provider(확인 메일 필수)를 켜도 백엔드는 provider 무관 동일 JWT 검증·JIT 경로 → 이메일 가입을 위한 추가 분기 없음(테스트로 증명).
  - `SupabaseJwtVerifier` + `SupabaseJwtFilter`: `Authorization: Bearer <Supabase access token>` 검증(**JWKS ES256 비대칭** — 프로젝트가 JWT Signing Keys 사용. `NimbusJwtDecoder.withJwkSetUri` + aud `authenticated`), `sub`/`email`/`user_metadata` 클레임 추출. `SecurityConfig`/`SecurityUser` 재사용·수정, `JwtAuthenticationEntryPoint` 유지
  - `UserProvisioningService`: `supabase_uid`로 `users` 조회, 없으면 자동 가입. 폐기된 트리거의 폴백 규칙을 Java로 이식 — 닉네임 = `name → full_name → nickname → user_name → email local-part`, 아바타 = `avatar_url → picture`, email = JWT `email`(클레임/`user_metadata`)
  - `application*.yml`: `record.jwt.*` 제거 → `supabase.url`(환경변수, JWKS URI 파생) 추가. JWKS(ES256)라 대칭 secret 불필요. `application-cloud.yml`은 별도 PostgreSQL 표준 설정으로 정리됨(Supabase Pooler 전제 제거 완료)
  - **(구현 직후 필수 테스트)** JUnit5 + Testcontainers — 유효 토큰 인증 통과, 위조 서명(401), 만료 토큰(401), 신규 사용자 JIT 가입(닉네임·아바타 폴백이 메타데이터로 채워짐), 기존 사용자 매핑(트리거 없이 1행만, 중복 가입 없음), **이메일 가입 토큰도 동일 JIT 경로**, Flyway V1(users) 적용·`uq_users_email_active` 부분 유니크 동작

- **Task 007-1: 백엔드 프로필 조회·수정 API** ✅ - 구현 완료(통합테스트 Docker 대기)
  - 구현 기능: F011
  - ✅ `domain/user/`(Controller/Service/Mapper+XML/DTO) 구현. `UserControllerTest`(@WebMvcTest) 4/4 통과(검증 400 경로). IDOR 구조적 차단·bio 빈문자열→NULL. `UserServiceTest`(Testcontainers)는 작성 완료, 실행은 Docker 가용 시.
  - `domain/user/` 구현(현재 `.gitkeep`만): `UserController`(`GET /users/me`, `PUT /users/me`) → `UserService`(@Transactional) → `UserMapper`(+`UserMapper.xml`) → DB
  - 수정 대상: 닉네임 + 프로필 이미지 URL + 자기소개(`bio`). 소유권은 SecurityContext의 내부 `userId`로만 결정(`UPDATE … WHERE id = #{principalUserId}`) → 타인 프로필 수정 구조적 차단(IDOR 방지)
  - DTO: `UserProfileResponse`(uuid/nickname/email/profileImageUrl/bio), `UpdateProfileRequest`(`@NotBlank @Size(50)` nickname, `@Size(300)` bio, `@URL @Size(2048)` profileImageUrl). bio 빈 문자열 → NULL 정규화
  - 검증 실패는 기존 `GlobalExceptionHandler`가 `VALIDATION_ERROR`(400)로 변환 — 신규 ErrorCode 불필요
  - **(구현 직후 필수 테스트)** JUnit5 + Testcontainers — 프로필 조회(JIT 보장), 수정 정상(updated_at 갱신), 검증 실패(닉네임 빈값/길이·bio 길이·URL 형식 → 400), 본인 외 수정 불가(IDOR), 미인증(401)

- **Task 007-2: 백엔드 프로필 이미지 업로드(StorageService + 정적 서빙)** ✅ - 구현 완료(통합테스트 Docker 대기)
  - 구현 기능: F011 (프로필 이미지 파일 첨부)
  - ✅ `infra/storage`(StorageService(if)/LocalDiskStorageService/StorageProperties)·`global/config/WebMvcConfig`(정적 서빙)·`POST /users/me/avatar`(multipart) 구현. 컴파일 통과 + `UserControllerTest`(업로드 슬라이스 포함) 4/4·`SupabaseJwtVerifierTest` 통과. `updateAvatar`/분리 회귀 Testcontainers 테스트는 작성 완료, 실행은 Docker 가용 시.
  - **저장 방식(확정)**: 파일 바이너리는 백엔드 **로컬 디스크**(`record.storage.root`, 기본 `./var/storage`)에 `avatars/yyyy/MM/{uuid}.{ext}`로 저장하고, DB(`users.profile_image_url`)에는 **호스트 비종속 상대경로**(`/files/...`)만 저장(BYTEA·Supabase Storage 미사용). **DB 스키마 변경 없음**(`profile_image_url TEXT` 재사용).
  - **검증/보안**: 매직바이트(jpg/png/webp) 검증, 서버 생성 UUID 파일명(경로 탐색 차단), 멀티파트 한도 5MB(`spring.servlet.multipart.*`) → `GlobalExceptionHandler`가 `FILE_TOO_LARGE`(413). 신규 `ErrorCode`: `INVALID_FILE`/`FILE_TOO_LARGE`.
  - **정적 서빙**: `WebMvcConfig`가 `/files/**` → 저장 루트 매핑, `SecurityConfig`에서 `GET /files/**` permitAll(공개, UUID 파일명으로 열거 차단).
  - **PUT 분리(중요)**: `UpdateProfileRequest`에서 `profileImageUrl` 제거 + `updateProfile` 매퍼가 `profile_image_url`을 더 이상 갱신하지 않음 → 닉네임/자기소개 수정이 아바타를 NULL로 덮어쓰던 잠재 버그 해소. 아바타는 `updateAvatar`(파일 저장 tx 밖 + 단일 UPDATE + 실패 시 보상 삭제 + 구 파일 best-effort 삭제)로만 갱신.
  - ⚠️ **배포 영속성**: 로컬 디스크는 컨테이너 ephemeral → 운영 진입 전 `S3StorageService` 교체 또는 영속 볼륨 마운트 결정 필요(인터페이스 격리로 구현체만 교체).
  - **(구현 직후 필수 테스트)** JUnit5 + Testcontainers — 정상 업로드(경로 저장·디스크 파일 생성), 기존 파일 교체 시 구 파일 삭제, 잘못된 MIME → INVALID_FILE(기존 이미지 보존), 외부 URL 보유자 업로드 시 no-op 삭제, **PUT 닉네임 수정이 이미지 보존(분리 회귀)**, 업로드 슬라이스 200·미인증 401

- **Task 008: 백엔드 기록 upsert CRUD + 캘린더 엔드포인트 (+사진 첨부·글자수 제한)** ✅ - 구현 완료(통합테스트 Docker 대기)
  - ✅ `V2 diaries`(content CHECK 1~500)·`V3 diary_images`(1:N) 마이그레이션 + FlywayMigrationTest, DiaryConstraints(500자·5장)·VO·DTO·DiaryMapper/DiaryImageMapper(+XML, upsert RETURNING xmax 201/200·images resultMap), DiaryService(소유권 IDOR·트랜잭션 경계·사진 업로드/삭제 파일 IO 트랜잭션 밖+보상삭제·삭제 시 디스크 즉시 회수)·DiaryController(+@WebMvcTest 5건)·ErrorCode IMAGE_LIMIT_EXCEEDED(409)·multipart 26MB. DiaryServiceTest(Testcontainers, CRUD/엣지/이미지/디스크 회수) 작성. 컴파일·@WebMvcTest 통과, Testcontainers 실행은 Docker 일괄.
  - DB: `V2__add_diaries.sql` 신설로 `diaries` 테이블·`uq_diary_user_day` 부분 유니크·인덱스 생성(Task 007에서 V1의 users만 남기고 분리됨). 기존 `FlywayMigrationTest`의 diaries 검증(부분 유니크·upsert·소프트삭제 재작성)을 여기로 이관. 사진은 `V3__add_diary_images.sql`(1:N, 경로만 저장)로 분리
  - 구현 기능: F002, F003, F005, F006, F007
  - `POST /diaries`: `(user_id, written_date)` 부분 유니크 충돌 키 기반 upsert(`INSERT … ON CONFLICT DO UPDATE`) — 신규 201 / 갱신 200
  - `GET /diaries/me/summary?yearMonth=`: 해당 월 활성 기록 존재 날짜 목록(캘린더 dot용)
  - `GET /diaries/by-date/{date}`: 날짜 단건 조회, 없으면 404 `DIARY_NOT_FOUND`
  - `GET /diaries/{id}`: 단건 상세 조회
  - `PUT /diaries/{id}`: id 기반 명시적 수정
  - `DELETE /diaries/{id}`: 소프트 삭제(`deleted_at` 기록), 삭제 후 같은 날짜 재작성 허용
  - 본인 소유 검증(타인 기록 접근 403)
  - **(구현 직후 필수 테스트)** JUnit5 + Testcontainers — 정상 생성/조회/수정/삭제, 같은 날짜 재저장 시 UPDATE 동작(엣지), 소프트 삭제 후 같은 날짜 재INSERT 허용(엣지), 존재하지 않는 id/date(404), 타인 기록 접근(403), 잘못된 날짜·빈 content(유효성 400)

- **Task 009: 백엔드 기록 목록 커서 페이징** ✅ - 구현 완료(통합테스트 Docker 대기)
  - ✅ `GET /diaries/me?cursor=&size=`(DiaryMapper.findList, id DESC, size+1로 hasNext·nextCursor), 목록 N+1 회피 위해 `DiaryListItem`(대표 thumbnailUrl·imageCount만, 이미지 전체 미포함). DiaryServiceTest에 커서 페이징 7케이스 추가. 컴파일 통과, Testcontainers 실행은 Docker 일괄.
  - 구현 기능: F004
  - `GET /diaries/me?cursor=&size=`: `id DESC` 정렬, OFFSET 미사용 커서 페이징, `{ items, nextCursor, hasNext }` 반환
  - 소프트 삭제(`deleted_at IS NOT NULL`) 행 제외
  - **(구현 직후 필수 테스트)** JUnit5 + Testcontainers — 첫 페이지(cursor 생략)/다음 페이지 연속 조회, 마지막 페이지 `hasNext=false`, 경계값(size=1, 빈 결과), 삭제된 기록 미노출(엣지)

- **Task 010: 앱 Supabase Auth 연동 (이메일·소셜·프로필 토대)** ✅ - 구현 완료(`flutter analyze` 무경고 + `flutter test` 36개)
  - 구현 기능: F001, F010, F011
  - ✅ (구현됨) Supabase 초기화, 구글(`signInWithIdToken`)·카카오(`signInWithOAuth`) 로그인, `onAuthStateChange` 기반 세션 감시, go_router 가드(Supabase 세션 기준), 로그인 UI, 소셜 OAuth 콘솔 설정(Google) + 앱 설정값(`supabase_config.dart`)
  - **이메일 가입/로그인 UI 추가**: `signUpWithEmail`(닉네임→`user_metadata`)·`signInWithEmail`·`resendConfirmationEmail`, `EmailAuthController`(에러 한국어 매핑), `signup_page`(`/signup`)·`email_confirm_page`(`/signup/confirm`) 신설, login_page에 이메일 폼, 가드 공개경로 일반화. Supabase 콘솔 Email provider·Confirm email·Redirect URL 설정
  - ✅ `AuthInterceptor`를 **Supabase access token 첨부**로 정리 완료, 미사용 `TokenStorage`·`token_response.dart`(자체 JWT 잔재) 제거.
  - ✅ **인증 즉시 프로비저닝(워밍업)**: 로그인(`signedIn`)·OAuth 리다이렉트/앱 시작(`initialSession`) 시 `GET /users/me`를 1회 자동 호출 → 프로필 진입 없이 `users` 즉시 저장(웹 E2E 실측 — 이메일·구글 모두).
  - ✅ **웹 구글 로그인**: `kIsWeb` 분기로 웹은 `signInWithOAuth(google)` 리다이렉트(모바일은 `GoogleSignIn` idToken 유지). 카카오는 이미 OAuth 방식.
  - ✅ **중복 가입 명시**: `signUp` 응답 `user.identities` 빈 배열 감지 → "이미 가입된 이메일" 안내(enumeration protection 유지).
  - ✅ **비밀번호 재설정**: `forgot_password_page`·`reset_password_page` 신설 + `passwordRecovery` 라우팅(`resetPasswordForEmail`/`updateUser`).
  - 잔여(사용자 콘솔 작업): Supabase **Site URL=`http://localhost:8000`** + Redirect URLs, Google **웹 OAuth Client ID/Secret** 등록(`tasks/_SUPABASE_SETUP.md`), Kakao provider 마무리, 안드로이드 실기기 검증.
  - **(구현 직후 필수 테스트)** `integration_test` E2E — 로그인 성공 → 메인 진입, 인증 실패 → 에러 토스트 유지, 세션 만료 시 SDK 자동 갱신 후 요청 성공, 로그아웃 후 보호 화면 접근 차단, **이메일 가입→확인 안내 화면, 미인증 로그인 차단(재전송), 인증 후 로그인 성공**

- **Task 010-1: 앱 프로필 화면 (조회·수정)** ✅ - 완료
  - 구현 기능: F011
  - ✅ `features/profile/` 신설·`User` 모델 bio 추가·`/profile`·`/profile/edit` 라우트·메인 앱바 진입점 구현. `flutter analyze` 무경고 + `flutter test`(프로필 7건 포함) 통과. 웹에서 조회·수정 실동작 확인.
  - `features/profile/` 신설(diary feature의 `domain abstract + data impl + Provider override` 패턴 미러링): `ProfileRepository`(getMe/updateMe) + `ApiProfileRepository`(Dio + ApiResponse 언랩), `UpdateProfileRequest` DTO, `profile_page`(조회)·`profile_edit_page`(수정)·`profile_providers`(`myProfileProvider` FutureProvider)
  - `shared/models/user.dart`에 `bio` 추가(fromJson/toJson/copyWith/==/hashCode). 라우트 `/profile`·`/profile/edit`(push). 진입점: 메인 상단 앱바. 하단 탭은 캘린더/목록 2개 유지
  - 수정 성공 시 `ref.invalidate(myProfileProvider)` + 스낵바 + pop. (선행: Task 007-1 백엔드 `PUT /users/me`, Task 010 `AuthInterceptor` 토큰 첨부)
  - **(구현 직후 필수 테스트)** `integration_test`(Fake repository override) — 프로필 조회(로딩→데이터), 수정 제출(`UpdateProfileRequest.toJson` 인자 검증→invalidate→pop), bio 300자 검증, 미인증 `/profile` 접근 가드

- **Task 010-2: 앱 프로필 이미지 표시·업로드 (앱바 아바타·기본이미지·image_picker)** ✅ - 완료
  - 구현 기능: F011 (프로필 이미지 파일 첨부)
  - ✅ 공용 `shared/widgets/profile_avatar.dart`(등록 이미지/닉네임 이니셜/사람 아이콘 폴백, onTap 시맨틱스) 신설 → 메인 앱바 프로필 버튼(아이콘→아바타, 48dp 탭영역)·프로필 화면 아바타에 재사용. `ApiConfig.resolveImageUrl`(http→그대로 / 상대경로→apiBaseUrl 결합) 추가.
  - ✅ 이미지 선택·업로드: `image_picker` 추가, `ProfileEditImageSection`(미리보기·업로드 오버레이·"사진 변경") 신설, `profile_edit_page`에 삽입 + URL 텍스트필드 제거. `_onPickImage`가 바이트(`Uint8List`, 웹·모바일 공통)를 읽어 즉시 `uploadAvatar`→`invalidate(myProfileProvider)`. 닉네임/bio 저장과 분리.
  - ✅ `ProfileRepository.uploadAvatar(bytes, filename)`(+ `ApiProfileRepository` FormData multipart) 추가, 앱 `UpdateProfileRequest`에서 `profileImageUrl` 제거(백엔드 DTO 정합).
  - ✅ `flutter analyze` 무경고 + `flutter test` 45개(프로필 이미지 9건 신설 포함) 통과. ⚠️ `cached_network_image`는 네이티브 의존성·테스트 결정성 고려로 미도입(`Image.network`+세션 ImageCache 사용), 향후 최적화로 남김.
  - **(구현 직후 필수 테스트)** `flutter test` — `ProfileAvatar`(이미지/이니셜/아이콘 폴백·onTap), `ProfileEditImageSection`(업로드 오버레이·로컬 미리보기·사진변경 콜백), `uploadAvatar` 저장소 계약(바이트·파일명 전달·실패 INVALID_FILE). image_picker 실선택 E2E는 웹/실기기 수동 검증.

- **Task 011: 앱 기록 기능 API 연동 (더미 교체) (+사진 첨부·글자수 카운터)** ✅ - 완료
  - ✅ 에디터 UI(사진 썸네일 수평스크롤·추가/삭제·5장 비활성, 글자수 카운터 하드 500·3단계 색), `DiaryPhotoItem`/`DiaryPhotoThumbnail`, `ApiDiaryRepository`(getByDate 404→null·커서·multipart files·삭제) + provider 교체, `Diary.images`/thumbnailUrl 정합, 4개 화면 실연동·더미 제거, image_picker 다중선택·저장 시 upsert→uploadImages/deleteImage 일괄 반영. `flutter test` 63개 + `integration_test` 4개 통과, `flutter analyze` 무경고.
  - 구현 기능: F002, F003, F004, F005, F006, F007, F012
  - 캘린더: `GET /diaries/me/summary`로 dot 렌더링, 날짜 탭 시 `GET /diaries/by-date/{date}` → 있으면 상세, 404면 신규 에디터로 분기
  - 에디터 저장: `POST /diaries`(날짜+내용 upsert, id 불필요), 상세 수정은 `PUT /diaries/{id}`
  - 목록: `GET /diaries/me` 커서 무한 스크롤 실연동
  - 상세: `GET /diaries/{id}`, 삭제: `DELETE /diaries/{id}` + 확인 다이얼로그 → 메인 복귀
  - 모든 더미 데이터 제거, 로딩/에러/빈 상태 처리
  - **(구현 직후 필수 테스트)** `integration_test` E2E — 캘린더 dot 표시, 신규 작성 → 캘린더 반영, 같은 날짜 재작성 시 수정 반영(엣지), 목록 스크롤 페이징, 상세 조회, 수정, 삭제 후 같은 날짜 재작성 허용(엣지), API 오류 시 에러 UI 노출

- **Task 011-1: 핵심 기능 통합 테스트** ✅ - 구현 완료(백엔드 Testcontainers Docker 대기)
  - ✅ 앱 `integration_test/diary_journey_test.dart`(작성[카운터·500 하드제한]→목록→상세→수정[같은 날짜 UPDATE]→삭제[재작성 허용]+저장 실패 에러 UI+사진 섹션 한도, Supabase/Dio override로 결정성) 4건 통과. 백엔드 `DiaryIntegrationTest`(@SpringBootTest+Testcontainers: JIT 가입→CRUD→이미지 업로드/삭제·디스크 회수→커서 페이징→IDOR 404·프로비저닝 멱등·이미지 한도) 작성·컴파일 통과.
  - 구현 기능: F001~F007, F010, F012 전체 검증
  - `integration_test`로 전체 사용자 여정 E2E: 로그인 → 캘린더 → 작성 → 목록 → 상세 → 수정 → 삭제 → 로그아웃 (시나리오별 단계 명시)
  - 백엔드: `@SpringBootTest` + Testcontainers로 auth·diary 도메인 간 통합 시나리오 검증
  - 에러 핸들링 및 엣지 케이스: 중복 날짜 upsert, 소프트 삭제 후 재작성, 토큰 만료·갱신, 비인가/타인 기록 접근(401/403), 빈 데이터·경계값
  - ⚠️ **잔여 검증**: 백엔드 Testcontainers(DiaryServiceTest·DiaryIntegrationTest·FlywayMigrationTest)는 코드 작성 완료, **실행은 배포 전 Docker 일괄**(007 계열과 동일 방침). 이 실행 통과 후 Phase 3 전체 ✅ 확정.

- **Task 011-2: 리치 텍스트 에디터 전환 + 인라인 이미지 통합 + 목록 실시간 갱신 + 미래 날짜 차단** ✅ - 완료(백엔드 Testcontainers Docker 대기)
  - 구현 기능: F003/F005/F006(에디터·상세 고도화), F012(이미지) 재설계
  - **에디터 리치 텍스트 전환**: 기록 본문 입력을 plain `TextField` → **flutter_quill**(Delta JSON)로 교체. 폰트·글자 크기·굵게/기울임/밑줄·정렬·목록 등 서식 툴바 + **본문 중간 인라인 이미지 삽입**. 본문은 `diaries.content`에 **Quill Delta JSON 문자열**로 저장(`V4__diary_rich_content.sql`).
  - **순수 텍스트 분리(`content_text`)**: 서식·이미지 마크업을 제외한 순수 텍스트를 별도 컬럼으로 저장 → **글자수 500자 하드 제한은 순수 텍스트 기준**(LLM 비용·품질 정책 유지), 목록 미리보기·향후 LLM 입력에 사용. DB CHECK도 `content`(JSON, 길이 무의미)에서 `content_text`로 이전.
  - **이미지 모델 인라인 통합 + `diary_images` 테이블 제거(`V5__drop_diary_images.sql`)**: 사진을 본문과 분리된 하단 첨부에서 **본문 Delta 임베드로 단일화**. content가 이미지의 **단일 진실 공급원**이 되어 별도 1:N 테이블 폐지. 업로드는 작성 중 `POST /diaries/images`(part `file` → `{url}`)로 즉시 업로드해 Delta에 임베드. **목록 썸네일·개수는 content의 jsonb에서 산출**, **디스크 파일 회수는 content 파싱**(삭제 시 본문 이미지 파일 회수, 수정 시 본문에서 빠진 이미지 파일 회수). 미참조 업로드 파일은 MVP 허용(향후 GC). 관련 코드 정리: 백엔드 `DiaryImageMapper`·`DiaryImageResponse`·`DiaryResponse.images` 제거, 앱 `DiaryImage`·`DiaryPhotoItem`·`DiaryPhotoThumbnail` 제거.
  - **목록 실시간 갱신**: `StatefulShellRoute.indexedStack`이 목록 페이지 State를 유지해 새 글이 안 보이던 문제를, 월 목록을 `monthDiariesProvider`(FutureProvider.family)로 전환하고 저장/삭제 시 `ref.invalidate` → **탭 복귀 없이 즉시 반영**.
  - **미래 날짜 선택 차단**: 캘린더에서 오늘 이후 날짜는 흐리게+탭 무효(`_DayCell.isDisabled`), 이번 달이면 다음 달 chevron 비활성(스와이프 포함, 캘린더·목록 공통), 에디터/탭 진입에 이중 방어 가드.
  - ⚠️ **웹 한글 IME 한계(수용)**: flutter_quill 에디터는 Flutter **웹**에서 한글(CJK) IME 조합 입력이 제한됨(알려진 한계, 영문 정상). **한글 입력은 Android/iOS에서 검증**(코드·`tasks/_LOCAL_E2E_TEST_DIARY.md`에 명시). 웹은 영문·서식·이미지·날짜·실시간 갱신 검증용.
  - 검증: 앱 `flutter analyze` 무경고 + `flutter test` 60건 통과. 백엔드 `compileJava/compileTestJava` 통과, 로컬 PostgreSQL 18(`recorme`)에 **Flyway V4/V5 적용 실측**(기존 기록이 Delta+인라인 이미지로 변환 확인). Testcontainers 실행은 배포 전 Docker 일괄(기존 방침).

### Phase 5: 작심삼일(3일 결심) ✅

기록(diary)과 독립된 부가 기능으로 **작심삼일**(시작일 + 할일 + 3일)을 구현한다. 매일 '완료'를 체크해 3일 완주하면 `SUCCESS`, 하루라도 그 날(KST 자정 전) 미완료면 `FAILED`, 성공 시 '다음 3일'로 **연장**해 연속(streak)을 이어간다. 동시 다중 진행·월별 캘린더·매일 리마인더를 지원한다. DB·백엔드 도메인/스케줄러·모바일(데이터·UI)·**FCM 서버 푸시(Firebase 연동)**까지 **코드·설정 레벨 구현 완료**됐고, 남은 것은 **실기기(Z Flip3) 실제 푸시 수신·딥링크 라이브 검증**뿐이다.

> **진행 현황**: 백엔드 도메인(`domain/resolution`·`domain/device`) + 스케줄러(자정 실패 배치·오늘 리마인더 선점) + `infra/push`(FCM 다형·무키 Stub 폴백) + 통합/단위 테스트 **108개 통과**. DB는 `V9`(resolutions·resolution_checks)·`V10`(device_tokens). 모바일은 데이터 계층·UI + FCM 연동(`firebase_messaging`·`flutter_local_notifications`) 완료(`flutter analyze` 무경고 + 디버그 APK 빌드 성공). **FCM**: Firebase 프로젝트 `recorme-c5e1c` 생성·`flutterfire configure`(앱 수신) + 서비스계정 키 `FCM_CREDENTIALS` 주입 시 백엔드가 `FcmPushService` 선택(발송) — 기동 로그로 확인. 날짜 판정은 전부 **KST(Asia/Seoul) 서버 권위**. 완료 체크는 날짜 인자 없이 서버 '오늘'로 판정하며 멱등. 리마인더는 `reminded_on` 하루 1회 멱등 + `FOR UPDATE ... SKIP LOCKED` 다중 인스턴스 안전.

- **Task 020: 백엔드 작심삼일 도메인 (CRUD·완료·연장·캘린더)** ✅ - 완료
  - 구현 기능: F013(결심 생성/조회), F014(완료 체크·성공/실패 전이), F015(연장 streak), F016(월별 캘린더)
  - ✅ `V9__add_resolutions.sql`(resolutions·resolution_checks + 부분 인덱스·제약), `ResolutionController`(`POST /resolutions`·`GET /resolutions/me`·`/me/calendar`·`/{id}`·`PUT /{id}`·`POST /{id}/checks/today`·`POST /{id}/extend`·`DELETE /{id}`), `ResolutionService`(@Transactional, KST 날짜 판정, 소유권 IDOR 차단), `ResolutionMapper`(+XML). 생성/연장은 신규 리소스 201.
  - ✅ **수정(F013 확장, 후속 추가)**: `PUT /resolutions/{id}` + `UpdateResolutionRequest`(제목·알림 시각) — 진행 중(ONGOING) 결심만 제목·알림 시각 수정, 시작일 변경은 종료일·체크 재계산 복잡도로 미지원(삭제 후 재작성 유도). 소유·ONGOING 검증 + 영향 행수 검사(경합 시 조용한 실패 방지, `updateResolution` SQL에 `status='ONGOING'` 가드).
  - 상태 전이: 생성=`ONGOING`(3일 체크 PENDING 프리생성) → 오늘 체크 `DONE` → 3일 완주 시 `SUCCESS`(`status='ONGOING'` 가드 1회). '예정'은 `start_date > 오늘` 파생, 취소는 소프트 삭제.
  - 완료 체크(멱등): `POST /{id}/checks/today`가 날짜 인자 없이 KST '오늘' 체크를 `DONE` 전이. 이미 `DONE`이면 재요청 200. 진행 중 아니면 409 `RESOLUTION_NOT_ACTIVE`, 오늘 체크 없으면 409 `RESOLUTION_CHECK_NOT_TODAY`.
  - 연장(streak): 성공한 결심만 `streak_group_id` 복사 + `streak_seq+1`로 신규 생성(시작일 `max(prev.endDate+1, 오늘)`). 성공 아니면 409 `RESOLUTION_NOT_EXTENDABLE`, 이중 연장은 선검사 + `uq(streak_group_id, streak_seq)`로 409 `RESOLUTION_ALREADY_EXTENDED`.
  - 목록: `GET /resolutions/me?status=&cursor=&size=` 커서 페이징(id DESC), 항목은 `dayStatuses`(day_index 순 체크 상태를 **콤마 결합 문자열** "DONE,PENDING,PENDING")만 얇게 적재. 캘린더: `GET /resolutions/me/calendar?yearMonth=`가 (날짜, 결심)당 1행.
  - 에러 코드(신규 5종): `RESOLUTION_NOT_FOUND`(404)·`RESOLUTION_NOT_ACTIVE`·`RESOLUTION_CHECK_NOT_TODAY`·`RESOLUTION_NOT_EXTENDABLE`·`RESOLUTION_ALREADY_EXTENDED`(409).
  - **(테스트)** JUnit5 + Testcontainers/단위 — 작심삼일·기기 도메인 통합/단위 **108개 통과**(생성·완료 멱등·성공 전이·연장 체인·이중 연장 경합·캘린더·IDOR 404·자정 실패 배치·리마인더 선점).

- **Task 021: 백엔드 스케줄러 (자정 실패 배치·오늘 리마인더 선점)** ✅ - 완료
  - 구현 기능: F017(리마인더/완주 알림의 서버측 파이프라인)
  - ✅ `ResolutionFailurePoller`(자정 이후 `check_date < today` PENDING 체크를 `FOR UPDATE ... SKIP LOCKED`로 선점 → `MISSED` + 결심 `FAILED`, 짧은 `@Transactional` 배치·다중 인스턴스 안전), `ResolutionReminderScheduler`(오늘·PENDING·미발송·시각 도래 체크를 CTE 한 문장으로 선점+`reminded_on=오늘` 마킹 → 하루 1회 멱등), `ResolutionPushNotifier`(@Async, 완주 축하는 커밋 후 `afterCommit` 발송).
  - `device_tokens`(`V10`) + `DeviceTokenController`(`POST /devices/tokens`·`DELETE /devices/tokens?token=`, 멱등 200) + `DeviceTokenService`(upsert 소유 재귀속). 토큰 전역 UNIQUE, 팬아웃 인덱스.
  - ✅ **FCM 서버 발송부 연결 완료**(Task 023): `ResolutionPushNotifier`가 `infra/push/PushService`로 실제 전송. 서비스계정 키(`FCM_CREDENTIALS`) 주입 시 `FcmPushService`(Firebase Admin SDK, `sendEachForMulticast` + 무효 토큰 `UNREGISTERED/INVALID_ARGUMENT` 회수), 미주입 시 `StubPushService` 폴백.

- **Task 022: 앱 작심삼일 (데이터·UI)** ✅ - 완료
  - 구현 기능: F013~F016 (모바일)
  - ✅ 작심삼일 데이터 계층(Repository + Dio 실연동, 표준 응답 언랩·커서 페이징)·UI(목록 탭 진행/성공/실패 + 3일 진행 도트[`dayStatuses` 콤마 분해], 생성 폼[제목·시작일·알림시각], 상세[3일 체크·오늘 완료 버튼·연장·취소], 월별 캘린더 배지) 구현.
  - ✅ **수정 화면(F013 확장, 후속 추가)**: `resolution_edit_page`·`/resolution/:id/edit` 라우트·`UpdateResolutionController`, 상세 AppBar 수정 버튼(ONGOING만 노출) → 제목·알림 시각 수정. `Repository.update`(Api/Fake)·DTO 추가, 제목 maxLength 30→100(백엔드/DB 정합).
  - ✅ **앱 FCM 연동 완료**(Task 023): `firebase_messaging` 토큰 발급 → `POST /devices/tokens` 등록·`onTokenRefresh` 재등록·로그아웃 `DELETE`, 포그라운드 `flutter_local_notifications` 표시, 알림 탭 딥링크(`/resolution/:id`)까지 구현.

- **Task 023: FCM 서버 푸시 연동** ✅ - 완료(실기기 라이브 검증 대기)
  - 구현 기능: F017 (리마인더·완주 축하 푸시 실제 전송)
  - ✅ **Firebase 준비**: 프로젝트 `recorme-c5e1c`(Spark) 생성, 앱 `com.recorme.app`(Android/iOS) 등록. `flutterfire configure`로 `lib/firebase_options.dart`·`android/app/google-services.json`·`com.google.gms.google-services` Gradle 플러그인 자동 배선. 서비스계정 키는 `backend/fcm-service-account.json`(gitignore) + 환경변수 `FCM_CREDENTIALS`로 주입(코드·git 금지).
  - ✅ **백엔드 발송**: `infra/push`(`PushService`/`FcmPushService`/`StubPushService`/`PushConfig` 무키 폴백, `firebase-admin`) — 키 주입 시 기동 로그 `Push service = FCM`. `ResolutionPushNotifier`가 대상 토큰 팬아웃 + `sendEachForMulticast` + 무효 토큰(`UNREGISTERED/INVALID_ARGUMENT`) 물리 회수.
  - ✅ **앱 수신**: `main.dart` `Firebase.initializeApp`(+백그라운드 핸들러) → Supabase 순서, `core/notifications/NotificationService`(권한 요청 1회 시트·토큰 등록/갱신/삭제·포그라운드 로컬 알림·`onMessageOpenedApp`/`getInitialMessage` 딥링크), Android `POST_NOTIFICATIONS`·core library desugaring. `flutter analyze` 무경고 + `flutter build apk --debug` 성공.
  - ✅ **웹 실행 지원(후속 추가)**: `NotificationService`에서 `dart:io` 제거(→ `defaultTargetPlatform`), `init()`에 `kIsWeb` 조기 반환(웹 미지원 FCM·`flutter_local_notifications`를 no-op) → 웹 빌드/개발 실행 복구(모바일 동작 불변).
  - ⏳ **잔여(라이브 검증)**: 실기기(Z Flip3)에서 알림 권한 허용 → 토큰 등록 → 리마인더 시각 도래 1회 발송(멱등)·완주 축하·자정 실패 알림·다중 기기 팬아웃·무효 토큰 회수·알림 탭 딥링크 실동작 확인. iOS는 APNs 키·`GoogleService-Info.plist` 별도 필요.

### Phase 4: 감정 분석 · 동적 테마 ✅ (음악·공유·배포는 이후 개요)

기록 **확정(DRAFT→PENDING)** 시 멀티모달 LLM으로 감정을 분석해 **대표 감정 · 테마색(배경/글자/강조) · AI 한 줄 코멘트 · AI 제목 · 무드 이모지 · 감정 점수 분포**를 생성하고, 앱은 이를 **감정 마스코트 영상 · 상세 시네마틱 인트로 · 러닝 로딩 연출 · 감정 기반 동적 테마**로 렌더링한다. 비동기 감정 분석은 트랜잭션 밖에서 `@Async`(전용 풀 `emotionAnalysisExecutor`)로 수행하고, 실패 시 `NEUTRAL` 폴백한다. **감정 6종**(JOY/SADNESS/ANGER/CALM/ANXIETY/NEUTRAL)은 `emotion_types` 마스터로 관리한다. 아래 감정 분석·동적 테마(Task 012·013)는 **구현 완료**이며, 음악(014)·공유/피드(015)·배포(016)는 여전히 MVP 이후 개요다.

> **진행 현황**: 백엔드 감정 분석 엔진(`domain.emotion`: EmotionAnalysisService/Poller/Analyzer + `infra.llm` LlmClient 추상화 Claude/Gemini/Ollama/Stub) + `V6`(content_text NOT NULL)·`V7`(emotion_types 마스터 + diaries 감정·테마 컬럼) + Diary confirm/DRAFT 라이프사이클(`V8`) **구현 완료**. 앱은 draft→확정 2버튼·분석중 3초 폴링·감정 동적 테마(`diary_theme.dart`)·감정 마스코트/러닝 로딩 영상(`emotion_video.dart`·`running_sel.mp4`, `video_player`)·상세 시네마틱 인트로·캘린더 감정색/이모지 표시까지 완료. LLM provider는 설정으로 선택(무키 시 `StubLlmClient` 폴백, 로컬 Ollama 무키). Testcontainers 실행은 배포 전 Docker 일괄(기존 방침). **음악·공유·피드·배포는 아래 개요로 유지.**

- **Task 011-3: 기록 draft→확정 라이프사이클 (감정 분석 선행 작업)** ✅ - 구현 완료(백엔드 Testcontainers Docker 대기)
  - 구현 기능: F003/F006 확장 (Task 012/013 감정 분석·테마의 **선행 작업** — 확정 시점이 분석 트리거가 됨)
  - **상태 모델 확장**: `analysis_status`(VARCHAR(20)) 값 집합을 `DRAFT`(미확정·수정가능·미분석) → `PENDING`(확정·분석대기) → `DONE`/`FAILED`로 확장. 기본값 `'PENDING'` → **`'DRAFT'`**. 신규 마이그레이션 `V8__diary_draft_lifecycle.sql`(`SET DEFAULT 'DRAFT'` + `CHECK (analysis_status IN ('DRAFT','PENDING','DONE','FAILED'))`, 기존 데이터 백필 없음)
  - **2단계 저장**: `POST /diaries`에 `confirm`(boolean, 기본 false) 추가 — `false`→DRAFT 저장(수정 가능·AI 미호출), `true`('오늘을 기억하기')→확정(PENDING·감정분석 1회). 확정 기록은 재upsert·`PUT` 모두 409 `DIARY_ALREADY_CONFIRMED`(불변성). 삭제는 허용(소프트 삭제 → 같은 날짜 재작성)
  - **정책 변경**: 기존 "내용 수정 시 재분석" 폐기 → "확정 시 1회 분석". 매 수정 LLM 호출 과부하 제거. upsert SQL에 `WHERE analysis_status='DRAFT'` 불변성 가드
  - **앱**: 에디터 [취소][등록][오늘을 기억하기] 버튼, 확정 전 확인 다이얼로그, 확정 직후 상세에서 "분석 중(약 1분)" 표시 + 폴링 자동 갱신. 캘린더/목록에서 DRAFT는 에디터로·확정은 상세로 분기
  - **(구현 직후 필수 테스트)** JUnit5 + Testcontainers — DRAFT 저장(미분석)·확정(PENDING) 분기, 확정 기록 재upsert/PUT 409, DRAFT 수정 정상, 소프트 삭제 후 재작성, V8 CHECK 제약 동작 / 앱 `flutter test`·`integration_test` — 2버튼 분기·확정 다이얼로그·분석중 폴링

- **Task 012: 감정 분석 (멀티모달 LLM) — 백엔드 엔진 + 비동기 파이프라인** ✅ - 완료(Testcontainers Docker 대기)
  - 구현 기능: F003/F006 확장 (확정 시 1회 감정 분석) — **F018**
  - ⚠️ **Phase 7에서 비활성화 예정(코드 보존)** — **Task 024 미착수이므로 현재는 LLM 감정 분석이 활성 상태다**: Task 024가 `record.analysis.enabled=false`(기본값)로 LLM 분석 파이프라인을 `@ConditionalOnProperty` 차단한다. `domain.emotion`·`infra.llm`·`emotion_types` 마스터·`diaries` 감정/테마 컬럼은 **삭제하지 않고 보존**하며, `ANALYSIS_ENABLED=true` 한 줄로 복구 가능하다. flag off 상태에서는 감정을 **사용자가 직접 입력**(프리셋 6종 또는 자유 텍스트)하고, 확정 시 즉시 `DONE`으로 전이한다.
  - ✅ `V7__add_emotion_analysis.sql`(emotion_types 마스터 6종 시드 + diaries에 `primary_emotion`(FK)·`background_color`/`text_color`/`accent_color`(색 형식 CHECK)·`ai_comment`·`ai_title`·`mood_emoji`·`emotion_scores`(JSONB)·`analyzed_at`, `chk_diaries_done_has_emotion`) 구현. `V6__diary_content_text_not_null.sql`로 content_text NOT NULL 강화.
  - ✅ `domain.emotion`: `EmotionAnalysisService`(`@Async("emotionAnalysisExecutor")`, 트랜잭션 밖 LLM 호출·낙관적 조건부 UPDATE — 분석 중 수정/삭제 시 stale 폐기)·`EmotionAnalysisPoller`(PENDING 백스톱)·`EmotionAnalyzer`/`LlmEmotionAnalyzer`·`DiaryImagePreparer`(본문 인라인 이미지 → 멀티모달 입력)·`EmotionAnalysisMapper`.
  - ✅ 확장 포인트 인터페이스 격리 `infra.llm.LlmClient`: `ClaudeLlmClient`(`anthropic-java`)·`GeminiLlmClient`·`OllamaLlmClient`(로컬 무키)·`StubLlmClient`(무키 로컬/CI 폴백). `LlmConfig`가 provider·키 유무로 구현체 프로그램적 선택(기본 provider=`gemini`, 무키 시 Stub 폴백). LLM 실패는 analyzer가 `NEUTRAL`로 흡수 → FAILED+NEUTRAL 반영(CHECK 통과).
  - ✅ **확정 시 1회만 분석**(확정 후 수정 불가 — Task 011-3 라이프사이클 전제): DiaryService가 확정 커밋 후 `analyzeAsync(diaryId)` 트리거. 재분석은 삭제 후 재작성·재확정.
  - ✅ 분석 결과는 `DiaryResponse`·`DiarySummaryDay`(캘린더)로 노출. `DiarySummaryDay`는 DONE 기록만 `primaryEmotion`·`moodEmoji` 값 보유(캘린더 감정색/이모지 렌더).

- **Task 013: 감정 기반 동적 테마 · 마스코트/시네마틱 연출 (앱)** ✅ - 완료
  - 구현 기능: F003/F005/F006 확장 (감정 표현 계층) — **F019**
  - ⚠️ **Phase 7에서 연출 제거 예정(캐릭터로 대체)** — **Task 025 미착수이므로 현재는 감정 연출이 그대로 살아 있다**: Task 025가 감정 마스코트 mp4 6종·`emotion_alpha.frag` 셰이더·`flutter_shaders`·동적 배경 테마·상세 시네마틱 인트로·러닝 로딩 영상·PENDING 폴링을 **삭제**한다. 연출 주인공은 **내 캐릭터 하나로 일원화**되며(`ReactionOverlay`·`CharacterStage`), 감정은 **달력 점 색 + 감정 칩**에만 남는 순수 기록 메타데이터가 된다. **로그인 마스코트 영상 3종과 `video_player`는 브랜딩 자산으로 유지.**
  - ✅ **감정 동적 테마**: `core/theme/diary_theme.dart`가 `primaryEmotion`(+백엔드 생성 색) 기반 배경/글자/강조 팔레트를 상세·목록에 적용. `core/theme/emotion_assets.dart`가 감정 6종별 PNG·mp4 매핑.
  - ✅ **감정 마스코트 영상**: `shared/widgets/emotion_video.dart`(감정 코드별 마스코트 mp4 자동재생·무한루프·무음, PNG 폴백, `video_player`).
  - ✅ **마스코트 투명 배경(후속 추가)**: 단일 영상 코덱으로 iOS+Android 동시 네이티브 투명이 불가(H.264=알파 없음, VP9-알파 webm=iOS 미재생)하여, **불투명 H.264에 [좌:색\|우:실루엣 알파]를 2:1로 패킹**하고 `flutter_shaders` `AnimatedSampler` + 프래그먼트 셰이더(`emotion_alpha.frag`)로 premultiplied RGBA 합성 → 배경 투명. 매 프레임 리페인트 티커로 영상 정지 방지. 웹은 셰이더 합성 불가(video_player DOM 오버레이)라 투명 PNG 포스터 폴백. 원본 webm은 `docs/`에 재인코딩 소스로 보관.
  - ✅ **상세 시네마틱 인트로 + 러닝 로딩 연출**: `diary_detail_view.dart`의 `_IntroPhase`(big/settle/rest 3단계 애니메이션) + `_RunningIntroOverlay`(PENDING 진입 시 `assets/videos/running_sel.mp4` 1회 재생 후 페이드아웃) + DONE 시 무드 이모지·AI 제목·AI 코멘트 안착.
  - ✅ **분석중 폴링**: 확정 직후 상세에서 PENDING이면 3초 간격 폴링(`diaryByIdProvider` invalidate) → DONE 자동 전환. 앱 DTO(`diary_dto.dart`)에 `primaryEmotion`·`moodEmoji`·`aiComment`·`aiTitle`·`backgroundColor`·`textColor`·`accentColor` 완비.
  - ⚠️ **필체(폰트) 동적 적용**은 미도입(감정별 배경/글자/강조 색 + 이모지·마스코트로 대체). 음악(Task 014)은 미구현.

- **Task 014: 감정 기반 음악 개요**
  - 감정에 매핑된 음악 재생. 음악 소스 미정 흡수를 위한 `MusicSource` + `tracks.source_type` 추상화

### Phase 6: 소셜(친구·공유·피드·공감) ✅ (Testcontainers Docker 대기)

기록장에 **소셜 계층**을 추가한다. 단계적 4개 Task로 분할했고, 목표 스키마·API 계약이 `docs/`에 이미 확정돼 있어 구현 작업으로 진행했다. Flyway `V11~V14`, 백엔드 신규 `domain.{social,feed}` + `domain.diary` 확장, 앱 `features/{friend,feed}` + 4번째 탭(피드). 감정 상호작용은 **공감(EMPATHY)만**(댓글 범위 외), 외부 노출은 UUID/친구코드. F020~F025.

> **진행 현황**: 백엔드 compileJava/compileTestJava 통과 + 슬라이스 테스트(@WebMvcTest: Friend/Feed/Reaction/Diary Controller) 통과. Testcontainers 통합(FriendServiceTest·FeedServiceTest·ReactionServiceTest·DiaryServiceTest 확장) **작성·컴파일 완료, 실행은 배포 전 Docker 일괄**(기존 007/008 계열 방침). 앱 `flutter analyze` 무경고 + `flutter test` 93건 전체 통과.

- **Task 015-1: 친구 관계 (친구코드+검색·요청·수락·차단)** ✅ - 구현 완료(Testcontainers Docker 대기)
  - 구현 기능: F020(친구 관계), F021(친구 검색)
  - DB `V11`: `users.friend_code`(혼동문자 제외 base32 8자, nullable→백필→UNIQUE→NOT NULL), `friendships`(status PENDING/ACCEPTED/BLOCKED·blocker_id). **역방향 중복은 정렬쌍 함수 유니크**(`uq_friendship_pair` LEAST/GREATEST)로 차단(방향 유니크로는 불충분).
  - 백엔드 `domain.social`: `FriendController`(`POST /friends/requests`·`/requests/{id}/accept|reject`·`GET /friends`·`GET /friends/requests?direction=`·`GET /friends/search?query=`·`DELETE /friends/{userUuid}?block=`), `FriendService`(대상 친구코드/uuid 해석, 역방향 PENDING 자동수락, 소유권 가드 404 은닉), `FriendCodeGenerator`, `UserProvisioningService` 친구코드 발급, `GET /users/me`에 `friendCode`. ErrorCode `FRIEND_*` 5종.
  - 앱 `features/friend`: `/friends`(목록·요청함 배지)·`/friends/requests`(받은/보낸)·`/friends/add`(친구코드 카드·코드입력·닉네임 검색). 프로필에서 진입.

- **Task 015-2: 공개범위 변경 + 공유 링크** ✅ - 구현 완료(Testcontainers Docker 대기)
  - 구현 기능: F022(공개범위·확정 후 변경), F023(공유 링크)
  - DB `V12`: `chk_diaries_visibility` CHECK. (`share_token`·`visibility`는 V2에 존재)
  - 백엔드: `PATCH /diaries/{id}/visibility`(확정 기록도 허용 — 본문 불변과 분리한 전용 UPDATE), `GET /diaries/shared/{shareToken}`(비인증, 활성·확정·**PRIVATE 아님**만 — PRIVATE은 링크로도 차단), `SecurityConfig` CORS에 PATCH 추가.
  - 앱: 에디터 공개범위 선택(`VisibilitySegment`), 상세 AppBar 공개범위 변경 시트+공유 시트(`share_plus`, PRIVATE이면 공유 비활성).

- **Task 015-3: 피드 (감정 카드→전문)** ✅ - 구현 완료(Testcontainers Docker 대기)
  - 구현 기능: F024
  - DB `V13`: 피드용 부분 인덱스(`idx_diaries_public_feed`·`idx_diaries_friends_feed`, 정렬키 id DESC).
  - 백엔드 `domain.feed`: `GET /feed`(본인+PUBLIC+수락친구 FRIENDS·DONE·비차단, id DESC 커서, 감정 카드 DTO), `GET /feed/{id}`(viewer-aware 전문, 볼 수 없으면 404). `DiaryMapper.findFeed`/`findViewableById` + 공용 가시성 SQL fragment. 기존 owner-only `GET /diaries/{id}` 유지.
  - 앱: 하단 탭 3→4개(피드, 브랜치 맨 뒤 append), `FeedNotifier`(무한 스크롤·새로고침), 감정 파스텔 카드→`/feed/diary/:id` 전문.

- **Task 015-4: 공감 (리액션)** ✅ - 구현 완료(Testcontainers Docker 대기)
  - 구현 기능: F025
  - DB `V14`: `diary_reactions`(1인 1회 `uq_reaction_once`) + `diaries.reaction_count`(비정규화 캐시, 서비스 원자 증감).
  - 백엔드 `domain.social`: `POST/DELETE /diaries/{id}/reactions`(멱등, `ReactionResponse{reactionCount,reacted}`), `ReactionService`(볼 수 없는 글 공감 시 404, 가시성 술어는 findFeed와 공유). findFeed/findViewableById의 공감 리터럴을 실제 값(캐시 + EXISTS)으로 교체.
  - 앱: 공용 `ReactionButton`(바운스 애니메이션·낙관적 갱신), 피드 카드·전문에 배선.

- **Task 015(구): 공유·피드·친구·공감 개요** — 위 015-1~4로 분해·구현됨(원 개요 보존)
  - 공유: visibility(PRIVATE/FRIENDS/PUBLIC) + `share_token` 공유 링크 단건 조회
  - 피드: 본인 + PUBLIC + FRIENDS 기록 커서 페이징(`GET /feed`)
  - 친구: 요청/수락/거절/목록/삭제(`/friends/*`)
  - 공감(리액션): 1인 1회 추가/취소(`/diaries/{id}/reactions`). 댓글은 범위 외

- **Task 016: 홈서버 배포** — 상세 절차: **`docs/deployment.md`**, 실행 체크리스트: **shrimp task manager**
  - **채택 아키텍처**: 집 서버 PC(Windows 10) → WSL2 Ubuntu → Docker(`postgres:18` + backend:8080 + Jenkins pollSCM + 보류 ollama). 폰(Z Flip3)은 **Tailscale VPN**으로 접속(포트포워딩·CGNAT 회피, 외부 미개방). Supabase Auth·FCM·Gemini는 클라우드 그대로.
  - **자체호스팅 PostgreSQL**: 같은 서버 컨테이너(`recorme` DB), 빈 DB 최초 기동 시 Flyway V1~V17 자동 적용. `application-cloud.yml`은 `DB_URL/DB_USER/DB_PASSWORD` 환경변수로 연결. 백업(pg_dump)·명명 볼륨(`uploads`) 영속화.
  - **준비된 산출물**(커밋 완료): `backend/Dockerfile`(self-contained 멀티스테이지), `deploy/docker-compose.yml`, `deploy/env.example`, `Jenkinsfile`(pollSCM 5분), 앱 `network_security_config.xml`·릴리즈 서명 config·`build_release` 스크립트.
  - **정합성 교정**(배포 시 필수): `SPRING_PROFILES_ACTIVE=cloud` / 데이터소스 var 이름 / `STORAGE_ROOT` 볼륨 경로 일치 / 릴리즈 앱 cleartext·서명. (§`docs/deployment.md` 트러블슈팅)
  - **잔여 검증 실행**(Docker 확보 후): 백엔드 Testcontainers 통합테스트 일괄 실행 ②, 작심삼일 FCM 실기기(Z Flip3) 라이브 검증 ①.
  - 성능(캘린더 summary 캐싱·인덱스 튜닝), 모니터링·로깅, 애플 로그인(Supabase Apple provider) 확장은 이후.

### Phase 7: 캐릭터 중심 전환 (LLM 감정 분석 비활성화 · 커스터마이징 · 미션/해금 · 락인)

제품의 중심을 **"기록하면 LLM이 감정을 분석해 테마·영상을 입힌다"**에서 **"기록하면 내 캐릭터가 반응하고, 쌓일수록 캐릭터가 꾸며진다"**로 전환한다. 목표는 애착 기반 7일 리텐션(1단계)과, 데이터가 쌓일수록 떠나기 어려운 락인 구조(2단계)다. 감정 분석(F018)·동적 테마(F019)는 **삭제가 아니라 비활성화/대체**한다 — 백엔드 LLM 코드·테이블은 flag로 보존하고(`ANALYSIS_ENABLED=true` 한 줄로 복구), 앱 감정 연출만 제거해 연출 주인공을 **내 캐릭터 하나로 일원화**한다. 감정은 **사용자가 직접 입력**(프리셋 6종 또는 자유 텍스트 ≤20자)하는 **순수 기록 메타데이터**가 되며, 캐릭터 리액션·미션 판정·해금 어디에도 관여하지 않는다(달력 표시·회고 통계 전용). 확정('오늘을 기억하기') 라이프사이클은 **유지**되어 리액션·코인·해금의 유일한 트리거가 된다(확정 후 수정 불가 = 보상 어뷰징 방지).

> **핵심 설계**: ① 캐릭터 **2종으로 시작**(`MONKEY` 원숭이 — 여유롭고 느긋함 / `RED_PANDA` 레서판다 — 부지런하고 애착 강함). ② 렌더는 **통짜 PNG + 메시 워프**(`IdleCharacterView`) — 3D 렌더풍 정면 PNG를 12×16 격자로 쪼개 정점마다 변형한다. **Rive와 파츠 조립을 둘 다 시도했다가 되돌렸다**(Task 031 참고 — 파츠가 서로 맞지 않아 캐릭터가 조각나 보였다). 의상·소품은 `RenderMeta` 좌표로 오버레이(아이템 추가에 앱 재배포 불필요). ③ 아이템은 **group(소유·착용) ↔ variant(렌더) 2단 구조** — 캐릭터마다 체형이 달라 옷 PNG를 따로 그려야 하므로, 사용자는 `group_code`("빨간 후드티")를 소유하고 렌더 시에만 `(group_code + 캐릭터)`로 variant를 해석한다 → **캐릭터를 바꿔도 옷장이 그대로 따라온다**. ④ 해금은 **미션(누적 업적) 단일 경로**. ⑤ 모든 적립·해금·구매는 `character_events(user_id, event_key) UNIQUE` **단일 멱등 관문**을 통과한다. ⑥ 렌더러는 외부 의존성 0(`IdleCharacterView` — 메시 워프)이라 에셋 제작이 크리티컬 패스에 걸리지 않는다. ⚠️ **눈 깜빡임은 미지원**(통짜 이미지 한계 — Task 031).

> **탭 재편(회귀 주의) — 아직 수행하지 않았다**: 목표는 `[캐릭터(홈)] [캘린더] [작심삼일] [피드] [프로필]`이며 캘린더가 index 0 → 1로 밀린다. Phase 6의 "탭은 맨 뒤 append로 인덱스 보존" 전제가 여기서 깨지므로 **FCM 딥링크·`context.go` 경로 전수 점검 + 탭 인덱스 회귀 테스트 필수**.
> **현재 상태**: Task 029가 회귀 위험을 이유로 탭 재편을 **캐릭터 홈 구현과 함께 별도 작업으로 미뤘다.** 탭은 여전히 `[캘린더][목록][작심삼일][피드]` **4개**이고, 라우터에는 **현재 브랜치 순서(캘린더 index 0)를 못박는 가드 테스트**가 걸려 있다 — 탭을 재편하는 순간 이 가드가 실패하며 전수 점검을 강제한다.

> **신규 기능 ID(진행 현황)**: **F026** 캐릭터 선택 — 🔶 **부분**(백엔드 API ✅ / 앱 온보딩 선택 ✅ / Rive 렌더 ❌) / **F027** 코스튬·옷장 — 🔶 **부분**(백엔드 착용 API ✅ / 앱 옷장 UI ❌) / **F028** 코인 — ❌ / **F029** 코인 구매(옷장 통합 — 별도 상점 화면 폐기) — ❌ / **F030** 미션 해금 — 🔶 **부분**(스키마·`GET /missions` ✅ / 판정·지급 엔진 ❌) / **F031** 기록 리액션 — ❌ / **F032** 월간 회고·성장 — ❌ / **F033** 캐릭터 홈·소품 진열 — 🔶 **부분**(백엔드 ✅ / 앱 홈 화면 ❌).
> **F018(감정 분석)·F019(동적 테마·연출)**: 원안대로 "비활성/캐릭터로 대체됨"으로 전환할 예정이나 **Task 024·025가 미착수라 아직 활성 상태**다(Phase 4 Task 012·013 ⚠️ 주석 참조).

> **순서 원칙**: 감정 걷어내기 → 스키마 → 백엔드 → 앱(대체 렌더러로 전 기능 완성) → Rive 교체(에셋 의존, 최후) → 락인. **최대 리스크는 Task 028(멱등성)** — 여기만 정확하면 나머지는 CRUD다.

> **⚠️ 마이그레이션 번호 재배치(실적 반영)**: 실제로는 **Task 026을 먼저 착수**해 **V15~V17을 선점**했고, 이어 **보상 재설계(경험치/레벨 드롭)가 V18을 선점**했다. Task 024가 원안대로 V15를 쓰면 이미 적용된 DB에 뒤늦게 V15가 등장해 Flyway가 **out-of-order로 기동을 거부**한다. → **Task 026 = V15~V17**, **보상 재설계 = V18**, **Task 024 = V19**.

> **📊 Phase 7 진행 현황**(2026-07-20): **Task 024·025·026·027·029·031·032·033 ✅ 완료** · **Task 028 ✅ 부분 완료(코인 적립 엔진 + 상점 구매 — 미션 아이템 지급만 범위 밖)** · **Task 030 ✅ 완료(옷장·보상함·구매 실행 UI. 상점·미션 화면은 재설계로 폐기)**. **Phase 7 전 Task 구현 완료** — 남은 건 실기기/에뮬 검증뿐(작심삼일 FCM 라이브, Task 032 `integration_test`, Task 033 두 계정 E2E).
> ✅ Task 024/025 완료로 **LLM 감정 자동 분석은 기본 비활성**(`record.analysis.enabled` 기본 false)이며, 확정 시 즉시 `DONE` + **사용자 직접 입력 감정**(프리셋/자유 텍스트)을 저장한다.
> ✅ Task 029 완료로 **탭은 `[캐릭터 홈][캘린더][작심삼일][피드][프로필]` 5개, 캐릭터 홈 index 0**이다(로그인 후 첫 화면). 목록은 캘린더 앱바 버튼으로, 프로필은 탭으로 승격됐다.

- **Task 024: 백엔드 LLM 비활성화 flag + 감정 사용자 입력 전환 (V19)** - 우선순위 · **미착수**
  - 구현 기능: F018·F019 축소 (감정 분석 비활성화 + 사용자 직접 입력 전환)
  - DB `V19__diary_manual_emotion.sql`(**원안 V15 → V18 → V19**: Task 026이 V15~V17, 보상 재설계가 V18 선점): `diaries`에 `emotion_label VARCHAR(20)`(직접 입력 감정) 추가 + `chk_diaries_done_has_emotion` **DROP**(감정 미입력도 확정 가능). `emotion_types` 6종 마스터는 **유지**(프리셋 라벨·정렬의 단일 진실원). 기존 감정·테마 컬럼은 **보존**(LLM 복구 대비)
  - 설정: `application.yml`에 `record.analysis.enabled: ${ANALYSIS_ENABLED:false}` 추가. `EmotionAnalysisService`·`EmotionAnalysisPoller`·`LlmEmotionAnalyzer`·`infra/llm/*`를 **삭제하지 않고** `@ConditionalOnProperty`로 빈 미등록 처리 → LLM 호출·비용 0, 코드 100% 보존
  - `SaveDiaryRequest`에 `emotion`(프리셋 코드, `emotion_types` FK) + `emotionLabel`(자유 텍스트 `@Size(max=20)`) 추가 — **둘 다 선택**(감정 없이도 저장·확정 가능), **동시 지정 시 400 `EMOTION_CONFLICT`**(신규 ErrorCode)
  - `DiaryService.upsert`: flag **off** → 확정 시 `analysis_status='DONE'` **즉시 전이**(대기 없음 → 리액션 지연 0) + 사용자 감정 저장, 색상·AI 필드(`background_color`/`ai_comment`/`ai_title`/`mood_emoji`/`emotion_scores`)는 NULL / flag **on** → 기존 `PENDING`+비동기 분석 경로 **무손상 유지**
  - `GET /diaries/me/emotions/recent`: 최근 사용한 커스텀 감정 목록(재입력 편의 — 앱 작성기 추천 칩)
  - **(구현 직후 필수 테스트)** JUnit5 + Testcontainers — flag off 시 확정하면 `analysis_status='DONE'` + 사용자 감정 저장 + AI 필드 NULL 검증 / 프리셋·커스텀 **동시 지정 400 `EMOTION_CONFLICT`** / **감정 미입력도 확정 성공**(CHECK 해제 확인) / `emotionLabel` 21자 → 400 / **flag on 복구 시 기존 PENDING 분석 경로 정상 동작**(회귀 방지 — 가장 중요) / flag off 시 LLM 관련 빈 **미등록** 확인 / V19 마이그레이션 적용 및 기존 확정 기록 무손상

- **Task 025: 앱 감정 연출 제거 + 작성기 감정 입력 위젯** · **미착수**
  - 구현 기능: F018·F019 축소 (모바일 — 연출 제거 + 사용자 입력 UI)
  - **제거**: `shared/widgets/emotion_video.dart`·`emotion_avatar.dart`, `shaders/emotion_alpha.frag` + pubspec `shaders:` 섹션 + `flutter_shaders` 의존성, `assets/emotions/**`·`assets/videos/running_sel.mp4`(원본은 `docs/`에 재인코딩 소스로 보존), `diary_detail_view.dart`의 `_IntroPhase`·`_RunningIntroOverlay`·**PENDING 3초 폴링**(확정 응답이 곧 DONE이므로 불필요), 피드 카드 감정 배경색·`diary_dto.hasTheme`
  - **축소**: `core/theme/diary_theme.dart` 팔레트 → `emotion_palette.dart`(**달력 점 색 + 감정 칩 색만**), `core/theme/emotion_assets.dart`(PNG/mp4 경로) → `emotion_labels.dart`(**라벨만**). 상세·목록·피드는 **중립 카드 + 감정 칩**으로 렌더
  - **유지**: 로그인 마스코트 영상 3종과 `video_player`(브랜딩 자산) — 삭제하지 않는다
  - **추가**: `diary_editor_view.dart`에 감정 입력 위젯 — **프리셋 칩 6종**(JOY/SADNESS/ANGER/CALM/ANXIETY/NEUTRAL) + **"직접 입력"**(≤20자, 카운터) + **최근 사용 감정 추천**(`GET /diaries/me/emotions/recent`). **감정은 선택 사항**이며 미입력 확정도 정상 동작
  - **(구현 직후 필수 테스트)** `flutter test` — 프리셋 칩 선택/해제, 직접 입력 20자 경계(21자 입력 차단), 프리셋·직접 입력 **상호 배타**(동시 선택 불가 → 400 사전 차단), 최근 감정 추천 칩 탭 시 값 채움, **감정 없이 확정 가능**, 확정 직후 상세가 **폴링 없이 즉시 DONE 렌더** / `flutter analyze` **클린**(삭제 위젯·셰이더·에셋 참조 0건 — 잔존 import 0 확인)

- **Task 026: DB 캐릭터 도메인 스키마 (V15~V17) + 캐릭터 2종 시드** — ✅ **완료**
  - 구현 기능: 캐릭터 도메인 토대 (F026~F033 공통)
  - **실적**: V15(캐릭터 **2종**·대사 **33행**·item_group **5종**·variant **8행** 시드) / V16(미션 **5종** 시드) / V17(사용자 상태 6테이블). 로컬 PG18 `recorme` **적용 완료**(Flyway 버전 **17**), `CharacterSchemaTest`(Testcontainers) **통과**
  - **`uq_variant`는 `UNIQUE NULLS NOT DISTINCT(group_code, character_code)`** — 공용 아이템은 `character_code`가 NULL인데, 표준 UNIQUE는 NULL을 서로 다른 값으로 봐서 **공용 variant의 중복을 못 막는다**(PG15+ 문법 필수)
  - `V15__add_character_catalog.sql`: `characters`(code PK·name_ko·tagline·rive_artboard·thumbnail_url·sort_order·active) + **2종 시드**(`MONKEY` 여유롭고 느긋한 / `RED_PANDA` 부지런하고 애착 강한 — 둘 다 온보딩 무료 선택). `item_groups`(code PK·slot·name_ko·thumbnail_url·acquire_type(DEFAULT/MISSION/COIN)·coin_price·sort_order·active) = **상점·인벤토리가 다루는 단위**, slot ∈ `HAT`/`OUTFIT`/`GLASSES`/`PROP`(손)/`ROOM_PROP`(방 소품)/`BACKGROUND`. `character_items`(group_code FK·character_code FK **nullable**·image_url·rive_slot·render_meta JSONB) = **렌더 단위(variant)**, `character_code` NOT NULL=캐릭터 전용(체형·머리 크기가 달라 별도 PNG 필요) / NULL=공용(ROOM_PROP·BACKGROUND), `uq_variant UNIQUE(group_code, character_code)`. `character_lines`(character_code nullable(=공용)·context·line_ko·rive_trigger·weight) — **`context`는 감정이 아님**: `CONFIRM`/`STREAK_3`/`STREAK_7`/`MISSION`/`LEVEL_UP`/`IDLE`
  - `V16__add_missions.sql`: `missions`(code PK·title·description·**rule JSONB**·coin_reward·item_group_reward FK·sort_order·active + `chk_missions_reward CHECK(coin_reward > 0 OR item_group_reward IS NOT NULL)`) + `user_missions(user_id, mission_code, achieved_at, PK(user_id, mission_code))`. rule 타입: `DIARY_COUNT`/`CONSECUTIVE_DAYS`/`RESOLUTION_SUCCESS`/`RESOLUTION_STREAK`(⚠️ V16엔 `LEVEL`도 있었으나 **V18 보상 재설계에서 제거** → 4종) — **감정 규칙 없음**. 판정은 DB 트리거가 아닌 `MissionEvaluator` 순수 함수
  - `V17__add_user_character_state.sql`: `user_character_state`(user_id PK·selected_character FK — ⚠️ V17엔 `level`·`exp` 컬럼도 있었으나 **V18에서 드롭**, 경험치/레벨 폐기), `user_item_groups(user_id, group_code)` — **소유는 group 단위**(캐릭터 교체 시 옷장 유지), `user_equipment(user_id, slot, slot_index, group_code)` + `CHECK(slot='ROOM_PROP' OR slot_index=0)`(단일 슬롯 1개 / ROOM_PROP만 0~5 다중 진열), `user_progress`(confirmed_diary_count·consecutive_days·last_confirmed_date·resolution_success_count·max_streak_seq — **미션 판정 O(1) 캐시**), `user_wallets`(balance INT `CHECK >= 0`), `character_events`(user_id·event_key·event_type·coin_delta·balance_after·diary_id·payload JSONB·acked_at) + **`uq_character_events_key UNIQUE(user_id, event_key)`** — 이 한 테이블이 ① 멱등 관문 ② 코인 원장 ③ 리액션 페이로드 ④ 미확인 보상 알림함을 겸한다
  - **(구현 직후 필수 테스트 — 완료)** JUnit5 + Testcontainers — V15~V17 무오류 적용, `uq_variant(group_code, character_code)` 중복 차단, **`uq_character_events_key` 중복 삽입 차단**(멱등 관문의 물리적 근거), `user_wallets.balance` **음수 UPDATE 거부**(CHECK), `chk_missions_reward`(보상 둘 다 없으면 거부), `user_equipment` slot_index CHECK(ROOM_PROP 아닌데 index≠0 거부), **캐릭터 2종 시드 존재**(MONKEY·RED_PANDA), FK 무결성(존재하지 않는 group_code 소유 거부)

- **Task 027: 백엔드 캐릭터·미션 조회/선택/착용 API (group↔variant 해석)** — ✅ **완료**
  - 구현 기능: F026(캐릭터 선택), F027(코스튬·옷장), F033(캐릭터 홈·소품 진열)
  - **실적**: controller 3 / service 4(+`CatalogCache`) / mapper 3(+XML) / dto·vo. ErrorCode 4종은 실제로 **`global/exception/ErrorCode.java`**에 추가(설계 시 적어둔 `global/error/`가 아님). **백엔드 전체 202개 테스트 통과**(Docker 실기동 — Testcontainers 포함)
  - **설계와 의도적 차이**: ① `GET /characters/me`는 **미선택자도 200 + `character: null`**(앱이 온보딩 분기를 에러가 아닌 정상 응답으로 판정) ② `PUT /characters/me/equipment`는 **전체 스냅샷 PUT** ③ 존재하지 않는 캐릭터 코드는 404가 아니라 **409 `CHARACTER_NOT_OWNED`로 통일**(카탈로그 존재 여부를 캐내는 열거 신호 차단)
  - **원안에 없던 추가**: **`acquire_type='DEFAULT'` 아이템의 기본 지급을 JIT 프로비저닝에 포함**. DEFAULT 그룹은 미션·구매 어느 경로로도 지급되지 않아 **아무도 소유할 수 없는 구멍**이 되므로 baseline으로 함께 지급한다(보상 **적립**이 아니라 초기 상태 구성 → Task 028 영역 불침범)
  - **부수 수정**: `FlywayMigrationTest`·`CharacterSchemaTest`의 `insertUser` 픽스처가 `users.friend_code`(V11 NOT NULL+UNIQUE)를 누락해 **Docker 실행 시 21개가 전부 실패**하던 선행 결함을 함께 고침
  - 신규 패키지 `com.recordapp.domain.character`: `controller/`(CharacterController·WardrobeController·MissionController) → `service/`(CharacterService·WardrobeService·MissionService·CatalogCache) → `mapper/`(CharacterCatalogMapper·UserCharacterMapper·MissionMapper) → `dto/`·`vo/`
  - **기본 상태 JIT 생성**: 최초 접근 시 `user_character_state`·`user_wallets`·`user_progress` 자동 생성(멱등 — `ON CONFLICT DO NOTHING`). `UserProvisioningService`와 동일 철학
  - API: `GET /characters`(2종 + owned) · `GET /characters/me`(선택·착용·코인·미확인 보상 수 — ⚠️ level/exp 필드는 V18 보상 재설계로 제거) · `PUT /characters/me/selection` · `PUT /characters/me/equipment`(**배치 교체**, `group_code` 단위) · `GET /characters/items?slot=`(group 목록 + owned + **내 캐릭터 기준 variant 이미지**) · `GET /missions`(달성 여부 + 진행률)
  - **★ group↔variant 해석**: 착용·소유는 `group_code`로만 저장하고, 응답 렌더 정보는 `(group_code + 선택 캐릭터)`로 `character_items`를 조인해 이미지/`rive_slot`/`render_meta`를 해석한다 → **캐릭터를 교체해도 착용 상태는 유지되고 variant만 재해석**된다. 해당 캐릭터용 variant가 미제작이면 409 `ITEM_VARIANT_MISSING`
  - 신규 ErrorCode: `CHARACTER_NOT_OWNED`(409), `ITEM_NOT_OWNED`(409), `ITEM_SLOT_MISMATCH`(400), `ITEM_VARIANT_MISSING`(409)
  - **(구현 직후 필수 테스트 — 완료)** JUnit5 + Testcontainers — **JIT 기본 상태 생성 멱등**(동시 2회 호출에도 1행), 미보유 group 착용 시도 **409 `ITEM_NOT_OWNED`**, slot 불일치 착용 400, **★ 캐릭터 교체 시 착용 유지 + variant만 재해석**(핵심 시나리오), 해당 캐릭터용 variant 미제작 시 **409 `ITEM_VARIANT_MISSING`**, `ROOM_PROP` 다중 진열(0~5) + 단일 슬롯 중복 착용 거부, 배치 교체가 원자적(일부 실패 시 전체 롤백), **IDOR 차단**(타인 상태 조회·수정 불가)

- **Task 028: ★ 백엔드 보상 엔진 — 이벤트 훅 + 멱등 게이트 + 미션 판정 + 코인 + 백스톱 폴러** · **미착수**
  - 구현 기능: F028(코인), F029(상점), F030(미션 해금)
  - ⚠️ **Phase 7 최대 리스크 지점.** 여기만 정확하면 나머지는 CRUD다. 테스트를 가장 두껍게 작성한다
  - **도메인 훅킹(단방향)**: `global/event/`에 `DiaryConfirmedEvent(userId, diaryId, writtenDate)`·`ResolutionSucceededEvent(userId, resolutionId, streakSeq)` 정의. 기존 코드는 **`publishEvent` 한 줄씩만** 추가 — `DiaryService.upsert`(확정=DONE 전이 시), `ResolutionService.completeToday`(`markResolutionSuccessIfAllDone(id)==1` 블록, 기존 push 훅 옆). **diary·resolution은 character를 모른다** → 보상이 터져도 기록 저장은 롤백되지 않는다
  - **수신**: `CharacterEventListener` — `@TransactionalEventListener(AFTER_COMMIT)` + `@Async("characterExecutor")`. `AsyncConfig`에 `characterExecutor`(core 2 / max 4 / queue 200 / CallerRunsPolicy) 추가
  - **★ 멱등 보상 엔진** `CharacterRewardService`(`@Transactional(propagation = REQUIRES_NEW)`): ① `character_events`에 `event_key`(`DIARY_CONFIRM:{diaryId}`) **`INSERT … ON CONFLICT DO NOTHING`** → **0행이면 즉시 no-op 반환**(재전달·폴러 중복 흡수). 게이트 삽입 성공(1행)이 **모든 부작용의 유일한 진입 조건** ② 코인 적립 + `balance_after` 기록 ③ `user_progress` UPSERT + RETURNING(확정 수·연속일·최대 streak) ④ `MissionEvaluator`(순수 함수)로 미션 판정 — 미션도 `event_key='MISSION:{code}'` 게이트를 통과해 **보상 1회 보장** ⑤ `character_lines`에서 **캐릭터별·맥락별**(감정 아님 — CONFIRM/STREAK/MISSION/LEVEL_UP) 대사 1줄 선택 ⑥ `payload` 갱신 → **앱 리액션의 단일 소스**
  - **코인 소비(경합 안전)**: `POST /characters/items/{groupCode}/purchase` → `UPDATE user_wallets SET balance = balance - ? WHERE user_id = ? AND balance >= ?` → **0행이면 409 `COIN_INSUFFICIENT`**(CHECK 제약이 최종 방어선). `record.character.coin-enabled=false`(기본)이면 403 `FEATURE_DISABLED` — **적립은 항상 동작, 상점 소비만 게이팅**
  - **백스톱 폴러** `CharacterRewardBackfillPoller`: `EmotionAnalysisPoller`와 동일 철학 — 확정됐으나 `character_events`에 게이트가 없는 기록을 주기적으로 스캔·보정(비동기 유실 대비). 게이트가 멱등하므로 중복 적립 불가
  - API: `GET /characters/me/wallet` · `GET /characters/me/rewards`(커서 — 미확인 보상함) · `POST /characters/me/rewards/ack` · `POST /characters/items/{groupCode}/purchase` · `GET /characters/me/reaction?diaryId=`(**확정 즉시 생성 → 폴링 불필요**)
  - 설정: `record.character.{coin-enabled: false, coin-per-diary: 10, coin-per-resolution-success: 30}`(⚠️ `exp-per-diary`는 경험치/레벨 폐기(V18)로 제거). 신규 ErrorCode: `COIN_INSUFFICIENT`(409), `FEATURE_DISABLED`(403)
  - **(구현 직후 필수 테스트 — 가장 두껍게)** JUnit5 + Testcontainers — ① 확정 1회 → **코인·진척도·`character_events` 정확히 1행** ② **★ 같은 이벤트 3회 재전달 → 잔액·진척도·미션 전부 불변**(멱등 핵심) ③ 미션 임계값 도달 시 **보상 1회만** 지급(재판정해도 재지급 없음) ④ 작심삼일 완주 시 코인 적립 + `RESOLUTION_STREAK` 미션 판정 ⑤ **트랜잭션 롤백 시 미적립**(AFTER_COMMIT 보장 — 기록 저장 실패했는데 코인만 들어오면 안 됨) ⑥ **백스톱 폴러가 유실분 보정**(리스너 미실행 상황 시뮬레이션 → 폴러 실행 → 1회만 적립) ⑦ **구매 동시 요청 경합 시 잔액 음수 불가**(0행 UPDATE → `COIN_INSUFFICIENT`) ⑧ **연속일 계산**(연속 확정 시 증가 / **하루 건너뛰면 리셋** / 같은 날 재확정은 불변) ⑨ `coin-enabled=false`에서 구매 403 `FEATURE_DISABLED`(적립은 정상)

- **Task 029: 앱 캐릭터 홈(1번 탭) + 탭 재편 + 온보딩 + 대체 렌더러 + 데이터 계층** — 🔶 **부분 완료(온보딩 선택창까지)**
  - 구현 기능: F026(캐릭터 선택) **부분** / F033(캐릭터 홈·소품 진열) **미착수**
  - **✅ 완료**: 데이터 계층(`CharacterRepository` abstract → Api/Fake + Riverpod providers) · `/onboarding/character` 라우트 + **redirect 가드**(`characterOnboardingRedirect` **순수 함수** — async 호출 없이 상태만 보고 판정, 판단 불가면 `null`로 분기 보류 → 루프 방지) · **캐릭터 선택 온보딩 화면** · `CharacterStage` 렌더러 스위치 · `IdleCharacterView`. `flutter analyze` 무경고 · `flutter test` **112개 통과**
  - **❌ 미착수(중요)**: **탭 재편을 하지 않았다** — 하단 탭은 여전히 `[캘린더][목록][작심삼일][피드]` **4개**, **캘린더 index 0 유지**. FCM 딥링크 회귀 위험이 커서 **캐릭터 홈 구현과 한 덩어리로 묶어** 별도 작업으로 미룸. 그 사이 라우터에는 **현재 브랜치 순서를 못박는 가드 테스트**를 걸어 둠(탭 재편 시 실패하며 전수 점검을 강제). / **캐릭터 홈(1번 탭)·`placeholder_character_view.dart`·상태바·소품 진열·하단 액션 전부 미구현** / **`AppColors.currency` 토큰 미추가**(코인을 그리는 화면이 아직 없음)
  - **온보딩 UI는 설계와 다르게 갔다**: 원안의 "좌우 2장 대형 비교"가 아니라 **peek 캐러셀**(`PageView`, `viewportFraction 0.78`) + 페이지 도트 + 하단 "선택" CTA, 전환 3수단(드래그·옆 카드 탭·도트 탭). 사용자 요청이며, **캐릭터가 3종 이상으로 늘어도 레이아웃이 그대로 확장**된다. 헤드라인은 "기억을 같이 만들어갈 / 친구를 선택해주세요.", **tagline은 렌더하지 않음**
  - **렌더러는 `IdleCharacterView`(메시 워프)** — `Canvas.drawVertices` + `ImageShader`로 PNG를 **12×16 격자**로 변형(발 고정 스웨이·숨쉬기 스쿼시&스트레치·머리 두리번·12초 주기 정수배 하모닉). 이미지를 통째로 `Transform`하면 **판자가 흔들리는 모양**이 되기 때문이다(Rive가 자연스러운 건 런타임이 아니라 **아트보드가 메시로 리깅**돼서다 — 같은 원리를 Flutter에서 직접 구현)
  - **`app.dart`에 `_AppScrollBehavior` 추가**: Flutter 기본 `MaterialScrollBehavior`가 `dragDevices`에서 **마우스를 제외**해 **웹에서 `PageView`가 마우스로 끌리지 않던** 문제 해결
  - 신규 feature `app/lib/features/character/`: `domain/`(character·item_group·my_character·mission·reward_event·retrospect + `CharacterRepository` **abstract**) → `data/`(`ApiCharacterRepository`·`FakeCharacterRepository`·dto) → `presentation/`(page·providers·widgets). **기존 컨벤션 준수**: abstract Repository → Api/Fake impl → Riverpod provider override → 라우트
  - **⚠️ 탭 재편(회귀 주의)**: `core/router/app_router.dart`·`scaffold_with_nav_bar.dart`를 `[캐릭터(홈)] [캘린더] [작심삼일] [피드] [프로필]`로 재구성 → **캘린더가 index 0 → 1로 밀린다**. **FCM 딥링크(`/resolution/:id`)·모든 `context.go` 경로 전수 점검** 필수(Phase 6의 "맨 뒤 append로 인덱스 보존" 전제가 깨짐)
  - **온보딩**: 가입 완료 후 `selectedCharacter == null`이면 go_router `redirect`로 `/onboarding/character` → **원숭이 vs 레서판다 좌우 대형 2장 비교** + 성격 소개 문구 → "이 친구와 시작하기" → `PUT /characters/me/selection`
  - **캐릭터 홈(몰입형 풀스크린 "내 방")**: 상단 반투명 상태바(`character_home_stat_bar` — 코인·보상 알림 배지. ⚠️ Lv·성장 게이지는 V18 보상 재설계로 폐기), 중앙 대형 캐릭터(idle 두리번거림), 주변 **소품 4슬롯 진열**, 배경은 착용 `BACKGROUND`, 하단 플로팅 패널(`character_home_bottom_actions` — **"오늘 기록하기" 주 CTA** + 옷장·미션. 별도 상점 버튼 없음 — 구매는 옷장 통합)
  - **★ 렌더러**: `character_stage.dart`(배경 카드 + 렌더러 배선) + `idle_character_view.dart`(**통짜 PNG 메시 워프**). 아이템 오버레이는 `render_meta`의 `anchorX`/`anchorY`/`scale`/`z`로 배치한다(Task 030). 외부 의존성이 없어 웹 포함 전 플랫폼 동일 동작
  - 색 역할 준수(`primary`=선택/CTA, `accent`는 AI 전용이므로 **미사용**. ⚠️ `success`=성장 게이지 역할은 게이지 폐기(V18)로 사라짐). 코인 색은 `AppColors`에 **`currency`(골드) 토큰 신규 승격**
  - **(구현 직후 필수 테스트)** `flutter test` — **★ 탭 인덱스 회귀**(캘린더 0→1 이동 후 각 탭 라우트 정상 진입, **FCM 딥링크 `/resolution/:id` 전수 검증**), 온보딩 리다이렉트(`selectedCharacter == null` → `/onboarding/character`, 선택 후 홈 복귀·재진입 시 리다이렉트 없음), **플레이스홀더가 `render_meta` 좌표(anchor·scale·z)대로 아이템 렌더**, 미착용 슬롯은 렌더 생략, 상태바 Lv·게이지·코인 바인딩, 로딩/에러/빈 상태 / `flutter analyze` 무경고

- **Task 030: 앱 옷장 · 상점 · 미션 · 보상함 UI** · **미착수**
  - 구현 기능: F027(코스튬·옷장), F029(상점), F030(미션 해금)
  - `wardrobe_page.dart`: slot 탭(HAT/OUTFIT/GLASSES/PROP/ROOM_PROP/BACKGROUND) + `item_grid_tile`(보유/미보유·착용중 표시) → 착용/해제 → **`PUT /characters/me/equipment` 배치 교체**. ROOM_PROP은 0~5 다중 진열 슬롯 UI
  - `shop_page.dart`: `acquire_type=COIN` group 목록 + 가격·잔액 표시 → 구매 확인 → `POST /characters/items/{groupCode}/purchase`. **잔액 부족 시 `COIN_INSUFFICIENT` 에러 UI**, `coin-enabled=false`면 `FEATURE_DISABLED` 안내(준비 중)
  - `mission_page.dart`: `mission_tile` + **`unlock_progress_bar`**(진행률 — "10개 중 7개 기록") + 달성 시 보상(코인·아이템) 표시. 해금은 **미션 단일 경로**임을 UI로도 명확히
  - 보상함: 미확인 `character_events` 목록(커서) → 확인 시 `POST /characters/me/rewards/ack` → 상태바 배지 감소
  - **(구현 직후 필수 테스트)** `flutter test` — 착용/해제 시 **배치 payload가 group_code 단위**로 정확히 구성됨, 미보유 아이템 착용 불가(비활성), **구매 성공 → 잔액 차감·소유 반영 / 구매 실패(잔액 부족) → 에러 UI·잔액 불변**, `FEATURE_DISABLED` 안내 노출, 미션 진행률 바 경계값(0%·99%·100%), 보상함 ack 후 배지 감소 및 목록에서 제거, 커서 페이징

- **Task 031: 캐릭터 렌더러 — 통짜 PNG + 메시 워프 (Rive·파츠 조립 둘 다 미채택)** · **완료**
  - 구현 기능: F026(캐릭터 렌더 품질)
  - **결론**: 기존 `IdleCharacterView`(통짜 PNG를 12×16 격자 메시로 워프 — 발 고정 스웨이·숨쉬기 스쿼시&스트레치·머리 두리번·12초 정수배 하모닉)를 **그대로 유지**하고, **에셋만 고해상도 투명 PNG로 교체**했다(`docs/recormeImo/chImg/` → 높이 1400 리샘플)
  - **Rive 미채택**: 고유 강점인 메시 변형·IK가 이 캐릭터엔 불필요하고, `.riv` **런타임 export가 유료**(2025-10 정책 변경)이며, `.riv`를 **코드·CLI로 만드는 공식 방법이 없어** 리깅이 GUI 수작업으로 남는다
  - **파츠 조립 미채택(구현했다가 되돌림)**: 파츠 28장을 관절로 엮는 렌더러를 끝까지 구현했으나(테스트 128개 통과) **화면에서 캐릭터가 조각나 보였다.** 원인은 코드가 아니라 에셋 — **파츠가 같은 3D 모델을 분해한 게 아니라 각각 따로 생성된 이미지**라 서로 맞지 않는다(눈 간격 **101 vs 117**, 몸통 색이 판다색, 팔 소켓과 소매 구멍 크기 불일치, **겹침 여유 없음** → 팔을 들면 어깨에 구멍). 고칠 때마다 다른 곳이 틀어져 **코드로 수렴하지 않는다**
  - ⚠️ **눈 깜빡임(F033)은 포기**: 통짜 이미지로는 눈을 감길 수 없다. 눈 깜빡임 하나를 위해 캐릭터가 조각나 보이는 건 손해다. 되살리려면 **에셋을 다시 만들어야** 한다(일관된 스케일 + 겹침 마진 + 앵커 메타)
  - **(검증)** `flutter analyze` 무경고 · `flutter test` **112개 통과** · 웹 실기 렌더 육안 확인. 상세 경위는 `tasks/031-app-parts-character-renderer.md`

- **Task 032: 앱 리액션 오버레이 + 월간 회고 카드 (락인 완성)** · ✅ **완료(2026-07-16)**
  - 구현 기능: F031(기록 리액션), F032(월간 회고·성장)
  - **리액션 오버레이**: `reaction_overlay.dart` + `character_speech_bubble.dart`. 확정 직후 editor 가 `/diary/:id?reaction=1` 로 push → `DiaryDetailPage(showReaction:true)` 가 상세 위 `Stack` 에 오버레이를 겹친다. **확정 응답이 곧 `DONE`이므로 대기·스피너 없이 즉시** 홈과 동일한 `CharacterStage` 로 캐릭터 등장 → 말풍선(맥락 기반 대사) + 코인 획득 카드 → 탭/‘확인’ → `ackRewards`(홈 배지 감소)·재표시 잠금. **획득이 없어도 대사 1줄은 항상**(서버 대사 없으면 캐릭터별 기본 대사 — 빈손 금지). 페이로드 소스는 `GET /characters/me/reaction?diaryId=`(data=null 허용). 일반 재진입(`reaction` 미지정)은 오버레이 미표시. 미션 달성 카드는 미션 아이템 지급이 범위 밖이라 코인 카드만 렌더
  - **월간 회고 카드(★ 락인)**: `retrospect_page.dart` + `/retrospect` 라우트 + 캐릭터 홈 ‘이달의 기록’ 버튼. `GET /characters/me/retrospect?yearMonth=` → 이달의 기록 수·최장 연속일·**감정 분포**(프리셋+직접 입력 혼재 막대)·획득 아이템 그리드·획득 코인 요약 + 월 이동(이전/다음, 미래 차단) + 빈 달 빈 상태(레벨 성장은 V18 보상 재설계로 폐기). 백엔드 `RetrospectService` — 기록은 `written_date`, 보상·아이템은 KST `created_at`/`acquired_at` 월 범위로 집계
  - **(검증)** 백엔드 `RetrospectServiceTest`(Testcontainers — 종합 집계·빈 달·연속일 리셋·IDOR) + `RetrospectControllerTest`(yearMonth 400/위임), **백엔드 전체 그린**. 앱 `reaction_overlay_test`·`retrospect_test` 신규, `flutter analyze` 무경고 · `flutter test` **149개 통과** · 코드 리뷰 클린. `integration_test/character_journey_test.dart`(가입→온보딩→홈→회고 + 리액션 즉시 등장 + 코인 멱등 + 구매·착용 관통)는 작성·컴파일 검증 완료, **실기기/에뮬 실행 대상**(데스크톱 프로젝트 미구성)

- **Task 033: 친구 둘러보기 (읽기 전용)** · ✅ **완료(2026-07-20)**
  - 친구 목록에서 **이름을 탭하면 그 친구의 recorme**(캐릭터 홈·캘린더·작심삼일)를 구경한다. 프로필·피드는 범위 밖
  - **탭 재구성**: 하단 탭의 **피드 → 친구**로 교체(5개 유지). 피드는 친구 목록 앱바에서 push(`/feed`, 셸 밖 → 뒤로가기 자동). 진입 방향이 기존과 반대다. 브랜치 정합은 `character_onboarding_redirect_test`의 '탭 브랜치 순서' 테스트가 지킨다
  - **백엔드**: `FriendBrowseController`(GET 3개 — `/friends/{userUuid}/character`·`/diaries/summary`·`/resolutions`) + `FriendBrowseService`. **권한 게이트는 `resolveFriendId` 단 하나**로, 친구아님·PENDING·차단·탈퇴·없는 uuid·**잘못된 형식 uuid**·자기자신을 전부 `USER_NOT_FOUND`(404)로 은닉한다(403은 uuid 실존을 흘리므로 회피). 차단 별도 검사는 불필요 — `uq_friendship_pair`가 쌍당 1행을 강제해 ACCEPTED와 BLOCKED가 공존할 수 없다
  - **프라이버시**: 캘린더는 `visibility IN ('FRIENDS','PUBLIC')` 확정 기록만 노출(신규 `findFriendSummaryDays` — 본인용 `findSummaryDays`는 무수정). **PRIVATE·DRAFT는 목록에서 빠져 "없는 날"과 구분되지 않는다.** 캐릭터 응답은 코인·미확인보상을 **타입에서 제외**(`FriendCharacterResponse`). 새 공개설정 컬럼·마이그레이션 없음
  - **재사용**: `CharacterService.buildMyCharacter`를 public 승격해 재사용 — `ensureState`(INSERT 4건)를 타지 않는 순수 조회라 **타인 계정에 상태 행을 만들지 않으며** 착용 아이템 variant 해석이 따라온다. `ResolutionService.getList/getCalendar`는 이미 userId 파라미터를 받아 **무수정 재사용**. 앱은 `CharacterStage`·`CalendarMonthView`·`ResolutionListTile`을 그대로 씀
  - **읽기 전용 보장**: 신규 API는 전부 GET이고 기존 쓰기 API는 모두 `principal.userId()`로만 대상을 정하므로 **남의 리소스를 바꿀 API 자체가 없다**(UI 제거는 UX 문제이지 보안 경계가 아니다)
  - **(검증)** 백엔드 `FriendBrowseServiceTest` 15개(권한 게이트 8·노출범위 4·작심삼일 2 + **`캐릭터_조회는_대상의_상태행을_생성하지_않는다`** 회귀 방어) → **백엔드 전체 251개 통과**. 앱 `friend_browse_test` 8개(쓰기 진입점 부재·캘린더 이동·비공개 무반응 포함) → **앱 157개 통과**, `flutter analyze` 무경고

- **Phase 7 로컬 실행**: `cd backend && ./gradlew bootRun`(네이티브 PG 18 `recorme`) + `cd app && flutter run` + `adb reverse tcp:8080 tcp:8080`
  - **웹 테스트**: `flutter run -d web-server --web-port=8000 --dart-define=API_BASE_URL=http://localhost:8080`. 포트 8000은 Supabase Site URL과 맞춘 값이라 OAuth 콜백이 돌아온다(다른 포트면 리다이렉트가 어긋난다). CORS는 `SecurityConfig`가 `http://localhost:*`를 허용한다

## 상태 범례

- **Phase 제목 + ✅**: 완료된 Phase
- **Task + ✅ - 완료**: 완료된 작업 (`See: /tasks/XXX-xxx.md` 참조 추가, 테스트 통과 확인 후에만)
- **Task + - 우선순위**: 즉시 시작해야 할 작업
- **구현 사항 ✅**: 완료된 세부 항목 / **-**: 미완료 세부 항목
- **완료(✅) 전제 조건**: 해당 Task의 "## 테스트 체크리스트"가 모두 통과해야 하며, 테스트 미수행·실패 Task는 절대 완료로 표시하지 않는다
