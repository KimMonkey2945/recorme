# record 모바일 구조 (Flutter)

> Dart / Flutter. Feature-first + Riverpod + Dio. 코드 위치 기준 `app/lib/`.

## 1. 구조 선택: Feature-first (권장)

- **근거**: 기능 경계가 뚜렷(auth/diary/feed/profile)하고, 각 기능 안에서 presentation/domain/data를 응집해 관리하면 신규 기능 추가·삭제가 폴더 단위로 격리된다. Layer-first는 기능이 늘수록 같은 기능 코드가 layer별로 흩어져 탐색 비용이 커진다.

## 2. 폴더 트리 (`app/lib/`)

```
lib/
├─ main.dart
├─ app.dart                         # MaterialApp, 라우터, 전역 테마
├─ core/
│  ├─ config/      (env, api_base)
│  ├─ network/     (dio_client.dart, auth_interceptor.dart, api_result.dart)
│  ├─ error/       (failure.dart, exception_mapper.dart)
│  ├─ router/      (app_router.dart — go_router)
│  ├─ storage/     (secure_storage.dart — 토큰)
│  └─ theme/       (app_theme.dart, emotion_palette.dart, font_registry.dart)
├─ features/
│  ├─ auth/
│  │  ├─ data/      (auth_api.dart, auth_repository_impl.dart, dto/)
│  │  ├─ domain/    (auth_repository.dart, entities/, usecases/)
│  │  └─ presentation/ (login_page.dart, providers/auth_provider.dart)
│  ├─ character/    ★ Phase 7 — **구현 완료**(온보딩·캐릭터 홈·옷장·보상함·월간 회고·리액션 오버레이)
│  │  ├─ data/      (api_character_repository.dart, fake_character_repository.dart, dto/character_dto.dart)
│  │  ├─ domain/    (character.dart, my_character.dart, equipment_item.dart, render_meta.dart,
│  │  │              item_group.dart, reward.dart, retrospect.dart, character_repository.dart[abstract])
│  │  └─ presentation/ (character_onboarding_page.dart ★ peek 캐러셀 선택 — `/onboarding/character`
│  │                    character_home_page.dart ★ 탭 index 0(로그인 후 첫 화면 — §7-6은 상세에서)
│  │                    wardrobe_page.dart(`/wardrobe`)·rewards_page.dart(`/rewards`)·retrospect_page.dart(`/retrospect`)
│  │                    providers/character_providers.dart
│  │                    widgets/ character_stage.dart      ★ 배경 카드 + 렌더러 배선(§7-1)
│  │                             idle_character_view.dart  ★ PNG 메시 워프 idle(§7-2)
│  │                             reaction_overlay.dart·character_speech_bubble.dart ★ 확정 직후 리액션(§7-6)
│  │                             wardrobe_save_bar·wardrobe_slot_tabs·item_grid_tile·locked_item_sheet)
│  │                    ⚠️ 별도 상점·미션 화면은 보상 재설계로 폐기(구매는 옷장 통합)
│  ├─ diary/
│  │  ├─ data/      (diary_api.dart, diary_repository_impl.dart, dto/diary_dto.dart)
│  │  ├─ domain/    (diary.dart, diary_repository.dart)
│  │  └─ presentation/ (diary_editor_view.dart[감정 입력 위젯 포함], diary_detail_view.dart, providers/)
│  ├─ resolution/    (작심삼일)
│  ├─ feed/          (Phase 6: feed_page·feed_diary_detail_page, FeedNotifier 무한스크롤, feed_diary_card)
│  ├─ friend/        (Phase 6: friends_list·friend_requests·add_friend + 위젯, ApiFriendRepository)
│  └─ profile/
└─ shared/
   ├─ widgets/      (공용 위젯 — ReactionButton·VisibilitySegment·visibility_change_sheet·share_options_sheet 등)
   └─ models/       (공통 모델, ApiResponse 래퍼)

에셋: `assets/characters/{monkey,red_panda}.png` — **투명 배경, 높이 1400**
  (원본 `docs/recormeImo/chImg/{paper_monkey,paper_red}.png` 1600×2602를 리샘플)
```

