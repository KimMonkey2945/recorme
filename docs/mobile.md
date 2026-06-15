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
│  └─ theme/       (app_theme.dart, diary_theme.dart, font_registry.dart)
├─ features/
│  ├─ auth/
│  │  ├─ data/      (auth_api.dart, auth_repository_impl.dart, dto/)
│  │  ├─ domain/    (auth_repository.dart, entities/, usecases/)
│  │  └─ presentation/ (login_page.dart, providers/auth_provider.dart)
│  ├─ diary/
│  │  ├─ data/      (diary_api.dart, diary_repository_impl.dart, dto/diary_dto.dart)
│  │  ├─ domain/    (diary.dart, diary_repository.dart)
│  │  └─ presentation/ (diary_write_page.dart, diary_detail_page.dart,
│  │                     widgets/diary_themed_view.dart, providers/)
│  ├─ feed/
│  └─ profile/
└─ shared/
   ├─ widgets/      (공용 위젯)
   └─ models/       (공통 모델, ApiResponse 래퍼)
```

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

- **Dio + 인터셉터**: `AuthInterceptor`(access 토큰 첨부, 401 시 refresh 회전 후 재시도), 공통 에러 매핑.
- 응답 표준 `ApiResponse<T>` 언랩 → 실패 시 `Failure`로 변환해 도메인 전달.
- **모델 직렬화**: `freezed` + `json_serializable`(불변·copyWith·동등성).
- 백엔드 응답 DTO와 앱 DTO는 1:1 매핑(→ [`api-contract.md`](./api-contract.md)).

## 6. 감정 테마/음악 동적 적용 전략

- 백엔드 `DiaryResponse`에 테마 스펙(`backgroundType`/`backgroundValue`, `fontFamily`, `textColor`)과 트랙(`streamUrl`/`sourceType`/`sourceRef`) 포함.
- 앱은 손글씨체 등 폰트를 `pubspec.yaml` assets로 번들하고, `font_registry`로 `fontFamily` 키 → 실제 폰트 매핑.
- `DiaryThemedView` 위젯이 테마 스펙을 받아 배경(Color/Gradient/Image) + `DefaultTextStyle`(font/color)로 래핑 → 조회 시 그날의 분위기 재현.
- 음악: `MusicPlayer`(`just_audio` 등)가 `sourceType`에 따라 재생 분기(LOCAL_FILE: URL 스트리밍 / 외부 API: 추후 SDK). 소스 추상화로 미정 상태 흡수.
- 테마 프리셋은 앱 시작 시 1회 캐시(선택). **폰트 라이선스(상용/임베딩) 사전 확인 필요.**

## 7. 권장 의존성 (구현 시)

| 용도 | 패키지 |
|---|---|
| 상태관리 | `flutter_riverpod`, `riverpod_generator` |
| 라우팅 | `go_router` |
| 네트워크 | `dio` |
| 직렬화/모델 | `freezed`, `json_serializable` |
| 보안 저장 | `flutter_secure_storage` |
| 음악 재생 | `just_audio` |
| 소셜 로그인 | `kakao_flutter_sdk`, `google_sign_in`, `sign_in_with_apple` |

> 실제 버전은 스캐폴딩 단계에서 `pubspec.yaml`에 확정한다.
