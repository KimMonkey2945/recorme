# record 아키텍처 개요

> 모바일 기록·감정 분석 앱 `record`의 전체 시스템 아키텍처 문서.
> 소규모/개인~소수 팀 규모를 전제로, 과도한 엔지니어링은 배제하고 확장 포인트는 인터페이스로 격리한다.

## 1. 프로젝트 개요

`record`는 매일의 하루를 글로 기록하고, 나와 다른 사람의 하루를 서로 공유하는 모바일 앱이다.
단순 기록을 넘어 작성한 글의 **감정을 분석**하여 그날 기분에 어울리는 **테마(배경·필체)**와 **음악**을
자동으로 입혀, 다시 볼 때 그날의 분위기를 그대로 느끼게 한다.

### 핵심 기능
1. 📝 **하루 기록** — 그날의 하루를 글로 자유롭게 기록 (하루 1개, 확정 전까지 수정 가능)
2. 🐵 **내 캐릭터** — 기록을 확정하면 **내 캐릭터가 반응**하고, 쌓일수록 레벨·코인·미션으로 **꾸며진다**(원숭이 / 레서판다 2종). 캐릭터 홈이 앱의 메인이며 연출의 주인공이다 *(Phase 7 진행 중 — 현재 캐릭터 선택·옷장(착용 UI·오버레이 렌더 포함)·미션 조회까지 구현, 보상·홈은 미구현. §3.3)*
3. 🎨 **감정 메타데이터** — 감정은 **사용자가 직접 입력**(프리셋 6종 또는 자유 텍스트)하며, 달력 점 색·감정 칩·회고 통계에만 쓰인다 *(⏳ 계획 — **현재는 LLM 자동 분석이 그대로 동작 중**이다. §3·§3.3 참조)*
4. 🎵 **감정 기반 음악** — 분석된 기분에 어울리는 음악을 자동 설정해 함께 감상 *(MVP 이후)*
5. 🤝 **하루 공유** — 나와 다른 사람의 하루를 서로 공유 (친구 + 공감 리액션)

## 2. 기술 스택

| 구분 | 기술 |
|---|---|
| 모바일 | Dart, Flutter (Feature-first, Riverpod, Dio) |
| 백엔드 | Java 21, Spring Boot 3.x |
| 데이터 접근 | MyBatis (동적 SQL, 매퍼 XML) |
| 데이터베이스 | **별도 PostgreSQL**(Supabase와 무관, Flyway 스키마 관리, 기능별 마이그레이션 분할). 로컬: 네이티브 PostgreSQL 18, 배포: Docker/관리형 |
| 감정 분석 | 외부 LLM API (추상화 인터페이스) |
| 인증 | Supabase **Auth 전용**(이메일 + 소셜: 카카오/구글, 애플은 추후) + 백엔드 Supabase JWT 검증. 데이터 저장에는 Supabase 미사용 |

## 3. 확정된 핵심 결정사항

