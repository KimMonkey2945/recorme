# record 개발 로드맵

날짜별로 하루를 글로 기록하고 언제든 다시 꺼내볼 수 있는 개인 모바일 일기장 — Flutter 앱과 Spring Boot 백엔드를 단일 저장소에서 함께 관리하는 모노레포 프로젝트.

## 개요

`record`는 매일 짧은 글쓰기로 하루를 정리하고 싶은 모바일 사용자를 위한 **날짜 기반 개인 일기장**으로, MVP에서 다음 핵심 기능을 제공합니다:

- **소셜 로그인 (Supabase Auth, F001/F010)**: Supabase Auth로 소셜 로그인(카카오/구글) → Supabase 세션(JWT). 백엔드는 Supabase JWT를 검증하고 최초 요청 시 자동 가입(JIT 프로비저닝). 세션 발급·갱신은 Supabase SDK가 담당
- **캘린더 기반 작성·조회 (F002/F003/F005)**: 월별 캘린더에서 작성 여부를 점(dot)으로 표시하고, 날짜 탭으로 신규 작성 또는 단건 조회로 분기
- **하루 1기록 upsert (F003/F006)**: `(user_id, written_date)` 부분 유니크 기반 upsert로 같은 날짜 재작성은 INSERT가 아닌 UPDATE 처리. 클라이언트는 일기 id 없이 날짜+내용만으로 저장
- **목록 탐색 + 소프트 삭제 (F004/F007)**: 커서 기반 무한 스크롤로 과거 기록을 역순 탐색하고, `deleted_at` 기록으로 소프트 삭제(삭제 후 같은 날짜 재작성 허용)

> 아키텍처·DB·API 계약의 단일 진실 공급원은 `docs/`다. 모든 구현은 `docs/PRD.md`, `docs/architecture.md`, `docs/database.md`, `docs/backend.md`, `docs/mobile.md`, `docs/api-contract.md`를 기준으로 한다.

## 기술 스택

| 구분 | 스택 |
|---|---|
| 모바일(`app/`) | Flutter 3.27.x / Dart 3.6.x, feature-first 구조, Riverpod, go_router, Dio(Supabase 토큰 첨부 인터셉터), json_serializable, flutter_secure_storage, supabase_flutter(Supabase Auth) / google_sign_in |
| 백엔드(`backend/`) | Java 21 / Spring Boot 3.3.x, 도메인 기반 패키지 `com.recordapp.domain.*`, Controller → Service(@Transactional) → Mapper(MyBatis) → PostgreSQL, Supabase JWT 검증(자체 발급 없음) |
| DB | PostgreSQL 16.x, Flyway 10.x (`uq_diary_user_day` 부분 유니크) |
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

> 구현 방식: "조용한 일기장" 디자인 컨셉(중립 캔버스 + 더스크 바이올렛 accent) + 화사한 웜 그라데이션 배경(Foodu 톤 참고). 더미 데이터는 `DiaryRepository` 추상 + `FakeDiaryRepository`로 격리(Phase 3에서 구현체만 교체). 앱명 `record` → `recorme`로 정합화. `flutter analyze` 무경고 + `flutter test` 17개 통과.

- **Task 005: 로그인·캘린더 화면 UI 구현 (더미)** ✅ - 완료
  - 구현 기능: F001, F002 (UI)
  - ✅ 디자인 토큰·공통 위젯 토대(테마/spacing/Empty·Error·Loading·ConfirmDialog·SnackBar), 더미 `DiaryRepository`+`FakeDiaryRepository`+Riverpod provider, 로그인 UI(recorme 브랜딩·카카오 말풍선/구글 멀티컬러 G 아이콘), 캘린더 UI(월 스와이프·작성일 dot·오늘 강조·날짜 탭 분기). `flutter analyze` 무경고.
  - 로그인 페이지: 카카오/구글 소셜 로그인 버튼, 에러 토스트 자리 (실제 SDK 호출은 Phase 3)
  - 메인 페이지: 월별 캘린더 위젯, 좌우 스와이프 월 이동, 작성된 날짜 dot 표시(더미 summary), 오늘 날짜 하이라이트
  - 날짜 탭 분기 로직(더미 기준: 일기 있음 → 상세, 없음 → 에디터)
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

백엔드 인증·일기 CRUD를 실제로 구현하고, 앱의 더미 데이터를 실제 API 호출로 교체한다. 모든 API/로직 Task는 구현 직후 스택 네이티브 테스트로 검증한다.

