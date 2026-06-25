import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';
import 'auth_interceptor.dart';

/// 공통 BaseOptions + AuthInterceptor가 적용된 Dio 인스턴스를 생성한다.
///
/// 인증 토큰은 [AuthInterceptor]가 Supabase 세션에서 직접 읽어 첨부하므로
/// 별도 토큰 저장소 주입이 필요 없다.
Dio createDio() {
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      contentType: 'application/json',
    ),
  );
  dio.interceptors.add(AuthInterceptor());
  return dio;
}

final dioProvider = Provider<Dio>((ref) => createDio());
