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
| DB | PostgreSQL 18 (Flyway V1~V17) |
| 감정 분석 | 멀티모달 외부 LLM API (`LlmClient` 추상화: 기본 Gemini / Claude·Ollama·Stub) |
| 인증 | Supabase Auth(소셜: 카카오/구글, 이메일; 애플 추후) + 백엔드 Supabase JWT(JWKS ES256) 검증 |
| 푸시 | FCM (작심삼일 리마인더/완주, firebase-admin) |

## 현재 상태 (중요)

MVP(Phase 1~6)는 **구현 완료**이고, 현재 **Phase 7(캐릭터 도메인)이 진행 중**이다. 작업 전 다음을 인지할 것:

- `backend/`: Spring Boot 3.5.x. 패키지 `com.recordapp` 아래 `domain.{auth,user,diary,emotion,resolution,device,social,feed,character}` + `infra.{llm,push,storage}` + `global.*`(보안/예외/표준 응답)이 실제 구현돼 있다. Flyway **`V1~V17`** 마이그레이션 실재(캐릭터는 `V15`=카탈로그, `V16`=미션, `V17`=사용자 캐릭터 상태). 로컬은 네이티브 PostgreSQL 18(`recorme` DB)로 `bootRun` 실측됨. 백엔드 테스트 **202개 통과**(Testcontainers 포함).
- `app/`: Flutter feature-first 앱. `lib/features/{auth,diary,profile,resolution,feed,friend,character}` + `lib/core/*` + `lib/shared/*`. flutter_quill 리치 에디터·감정 동적 테마·마스코트/영상 연출·FCM 연동 포함. 앱 테스트 **127개 통과**, `flutter analyze` 무경고.
- 그래도 **`docs/`가 설계의 단일 진실 공급원(source of truth)**이다. 구현·수정 시 항상 `docs/`와 정합을 맞추고, 신규 기능은 로드맵 순서를 따른다.
  - ⚠️ `docs/`는 **Phase 7 전체를 앞서 설계**해 둔 상태라, 일부 절이 "이미 된 것처럼" 읽힌다. **구현 여부는 `docs/architecture.md` §3.3(Phase 7 구현 현황) 표를 기준**으로 판단할 것.

### Phase 7 진행 상황 (캐릭터)