> **Phase 6 소셜**: 공개범위·공유·공감은 diary/feed 화면에 통합. 앱은 백엔드 REST(`/friends/*`·`/feed`·`/diaries/{id}/reactions`·`PATCH /diaries/{id}/visibility`)만 사용.
> ⚠️ "친구는 탭이 아니라 피드 AppBar에서 진입"은 **더 이상 사실이 아니다** — 친구가 탭으로 승격되고 피드가 셸 밖으로 나갔다(§2-1).

### 2-1. 탭 구성 — ✅ 구현 완료

```
[캐릭터(홈)] [캘린더] [작심삼일] [친구] [프로필]
     0          1         2       3       4
```

- **캐릭터 홈이 앱의 메인**(index 0) — 로그인 후 첫 화면이다(Task 029).
- **index 3은 친구다**(친구 둘러보기 기능과 함께 피드에서 교체). 피드는 탭에서 빠져 **친구 목록 AppBar에서 push** 로 진입한다(`/feed`, 셸 밖 → 뒤로가기 자동 생성). 진입 방향이 과거와 반대다.
- 목록(`/list`)은 탭에서 빠져 캘린더 AppBar 버튼으로, 프로필은 셸 밖에서 탭으로 승격됐다.
- ⚠️ **브랜치 순서(`app_router.dart`) = destinations 순서(`scaffold_with_nav_bar.dart`) = 탭 인덱스.** 두 파일을 항상 함께 고친다. 정합은 `character_onboarding_redirect_test.dart`의 '탭 브랜치 순서' 테스트가 실제 라우터를 대상으로 지킨다.
- FCM 딥링크는 **경로 문자열 push** 라 탭 인덱스 변경과 무관하다(회귀 없음).
- **캐릭터 홈**(미구현): 몰입형 풀스크린 "내 방" — 상단 반투명 상태바(코인·보상 알림. ⚠️ Lv·성장 게이지는 V18 보상 재설계로 폐기), 중앙 캐릭터(대형, idle 두리번거림), 주변 ROOM_PROP 슬롯 진열, 배경은 착용 BACKGROUND, 하단 플로팅 패널("오늘 기록하기" 주 CTA + 옷장·미션. 별도 상점 버튼 없음 — 구매는 옷장 통합).
- **색 역할 준수**: `primary`=선택/CTA, `accent`는 AI 전용이므로 **미사용**(⚠️ `success`=성장 게이지 역할은 게이지 폐기로 사라짐). 코인 색은 `AppColors`에 `currency`(골드) 토큰을 신규 승격.

**온보딩 리다이렉트는 구현됐다** → §7-3.

## 3. 계층 분리

- **presentation**: 위젯 + Riverpod Provider(상태/이벤트). UI는 상태 구독만.
- **domain**: Entity, Repository 인터페이스, (필요 시) UseCase. 프레임워크 비의존.
- **data**: DTO(json_serializable/freezed), API(Dio), RepositoryImpl(DTO↔Entity 매핑).

## 4. 상태관리: Riverpod (권장)

- **근거**: 컴파일 안전(코드 생성), `AsyncValue`로 로딩/에러/데이터 비동기 표현이 API 호출과 자연스럽게 맞음, Provider 조합·테스트 용이, 소규모에 보일러플레이트 적정.
- **대안**:
  - Bloc — 이벤트/상태 명확하나 보일러플레이트 과함, 단순 CRUD엔 과투자.
  - Provider — 기능 부족.
  - GetX — 비권장(마법적/테스트성 약함).

## 5. API 통신 계층

