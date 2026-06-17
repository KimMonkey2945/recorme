# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 언어 및 커뮤니케이션 규칙

- **기본 응답 언어**: 한국어
- **코드 주석**: 한국어로 작성
- **커밋 메시지**: 한국어로 작성
- **문서화**: 한국어로 작성
- **변수명/함수명**: 영어 (코드 표준 준수)

## 프로젝트 개요

`record`는 하루를 글로 기록하고 다른 사람과 공유하는 모바일 앱이다. 작성한 글의 **감정을 외부 LLM으로 분석**하여, 기분에 맞는 **테마(배경·필체)**와 **음악**을 자동으로 입히는 것이 핵심이다.

**모노레포** 구조로, 단일 저장소에서 모바일 앱(`app/`)과 백엔드(`backend/`)를 함께 관리한다.

| 구분 | 스택 |
|---|---|
| 모바일 | Dart, Flutter (Feature-first, Riverpod, Dio) |
| 백엔드 | Java 21, Spring Boot 3.x, MyBatis |
| DB | PostgreSQL (Flyway) |
| 감정 분석 | 외부 LLM API (추상화) |
| 인증 | 소셜 로그인(카카오/구글/애플) + 자체 JWT |

## 현재 상태 (중요)

이 저장소는 **설계 + 골격 단계**다. 작업 전 이 점을 반드시 인지할 것:

- `backend/`는 **빌드 설정(`build.gradle`)과 Java 코드가 아직 없다.** 도메인 기반 패키지 디렉터리만 `.gitkeep`으로 잡혀 있다. Spring Initializr 스캐폴딩은 후속 작업이다.
- `app/`은 **Flutter 기본 카운터 앱 스캐폴드** 상태다(`app/lib/main.dart`). Feature-first 폴더 골격(`core/`, `features/`, `shared/`)만 `.gitkeep`으로 생성되어 있고 실제 코드는 없다.
- 전체 설계는 코드보다 **`docs/`가 단일 진실 공급원(source of truth)**이다. 구현 시 항상 `docs/`를 기준으로 삼는다.
- 구현은 단계별로 진행한다. 한 번에 전체를 구현하지 말고, 설계 문서의 로드맵 순서를 따른다.

## 설계 문서 (구현의 기준)

| 문서 | 내용 |
|---|---|
| `docs/PRD.md` | MVP 제품 요구사항(사용자 여정, 기능 명세 F001~, 페이지·데이터 모델·기술 스택) |
| `docs/ROADMAP.md` | 개발 로드맵(Phase·Task 분해, 기능 ID 추적, 스택 네이티브 테스트 원칙) |
| `docs/architecture.md` | 전체 아키텍처, 확정 결정사항, 트레이드오프, 구현 로드맵 |
| `docs/database.md` | PostgreSQL ERD + 전체 DDL (Flyway `V1__init.sql`의 원본) |
| `docs/backend.md` | 패키지 구조, 계층, 표준 응답, MyBatis 매퍼 예시, JWT/LLM 설계 |
| `docs/mobile.md` | Feature-first 구조, Riverpod, Dio 통신, 테마 동적 적용 |
| `docs/api-contract.md` | REST API 계약 (`/api/v1`), 표준 응답·커서 페이징 |

## 핵심 아키텍처 결정 (반드시 준수)

- **패키지 베이스는 `com.recordapp`** — Java `record` 키워드 혼동 회피.
- **백엔드 계층**: Controller → Service(`@Transactional`) → Mapper(MyBatis) → DB. **외부 LLM 호출은 트랜잭션 밖**에서 비동기로 수행.
- **감정 분석은 비동기**: 일기 저장/수정은 동기로 `analysis_status=PENDING` 즉시 반환 → `@Async`로 LLM 분석·테마/음악 매핑 후 `DONE` 갱신. 실패 시 `NEUTRAL` 폴백. 내용 수정 시 재분석.
- **하루 1기록 + 수정**: 사용자·날짜당 일기 1개(`uq_diary_user_day` 부분 유니크). 같은 날짜 재작성은 INSERT가 아닌 **UPDATE**.
- **PK 전략**: 내부 PK는 `BIGINT IDENTITY`, 외부 노출(회원/공유)은 별도 `UUID`(`users.uuid`, `diaries.share_token`).
- **확장 포인트는 인터페이스로 격리**: `EmotionAnalyzer`/`LlmClient`(LLM provider 교체), `MusicSource` + `tracks.source_type`(음악 소스 미정 흡수), `SocialVerifier`(소셜 provider별 검증).
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

### 백엔드 (Spring Boot)
> 아직 스캐폴딩 전이라 빌드 명령은 동작하지 않는다. Spring Initializr(Gradle, Java 21, Spring Boot 3.x)로 생성 후 사용 예정:
```bash
cd backend
./gradlew bootRun               # 애플리케이션 실행
./gradlew test                  # 전체 테스트
./gradlew test --tests "com.recordapp.<클래스명>"   # 단일 테스트
```

## 주의사항

- Flutter 작업은 IDE에서 **`app/`를 프로젝트 루트로 열어야** 정상 인식된다(모노레포 이전 결과).
- 빈 패키지의 `.gitkeep`은 실제 클래스/파일 추가 시 삭제한다.
- LLM API 키, JWT 시크릿, DB 비밀번호는 환경변수/시크릿으로 주입한다(코드·git 금지). 루트 `.gitignore`에 `*.env`, `application-secret.yml` 등이 제외되어 있다.
