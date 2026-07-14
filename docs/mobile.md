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
│  ├─ character/    ★ Phase 7 — 현재는 **온보딩(캐릭터 선택)까지만** 구현
│  │  ├─ data/      (api_character_repository.dart, fake_character_repository.dart, dto/character_dto.dart)
│  │  ├─ domain/    (character.dart, my_character.dart, equipment_item.dart, render_meta.dart,
│  │  │              character_repository.dart[abstract])
│  │  │              ⏳ item_group.dart·mission.dart·reward_event.dart·retrospect.dart — Task 030/032
│  │  └─ presentation/ (character_onboarding_page.dart ★ peek 캐러셀 선택 — `/onboarding/character`
│  │                    providers/character_providers.dart
│  │                    widgets/ character_stage.dart      ★ 렌더러 스위치(§7-1)
│  │                             idle_character_view.dart  ★ PNG 메시 워프 idle(§7-2)
│  │                    ⏳ character_home_page·wardrobe_page·shop_page·mission_page·retrospect_page,
│  │                       reaction_overlay·item_grid_tile·mission_tile 등 — Task 029 본편/030/032)
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
   ⏳ character/(rive_image_cache.dart — 아이템 url→bytes LRU+디스크 캐시)는 Rive 전환(Task 031) 시 추가

에셋: `assets/characters/{monkey,red_panda}.png` (640px)
  ⚠️ 현재 **배경이 불투명한 크림색**이며 투명 PNG로 교체 예정 → `CharacterStage`가 이를 흡수한다(§7-3).