- **Dio + 인터셉터**: `AuthInterceptor`(요청에 **Supabase access token** 첨부, 세션 갱신은 Supabase SDK가 담당), 공통 에러 매핑. 인증/세션 자체는 `supabase_flutter`가 관리.
- 응답 표준 `ApiResponse<T>` 언랩 → 실패 시 `Failure`로 변환해 도메인 전달.
- **모델 직렬화**: `freezed` + `json_serializable`(불변·copyWith·동등성).
- 백엔드 응답 DTO와 앱 DTO는 1:1 매핑(→ [`api-contract.md`](./api-contract.md)).

### 5-1. 프로필 이미지(파일 첨부) 흐름
- **선택·업로드**: `profile` 수정 화면에서 `image_picker`로 이미지를 고르면 바이트(`Uint8List`, 웹·모바일 공통)를 읽어 즉시 `POST /users/me/avatar`(multipart)로 업로드한다. 닉네임/자기소개 저장(`PUT /users/me`)과 **분리**된 별도 액션이라 텍스트 수정이 이미지를 덮어쓰지 않는다.
- **표시**: 공용 `ProfileAvatar` 위젯이 메인 앱바(작은 radius)와 프로필 화면(큰 radius)에서 재사용된다. 등록 이미지가 없으면 **닉네임 이니셜**(없으면 사람 아이콘)로 폴백.
- **URL 조립**: 서버가 돌려준 `profileImageUrl`은 `ApiConfig.resolveImageUrl`로 절대 URL화한다 — `http(s)`로 시작하면(외부 소셜) 그대로, 아니면(내부 업로드 상대경로 `/files/...`) `apiBaseUrl`(호스트+`/api/v1`)과 결합. 호스트는 DB에 저장하지 않아 환경 이전에 안전하다.

## 6. 감정 표현 전략 (Phase 7 개정 — ✅ Task 025 완료)

> **감정 시각 연출은 전부 제거됐다.** 감정 동적 배경/글자 테마·마스코트 mp4·알파 셰이더·상세 시네마틱 인트로·러닝 로딩 영상·PENDING 폴링을 모두 걷어냈고, 감정은 **사용자 직접 입력**(프리셋 6종 또는 자유 텍스트 ≤20자, 선택 사항)하는 **순수 기록 메타데이터**가 됐다. 백엔드 플래그(Task 024, 기본 off)와 정합한다 → [`backend.md`](./backend.md) §6. **연출의 주인공은 캐릭터** 하나다.

**제거 완료 목록**

| 삭제됨 | 대체 |
|---|---|
| `shared/widgets/emotion_video.dart`, `emotion_avatar.dart` | (삭제) — 감정 영상/아바타 폐지 |
| `shaders/emotion_alpha.frag` + `pubspec.yaml`의 `shaders:` + `flutter_shaders` 의존성 | (삭제) |
| `assets/emotions/**`(감정 마스코트 mp4/PNG 6종), `assets/videos/running_sel.mp4` | (삭제 — 원본은 `docs/`에 보존) |
| `diary_detail_view.dart`의 `_IntroPhase`·`_RunningIntroOverlay`·감정 안착 행 + `diary_detail_page.dart`의 PENDING 3초 폴링 | 읽기 전용 본문 + 감정 칩(확정 즉시 DONE — 캐릭터 리액션은 Task 032가 이 자리에) |
| `core/theme/diary_theme.dart`(감정 배경·글자·강조색 팔레트) | `core/theme/emotion_palette.dart` — **달력 점 색 + 감정 칩 색(accent)만** |
| `core/theme/emotion_assets.dart`(PNG/mp4 경로) | `core/theme/emotion_labels.dart`(프리셋 6종 + 라벨·이모지만) |
| 피드 카드 감정 배경색, `diary_dto.hasTheme` | 중립 카드(surface+hairline) + 감정 칩, `diary_dto.hasEmotion` |

**유지(삭제 금지)**: 로그인 화면 마스코트 영상 3종(`tea/box/ballet_sel.mp4`)과 `video_player` — 브랜딩 자산.

