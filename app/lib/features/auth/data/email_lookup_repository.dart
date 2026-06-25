import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/network/dio_client.dart';
import '../../../shared/models/api_response.dart';

/// 백엔드 이메일 조회 저장소. 비밀번호 재설정 전 미가입 이메일을 사전 확인한다.
///
/// 비로그인 상태에서 호출되며(공개 엔드포인트), Dio baseUrl이 `/api/v1`을 포함하므로
/// 경로는 `/auth/email-exists`만 쓴다. [AuthInterceptor]는 세션이 없으면 토큰을 생략한다.
class EmailLookupRepository {
  EmailLookupRepository(this._dio);

  final Dio _dio;

  /// 해당 이메일로 가입한 활성 회원이 있는지 조회한다.
  Future<bool> emailExists(String email) async {
    final res = await _dio.get(
      '/auth/email-exists',
      queryParameters: {'email': email},
    );
    return _unwrapExists(res.data);
  }

  /// 표준 응답 봉투에서 `exists`를 꺼낸다. 실패면 [Failure]로 변환해 던진다.
  bool _unwrapExists(Object? body) {
    if (body is! Map<String, dynamic>) {
      throw const Failure('PARSE_ERROR', '서버 응답을 해석하지 못했어요.');
    }
    final api = ApiResponse<bool>.fromJson(
      body,
      (json) => (json! as Map<String, dynamic>)['exists'] as bool,
    );
    if (!api.success || api.data == null) {
      throw Failure(
        api.error?.code ?? 'UNKNOWN',
        api.error?.message ?? '요청을 처리하지 못했어요.',
      );
    }
    return api.data!;
  }
}

final emailLookupRepositoryProvider = Provider<EmailLookupRepository>(
  (ref) => EmailLookupRepository(ref.watch(dioProvider)),
);