```

> **Phase 6 소셜**: 친구는 탭이 아니라 피드 AppBar·프로필에서 진입(셸 밖 `parentNavigatorKey` 라우트 `/friends`·`/friends/requests`·`/friends/add`·`/feed/diary/:id`). 공개범위·공유·공감은 diary/feed 화면에 통합. 앱은 백엔드 REST(`/friends/*`·`/feed`·`/diaries/{id}/reactions`·`PATCH /diaries/{id}/visibility`)만 사용.

### 2-1. 탭 재편 (Phase 7) — ⏳ 아직 하지 않았다

**현재 탭(구현 상태)** — Phase 6 그대로 4개다.

```
[캘린더] [목록] [작심삼일] [피드]
   0       1        2       3
```

**계획(Task 029 본편)** — 캐릭터 홈을 앞에 삽입한다.

```
[캐릭터(홈)] [캘린더] [작심삼일] [피드] [프로필]
     0          1         2        3       4
```

- **캐릭터 홈이 앱의 메인**(index 0)이 되면서 **캘린더가 index 0 → 1로 밀린다.**
- ⚠️ **Phase 6의 "탭은 브랜치 맨 뒤 append로 기존 IndexedStack 인덱스 보존" 규칙이 여기서 깨진다.** 앞에 삽입되기 때문이다.
- → **FCM 딥링크(작심삼일 리마인더/완주)와 `context.go`/`goBranch` 경로를 전수 점검**해야 한다(`core/router/app_router.dart`, `scaffold_with_nav_bar.dart`, 푸시 핸들러). **탭 인덱스 회귀 테스트 필수.**
- **→ 이 회귀 위험 때문에 탭 재편을 온보딩과 분리해 별도 Task로 미뤘다.** 온보딩(`/onboarding/character`)은 **셸 밖 풀스크린**이라 탭 구조를 건드리지 않으므로 먼저 넣을 수 있었다.
- **캐릭터 홈**(미구현): 몰입형 풀스크린 "내 방" — 상단 반투명 상태바(Lv·성장 게이지·코인·보상 알림), 중앙 캐릭터(대형, idle 두리번거림), 주변 ROOM_PROP 슬롯 진열, 배경은 착용 BACKGROUND, 하단 플로팅 패널("오늘 기록하기" 주 CTA + 옷장·미션·상점).
- **색 역할 준수**: `primary`=선택/CTA, `success`=성장 게이지, `accent`는 AI 전용이므로 **미사용**. 코인 색은 `AppColors`에 `currency`(골드) 토큰을 신규 승격.

**온보딩 리다이렉트는 구현됐다** → §7-4.

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

## 6. 감정 표현 전략 (Phase 7 개정 — ⏳ 계획, 미착수)

> **⚠️ 아직 아무것도 제거하지 않았다.** 감정 동적 테마·감정 마스코트 mp4·셰이더 연출은 **현재도 그대로 동작**하며, 감정은 **여전히 LLM이 분석**한다(백엔드 Task 024 미착수 → [`backend.md`](./backend.md) §6).
> `shared/widgets/emotion_video.dart`·`emotion_avatar.dart`, `core/theme/diary_theme.dart`·`emotion_assets.dart`, `flutter_shaders`·`shaders:` 선언, `assets/emotions/**` 모두 **아직 레포에 있다.**
>
> 아래는 **Task 025(앱)에서 수행할 계획**이다 — 감정을 LLM 분석에서 **사용자 직접 입력**으로 바꾸고 **순수 기록 메타데이터**로 격하한다. **연출의 주인공은 캐릭터**가 된다. 백엔드 플래그(Task 024)와 **함께 넘어가야** 한다.

**제거 예정 목록**

| 삭제 예정 | 대체 |
|---|---|
| `shared/widgets/emotion_video.dart`, `emotion_avatar.dart` | `features/character/.../character_stage.dart` |
| `shaders/emotion_alpha.frag` + `pubspec.yaml`의 `shaders:` + `flutter_shaders` 의존성 | — |
| `assets/emotions/**`(감정 마스코트 mp4/PNG 6종), `assets/videos/running_sel.mp4` | — (원본은 `docs/`에 보존) |
| `diary_detail_view.dart`의 `_IntroPhase`·`_RunningIntroOverlay`·PENDING 폴링 | `ReactionOverlay`(캐릭터) — 확정 응답이 곧 `DONE`이므로 **대기 없이 즉시** 등장 |
| `core/theme/diary_theme.dart`(감정 배경·글자·강조색 팔레트) | `core/theme/emotion_palette.dart` — **달력 점 색 + 감정 칩 색만** |
| `core/theme/emotion_assets.dart`(PNG/mp4 경로) | `emotion_labels.dart`(라벨만) |
| 피드 카드 감정 배경색, `diary_dto.hasTheme` | 중립 카드 + 감정 칩 |

**유지**: 로그인 화면 마스코트 영상 3종과 `video_player` — 브랜딩 자산이므로 남긴다.

**추가 예정**: `diary_editor_view.dart`의 감정 입력 위젯 — 프리셋 칩 6종 + "직접 입력"(≤20자) + 최근 사용 추천(`GET /diaries/me/emotions/recent`). **감정은 선택 사항**이며, 미입력 상태로도 확정할 수 있다.

## 7. 캐릭터 렌더링

> Rive(`.riv`) 전환은 **Task 031 예정**이다. 현재 렌더러는 **PNG 메시 워프**(`IdleCharacterView`)이고, `rive` 패키지는 **아직 `pubspec.yaml`에 없다** — 재생할 `.riv`가 없는 상태로 넣으면 빌드 리스크만 커지기 때문이다.

### 7-1. 렌더러 스위치 — `CharacterStage`

`CharacterStage`가 렌더러를 **단일 진입점에서** 스위치한다. Rive를 드롭인할 지점이 주석으로 준비돼 있다(Task 031).

- `--dart-define=USE_RIVE=false`가 **기본값** → `IdleCharacterView`(§7-2).
- `--dart-define=USE_RIVE=true` → Rive 경로. **다만 현재는 `.riv` 아트보드가 없어 이 분기도 `IdleCharacterView`로 폴백**한다.
- **`kIsWeb`이면 플래그와 무관하게 무조건 비-Rive 경로**(`rive_native` wasm 이슈 회피). 웹이 상시 개발·확인 경로라 이 보장이 중요하다.
- Rive는 네이티브 FFI 의존이라 **위젯 테스트는 비-Rive 경로를 유지**한다.

### 7-2. `IdleCharacterView` — PNG 메시 워프 (현재 렌더러)

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

### 7-3. `CharacterStage`의 배경 카드 (불투명 PNG 흡수)

캐릭터 PNG는 현재 **배경이 불투명한 크림색**이다(투명 PNG로 교체 예정). 그래서 캐릭터를 화면 배경에 그냥 얹지 않고, 크림색과 가까운 **`AppColors.paper` 카드 위에 올려 흰 박스가 튀지 않게** 한다. 바닥 그림자(타원)는 이미지 아래쪽 **바깥에** 그려 불투명 PNG에 가려지지 않게 배치한다. → 나중에 **투명 PNG로 파일만 교체해도 구도가 그대로** 동작한다.

### 7-4. 캐릭터 선택 온보딩 + 라우터 가드

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

### 7-5. `_AppScrollBehavior` (app.dart) — 웹에서 캐러셀을 마우스로 끌기

Flutter 기본 `MaterialScrollBehavior`의 `dragDevices`에는 **마우스가 빠져 있다.** 그래서 터치 기기에서는 잘 넘어가는 `PageView`(캐릭터 선택 캐러셀)가 **웹·데스크톱에서는 마우스로 전혀 끌리지 않는다.**

→ `MaterialApp.router(scrollBehavior:)`에 **마우스·트랙패드를 드래그 장치로 추가**했다. 실사용 타깃은 터치(iOS/Android)지만 **웹이 상시 개발·확인 경로**이므로 필요하다.

### 7-6. Rive Data Binding 사용 패턴 (⏳ Task 031 전환 시)

```dart
final file = await rive.File.asset('assets/rive/characters.riv', riveFactory: rive.Factory.rive);
_controller = rive.RiveWidgetController(file,
    artboardSelector: rive.ArtboardSelector.byName(spec.riveArtboard),   // 'MONKEY' | 'RED_PANDA'
    stateMachineSelector: rive.StateMachineSelector.byName('SM_Character'));
_vmi = _controller.dataBind(rive.DataBind.auto());

final bytes = await ref.read(riveImageCacheProvider).load(variant.imageUrl);
_vmi.image('outfit')?.value = await rive.Factory.rive.decodeImage(bytes);
_vmi.string('speech')?.value = reaction.line;
_vmi.number('expRatio')?.value = exp / expToNext;
_vmi.trigger('react')?.fire();
```

- 아이템 이미지는 `.riv`에 굽지 않고 **서버 `/files/items/`에서 런타임 주입**한다 → **아이템 추가에 앱 재배포 불필요**.
- `shared/character/rive_image_cache.dart`가 url→bytes를 **메모리 LRU + 디스크 캐시**로 관리한다.
- 재진입 시 컨트롤러·`ViewModelInstance` dispose 누락은 누수로 직결 → 실기기 50회 재진입 검증 대상.

### 7-7. `.riv` 에셋 스펙 (⏳ 미제작)

- **파일**: `assets/rive/characters.riv` (캐릭터당 아트보드 1개, 캔버스 1:1 1000×1000, 하단 정렬)
- **아트보드명 = DB `characters.code`** → `MONKEY` / `RED_PANDA`
- **State Machine `SM_Character`** (전 아트보드 동일)
  - `Idle`(루프): 숨쉬기(spine 미세 스케일) + 눈 깜빡임(랜덤) + **주기적으로 고개 돌려 두리번거림**
  - `React`(1회 → Idle 복귀) / `Celebrate`(1회) / `Wave`(선택 시)
- **ViewModel `CharacterVM`** (default instance export) — ***감정 프로퍼티 없음***

| 프로퍼티 | 타입 | 용도 |
|---|---|---|
| `hat` `outfit` `glasses` `prop` `background` | Image | 슬롯 런타임 주입(null = 미착용) |
| `roomProp0` ~ `roomProp5` | Image | 방 소품 진열(최대 6) |
| `speech` `nickname` | String | 말풍선·이름 |
| `level` `expRatio`(0~1) | Number | 레벨 뱃지·성장 게이지 |
| `react` `celebrate` `wave` | Trigger | 1회 재생 |

- **성능 예산**: 아트보드당 본 ≤40, 파일 ≤1.5MB, 이미지는 **referenced**(embed 금지).

### 7-8. 에셋 제작 워크플로우 (원본 PNG → Rive)

1. **맨몸 베이스 생성** — AI로 두 캐릭터의 **옷 없는 버전**을 만든다. 현재 PNG가 입고 있는 흰 티·검은 반바지는 **첫 의상 아이템**(`OUTFIT/BASIC_TEE`, `OUTFIT/BASIC_SHORTS`)으로 등록한다. 그래야 몸에 밀착하는 옷(셀프·반팔·수영복)이 나중에 가능하다.
2. **파츠 분리** — 배경 제거 후 레이어 분해. 가려진 부분(팔 뒤 몸통 등)은 **인페인팅으로 복원**한다.
   ```
   head.png / ears.png / eyes.png(깜빡임용 감은 눈 1장 추가)
   body.png / arm_L.png / arm_R.png / leg_L.png / leg_R.png / tail.png
   ```
3. **Rive 아트보드 조립** — 파츠를 **비트맵 그대로** 배치하고 본(spine/head/arm/tail)에 바인딩한다. **벡터로 다시 그리지 않는다.**
4. **슬롯 앵커** — 각 Image 노드를 해당 본(머리/몸통/손)에 부착해 애니메이션 시 함께 움직이게 한다.
5. **아이템 export** — 아이템 PNG는 **그 슬롯 프레임을 꽉 채우도록 미리 정렬**해 내보낸다(512×512 투명, ≤80KB).

### 7-9. 아이템 = 캐릭터별 PNG (group ↔ variant)

원숭이와 레서판다는 **체형이 다르다**(레서판다가 통통하고 팔이 짧음). 슬롯 프레임의 위치·크기도 다르다.
→ **셔츠 1종 = PNG 2장.** 그래서 아이템은 2단 구조다.

| 단위 | 의미 | 앱에서 |
|---|---|---|
| **group** (`item_groups.code`) | "빨간 후드티" — **소유·착용·상점의 단위** | 사용자가 보고 다루는 것. 착용 요청도 `group_code`로 보낸다 |
| **variant** (`character_items`) | `(group_code + character_code)` 조합의 **렌더용 PNG** | 서버가 **내 캐릭터 기준으로 해석**해 `imageUrl`·`riveSlot`·`renderMeta`를 내려준다 |

→ **캐릭터를 바꿔도 옷장은 그대로 따라오고 variant만 재해석**된다. 해당 캐릭터용 variant가 아직 없으면 `ITEM_VARIANT_MISSING`(409).
→ ⚠️ **캐릭터를 추가하면 기존 모든 옷의 variant를 새로 그려야 한다**(에셋 곱셈). 캐릭터 추가는 신중히.

### 7-10. 리액션 접점 (⏳ Task 032)

`diary_detail_view.dart`에서 인트로·러닝 영상·PENDING 폴링을 제거한 자리에 `ReactionOverlay`가 들어간다. LLM flag가 off라 **확정 응답이 곧 `DONE`** → 대기 없이 즉시 캐릭터 등장 → 말풍선(맥락 기반 대사) + 코인/미션 카드 → 탭하면 `POST /rewards/ack`. **획득이 없어도 대사 1줄은 항상** 나온다.

> 선행 조건: 감정 LLM off(Task 024/025) + 보상 엔진(Task 028). 현재는 셋 다 미착수라 **PENDING 폴링·인트로 연출이 그대로 살아 있다.**

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
| 영상 | `video_player` — 로그인 화면 마스코트 영상 + **(현행) 감정 mp4 연출**. 감정 연출 제거는 Task 025 |
| 셰이더 | `flutter_shaders` — **현행 유지**(감정 알파 셰이더). 제거 예정이나 Task 025 전까지는 살아 있다 |
| 음악 재생 | `just_audio` *(MVP 이후)* |
| 인증 | `supabase_flutter`(Supabase Auth: 소셜 로그인·세션), `google_sign_in`(구글 네이티브 idToken). 카카오는 Supabase 웹 OAuth로 처리, 애플은 추후 |

> 실제 버전은 `pubspec.yaml`에 확정한다.