**추가됨**: `diary/presentation/widgets/emotion_input_section.dart` — 프리셋 칩 6종 + "직접 입력"(≤20자, `LengthLimitingTextInputFormatter`) + 최근 사용 추천(`GET /diaries/me/emotions/recent`). 프리셋↔직접입력 **상호 배타**(동시 선택 불가로 `EMOTION_CONFLICT` 사전 차단), **감정은 선택 사항**이라 미입력 확정도 가능. 저장 payload에 `emotion`/`emotionLabel`을 실어 보낸다. 상세·피드 응답의 `emotionLabel`로 커스텀 감정 칩을 렌더한다.

## 7. 캐릭터 렌더링

> **최종 렌더러는 `IdleCharacterView`(통짜 PNG 메시 워프)다.** Rive와 파츠 조립을 **둘 다 시도했다가 되돌렸다**(Task 031). `rive` 패키지는 **넣지 않는다.**
>
> - **Rive**: `.riv` 런타임 export가 유료이고, `.riv`를 코드로 만드는 공식 방법이 없어 리깅이 GUI 수작업으로 남는다.
> - **파츠 조립**: 관절 렌더러를 끝까지 구현했지만 **캐릭터가 조각나 보였다.** 파츠들이 같은 3D 모델을 분해한 게 아니라 **각각 따로 생성된 이미지**라 서로 맞지 않는다(눈 간격 101 vs 117, 몸통 색 불일치, 소켓·구멍 크기 불일치, 겹침 여유 없음). **코드로 수렴하는 문제가 아니다.**
> - ⚠️ 그 대가로 **눈 깜빡임(F033)을 포기**했다. 통짜 이미지로는 눈을 감길 수 없다.

### 7-1. `CharacterStage` — 배경 카드 + 렌더러 배선

캐릭터를 [AppColors.paper] 카드 위에 올리고 발밑에 바닥 그림자(타원)를 깔아 접지감을 준다.
렌더러는 `IdleCharacterView` 하나뿐이며 외부 의존성이 없어 **웹 포함 전 플랫폼에서 동일하게 동작**한다.

### 7-2. `IdleCharacterView` — PNG 메시 워프

**정적 PNG 한 장을 "살아 있는" 캐릭터로 보이게 하는 절차적 idle 애니메이션.**

Rive 공식 문서상 **`.riv` 아트보드 없이는 PNG를 애니메이션할 수 없다**("The Flutter runtime does not provide animation capabilities for plain PNG images"). 그리고 이미지를 통째로 `Transform.rotate`/`scale` 하면 **딱딱한 판자가 흔들리는** 모양이 된다 — Rive가 자연스러운 건 런타임이 아니라 아트보드가 **메시로 리깅**돼 있기 때문이다. → **그 원리를 Flutter에서 직접 구현했다.**

PNG를 **12×16 격자 메시**로 쪼개 `Canvas.drawVertices` + `ImageShader`로 **정점마다 다르게** 변형한다. 모든 움직임은 정규화 높이 `v`(발 0 → 머리 1)로 가중된다.

| 움직임 | 방식 |
|---|---|
| **스웨이** | 상체일수록 크게 좌우로 흔들린다(`v^1.6` 가중 → **발은 바닥에 고정**) |
| **숨쉬기** | 바닥 기준 세로 스쿼시&스트레치. **부피 보존 근사**로 가로는 반대로 움직인다 |
| **두리번** | `smoothstep(0.55, 1.0, v)` 마스크로 **머리에만** 가로 변위 → 좌→우로 한 번 훑는다 |
| **하모닉 합성** | 사인 하나면 메트로놈처럼 보인다 → 12초 기본 주기의 **정수배 하모닉(2·3·5·7)** 을 섞어 유기적으로 만들되, 정수배라 루프 경계에서 끊기지 않는다 |