| 항목 | 결정 | 근거 |
|---|---|---|
| 저장소 구조 | **모노레포** (`app/` + `backend/`) | 1인~소수 팀, 프론트-백 동시 변경 잦음 → 단일 PR 관리 |
| ~~감정 분석~~ | ~~**외부 LLM API + 비동기**~~ | ~~빠른 구현·높은 정확도, 저장 UX·장애 격리~~ → **Phase 7에서 번복**(아래 행) |
| 감정 분석 (개정) ⏳ **미착수** | **LLM 자동 분석 비활성화**(`record.analysis.enabled=false`, `@ConditionalOnProperty`로 빈 미등록). **감정은 사용자 직접 입력**(프리셋 6종 / 자유 텍스트 ≤20자). **감정은 순수 기록 메타데이터** — 캐릭터 리액션·미션 판정·해금 어디에도 쓰지 않는다 | ① 제품 중심축을 "AI가 분석해준다"에서 **"내 캐릭터에 애착이 생긴다"**로 전환 — 리텐션 동력이 분석 정확도가 아니라 캐릭터 성장이라고 판단 ② **LLM 호출 비용·레이턴시·출력 불안정**을 0으로 제거 ③ 확정 즉시 `DONE` → **리액션 지연 0**(PENDING 대기·클라 폴링 소멸) ④ 감정을 캐릭터에서 분리해야 리액션 대사가 **맥락**(확정/연속/미션) 기반으로 단순해짐(레벨업 맥락은 경험치/레벨 폐기로 미사용). **코드·테이블은 보존**하여 `ANALYSIS_ENABLED=true` 한 줄로 복구 가능(되돌릴 수 있는 번복)<br>⚠️ **결정만 됐고 코드는 그대로다** — `record.analysis.enabled` 플래그는 **아직 존재하지 않으며 LLM 분석이 활성**이다(Task 024/025) |
| 캐릭터 렌더 | **Rive 비트맵 리깅** (원본 PNG 파츠를 본에 바인딩, 벡터 재작화 없음) + Data Binding 이미지 슬롯 런타임 주입 | 후보 비교는 아래 "캐릭터 렌더 방식 비교" 참조.<br>⏳ **`.riv` 미제작(Task 031)** — 현재는 `IdleCharacterView`(PNG **메시 워프**)가 렌더한다. `rive` 패키지는 재생할 `.riv`가 생길 때 추가한다 |
| 아이템 모델 | **group(소유·착용) ↔ variant(렌더)** 2단 구조 | 원숭이·레서판다는 **체형이 달라 옷 PNG를 캐릭터별로 따로** 그려야 한다. 사용자에게는 group("빨간 후드티")만 노출하고 렌더 시점에만 `(group + 내 캐릭터)`로 variant를 해석 → **캐릭터를 바꿔도 옷장이 그대로 따라온다** |
| 보상 멱등 ⏳ **미구현** | **단일 관문 `character_events(user_id, event_key) UNIQUE`** | 코인 적립·미션 달성·해금·구매가 전부 이 게이트를 통과 → 이벤트 재전달·백스톱 폴러 중복에도 **중복 적립 불가**. 게이트 1행 삽입 성공이 모든 부작용의 유일한 진입 조건.<br>**테이블(V17)은 있고 보상 엔진 코드는 없다**(Task 028) |
| 도메인 결합 ⏳ **미구현** | **`ApplicationEventPublisher` + `@TransactionalEventListener(AFTER_COMMIT)` + `@Async`** | diary/resolution은 character를 **모른다**(단방향). 보상 로직이 터져도 기록 저장이 롤백되지 않는다. 대가(커밋 후 유실)는 백스톱 폴러로 보정 → 상세는 [`backend.md`](./backend.md) §2-1.<br>**`global/event/`·리스너·`characterExecutor` 모두 Task 028에서 추가**된다 |
| 아이템 소유 ✅ **구현** | 소유·착용은 **group_code로만** 저장, 렌더 이미지는 **선택 캐릭터로 해석** | 캐릭터를 바꿔도 `user_equipment`를 손대지 않고 variant만 재해석 → **옷장이 캐릭터를 따라온다**. 해석은 SQL 조인(`DISTINCT ON` + `NULLS LAST`)과 `CatalogCache` 메모리 두 경로 → [`backend.md`](./backend.md) §8 |
| 인증 | **Supabase Auth(이메일 + 소셜: 카카오·구글) → 백엔드 Supabase JWT 검증** | 자체 소셜 검증·JWT 발급/회전 구현 부담 제거(Supabase 위임). 이메일·소셜 모두 동일 토큰이라 백엔드 분기 없음. 트레이드오프: Auth만 Supabase 종속(데이터는 무관). 애플은 추후 확장 |
| 데이터 저장소 | **별도 PostgreSQL(Supabase 미사용)** | 인증만 Supabase, 데이터는 별도 PG로 분리해 DB 통제권 확보·종속을 Auth로 한정. 대가: 배포 DB 운영(백업·리전·패치) 직접 부담. 인증↔데이터는 `users.supabase_uid` 컬럼 매핑으로 연결(FK·RLS·트리거 미사용) |
| 음악 소스 | **미정 → 인터페이스 추상화** | 자체 음원/외부 API 어느 쪽도 흡수 |
| 하루 기록 수 | **하루 1개 + draft→확정 라이프사이클** | "오늘의 기록" 컨셉, 재작성은 UPDATE. DRAFT(미확정)만 수정 가능, '오늘을 기억하기'로 확정 후 수정 불가(삭제는 허용 → 재작성). 감정 분석은 확정 시 1회 |
| 소셜 상호작용 | **공감(리액션)만** | 댓글의 알림/신고/모더레이션 복잡도 회피 |
| 패키지 베이스 | `com.recordapp` | Java `record` 키워드 혼동 회피 |

