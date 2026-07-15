# Task 029 — 앱 캐릭터 홈(1번 탭) + 탭 재편 + 온보딩 + 플레이스홀더 렌더러 + 데이터 계층

- **Phase**: 7 (캐릭터 중심 전환)
- **구현 기능**: F026(캐릭터 선택), F033(캐릭터 홈·소품 진열)
- **상태**: 🔶 **부분 완료 — 온보딩 선택창만**
- **선행**: Task 027(캐릭터 조회·선택·착용 API) — 완료

> ⚠️ **아직 안 된 것**: **탭 재편·캐릭터 홈(1번 탭)·상태바·소품 진열·하단 액션**.
> 하단 탭은 여전히 `[캘린더][목록][작심삼일][피드]` **4개**이고 **캘린더는 index 0 그대로**다.
> 완료된 것은 **데이터 계층 + 온보딩 캐릭터 선택 화면 + 렌더러 스위치**까지다.

> 📌 **2026-07-15 보상 재설계(1단계) 반영**: 경험치/레벨·별도 상점 화면을 폐기했다(V18). 미구현인 **캐릭터 홈 상태바에서 Lv·성장 게이지를 제거**(코인·미확인 보상 배지만), 하단 액션의 **상점 버튼 제거**(구매는 옷장 통합). `success`=성장 게이지 색 역할도 폐기.

## 개요

앱의 메인을 **캐릭터 홈**으로 바꾸고, 가입 직후 **캐릭터 선택 온보딩**을 넣는다.
렌더는 **Rive 에셋 없이도 전 기능을 개발·테스트할 수 있는 대체 렌더러**로 구현한다
(Rive 교체는 최후의 Task 031). `--dart-define=USE_RIVE=false`가 기본값이며, **웹(`kIsWeb`)은 항상 비-Rive 경로**.

### ⚠️ 탭 재편 회귀 (이 Task의 최대 주의점) — **미착수**
```
[캐릭터(홈)] [캘린더] [작심삼일] [피드] [프로필]
```
**캘린더가 index 0 → 1로 밀린다.** Phase 6의 "탭은 맨 뒤 append로 인덱스 보존" 전제가 여기서 깨진다.
→ **FCM 딥링크(`/resolution/:id`)와 모든 `context.go` 경로를 전수 점검**하고 **탭 인덱스 회귀 테스트를 반드시 작성**한다.

> **이 회귀 위험 때문에 탭 재편을 이번 작업에서 분리했다.** 캐릭터 홈이 실제로 채워질 때 함께 수행한다.
> 그때까지 라우터에는 **현재 브랜치 순서(캘린더 index 0)를 못박는 가드 테스트**를 걸어 둔 상태다.

## 관련 파일

```
app/lib/features/character/
├── domain/       character.dart, my_character.dart, equipment_item.dart,
│                 render_meta.dart, character_repository.dart (abstract)      ✅
├── data/         api_character_repository.dart, fake_character_repository.dart, dto/  ✅
└── presentation/ character_onboarding_page.dart  ✅ 캐러셀 선택 화면
                  providers/character_providers.dart  ✅
                  widgets/ character_stage.dart      ✅ Rive/비-Rive 스위치
                           idle_character_view.dart  ✅ 메시 워프 idle 렌더러
                  character_home_page.dart            ❌ 미구현 (1번 탭)
                  widgets/ placeholder_character_view.dart    ❌ 미구현
                           character_home_stat_bar.dart       ❌ 미구현
                           character_home_bottom_actions.dart ❌ 미구현
```
- `app/lib/core/router/app_router.dart` — ✅ `/onboarding/character` 라우트 + redirect 가드 / ❌ 탭 재편
- `app/lib/core/router/scaffold_with_nav_bar.dart` — ❌ 탭 5개 재구성(미착수, 현재 4개)
- `app/lib/app.dart` — ✅ `_AppScrollBehavior` 추가(웹 마우스 드래그)
- `app/lib/core/theme/app_colors.dart` — ❌ **`currency`(골드) 토큰 미추가**
- `app/test/features/character/character_onboarding_test.dart` — ✅ 신규
- `app/test/features/character/character_onboarding_redirect_test.dart` — ✅ 신규(브랜치 순서 가드 포함)
- `app/test/features/character/tab_index_regression_test.dart` — ❌ **미작성**(탭 재편과 함께)