- **구현됨**: DB(`V15~V18`) / 백엔드 `domain.character`(캐릭터 조회·선택, 옷장 아이템 목록·착용, 미션 조회 — `CatalogCache` 마스터 캐시, group↔variant 2단 해석, 기본 상태 JIT) / 앱 `features/character`(**캐릭터 선택 온보딩** `/onboarding/character` + 라우터 redirect 가드 + `CharacterStage`·`IdleCharacterView` PNG 메시 워프 렌더러 + **옷장 UI `/wardrobe`**(Task 030 옷장분) — 착용형 아이템은 **캐릭터와 동일 프레임 풀프레임 PNG를 같은 메시 워프에 z순 오버레이**, BACKGROUND/ROOM_PROP은 스테이지 정적 배치, 탭=로컬 미리보기·저장=배치 커밋. 미보유 아이템 탭 시 `locked_item_sheet`로 해금 조건 안내(미션 진행바 / 코인 가격). ⚠️ `app/assets/items/*`는 **도형 플레이스홀더** — 실제 에셋은 인페인팅(원본 위 생성→diff 추출)으로 교체 예정) + **탭 재편·캐릭터 홈**(Task 029 완료): 하단 탭이 **`[캐릭터 홈(/)][캘린더(/calendar)][작심삼일][피드][프로필]` 5개, 캐릭터 홈이 index 0**이라 로그인 후 첫 화면이다. 캐릭터 홈(`character_home_page.dart`)은 상단 상태바(코인·미확인 보상 배지) + 중앙 `CharacterStage` + 이름·소개 패널 + 옷장 진입 버튼. 옷장은 이제 홈에서 진입한다(프로필 임시 버튼 제거). 목록은 탭에서 빠져 캘린더 앱바 버튼(`/list` 셸 밖 push)으로, 프로필은 셸 밖 라우트에서 탭으로 승격. 상태바의 코인·보상 실데이터는 Task 028(보상 엔진) 완료 전까지 0/기본값이다.
- **보상 설계(2026-07-15 재정의)**: 경험치/레벨·상점은 **폐기**. 성장은 **코인 + 미션 해금**으로만 표현한다. 코인은 **기록 확정·작심삼일 완주·미션**으로 적립(수치는 `record.character.coin-per-*` 설정 + `missions.coin_reward`로 조정), 아이템은 **옷장에서 코인 구매 또는 미션 해금**(별도 상점·미션 화면 없음, 옷장 잠금 안내가 단일 지점). **1단계 완료**: V18로 `user_character_state.level/exp`·LEVEL 미션 드롭, 앱/백엔드 응답에서 레벨·경험치 제거. ⚠️ 실제 코인 적립·미션 판정·구매 실행은 **Task 028(다음 단계)** — 지금 코인은 항상 0.
- **남은 Task**:
  - **024 — 감정 축소(백엔드)**: ✅ **완료(2026-07-16, V19)**. LLM 자동 분석을 `record.analysis.enabled`(기본 **false**) 플래그로 끄고, 확정 시 즉시 `DONE` + **사용자 직접 입력 감정**(프리셋 `primary_emotion` 또는 자유 텍스트 `emotion_label` ≤20자, 상호 배타 — 동시 지정 400 `EMOTION_CONFLICT`)을 저장한다. 감정/LLM 빈은 삭제 대신 `@ConditionalOnProperty`로 게이팅(플래그 on 시 기존 PENDING→분석 경로 무손상 복구), `DiaryService`는 `ObjectProvider`로 빈 부재 흡수. `GET /diaries/me/emotions/recent`로 최근 커스텀 라벨 추천. ⚠️ **감정 LLM 분석은 이제 기본 비활성**이다.
  - **025 — 감정 축소(앱)**: ✅ **완료(2026-07-16)**. 감정 시각 연출을 전부 제거(감정 mp4·`emotion_video`/`emotion_avatar`·`flutter_shaders`·`emotion_alpha.frag`·`assets/emotions/**`·`running_sel.mp4`·상세 시네마틱 인트로·러닝 오버레이·PENDING 폴링·`diary_theme.dart`·`emotion_assets.dart` 삭제)하고, 작성기에 **감정 입력 위젯**(`emotion_input_section.dart` — 프리셋 6종/직접 입력 ≤20자/최근 추천, 상호 배타)을 넣었다. 감정은 달력 점 색 + 감정 칩(신규 `emotion_palette.dart`·`emotion_labels.dart`)에만 쓰는 순수 메타데이터. 피드/상세는 중립 카드 + 감정 칩으로 전환. `flutter analyze` 무경고 + `flutter test` 136개 통과. ⚠️ **로그인 마스코트 영상 3종·`video_player`는 유지**.
  - **028 — 보상 엔진**: 코인 적립·구매·미션 판정·보상함·리액션. `character_events` 테이블(V17)은 있으나 **엔진 코드는 전혀 없다**(`global/event/`·`CharacterEventListener`·`characterExecutor` 모두 미존재). ⚠️ 경험치/레벨은 재설계로 제거됐으니 exp 적립·레벨업은 만들지 말 것.
  - **030 잔여 — 보상함·구매 실행 UI**: 옷장·탭 재편·캐릭터 홈(Task 029)·옷장 잠금 안내는 **완료**. 상점·미션 화면은 재설계로 **폐기**. 남은 건 보상함과 옷장 코인 구매 실행(둘 다 Task 028 선행 필요). (FCM 딥링크는 경로 문자열 push라 탭 인덱스 변경과 무관 — 회귀 없음이 확인됐다.)
  - ~~**031 — Rive 전환**~~ → **완료 (Rive·파츠 조립 둘 다 미채택)**: 렌더러는 기존 **`IdleCharacterView`(통짜 PNG 12×16 메시 워프)** 를 그대로 쓰고, **에셋만 고해상도 투명 PNG로 교체**했다. Rive는 `.riv` export 유료 + 리깅이 GUI 수작업이라 접었고, 파츠 조립은 구현까지 갔지만 **파츠들이 각각 따로 생성된 이미지라 서로 맞지 않아**(눈 간격 101 vs 117, 몸통 색·소켓 크기 불일치, 겹침 여유 없음) 캐릭터가 조각나 보여 되돌렸다. ⚠️ **눈 깜빡임(F033)은 미지원** — 통짜 이미지로는 불가능하며, 되살리려면 코드가 아니라 **에셋**을 다시 만들어야 한다. 경위: `tasks/031-app-parts-character-renderer.md`.
  - **032 — 리액션·회고**.
- **남은 검증**: 작심삼일 **FCM 실기기(Z Flip3) 라이브 검증**(딥링크·팬아웃).
- **MVP 이후(미구현)**: 감정 기반 **음악**, 성능 최적화, 애플 로그인.

## 설계 문서 (구현의 기준)

| 문서 | 내용 |
|---|---|
| `docs/PRD.md` | MVP 제품 요구사항(사용자 여정, 기능 명세 F001~, 페이지·데이터 모델·기술 스택) |
| `docs/ROADMAP.md` | 개발 로드맵(Phase·Task 분해, 기능 ID 추적, 스택 네이티브 테스트 원칙) |
| `docs/architecture.md` | 전체 아키텍처, 확정 결정사항, 트레이드오프, 구현 로드맵 |
| `docs/database.md` | PostgreSQL ERD + 전체 DDL (Flyway `V1~V17` 마이그레이션의 설계 원본) |
| `docs/backend.md` | 패키지 구조, 계층, 표준 응답, MyBatis 매퍼 예시, JWT/LLM 설계 |
| `docs/mobile.md` | Feature-first 구조, Riverpod, Dio 통신, 테마 동적 적용 |
| `docs/api-contract.md` | REST API 계약 (`/api/v1`), 표준 응답·커서 페이징 |

