# Task 003 — 앱 feature-first 골격 및 라우팅 구성

- **Phase**: 1 (애플리케이션 골격 구축)
- **구현 기능**: 전 화면 골격
- **상태**: 구현 완료 / 검증(analyze) 진행

## 개요

Flutter 앱을 feature-first 구조로 정리하고, go_router 기반 5화면 골격과 하단 탭 셸, 인증 가드를 구성한다.
카운터 스캐폴드를 제거하고 `ProviderScope` + `MaterialApp.router` 진입 구조로 전환한다.

## 관련 파일

- `app/pubspec.yaml` — flutter_riverpod, go_router, dio, freezed/json, flutter_secure_storage, kakao/google 의존성
- `lib/main.dart` — `ProviderScope` 진입점
- `lib/app.dart` — `MaterialApp.router` + 전역 테마
- `lib/core/theme/app_theme.dart` — 전역 테마
- `lib/core/router/app_router.dart` — go_router(5화면 + StatefulShellRoute + 인증 redirect)
- `lib/core/router/scaffold_with_nav_bar.dart` — 하단 탭(캘린더/목록) 셸
- `lib/features/auth/presentation/login_page.dart`
- `lib/features/auth/presentation/providers/auth_provider.dart` — AuthStatus Notifier(가드 연동)
- `lib/features/diary/presentation/{main_calendar_page, diary_list_page, diary_editor_page, diary_detail_page}.dart`

## 수락 기준

- [x] `core/`, `features/`, `shared/` 폴더 구조 확립, 카운터 스캐폴드 제거
- [x] 의존성 추가(riverpod/go_router/dio/freezed/json/secure_storage/kakao/google)
- [x] go_router 5화면 골격(로그인/메인/에디터/목록/상세)
- [x] 인증 상태 기반 리디렉션 가드 골격(토큰 유무 → 로그인/메인)
- [x] 하단 내비게이션 바(캘린더/목록) ShellRoute 골격
- [x] `flutter analyze` 무경고 (No issues found!)

## 구현 단계

1. [x] `flutter pub add`로 런타임 의존성 추가(버전 자동 해결)
2. [x] feature-first 폴더 정리 + 카운터 제거 + main/app 진입 구조
3. [x] go_router(StatefulShellRoute.indexedStack) + 인증 redirect 가드
4. [x] 5화면 placeholder + 하단 탭 셸
5. [x] `flutter analyze` 통과 확인 (No issues found!)

## 변경 사항 요약

- 버전 메모: Riverpod 3.3.2(Notifier API), go_router 17.3.0(StatefulShellRoute), freezed 3.x(abstract class) 채택.
- 인증 가드는 `authControllerProvider`(AuthStatus) 기반, go_router `refreshListenable`로 상태 변경 시 재평가.
- 임시 로그인 버튼(`debugSignIn`)으로 백엔드 없이 로그인→메인→작성/목록/상세 플로우 체험 가능(Phase 3에서 실제 소셜 로그인으로 교체).