## 구현 항목

- [x] **데이터 계층**(기존 컨벤션 준수): `CharacterRepository` **abstract** → `ApiCharacterRepository`(Dio + `ApiResponse` 언랩) / `FakeCharacterRepository` → Riverpod provider override
- [ ] **탭 재편**: `[캐릭터] [캘린더] [작심삼일] [피드] [프로필]`, `StatefulShellRoute.indexedStack` 브랜치 재구성
- [ ] **딥링크 전수 점검**: FCM `/resolution/:id`·모든 `context.go`/`context.push` 경로가 새 인덱스에서 정상 동작
- [x] **온보딩**: 가입 완료 후 `selectedCharacter == null`이면 go_router `redirect` → `/onboarding/character`
      → **캐릭터 선택 캐러셀**(아래 참조) → "선택" → `PUT /characters/me/selection`
- [ ] **캐릭터 홈(몰입형 풀스크린 "내 방")**: 상단 반투명 상태바(코인·보상 알림 배지 — ⚠️ Lv·성장 게이지는 폐기) / 중앙 대형 캐릭터(idle) /
      주변 **소품 4슬롯 진열** / 배경은 착용 `BACKGROUND` / 하단 플로팅 패널(**"오늘 기록하기" 주 CTA** + 옷장·미션. 별도 상점 버튼 없음)
- [x] **★ `character_stage.dart`** — `USE_RIVE` dart-define 스위치. `kIsWeb`이면 무조건 비-Rive 경로
- [ ] **★ `placeholder_character_view.dart`** — PNG Stack 합성, `render_meta`의 `anchorX`/`anchorY`/`scale`/`z`로 아이템 배치
      → **대신 `idle_character_view.dart`(메시 워프)를 구현했다**(아래 "변경 사항 요약" 참조). 아이템 합성 배치는 홈과 함께 미구현
- [ ] **색 역할 준수**: `primary`=선택/CTA, **`accent`는 AI 전용이므로 미사용**(⚠️ `success`=성장 게이지 역할은 게이지 폐기로 사라짐). 코인은 신규 `currency`(골드)
      → `currency` 토큰은 **코인 UI(상태바·옷장 구매 시트)가 생길 때** 추가한다. 지금은 코인을 그리는 화면이 없다

## 수락 기준

- [ ] 탭 5개 정상 동작 + **캘린더 index 이동에 따른 회귀 0건**(FCM 딥링크 포함)
- [x] 캐릭터 미선택 사용자는 온보딩으로 리다이렉트, 선택 후 홈 진입 / 재진입 시 리다이렉트 없음
- [ ] 캐릭터 홈이 착용 아이템·배경·소품을 `render_meta` 좌표대로 렌더(플레이스홀더)
- [ ] 상태바가 코인 잔액·미확인 보상 수를 바인딩 (⚠️ Lv·성장 게이지는 폐기)
- [x] `USE_RIVE=false`(기본)·`kIsWeb`에서 비-Rive 경로로 동작
- [ ] `flutter analyze` 무경고 + `flutter test` 전체 통과(**탭 인덱스 회귀 테스트 포함**)
      → **analyze 무경고 · `flutter test` 112개 통과**는 달성. 다만 **탭 인덱스 회귀 테스트가 없으므로**(탭 재편 미착수) 미충족 처리

## 구현 단계