- `phase`(0~1)를 캐릭터마다 달리 줘 **여러 캐릭터가 같은 박자로 움직이지 않게** 한다.
- 이미지 로드 전/실패 시에는 `Image.asset` 폴백으로 그린다(디코딩이 없는 위젯 테스트 환경도 이 경로로 안전 통과).
- ⚠️ **테스트 hang 방지**: 무한 반복 애니메이션은 `pumpAndSettle()`을 영원히 끝나지 않게 만든다. 두 가지 차단책 — ① `animate: false`(캐러셀의 옆 카드도 이걸 쓴다), ② `IdleCharacterView.debugDisableIdleAnimation`(라우터가 페이지를 직접 만들어 `animate`를 주입할 수 없는 리다이렉트 테스트용 전역 스위치).

### 7-3. 캐릭터 선택 온보딩 + 라우터 가드

**`/onboarding/character`** — **셸 밖 풀스크린**(탭 구조를 건드리지 않는다 → §2-1).

- **peek 캐러셀**: `PageView`(`viewportFraction: 0.78`)라 좌우 카드가 살짝 보인다. 중앙에서 멀어질수록 작고 흐리게(스와이프에 따라 연속 보간), **중앙 카드만 idle 애니메이션**이 살아 움직인다(옆 카드는 정지 → 시선 집중).
- **전환 수단 3가지**: 드래그 / **옆 카드 탭** / **도트 탭**. 드래그만으로는 전환되지 않는 입력 환경이 있고, 옆 카드를 눌러 고르는 편이 터치에서도 자연스럽다. 확정은 하단 "선택" CTA가 전담한다(중앙 카드 탭은 무시).
- 선택 실패 시 스낵바만 띄우고 **온보딩에 머문다**(홈으로 새지 않는다).

**리다이렉트 가드** — `app_router.dart`의 **순수 함수** `characterOnboardingRedirect({myCharacter, location})`.

go_router의 `redirect` 안에서는 **async 호출이 금지**돼 있다. → `myCharacterProvider`(`FutureProvider`, **`autoDispose` 아님** — 라우터가 구독하므로)의 **현재 값만 읽어** 동기 판단한다.

| 상태 | 판정 |
|---|---|
| `myCharacter == null` (미인증·로딩·에러) | **판단 보류**(리다이렉트 없음) |
| `character == null` (인증됨 + 미선택) | **온보딩으로.** 단 **온보딩 자체는 통과**시킨다 → 무한 루프 방지 |
| `character != null` (선택 완료) | 일반 경로는 그대로. **온보딩 재진입만** `/`로 되돌린다 |

- `myCharacterProvider`는 **미인증이면 네트워크 호출 없이 즉시 null**을 돌려준다(로그인 전 불필요한 401 방지).
- `--dart-define=USE_FAKE_CHARACTER_REPO=true`면 백엔드 없이 `FakeCharacterRepository`로 웹 프리뷰가 가능하다(기본 false).

### 7-4. `_AppScrollBehavior` (app.dart) — 웹에서 캐러셀을 마우스로 끌기

Flutter 기본 `MaterialScrollBehavior`의 `dragDevices`에는 **마우스가 빠져 있다.** 그래서 터치 기기에서는 잘 넘어가는 `PageView`(캐릭터 선택 캐러셀)가 **웹·데스크톱에서는 마우스로 전혀 끌리지 않는다.**

→ `MaterialApp.router(scrollBehavior:)`에 **마우스·트랙패드를 드래그 장치로 추가**했다. 실사용 타깃은 터치(iOS/Android)지만 **웹이 상시 개발·확인 경로**이므로 필요하다.

### 7-5. 아이템 = 캐릭터별 PNG (group ↔ variant)

원숭이와 레서판다는 **체형이 다르다**(레서판다가 통통하고 팔이 짧음). 슬롯 프레임의 위치·크기도 다르다.
→ **셔츠 1종 = PNG 2장.** 그래서 아이템은 2단 구조다.

