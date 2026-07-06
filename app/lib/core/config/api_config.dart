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

  /// 서버가 돌려준 이미지 경로를 화면에서 쓸 절대 URL로 변환한다.
  ///
  /// - null/빈 값 → null(표시 안 함)
  /// - http(s)로 시작(외부 소셜 이미지) → 그대로
  /// - 그 외(내부 업로드 상대경로 `/files/...`) → `apiBaseUrl`(호스트+/api/v1)에 결합
  ///   백엔드 정적 서빙이 `/api/v1/files/...`이므로 컨텍스트 경로를 포함한 apiBaseUrl과 맞물린다.
  static String? resolveImageUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$apiBaseUrl$path';
  }

  /// 공유 링크 절대 URL. 링크 소지자는 GET /diaries/shared/{shareToken}로 단건 조회한다.
  static String sharedUrl(String shareToken) => '$apiBaseUrl/diaries/shared/$shareToken';
}