## 핵심 아키텍처 결정 (반드시 준수)

- **패키지 베이스는 `com.recordapp`** — Java `record` 키워드 혼동 회피.
- **백엔드 계층**: Controller → Service(`@Transactional`) → Mapper(MyBatis) → DB. **외부 LLM 호출은 트랜잭션 밖**에서 비동기로 수행.
- **인증은 Supabase Auth**: 앱이 Supabase SDK로 이메일/소셜 로그인(이메일: `signUp`(닉네임→`user_metadata`)·`signInWithPassword`, 확인 메일 필수 / 구글: `signInWithIdToken` / 카카오: `signInWithOAuth`) → Supabase 세션(access JWT + refresh, **SDK가 저장·자동 갱신**). 백엔드는 앱이 보낸 **Supabase access token(Bearer)을 검증**(JWT secret/JWKS)하고 `sub`(uuid)로 `users`를 **JIT(최초 요청 시 자동) 프로비저닝**. **자체 JWT 발급·`refresh_tokens`·`social_accounts`·`SocialVerifier`는 미사용.** Supabase는 **Auth만** 사용(소셜 검증·세션·JWT). **앱 데이터는 Supabase와 무관한 별도 PostgreSQL**(로컬: 네이티브 PostgreSQL 18 `recorme` DB, 배포: Docker/관리형)에 저장하며 **Flyway 단일 진실원**(기능별 마이그레이션 분할: `V1=users`, `V2=diaries`, `V3~V6=사진 인라인화·리치 본문(Delta)·content_text`, `V7=감정 분석(emotion_types + diaries 감정·테마 컬럼)`, `V8=draft→확정 라이프사이클`, `V9=작심삼일`, `V10=device_tokens(FCM)`, `V11~V14=친구·피드·공감(Phase 6)`, `V15~V17=캐릭터 카탈로그·미션·사용자 캐릭터 상태(Phase 7)`). PostgREST/RLS/Edge Functions/`profiles` 테이블·트리거 미사용. 인증과 데이터는 물리적으로 분리되므로 `auth.users` FK 없이 `users.supabase_uid` 컬럼으로만 매핑한다. **이메일·소셜은 provider 무관 동일 JIT 경로**이며, 프로필(닉네임·프로필 이미지·자기소개 `bio`)은 `GET/PUT /users/me`로 조회·수정한다.
- **감정 분석은 비동기 + draft→확정 라이프사이클**: 기록은 `analysis_status=DRAFT`(미확정·수정가능·미분석)로 저장 → **'오늘을 기억하기' 확정 시 `PENDING`** 전이 후, **커밋 밖**에서 `@Async`(전용 풀 `emotionAnalysisExecutor`)로 멀티모달 LLM 분석·감정/테마 매핑 후 `DONE` 갱신. 실패 시 `NEUTRAL` 폴백. **확정 시 1회만 분석**(확정 후 수정 불가 → `DIARY_ALREADY_CONFIRMED`, 재분석은 삭제 후 재작성). 누락분은 `EmotionAnalysisPoller`(PENDING 백스톱)가 보완. (음악 매핑은 MVP 이후.)
- **하루 1기록 + 수정**: 사용자·날짜당 일기 1개(`uq_diary_user_day` 부분 유니크). 같은 날짜 재작성은 INSERT가 아닌 **UPDATE**.
- **캐릭터 아이템은 group ↔ variant 2단 구조**: 소유·착용은 **`group_code`로만** 저장하고(`user_item_groups`·`user_equipment`), 렌더 이미지는 **`(group + 선택 캐릭터)`로 해석**한다(`character_items`). 캐릭터 전용 variant 우선 → 없으면 공용(`character_code IS NULL`) 폴백 → 둘 다 없으면 `ITEM_VARIANT_MISSING`(409). **캐릭터를 바꿔도 `user_equipment`를 건드리지 않는다** — variant만 재해석되므로 옷장이 캐릭터를 따라온다. 해석 경로는 둘: SQL 조인(`DISTINCT ON` + `ORDER BY … character_code NULLS LAST`)과 `CatalogCache` 메모리 해석. 캐릭터 도메인의 모든 진입점은 `CharacterService.ensureState()`(멱등 JIT)를 먼저 통과한다.
- **PK 전략**: 내부 PK는 `BIGINT IDENTITY`, 외부 노출(회원/공유)은 별도 `UUID`(`users.uuid`, `diaries.share_token`).
- **확장 포인트는 인터페이스로 격리**: `EmotionAnalyzer`/`LlmClient`(LLM provider 교체 — **구현됨**: 기본 Gemini / Claude·Ollama·Stub, 무키 시 Stub 폴백), `PushService`(FCM/Stub 폴백), `StorageService`(로컬 디스크, 향후 S3 교체). `MusicSource` + `tracks.source_type`(음악 소스 미정 흡수)는 **MVP 이후**. (소셜 provider 검증은 Supabase Auth가 담당 — 백엔드 `SocialVerifier` 없음.)
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
