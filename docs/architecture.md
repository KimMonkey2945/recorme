# record 아키텍처 개요

> 모바일 일기/감정 기록 앱 `record`의 전체 시스템 아키텍처 문서.
> 소규모/개인~소수 팀 규모를 전제로, 과도한 엔지니어링은 배제하고 확장 포인트는 인터페이스로 격리한다.

## 1. 프로젝트 개요

`record`는 매일의 하루를 글로 기록하고, 나와 다른 사람의 하루를 서로 공유하는 모바일 앱이다.
단순 일기를 넘어 작성한 글의 **감정을 분석**하여 그날 기분에 어울리는 **테마(배경·필체)**와 **음악**을
자동으로 입혀, 다시 볼 때 그날의 분위기를 그대로 느끼게 한다.

### 핵심 기능
1. 📝 **하루 기록** — 그날의 하루를 글로 자유롭게 기록 (하루 1개, 수정 가능)
2. 🎨 **감정 기반 테마** — 글을 분석해 기분에 맞는 배경·필체를 자동 적용, 조회 시 반영
3. 🎵 **감정 기반 음악** — 분석된 기분에 어울리는 음악을 자동 설정해 함께 감상
4. 🤝 **하루 공유** — 나와 다른 사람의 하루를 서로 공유 (친구 + 공감 리액션)

## 2. 기술 스택

| 구분 | 기술 |
|---|---|
| 모바일 | Dart, Flutter (Feature-first, Riverpod, Dio) |
| 백엔드 | Java 21, Spring Boot 3.x |
| 데이터 접근 | MyBatis (동적 SQL, 매퍼 XML) |
| 데이터베이스 | PostgreSQL (Flyway 스키마 관리) |
| 감정 분석 | 외부 LLM API (추상화 인터페이스) |
| 인증 | 소셜 로그인(카카오/구글, 애플은 추후) + 자체 JWT |

## 3. 확정된 핵심 결정사항

| 항목 | 결정 | 근거 |
|---|---|---|
| 저장소 구조 | **모노레포** (`app/` + `backend/`) | 1인~소수 팀, 프론트-백 동시 변경 잦음 → 단일 PR 관리 |
| 감정 분석 | **외부 LLM API + 비동기** | 빠른 구현·높은 정확도, 저장 UX·장애 격리 |
| 인증 | **소셜 로그인(카카오·구글) → 자체 JWT** | 모바일 가입 진입장벽 최소화. 애플은 추후 확장 |
| 음악 소스 | **미정 → 인터페이스 추상화** | 자체 음원/외부 API 어느 쪽도 흡수 |
| 하루 기록 수 | **하루 1개 + 수정 가능** | "오늘의 일기" 컨셉, 재작성은 UPDATE |
| 소셜 상호작용 | **공감(리액션)만** | 댓글의 알림/신고/모더레이션 복잡도 회피 |
| 패키지 베이스 | `com.recordapp` | Java `record` 키워드 혼동 회피 |

## 4. 모노레포 레이아웃

```
record/
├─ app/                     # Flutter (기존 루트 파일 이동 대상)
│  ├─ lib/  android/  ios/  test/
│  ├─ pubspec.yaml
│  └─ analysis_options.yaml
├─ backend/                 # Spring Boot (신규)
│  ├─ src/main/java/com/recordapp/...
│  ├─ src/main/resources/   (application.yml, mapper/, db/migration/)
│  ├─ build.gradle
│  └─ settings.gradle
├─ docs/                    # 설계 문서 (본 문서 포함)
├─ .gitignore               # Flutter + Gradle 규칙 병합
└─ README.md
```

### 마이그레이션 가이드 (향후 실행)
> 본 문서 작성 시점에는 실제 이동을 수행하지 않는다. 아래는 후속 스캐폴딩 단계의 절차다.

1. `git mv`로 Flutter 산출물 이동(히스토리 보존): `lib/ android/ ios/ web/ test/ pubspec.yaml pubspec.lock analysis_options.yaml .metadata` → `app/`
2. `.dart_tool/`, `.idea/`는 이동하지 않고 재생성(빌드 캐시·IDE 메타).
3. 루트 `.gitignore`에 Flutter(`app/`)·Gradle(`backend/`) 규칙 병합.
4. `backend/`는 Spring Initializr로 신규 생성(Gradle, Java 21, Spring Boot 3.x).
5. CI는 경로 필터(`app/**`, `backend/**`)로 분리 트리거.

