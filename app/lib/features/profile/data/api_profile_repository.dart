import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/error/failure.dart';
import '../../../shared/models/api_response.dart';
import '../../../shared/models/user.dart';
import '../domain/profile_repository.dart';
import 'dto/update_profile_request.dart';

/// Dio 기반 프로필 저장소. 표준 응답 래퍼(`ApiResponse<User>`)를 언랩한다.
///
/// Dio baseUrl이 `/api/v1`을 포함하므로 경로는 `/users/me`만 쓴다.
/// 인증 토큰은 [AuthInterceptor]가 Supabase 세션에서 자동 첨부한다.
class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository(this._dio);

  final Dio _dio;

  @override
  Future<User> getMe() async {
    final res = await _dio.get('/users/me');
    return _unwrapUser(res.data);
  }

  @override
  Future<User> updateMe(UpdateProfileRequest request) async {
    final res = await _dio.put('/users/me', data: request.toJson());
    return _unwrapUser(res.data);
  }

  @override
  Future<User> uploadAvatar(Uint8List bytes, String filename) async {
    // multipart part 이름은 백엔드 @RequestPart("file")과 일치해야 한다.
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = await _dio.post('/users/me/avatar', data: form);
    return _unwrapUser(res.data);
  }

  /// 표준 응답 봉투에서 [User]를 꺼낸다. 실패면 [Failure]로 변환해 던진다.
  User _unwrapUser(Object? body) {
    if (body is! Map<String, dynamic>) {
      throw const Failure('PARSE_ERROR', '서버 응답을 해석하지 못했어요.');
    }
    final api = ApiResponse<User>.fromJson(
      body,
      (json) => User.fromJson(json as Map<String, dynamic>),
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
