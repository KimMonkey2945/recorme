# Task 004 — 앱 모델·DTO 및 네트워크 골격

- **Phase**: 1 (애플리케이션 골격 구축)
- **구현 기능**: F001~F007 공통 토대
- **상태**: 구현 완료 / analyze·test 검증

## 개요

api-contract와 1:1로 매핑되는 모델/DTO, Dio 클라이언트 + AuthInterceptor 골격, secure storage 추상화,
Riverpod provider 골격을 배치한다.

## 관련 파일

- `lib/shared/models/api_response.dart` — `ApiResponse<T>`(제네릭 envelope, 수동 fromJson) + `ApiError`
- `lib/shared/models/cursor_page.dart` — `CursorPage<T>`(items/nextCursor/hasNext)
- `lib/shared/models/user.dart` — `User`
- `lib/features/auth/data/dto/token_response.dart` — `TokenResponse`
- `lib/features/diary/data/dto/diary_dto.dart` — `Diary`, `DiarySummary`
- `lib/core/error/failure.dart` — `Failure`
- `lib/core/network/dio_client.dart` — Dio 인스턴스 + `dioProvider`
- `lib/core/network/auth_interceptor.dart` — Authorization 주입, 401→refresh 자리(`QueuedInterceptorsWrapper`)
- `lib/core/storage/secure_storage.dart` — `TokenStorage` + `secureStorageProvider`/`tokenStorageProvider`
- `lib/core/config/api_config.dart` — 베이스 URL/`/api/v1` prefix(`--dart-define` 주입)
- `lib/features/auth/presentation/providers/auth_provider.dart` — `authControllerProvider`(Task 003과 공유)
- `test/models_test.dart` — 모델 파싱 단위 테스트

## 수락 기준

- [x] 모델: ApiResponse 래퍼, 커서 페이지, User, Diary, DiarySummary, TokenResponse
- [x] Dio 클라이언트 골격 + AuthInterceptor 골격(Authorization, 401 refresh 자리, QueuedInterceptorsWrapper)
- [x] flutter_secure_storage 기반 토큰 저장소 추상화
- [x] Riverpod provider 골격(인증 상태, Dio, secure storage)
- [x] `flutter analyze` 무경고 (No issues found!) + 모델 단위 테스트 3/3 통과

## 구현 단계

1. [x] 모델/DTO 작성(api-contract 1:1)
2. [x] 네트워크(Dio/Interceptor) + secure storage + provider
3. [x] 모델 파싱 단위 테스트
4. [x] `flutter analyze` + `flutter test` 통과 확인 (analyze 0건, test 3/3)

## 테스트 체크리스트

- [x] ApiResponse: 성공 응답 data 변환기 파싱 / 실패 응답 error 파싱
- [x] CursorPage: items/nextCursor/hasNext 파싱

## 변경 사항 요약 — ⚠️ 설계 편차(중요)

- **freezed/json_serializable 코드 생성 보류**: 현재 Flutter SDK(Dart 3.10)에서 `flutter_test`가
  analyzer 8.x를 고정 → `build_runner`가 2.15.0까지만 해결됨. 이 버전은 네이티브 빌드 훅을 가진
  의존성(`google_sign_in_ios`의 `objective_c`, `kakao_flutter_sdk`의 `jni`)과 결합 시
  `dart compile`이 "does not support build hooks" 오류로 빌드 스크립트 AOT 컴파일에 실패한다.
- **대응**: 모델을 손 작성 불변 클래스(fromJson/toJson/==/copyWith)로 작성하고, 미사용 코드 생성
  의존성(freezed/json_serializable/build_runner/freezed_annotation/json_annotation)을 제거.
- **재검토 지점**: Phase 3에서 SDK 업그레이드 또는 패키지 버전 정합 후 freezed 코드 생성 재도입 검토.
  docs/mobile.md의 freezed 권장 방침과의 편차이므로 사용자 확인 필요.
