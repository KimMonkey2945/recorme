import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/error/failure.dart';
import '../../../shared/models/api_response.dart';
import '../../../shared/models/cursor_page.dart';
import '../domain/diary_repository.dart';
import 'dto/diary_dto.dart';

/// Dio 기반 기록 저장소. 표준 응답 래퍼(`{success, data, error}`)를 언랩한다.
///
/// Dio baseUrl이 `/api/v1`을 포함하므로 경로는 `/diaries...`만 쓴다.
/// 인증 토큰은 [AuthInterceptor]가 Supabase 세션에서 자동 첨부한다.
/// [ApiProfileRepository] 스타일을 미러링한다.
class ApiDiaryRepository implements DiaryRepository {
  ApiDiaryRepository(this._dio);

  final Dio _dio;

  @override
  Future<DiarySummary> getMonthlySummary(String yearMonth) async {
    try {
      final res = await _dio.get(
        '/diaries/me/summary',
        queryParameters: {'yearMonth': yearMonth},
      );
      return _unwrap(
        res.data,
        (json) => DiarySummary.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<Diary?> getByDate(DateTime date) async {
    try {
      final res = await _dio.get('/diaries/by-date/${_yyyyMMdd(date)}');
      return _unwrap(
        res.data,
        (json) => Diary.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      // 해당 날짜 기록이 없으면 404(DIARY_NOT_FOUND) → null로 매핑.
      if (e.response?.statusCode == 404) return null;
      throw _toFailure(e);
    }
  }

  @override
  Future<Diary> getById(int id) async {
    try {
      final res = await _dio.get('/diaries/$id');
      return _unwrap(
        res.data,
        (json) => Diary.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<CursorPage<Diary>> getList({int? cursor, int size = 20}) async {
    try {
      final res = await _dio.get(
        '/diaries/me',
        queryParameters: {
          'cursor': ?cursor,
          'size': size,
        },
      );
      // 목록 아이템(DiaryListItem)에는 visibility/shareToken이 없지만
      // Diary.fromJson이 tolerant하게 기본값 처리한다.
      return _unwrap(
        res.data,
        (json) => CursorPage<Diary>.fromJson(
          json as Map<String, dynamic>,
          (e) => Diary.fromJson(e as Map<String, dynamic>),
        ),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<List<Diary>> getMonthList(String yearMonth) async {
    try {
      final res = await _dio.get(
        '/diaries/me',
        queryParameters: {'yearMonth': yearMonth},
      );
      // 월 목록 data는 DiaryListItem 배열(visibility/shareToken 없음 → Diary.fromJson tolerant).
      return _unwrap(
        res.data,
        (json) => (json as List<dynamic>)
            .map((e) => Diary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<Diary> upsert({
    required DateTime date,
    required String content,
    required String contentText,
    bool confirm = false,
    String visibility = 'PRIVATE',
  }) async {
    try {
      // 신규 201 / 갱신 200 모두 success=true라 동일하게 처리한다.
      // confirm=false → DRAFT(분석 없음), confirm=true → PENDING(AI 분석 요청).
      final res = await _dio.post(
        '/diaries',
        data: {
          'content': content,
          'contentText': contentText,
          'writtenDate': _yyyyMMdd(date),
          'confirm': confirm,
          'visibility': visibility,
        },
      );
      return _unwrap(
        res.data,
        (json) => Diary.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      // 이미 확정된 기록을 다시 upsert하면 409 → 스낵바 안내용 Failure로 변환.
      if (e.response?.statusCode == 409) {
        final body = e.response?.data;
        if (body is Map<String, dynamic>) {
          final error = body['error'];
          if (error is Map<String, dynamic>) {
            throw Failure(
              error['code'] as String? ?? 'DIARY_ALREADY_CONFIRMED',
              error['message'] as String? ?? '이미 기억한 일기는 수정할 수 없어요.',
            );
          }
        }
        throw const Failure(
          'DIARY_ALREADY_CONFIRMED',
          '이미 기억한 일기는 수정할 수 없어요.',
        );
      }
      throw _toFailure(e);
    }
  }

  @override
  Future<Diary> changeVisibility(int id, String visibility) async {
    try {
      final res = await _dio.patch(
        '/diaries/$id/visibility',
        data: {'visibility': visibility},
      );
      return _unwrap(
        res.data,
        (json) => Diary.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<void> delete(int id) async {
    try {
      final res = await _dio.delete('/diaries/$id');
      _unwrapVoid(res.data);
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<String> uploadImage(Uint8List bytes, String filename) async {
    try {
      // 본문 인라인 이미지 1장 업로드(part명 "file"). 응답 data: { url }.
      final form = FormData();
      form.files.add(
        MapEntry('file', MultipartFile.fromBytes(bytes, filename: filename)),
      );
      final res = await _dio.post('/diaries/images', data: form);
      return _unwrap(
        res.data,
        (json) => (json as Map<String, dynamic>)['url'] as String,
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  // ── 유틸 ────────────────────────────────────────────────────

  /// 날짜를 'yyyy-MM-dd'(zero-pad)로 변환한다. 시간 정보는 버린다.
  String _yyyyMMdd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 표준 응답 봉투에서 데이터를 꺼낸다. 실패면 [Failure]로 변환해 던진다.
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

  /// data가 없는 응답(`ApiResponse<Void>`)의 성공 여부만 확인한다.
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

  /// DioException을 도메인 [Failure]로 변환한다.
  /// 가능하면 응답 바디의 error.code/message를 추출한다.
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
    return Failure(
      'NETWORK_ERROR',
      e.message ?? '네트워크 오류가 발생했어요.',
    );
  }
}
