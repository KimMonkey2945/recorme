/// API 기본 설정.
///
/// 백엔드 컨텍스트 경로는 `/api/v1`. 개발 시 베이스 URL은 실행 환경에 따라 다르다:
/// - Android 에뮬레이터: `http://10.0.2.2:8080`
/// - iOS 시뮬레이터/데스크톱: `http://localhost:8080`
/// 빌드 시 `--dart-define=API_BASE_URL=...` 로 주입할 수 있다.
class ApiConfig {
  ApiConfig._();

  static const String _defaultBaseUrl = 'http://10.0.2.2:8080';

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  /// 모든 엔드포인트 공통 prefix
  static const String apiPrefix = '/api/v1';

  static String get apiBaseUrl => '$baseUrl$apiPrefix';
}