1. [x] `features/character/domain` 모델 + abstract Repository 작성
2. [x] `data/`(Api/Fake impl + dto) + `character_providers.dart`
3. [ ] **탭 재편** + `/onboarding/character` 라우트 + redirect 가드 → **라우트·가드만 완료, 탭 재편 미착수**
4. [ ] **딥링크·라우트 전수 점검**(FCM `/resolution/:id` 포함) 및 회귀 테스트 선작성
5. [x] 렌더러 + `character_stage.dart`(스위치) — 플레이스홀더 대신 **`idle_character_view.dart`(메시 워프)**
6. [ ] `character_home_page.dart`(상태바·소품 진열·하단 액션) + `character_onboarding_page.dart`
      → **온보딩만 완료**, 홈 미착수
7. [ ] `AppColors.currency` 토큰 추가
8. [x] `flutter analyze` → `flutter test` 실행(현 범위 전체 통과)

## 테스트 체크리스트 (`flutter test`)

### ★ 탭 인덱스 회귀 (최우선) — **미착수(탭 재편과 동시 수행)**
- [ ] 탭 5개가 `[캐릭터][캘린더][작심삼일][피드][프로필]` 순서로 렌더
- [ ] 각 탭 탭핑 → 해당 브랜치 라우트 정상 진입(캘린더가 **index 1**)
- [ ] **FCM 딥링크 `/resolution/:id`** — 알림 탭 시 작심삼일 상세로 정상 이동(인덱스 변경 무관)
- [ ] 기존 `context.go` 경로(`/profile`, `/friends`, `/feed/diary/:id`, `/resolution/:id/edit` 등) **전수 정상 이동**
- [ ] 탭 전환 후 상태 보존(`indexedStack`) 유지

> 현재는 대신 **`character_onboarding_redirect_test.dart`에 "기존 탭 브랜치 순서 회귀 없음(캘린더 index 0 유지)" 가드**를 걸어,
> 탭 순서가 **모르는 사이에 바뀌는 것**을 막아 두었다. 탭 재편 시 이 가드가 실패하면서 전수 점검을 강제한다.

### 온보딩
- [x] `selectedCharacter == null` → `/onboarding/character` **리다이렉트**
- [x] 미선택 + 이미 온보딩 → 리다이렉트 없음(**루프 방지**)
- [x] 선택 완료 후 앱 재진입 시 **리다이렉트 없음** / 온보딩 재진입 시 메인으로
- [x] 판단 불가(미인증·로딩·에러) → 분기 보류(`null` 반환 — 성급한 이동 금지)
- [x] 캐릭터 2종 카드 렌더(이름) + 헤드라인 노출 / **tagline 미노출**
- [x] 캐러셀 전환 3수단 — **스와이프 / 옆 카드 탭 / 도트 탭** → 활성 도트 이동
- [x] "선택" 탭 → `PUT /characters/me/selection`(중앙 카드 코드)  호출 후 `/`로 이동
- [x] 선택 API 실패 시 **에러 스낵바 + 온보딩 유지**(홈으로 새지 않음)
- [x] 로딩 상태 → `LoadingView` / 목록 조회 실패 → `ErrorView`
- [x] `IdleCharacterView`가 애니메이션 정지 상태에서 예외 없이 렌더

### 캐릭터 홈 / 플레이스홀더 — **미착수**
- [ ] **플레이스홀더가 `render_meta`(anchorX·anchorY·scale·z) 좌표대로 아이템 렌더**
- [ ] `z` 순서대로 레이어 겹침(배경 → 캐릭터 → 의상 → 모자/안경 → 손 소품)
- [ ] **미착용 슬롯은 렌더 생략**(빈 이미지 요청 없음)
- [ ] `ROOM_PROP` 다중 진열(0~5) 렌더
- [ ] 상태바 코인 잔액·미확인 보상 배지 바인딩 (⚠️ Lv·성장 게이지(`expRatio`)는 폐기)
- [ ] 하단 "오늘 기록하기" CTA → 에디터 이동
- [x] `kIsWeb`·`USE_RIVE=false`에서 비-Rive 경로 선택 확인

