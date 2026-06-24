import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';
import '../storage/secure_storage.dart';
import 'auth_interceptor.dart';

/// 공통 BaseOptions + AuthInterceptor가 적용된 Dio 인스턴스를 생성한다.
Dio createDio(TokenStorage tokenStorage) {
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      contentType: 'application/json',
    ),
  );
  dio.interceptors.add(AuthInterceptor(tokenStorage));
  return dio;
}

final dioProvider = Provider<Dio>(
  (ref) => createDio(ref.watch(tokenStorageProvider)),
);
