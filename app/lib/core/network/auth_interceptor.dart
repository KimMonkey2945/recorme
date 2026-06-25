import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 모든 요청에 현재 Supabase 세션의 access token을 Authorization 헤더로 첨부한다.
///
/// 세션 저장·자동 갱신은 supabase_flutter SDK가 담당하므로, 여기서는 매 요청 시
/// 최신 access token을 읽어 붙이기만 한다(만료 임박 시 SDK가 갱신해 둔 값).
/// 401 발생 시 별도 refresh 로직은 두지 않는다 — 갱신 불가 상태면 SDK가
/// 세션을 비우고 `onAuthStateChange`가 라우터 가드를 로그인 화면으로 보낸다.
class AuthInterceptor extends QueuedInterceptorsWrapper {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