### 에러/엣지
- [x] 로딩 상태 / API 오류 상태 렌더(온보딩)
- [ ] 착용 아이템 0개(맨몸) 상태 렌더 / variant 이미지 로드 실패 시 해당 슬롯만 생략 — **홈과 함께**
- [x] `flutter analyze` 무경고

## 변경 사항 요약

### 완료 범위 — 데이터 계층 + 온보딩 선택창 + 렌더러 스위치

- **데이터 계층**: `CharacterRepository`(abstract) → `ApiCharacterRepository`(Dio) / `FakeCharacterRepository` + Riverpod providers. 기존 feature 컨벤션 그대로.
- **라우팅**: `/onboarding/character` 라우트 + **`characterOnboardingRedirect` 가드**.
  가드는 **순수 함수**(async 호출 없음)로 뽑았다 — go_router의 `redirect`는 라우팅마다 동기로 불리므로, 여기서 네트워크를 타면 **매 전환이 대기**하고 리다이렉트 **루프**를 만들기 쉽다. 상태를 인자로 받아 판정만 하고, "판단 불가"(미인증·로딩·에러)면 `null`을 반환해 **분기를 보류**한다.
- **온보딩 화면**: `PageView`(`viewportFraction: 0.78`) **peek 캐러셀** — 양옆 카드가 살짝 보인다. 페이지 도트 + 하단 "선택" CTA. 전환 수단 3가지(드래그 · 옆 카드 탭 · 도트 탭).
- **`CharacterStage`**: `USE_RIVE` dart-define 스위치. **`kIsWeb`이면 항상 비-Rive**. Rive 드롭인 지점은 주석으로 준비(Task 031).

### 설계 문서와 달라진 점 (의도적)

| 항목 | 원안 | 실제 | 이유 |
|---|---|---|---|
| 온보딩 레이아웃 | **좌우 2장 대형 비교** | **peek 캐러셀** | 사용자 요청. 캐릭터가 늘어나도 레이아웃이 그대로 확장된다(2장 고정 비교는 3종부터 깨진다) |
| 헤드라인 | "이 친구와 시작하기" CTA | "기억을 같이 만들어갈 / 친구를 선택해주세요." + **"선택"** CTA | — |
| tagline | 성격 소개 문구 노출 | **렌더하지 않음** | 카드가 이미지 중심이라 문구가 시각적 소음이 됐다 |
| 대체 렌더러 | `PlaceholderCharacterView`(PNG Stack) | **`IdleCharacterView`(메시 워프)** | 아래 참조 |

### `_AppScrollBehavior` — 웹에서 캐러셀이 안 끌리던 문제

Flutter 기본 `MaterialScrollBehavior`는 `dragDevices`에서 **마우스를 제외**한다(데스크톱에선 스크롤바를 쓰라는 전제).
그래서 웹에서 `PageView`를 **마우스로 드래그해도 아무 일도 일어나지 않았다**. `app.dart`에 `_AppScrollBehavior`를 두어 `PointerDeviceKind.mouse`를 추가했다.

### 미착수 — 탭 재편과 캐릭터 홈

- **탭 재편을 하지 않았다.** 하단 탭은 여전히 `[캘린더][목록][작심삼일][피드]` **4개**, **캘린더 index 0 유지**.
  캘린더를 index 1로 미는 순간 **FCM 딥링크(`/resolution/:id`)를 포함한 모든 `context.go` 경로가 회귀 후보**가 되므로, 이를 **캐릭터 홈 구현과 한 덩어리로 묶어** 별도 작업으로 미뤘다. 대신 리다이렉트 테스트에 **현재 브랜치 순서를 못박는 가드**를 넣어 두었다.
- **캐릭터 홈(1번 탭) 미구현** — `placeholder_character_view.dart`(PNG Stack·`render_meta` 배치)·상태바·소품 진열·하단 액션 전부 미착수.
- **`AppColors.currency` 토큰 미추가** — 코인을 그리는 화면이 아직 없다.

### 검증

- `flutter analyze` **무경고**, `flutter test` **112개 통과**.