| 단위 | 의미 | 앱에서 |
|---|---|---|
| **group** (`item_groups.code`) | "빨간 후드티" — **소유·착용·구매의 단위** | 사용자가 보고 다루는 것. 착용 요청도 `group_code`로 보낸다 |
| **variant** (`character_items`) | `(group_code + character_code)` 조합의 **렌더용 PNG** | 서버가 **내 캐릭터 기준으로 해석**해 `imageUrl`·`riveSlot`·`renderMeta`를 내려준다 |

→ **캐릭터를 바꿔도 옷장은 그대로 따라오고 variant만 재해석**된다. 해당 캐릭터용 variant가 아직 없으면 `ITEM_VARIANT_MISSING`(409).
→ ⚠️ **캐릭터를 추가하면 기존 모든 옷의 variant를 새로 그려야 한다**(에셋 곱셈). 캐릭터 추가는 신중히.

### 7-6. 리액션 접점 (✅ Task 032)

확정 직후 `diary_editor_page`가 `/diary/:id?reaction=1`로 push → `DiaryDetailPage(showReaction:true)`가 상세 위 `Stack`에 `ReactionOverlay`를 겹친다. LLM flag가 off라 **확정 응답이 곧 `DONE`** → 대기·스피너 없이 즉시 홈과 동일한 `CharacterStage`로 캐릭터 등장 → `CharacterSpeechBubble`(맥락 기반 대사) + 코인 획득 카드 → 탭/‘확인’ → `ackRewards`(홈 배지 감소)·`_reactionDismissed`로 재표시 잠금. **획득이 없어도 대사 1줄은 항상**(서버 대사 없으면 캐릭터별 기본 대사 — 빈손 금지) 나온다. 페이로드 소스는 `GET /characters/me/reaction?diaryId=`(data=null 허용). 일반 재진입(`reaction` 미지정)은 오버레이 미표시.

> 월간 회고(F032)는 캐릭터 홈 ‘이달의 기록’ 버튼 → `/retrospect`(`retrospect_page.dart`). `GET /characters/me/retrospect?yearMonth=`로 이달의 기록 수·최장 연속일·감정 분포(프리셋+커스텀)·획득 코인·획득 아이템을 집계해 보여주고, 월 이동(미래 차단)·빈 달 빈 상태를 지원한다.

## 8. 권장 의존성 (구현 시)

| 용도 | 패키지 |
|---|---|
| 상태관리 | `flutter_riverpod`, `riverpod_generator` |
| 라우팅 | `go_router` |
| 네트워크 | `dio` |
| 직렬화/모델 | `freezed`, `json_serializable` |
| 보안 저장 | `flutter_secure_storage` |
| **캐릭터 렌더(현재)** | **없음** — `IdleCharacterView`가 Flutter 기본 `dart:ui`(`drawVertices`·`ImageShader`)만 쓴다(§7-2) |
| **캐릭터 렌더(⏳ Task 031)** | **`rive`** (비트맵 리깅 + Data Binding. MIT·무료. 네이티브 FFI(`rive_native`) 의존 → APK 증가·웹 폴백). **재생할 `.riv`가 생길 때 pubspec에 추가**한다 |
| 영상 | `video_player` — **로그인 화면 마스코트 영상 전용**(감정 mp4 연출은 Task 025에서 제거됨) |
| 셰이더 | *(없음 — `flutter_shaders`는 감정 알파 셰이더와 함께 Task 025에서 제거됨)* |
| 음악 재생 | `just_audio` *(MVP 이후)* |
| 인증 | `supabase_flutter`(Supabase Auth: 소셜 로그인·세션), `google_sign_in`(구글 네이티브 idToken). 카카오는 Supabase 웹 OAuth로 처리, 애플은 추후 |

> 실제 버전은 `pubspec.yaml`에 확정한다.
