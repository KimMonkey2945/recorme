import 'package:dio/dio.dart';

import '../../../core/error/failure.dart';
import '../../../shared/models/api_response.dart';
import '../../../shared/models/cursor_page.dart';
import '../domain/feed_repository.dart';
import 'dto/feed_dto.dart';

/// Dio 기반 피드 저장소. 표준 응답 래퍼를 언랩한다(ApiDiaryRepository 미러링).
class ApiFeedRepository implements FeedRepository {
  ApiFeedRepository(this._dio);

  final Dio _dio;

  @override
  Future<CursorPage<FeedItem>> getFeed({int? cursor, int size = 20}) async {
    try {
      final res = await _dio.get(
        '/feed',
        queryParameters: {'cursor': ?cursor, 'size': size},
      );
      return _unwrap(
        res.data,
        (json) => CursorPage<FeedItem>.fromJson(
          json as Map<String, dynamic>,
          (e) => FeedItem.fromJson(e as Map<String, dynamic>),
        ),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<FeedDetail> getDetail(int id) async {
    try {
      final res = await _dio.get('/feed/$id');
      return _unwrap(
        res.data,
        (json) => FeedDetail.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<ReactionResult> react(int diaryId) => _reaction('POST', diaryId);

  @override
  Future<ReactionResult> unreact(int diaryId) => _reaction('DELETE', diaryId);

  /// 공감 자원(/diaries/{id}/reactions) POST/DELETE 공통 처리.
  Future<ReactionResult> _reaction(String method, int diaryId) async {
    try {
      final path = '/diaries/$diaryId/reactions';
      final res = method == 'POST'
          ? await _dio.post(path)
          : await _dio.delete(path);
      return _unwrap(
        res.data,
        (json) => ReactionResult.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

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
