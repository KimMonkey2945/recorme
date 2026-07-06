import 'package:dio/dio.dart';

import '../../../core/error/failure.dart';
import '../../../shared/models/api_response.dart';
import '../../../shared/models/cursor_page.dart';
import '../domain/friend_repository.dart';
import 'dto/friend_dto.dart';

/// Dio 기반 친구 저장소. 표준 응답 래퍼(`{success, data, error}`)를 언랩한다.
/// Dio baseUrl이 `/api/v1`을 포함하므로 경로는 `/friends...`만 쓴다.
/// 인증 토큰은 [AuthInterceptor]가 Supabase 세션에서 자동 첨부한다.
class ApiFriendRepository implements FriendRepository {
  ApiFriendRepository(this._dio);

  final Dio _dio;

  @override
  Future<FriendRequestResult> requestByCode(String friendCode) =>
      _sendRequest({'friendCode': friendCode});

  @override
  Future<FriendRequestResult> requestByUuid(String targetUuid) =>
      _sendRequest({'targetUuid': targetUuid});

  Future<FriendRequestResult> _sendRequest(Map<String, dynamic> body) async {
    try {
      final res = await _dio.post('/friends/requests', data: body);
      return _unwrap(
        res.data,
        (json) => FriendRequestResult.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<void> accept(int requestId) async {
    try {
      final res = await _dio.post('/friends/requests/$requestId/accept');
      _unwrapVoid(res.data);
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<void> reject(int requestId) async {
    try {
      final res = await _dio.post('/friends/requests/$requestId/reject');
      _unwrapVoid(res.data);
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<CursorPage<Friend>> getFriends({int? cursor, int size = 20}) async {
    try {
      final res = await _dio.get(
        '/friends',
        queryParameters: {'cursor': ?cursor, 'size': size},
      );
      return _unwrap(
        res.data,
        (json) => CursorPage<Friend>.fromJson(
          json as Map<String, dynamic>,
          (e) => Friend.fromJson(e as Map<String, dynamic>),
        ),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<CursorPage<FriendRequest>> getRequests({
    String direction = 'incoming',
    int? cursor,
    int size = 20,
  }) async {
    try {
      final res = await _dio.get(
        '/friends/requests',
        queryParameters: {'direction': direction, 'cursor': ?cursor, 'size': size},
      );
      return _unwrap(
        res.data,
        (json) => CursorPage<FriendRequest>.fromJson(
          json as Map<String, dynamic>,
          (e) => FriendRequest.fromJson(e as Map<String, dynamic>),
        ),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<List<FriendSearchResult>> search(String query) async {
    try {
      final res = await _dio.get(
        '/friends/search',
        queryParameters: {'query': query},
      );
      return _unwrap(
        res.data,
        (json) => (json as List<dynamic>)
            .map((e) => FriendSearchResult.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<void> remove(String userUuid, {bool block = false}) async {
    try {
      final res = await _dio.delete(
        '/friends/$userUuid',
        queryParameters: {'block': block},
      );
      _unwrapVoid(res.data);
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  // ── 유틸(ApiDiaryRepository 미러링) ──────────────────────────

  T _unwrap<T>(Object? body, T Function(Object? json) fromJsonT) {
    if (body is! Map<String, dynamic>) {
      throw const Failure('PARSE_ERROR', '서버 응답을 해석하지 못했어요.');
    }
    final api = ApiResponse<T>.fromJson(body, fromJsonT);
    if (!api.success || api.data == null) {
      throw Failure(
        api.error?.code ?? 'UNKNOWN',
        api.error?.message ?? '요청을 처리하지 못했어요.',
      );
    }
    return api.data as T;
  }

  void _unwrapVoid(Object? body) {
    if (body is! Map<String, dynamic>) {
      throw const Failure('PARSE_ERROR', '서버 응답을 해석하지 못했어요.');
    }
    final success = body['success'] as bool? ?? false;
    if (!success) {
      final error = body['error'];
      if (error is Map<String, dynamic>) {
        throw Failure(
          error['code'] as String? ?? 'UNKNOWN',
          error['message'] as String? ?? '요청을 처리하지 못했어요.',
        );
      }
      throw const Failure('UNKNOWN', '요청을 처리하지 못했어요.');
    }
  }

  Failure _toFailure(DioException e) {
    final body = e.response?.data;
    if (body is Map<String, dynamic>) {
      final error = body['error'];
      if (error is Map<String, dynamic>) {
        return Failure(
          error['code'] as String? ?? 'NETWORK_ERROR',
          error['message'] as String? ?? '네트워크 오류가 발생했어요.',
        );
      }
    }
    return Failure('NETWORK_ERROR', e.message ?? '네트워크 오류가 발생했어요.');
  }
}