## 5. 계층/통신 흐름

```
┌─────────────┐   소셜 SDK 로그인        ┌──────────────────────────┐
│  Flutter    │ ───────────────────────▶ │  Spring Boot (백엔드)     │
│  (app/)     │   JWT (Bearer)           │                          │
│             │ ◀─────────────────────── │  Controller              │
│  Riverpod   │   ApiResponse<T>         │   → Service(@Transactional)│
│  + Dio      │                          │     → Mapper(MyBatis)     │
└─────────────┘                          │       → PostgreSQL        │
                                         │                          │
                                         │  Service ─@Async─▶ LLM API│
                                         │  (감정분석, 트랜잭션 밖)   │
                                         └──────────────────────────┘
```

- 동기 경로: 앱 요청 → Controller → Service → Mapper → DB → 표준 응답.
- 비동기 경로: 일기 저장/수정 → `PENDING` 즉시 응답 → `@Async`로 LLM 감정 분석 → 테마/음악 매핑 → `DONE` 갱신.

## 6. 주요 트레이드오프

1. **BIGINT PK + 외부 UUID** — 내부 조인/인덱스는 BIGINT로 효율, 외부 노출(회원·공유)은 UUID로 enumeration 방지. 전면 UUID 대비 인덱스 비대화 회피.
2. **도메인 기반 패키징** — 기능 경계가 뚜렷(auth/diary/emotion/social)해 응집·확장에 유리. 레이어 기반은 도메인 수가 적을 때만 유리.
3. **감정 분석 비동기** — 저장 즉시 응답 + LLM 장애 격리. 대신 `PENDING` 상태 관리·클라 폴링 필요.
4. **LLM/음악 인터페이스 추상화** — provider·음악 소스 교체 비용 최소화.
5. **Riverpod** — `AsyncValue`가 API 비동기와 자연 정합, 소규모 적정 보일러플레이트. Bloc은 단순 CRUD엔 과투자.
6. **외부 큐/서킷브레이커 초기 미도입** — 과도한 엔지니어링 회피. 트래픽 증가 시 SQS/Kafka·Resilience4j 도입.

## 7. 리스크 / 병목

- **LLM 비용·레이턴시·출력 불안정**: 구조화 JSON 출력 강제·검증·폴백(`NEUTRAL`) 필수.
- **애플 로그인(추후 확장 시)**: JWKS 서명 검증·클라이언트 시크릿(`.p8` ES256 JWT, ~6개월 회전)·Android 웹 OAuth redirect 처리 복잡 → 현재 범위에서 제외하고 카카오·구글 2종으로 시작.
- **에셋 라이선스**: 손글씨 폰트 임베딩 라이선스/용량, 외부 음악 전환 시 저작권·약관.
- **피드 가시성 서브쿼리**: friendships 인덱스로 완화, 규모 확대 시 친구 목록 캐시.

## 8. 관련 문서
- 제품 요구사항(MVP) → [`PRD.md`](./PRD.md)
- 개발 로드맵(Phase·Task) → [`ROADMAP.md`](./ROADMAP.md)
- 데이터베이스 설계 / 전체 DDL → [`database.md`](./database.md)
- 백엔드 구조 → [`backend.md`](./backend.md)
- 모바일 구조 → [`mobile.md`](./mobile.md)
- API 계약 → [`api-contract.md`](./api-contract.md)

## 9. 구현 로드맵 (후속, 단계별 별도 승인)

> 아래는 큰 줄기 요약이다. **Phase·Task 단위 상세 로드맵은 [`ROADMAP.md`](./ROADMAP.md)를 기준**으로 한다.

1. 모노레포 이전(`git mv`) + backend 스캐폴드 + Flyway `V1__init.sql`.
2. 인증(소셜: 카카오 → 구글 순, 2종 범위) + JWT 골격. **애플은 추후 확장**(Android 웹 OAuth·client_secret 회전 비용으로 현재 범위 제외).
3. 일기 CRUD(하루 1개·수정) + 비동기 감정 분석(폴백) + 테마/음악 매핑.
4. 피드/친구 + 공유 + 공감 리액션.
5. 앱: Dio/Riverpod/go_router 골격 → 기능 순차 구현.
