import 'package:dio/dio.dart';

import '../storage/secure_storage.dart';

/// access 토큰 첨부 + 401 시 refresh 자동 갱신 골격.
///
/// `QueuedInterceptorsWrapper`는 동시에 발생한 401을 직렬화해,
/// refresh가 한 번만 일어나도록 한다. 실제 refresh 호출/원요청 재시도 로직은
/// Phase 3(Task 010)에서 완성한다.
class AuthInterceptor extends QueuedInterceptorsWrapper {
  AuthInterceptor(this._tokenStorage);

  final TokenStorage _tokenStorage;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokenStorage.readAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      // TODO(Task 010): POST /auth/refresh 로 access 갱신 후 원요청 재시도.
      //  - refresh 성공: 새 access 저장 → 원요청 재시도(resolve)
      //  - refresh 실패: 토큰 삭제 → 로그인 화면 강제 이동
    }
    handler.next(err);
  }
}