### 3.1 캐릭터 렌더 방식 비교 (5개 후보 → Rive 비트맵 리깅)

확보된 에셋이 **"3D 렌더처럼 보이는 2D 정면 PNG 2장"**이라는 사실이 방식을 결정했다.

| 후보 | 판정 | 근거 |
|---|---|---|
| 실시간 3D | ❌ 탈락 | `flutter_scene`은 **early preview + master 채널 필수**(프로덕션 불가). `model_viewer_plus`·`flutter_3d_controller`는 전부 **WebView에 `<model-viewer>`를 얹는 방식** → 홈에 상시 렌더하기엔 메모리·배터리·첫 프레임 지연이 모두 나쁘다. 결정적으로 **캐릭터를 돌려볼 필요가 없어 3D 엔진 자체가 불필요**하다 — 3D 룩은 이미 원본 이미지 안에 있다 |
| Spine | ❌ 탈락 | 후보 중 **유일한 유료**($99~). 파츠 컷아웃 노동이 가장 크고, 서버에서 아이템을 런타임 추가하기가 Rive보다 어렵다 |
| Rive 벡터 재작화 | ❌ 탈락 | AI는 **래스터 이미지만** 준다. 벡터로 다시 그리는 리깅 노동이 1인 개발의 병목이 된다 |
| 정적 PNG | △ 폴백용 | 연출 부재. 단, 에셋 제작 전 개발·테스트용 폴백으로 채택 → **실제로는 `IdleCharacterView`(PNG 메시 워프)로 구현**했다(아래) |
| **PNG 메시 워프** (현행) | ✅ **잠정 채택** | Rive 공식 문서상 **`.riv` 아트보드 없이는 PNG를 애니메이션할 수 없다**. 그래서 **Rive가 하는 일(메시 변형)을 Flutter로 직접** 구현했다 — PNG를 12×16 격자 메시로 쪼개 `drawVertices` + `ImageShader`로 정점마다 변형(발 고정 스웨이·숨쉬기 스쿼시&스트레치·머리 두리번). **`.riv` 없이도 캐릭터가 살아 움직인다** → 에셋 제작이 크리티컬 패스에서 빠진다. Task 031에서 `CharacterStage` 스위치로 Rive와 교체 → [`mobile.md`](./mobile.md) §7-2 |
| **Rive 비트맵 리깅** | ✅ **채택** | 원본 PNG를 파츠(머리/몸/팔/눈/꼬리)로 잘라 **비트맵 그대로** 아트보드에 넣고 본에 바인딩 → **재작화 없음**. 캐릭터가 2종뿐이라 리깅 부담을 감당할 수 있다. **MIT·무료**. State Machine으로 idle(숨쉬기·눈 깜빡임·두리번거림)·react·celebrate 구현. 의상/소품은 **Data Binding `image` 프로퍼티에 런타임 주입**(`.riv`에 굽지 않음) → **아이템 추가에 앱 재배포 불필요** |

### 3.2 확장 포인트 (인터페이스 격리)