- **Task 007: 백엔드 Supabase JWT 검증 + 사용자 JIT 프로비저닝** - 우선순위
  - 구현 기능: F001, F010
  - 레거시 정리: 자체 `JwtProvider`/`JwtProperties`/`HashUtil`, `domain/auth/social/*`(SocialVerifier·Router·Provider·SocialUserInfo)와 관련 단위 테스트(JwtProviderTest·HashUtilTest) 제거
  - DB: `V1__init.sql`에서 `social_accounts`·`refresh_tokens` 제거, `users.supabase_uid`(UNIQUE) 추가(운영 DB 미배포라 V1 직접 수정)
  - `SupabaseJwtVerifier` + `SupabaseJwtFilter`: `Authorization: Bearer <Supabase access token>` 검증(JWT secret HS256 또는 JWKS), `sub`/`email` 클레임 추출. `SecurityConfig`/`SecurityUser` 재사용·수정, `JwtAuthenticationEntryPoint` 유지
  - `UserProvisioningService`: `supabase_uid`로 `users` 조회, 없으면 자동 가입(닉네임·이메일·프로필을 클레임/`user_metadata`로 세팅)
  - `application*.yml`: `record.jwt.*` 제거 → `supabase.url`/`supabase.jwt-secret`(환경변수) 추가
  - **(구현 직후 필수 테스트)** JUnit5 + Testcontainers — 유효 토큰 인증 통과, 위조 서명(401), 만료 토큰(401), 신규 사용자 JIT 가입, 기존 사용자 매핑(중복 가입 없음)

- **Task 008: 백엔드 일기 upsert CRUD + 캘린더 엔드포인트** - 우선순위
  - 구현 기능: F002, F003, F005, F006, F007
  - `POST /diaries`: `(user_id, written_date)` 부분 유니크 충돌 키 기반 upsert(`INSERT … ON CONFLICT DO UPDATE`) — 신규 201 / 갱신 200
  - `GET /diaries/me/summary?yearMonth=`: 해당 월 활성 기록 존재 날짜 목록(캘린더 dot용)
  - `GET /diaries/by-date/{date}`: 날짜 단건 조회, 없으면 404 `DIARY_NOT_FOUND`
  - `GET /diaries/{id}`: 단건 상세 조회
  - `PUT /diaries/{id}`: id 기반 명시적 수정
  - `DELETE /diaries/{id}`: 소프트 삭제(`deleted_at` 기록), 삭제 후 같은 날짜 재작성 허용
  - 본인 소유 검증(타인 일기 접근 403)
  - **(구현 직후 필수 테스트)** JUnit5 + Testcontainers — 정상 생성/조회/수정/삭제, 같은 날짜 재저장 시 UPDATE 동작(엣지), 소프트 삭제 후 같은 날짜 재INSERT 허용(엣지), 존재하지 않는 id/date(404), 타인 일기 접근(403), 잘못된 날짜·빈 content(유효성 400)

- **Task 009: 백엔드 일기 목록 커서 페이징**
  - 구현 기능: F004
  - `GET /diaries/me?cursor=&size=`: `id DESC` 정렬, OFFSET 미사용 커서 페이징, `{ items, nextCursor, hasNext }` 반환
  - 소프트 삭제(`deleted_at IS NOT NULL`) 행 제외
  - **(구현 직후 필수 테스트)** JUnit5 + Testcontainers — 첫 페이지(cursor 생략)/다음 페이지 연속 조회, 마지막 페이지 `hasNext=false`, 경계값(size=1, 빈 결과), 삭제된 일기 미노출(엣지)

- **Task 010: 앱 Supabase Auth 연동** - 우선순위
  - 구현 기능: F001, F010
  - ✅ (구현됨) Supabase 초기화, 구글(`signInWithIdToken`)·카카오(`signInWithOAuth`) 로그인, `onAuthStateChange` 기반 세션 감시, go_router 가드(Supabase 세션 기준), 로그인 UI, 소셜 OAuth 콘솔 설정(Google) + 앱 설정값(`supabase_config.dart`)
  - 잔여: `AuthInterceptor`를 **Supabase access token 첨부**로 정리(자체 401 refresh 골격 제거), 미사용 `TokenStorage`(자체 JWT용) 제거, 로그아웃 `supabase signOut` 경로 정리
  - 잔여: Kakao provider 콘솔 설정 마무리(`tasks/_SUPABASE_SETUP.md` 3번) + 안드로이드 실제 로그인 검증
  - **(구현 직후 필수 테스트)** `integration_test` E2E — 로그인 성공 → 메인 진입, 인증 실패 → 에러 토스트 유지, 세션 만료 시 SDK 자동 갱신 후 요청 성공, 로그아웃 후 보호 화면 접근 차단