| 인터페이스 | 격리 대상 | 비고 |
|---|---|---|
| `EmotionAnalyzer` / `LlmClient` | LLM provider 교체(Gemini·Claude·Ollama·Stub) | ✅ **현재 활성**(기본 Gemini, 무키 시 Stub 폴백). 비활성화는 Task 024 예정 |
| `PushService` | FCM ↔ Stub 폴백 | 무키 시 `StubPushService` |
| `StorageService` | 로컬 디스크 → S3 | **캐릭터 아이템 PNG 서빙(`/files/items/`)에 그대로 재사용** — 신규 인프라 없음 |
| `CharacterStage` (앱) | **렌더러 배선** | 렌더러는 `IdleCharacterView`(통짜 PNG 12×16 메시 워프) 하나다. **Rive·파츠 조립을 둘 다 시도했다가 되돌렸다**(Task 031 — 파츠가 서로 맞지 않아 캐릭터가 조각나 보였다). 외부 의존성 0 → 웹 포함 전 플랫폼 동일 동작 |
| `CatalogCache` (백엔드) | 캐릭터·아이템·미션 **마스터 캐시** | 마이그레이션으로만 바뀌는 마스터라 요청마다 SQL을 태우지 않는다. 불변 스냅샷을 volatile 참조로 통째 교체(읽기 무락) |
| `MusicSource` + `tracks.source_type` | 음악 소스 미정 흡수 | **MVP 이후** |

### 3.3 Phase 7 구현 현황 (캐릭터 도메인)

> ⚠️ **위 §3의 결정 중 일부는 "결정만 됐고 코드는 아직 없다".** 문서를 읽고 구현에 들어가기 전에 이 표를 먼저 볼 것.

| 항목 | 상태 | 비고 |
|---|---|---|
| DB 스키마(캐릭터·미션·사용자 상태) | ✅ | Flyway `V15`~`V17` |
| 백엔드 `domain.character` — 조회·선택·착용·미션 조회 | ✅ | `CharacterController`·`WardrobeController`·`MissionController` (→ [`backend.md`](./backend.md) §8) |
| group ↔ variant 2단 해석 + `CatalogCache` | ✅ | SQL 조인 + 메모리 두 경로 |
| 기본 상태 JIT(`ensureState`) + DEFAULT 아이템 지급 | ✅ | `ON CONFLICT DO NOTHING` 멱등 |
| 앱 — 캐릭터 선택 온보딩 + 라우터 가드 | ✅ | `/onboarding/character` (셸 밖 풀스크린) |
| 앱 — `IdleCharacterView`(PNG 메시 워프 렌더러) | ✅ | `.riv` 대체재 (→ [`mobile.md`](./mobile.md) §7-2) |
| 앱 — 착용 아이템 오버레이 렌더 | ✅ | 착용형은 캐릭터와 **동일 프레임 풀프레임 PNG를 같은 메시 워프에 z순으로 겹침**(`IdleCharacterView.overlayAssetPaths`), BACKGROUND/ROOM_PROP은 `CharacterStage` 정적 배치. `assets/items/*`는 현재 **플레이스홀더**(도형) — 인페인팅 제작 에셋으로 교체 예정 |
| 앱 — 옷장 UI(`/wardrobe`) | ✅ | slot 탭 + 3상태 타일 + 로컬 미리보기 → 저장 시 배치 커밋. 진입점은 캐릭터 홈(Task 029) 전까지 **프로필의 임시 버튼** |
| **감정 LLM 분석 비활성화 + 수동 입력 전환** | ⏳ **미착수** | Task 024(백엔드)·025(앱). **지금은 LLM 분석이 활성**이다 |
| **보상 엔진**(코인·구매·미션 판정·보상함·리액션) | ⏳ **미구현** | Task 028. `character_events` 테이블만 존재 |
| **탭 재편 + 캐릭터 홈·미션 UI** | ⏳ **미구현** | Task 029 본편·030 잔여(구매·미션·보상함은 Task 028 선행 필요). ⚠️ 별도 상점 화면은 보상 재설계로 폐기 → 구매는 옷장 통합. FCM 딥링크 회귀 위험으로 분리 |
| **Rive `.riv` 아트보드 전환** | ⏳ **미제작** | Task 031. `rive` 패키지 미도입 |

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
┌─────────────┐                          ┌──────────────────────────┐
│  Flutter    │  ── 소셜 로그인 ──▶  Supabase Auth  ──▶ 세션(JWT)    │
│  (app/)     │                          │                          │
│  Riverpod   │   Supabase access JWT    │  Spring Boot (백엔드)     │
│  + Dio      │ ───(Bearer)────────────▶ │  SupabaseJwtFilter 검증   │
│             │ ◀─────────────────────── │   → JIT 프로비저닝(users) │
│             │   ApiResponse<T>         │   → Controller            │
└─────────────┘                          │     → Service(@Transactional)│
                                         │       → Mapper(MyBatis)   │
                                         │         → PostgreSQL      │
                                         │   (별도 PG, Supabase 아님) │
                                         │  Service ─@Async─▶ LLM API│
                                         │  (감정분석, 트랜잭션 밖)   │
                                         └──────────────────────────┘