- **Task 011: 앱 일기 기능 API 연동 (더미 교체)**
  - 구현 기능: F002, F003, F004, F005, F006, F007
  - 캘린더: `GET /diaries/me/summary`로 dot 렌더링, 날짜 탭 시 `GET /diaries/by-date/{date}` → 있으면 상세, 404면 신규 에디터로 분기
  - 에디터 저장: `POST /diaries`(날짜+내용 upsert, id 불필요), 상세 수정은 `PUT /diaries/{id}`
  - 목록: `GET /diaries/me` 커서 무한 스크롤 실연동
  - 상세: `GET /diaries/{id}`, 삭제: `DELETE /diaries/{id}` + 확인 다이얼로그 → 메인 복귀
  - 모든 더미 데이터 제거, 로딩/에러/빈 상태 처리
  - **(구현 직후 필수 테스트)** `integration_test` E2E — 캘린더 dot 표시, 신규 작성 → 캘린더 반영, 같은 날짜 재작성 시 수정 반영(엣지), 목록 스크롤 페이징, 상세 조회, 수정, 삭제 후 같은 날짜 재작성 허용(엣지), API 오류 시 에러 UI 노출

- **Task 011-1: 핵심 기능 통합 테스트**
  - 구현 기능: F001~F007, F010 전체 검증
  - `integration_test`로 전체 사용자 여정 E2E: 로그인 → 캘린더 → 작성 → 목록 → 상세 → 수정 → 삭제 → 로그아웃 (시나리오별 단계 명시)
  - 백엔드: `@SpringBootTest` + Testcontainers로 auth·diary 도메인 간 통합 시나리오 검증
  - 에러 핸들링 및 엣지 케이스: 중복 날짜 upsert, 소프트 삭제 후 재작성, 토큰 만료·갱신, 비인가/타인 일기 접근(401/403), 빈 데이터·경계값
  - 모든 시나리오 통과 확인 후 Phase 3 완료 처리 (테스트 통과 전 ✅ 표시 금지)

### Phase 4: MVP 이후 (개요)

> 아래 항목은 MVP 범위 밖이며, 상세 Task 분해는 추후 진행한다. 비동기 감정 분석은 트랜잭션 밖에서 `@Async`로 수행하고 실패 시 `NEUTRAL` 폴백한다는 아키텍처 원칙을 따른다.

- **Task 012: 감정 분석 (LLM) 개요**
  - 일기 저장 시 `analysis_status=PENDING` 즉시 반환 → `@Async`로 외부 LLM 분석 후 `DONE` 갱신, 실패 시 `NEUTRAL` 폴백, 내용 수정 시 재분석
  - 확장 포인트 인터페이스 격리: `EmotionAnalyzer` / `LlmClient`(provider 교체 가능)

- **Task 013: 감정 기반 테마 개요**
  - 감정 결과에 따른 배경(그라데이션 등)·필체(폰트)·텍스트 색상 동적 적용, 앱에서 테마 동적 렌더링

- **Task 014: 감정 기반 음악 개요**
  - 감정에 매핑된 음악 재생. 음악 소스 미정 흡수를 위한 `MusicSource` + `tracks.source_type` 추상화

- **Task 015: 공유·피드·친구·공감 개요**
  - 공유: visibility(PRIVATE/FRIENDS/PUBLIC) + `share_token` 공유 링크 단건 조회
  - 피드: 본인 + PUBLIC + FRIENDS 기록 커서 페이징(`GET /feed`)
  - 친구: 요청/수락/거절/목록/삭제(`/friends/*`)
  - 공감(리액션): 1인 1회 추가/취소(`/diaries/{id}/reactions`). 댓글은 범위 외

- **Task 016: 성능 최적화 및 배포 개요**
  - 캘린더 summary 캐싱, 커서 페이징 인덱스 튜닝
  - CI/CD 파이프라인(앱 빌드·백엔드 테스트), 모니터링·로깅 구성
  - 애플 로그인(Supabase Apple provider) 확장

## 상태 범례

- **Phase 제목 + ✅**: 완료된 Phase
- **Task + ✅ - 완료**: 완료된 작업 (`See: /tasks/XXX-xxx.md` 참조 추가, 테스트 통과 확인 후에만)
- **Task + - 우선순위**: 즉시 시작해야 할 작업
- **구현 사항 ✅**: 완료된 세부 항목 / **-**: 미완료 세부 항목
- **완료(✅) 전제 조건**: 해당 Task의 "## 테스트 체크리스트"가 모두 통과해야 하며, 테스트 미수행·실패 Task는 절대 완료로 표시하지 않는다