```

- 인증 경로: 앱이 **Supabase SDK로 이메일/소셜 로그인**(이메일 `signUp`(닉네임→`user_metadata`)·`signInWithPassword` 확인 메일 필수 / 구글 `signInWithIdToken` / 카카오 `signInWithOAuth`) → Supabase 세션(access JWT + refresh, SDK가 저장·자동 갱신). 앱은 백엔드 호출 시 `Authorization: Bearer <Supabase access token>` 첨부 → 백엔드 `SupabaseJwtFilter`가 JWKS(ES256 비대칭 공개키)로 서명/만료/aud 검증 후 `sub`(uuid)로 `users` JIT 프로비저닝. 자체 JWT 발급·refresh 회전 없음.
- 동기 경로: 앱 요청 → Controller → Service → Mapper → DB → 표준 응답.
- 비동기 경로: 기록 '등록' → `DRAFT`(미분석·수정가능) 저장 → '오늘을 기억하기'로 **확정** → `PENDING` 즉시 응답 → `@Async`로 LLM 감정 분석(확정 시 1회) → 테마/음악 매핑 → `DONE` 갱신. 확정 기록은 수정 불가(재upsert·PUT 모두 409), 삭제만 허용.

## 6. 주요 트레이드오프

1. **BIGINT PK + 외부 UUID** — 내부 조인/인덱스는 BIGINT로 효율, 외부 노출(회원·공유)은 UUID로 enumeration 방지. 전면 UUID 대비 인덱스 비대화 회피.
2. **도메인 기반 패키징** — 기능 경계가 뚜렷(auth/diary/emotion/social)해 응집·확장에 유리. 레이어 기반은 도메인 수가 적을 때만 유리.
3. **감정 분석 비동기** — 저장 즉시 응답 + LLM 장애 격리. 대신 `PENDING` 상태 관리·클라 폴링 필요.
4. **LLM/음악/스토리지 인터페이스 추상화** — provider·음악 소스·파일 저장소(로컬 디스크 → S3) 교체 비용 최소화. 프로필 이미지는 백엔드 파일 업로드 방식(`StorageService`)으로 처리하고 DB에는 경로만 저장한다(Supabase Storage 미사용 — Auth 전용 원칙 유지).
5. **Riverpod** — `AsyncValue`가 API 비동기와 자연 정합, 소규모 적정 보일러플레이트. Bloc은 단순 CRUD엔 과투자.
6. **외부 큐/서킷브레이커 초기 미도입** — 과도한 엔지니어링 회피. 트래픽 증가 시 SQS/Kafka·Resilience4j 도입.

## 7. 리스크 / 병목

- **캐릭터 추가 = 옷 에셋 곱셈**: 아이템은 캐릭터별 PNG(variant)라, **3번째 캐릭터를 추가하면 기존 모든 옷의 variant를 새로 그려야 한다**(셔츠 1종 = PNG N장). 캐릭터 추가는 아이템 수가 적을 때 신중히. 2종으로 시작하는 이유가 이것이다.
- **에셋 제작 노동(파츠 분리·인페인팅·리깅)**: 맨몸 베이스 생성 → 파츠 분리(가려진 부분 인페인팅) → Rive 아트보드 조립·본 바인딩은 수작업 병목. → 로드맵 **최후방(Task 031)**으로 배치하고 `IdleCharacterView`(PNG 메시 워프)로 크리티컬 패스에서 제거했다. 먼저 **캐릭터 1종 + 아이템 2개로 전 구간(DB→API→상점→착용→렌더)을 관통**시킨 뒤 나머지를 채운다.
- ~~**캐릭터 PNG 배경 불투명**~~ **해소됨**: Task 031에서 `assets/characters/*.png`를 고해상도 **투명 배경 PNG**로 교체했고, 그 위에 아이템 오버레이(옷장)까지 구현됐다. 단 **아이템 에셋은 현재 코드 생성 플레이스홀더**라, 인페인팅(캐릭터 원본 위에 아이템을 입혀 생성 → diff로 아이템만 추출) 방식의 실제 에셋 제작이 남아 있다.
- **APK 용량 증가**: `rive_native` 바이너리(네이티브 FFI)가 앱 크기를 키운다. → **아직 `rive`를 pubspec에 넣지 않았다**(재생할 `.riv`가 없어 빌드 리스크만 커지므로). Task 031에서 증가분을 실측·기록한다.
- **웹 미지원**: `rive_native`의 wasm 이슈 가능 → `kIsWeb`이면 무조건 비-Rive 경로로 폴백한다. 웹이 상시 개발·확인 경로라 이 폴백은 계속 유지한다.
- **보상 멱등성(최대 리스크)** ⏳ **미구현**: `AFTER_COMMIT` 리스너는 커밋 후 크래시 시 이벤트가 유실될 수 있다 → `character_events` 게이트 + `CharacterRewardBackfillPoller` 백스톱으로 보정한다. **Task 028에서 구현하며, 이 도메인 최대 리스크 지점이다.**
- **LLM 비용·레이턴시·출력 불안정** *(현재도 유효)*: 구조화 JSON 출력 강제·검증·폴백(`NEUTRAL`)으로 완화 중. **감정 분석은 아직 비활성화되지 않았다** — Task 024로 끄면 해소되고, 되살리면 다시 유효해진다.
- **애플 로그인(추후 확장 시)**: JWKS 서명 검증·클라이언트 시크릿(`.p8` ES256 JWT, ~6개월 회전)·Android 웹 OAuth redirect 처리 복잡 → 현재 범위에서 제외하고 카카오·구글 2종으로 시작.
- **에셋 라이선스**: 손글씨 폰트 임베딩 라이선스/용량, 외부 음악 전환 시 저작권·약관.
- **업로드 파일 영속성**: 프로필 이미지는 로컬 디스크에 저장하므로 컨테이너 재배포(ephemeral) 시 유실된다. MVP는 단일 인스턴스 전제이며, 운영 진입 전 `S3StorageService` 교체 또는 영속 볼륨 마운트를 결정해야 한다(인터페이스 격리로 구현체만 교체).
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
2. 인증: **Supabase Auth**(이메일 + 소셜 카카오·구글) — 앱은 Supabase SDK 로그인, 백엔드는 Supabase JWT 검증 + `users` JIT 프로비저닝(이메일·소셜 동일 경로). 프로필은 `GET/PUT /users/me`로 조회·수정. **애플은 추후 확장**(Supabase Apple provider 추가).
3. 기록 CRUD(하루 1개·수정) + 비동기 감정 분석(폴백) + 테마/음악 매핑.
4. 피드/친구 + 공유 + 공감 리액션.
5. 앱: Dio/Riverpod/go_router 골격 → 기능 순차 구현.
