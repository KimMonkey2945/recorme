import 'package:dio/dio.dart';

import '../../../core/error/failure.dart';
import '../../../shared/models/api_response.dart';
import '../../../shared/models/cursor_page.dart';
import '../domain/resolution.dart';
import '../domain/resolution_repository.dart';
import 'dto/resolution_dto.dart';

/// Dio 기반 결심 저장소. 표준 응답 래퍼(`{success, data, error}`)를 언랩한다.
///
/// Dio baseUrl이 `/api/v1`을 포함하므로 경로는 `/resolutions...`만 쓴다.
/// 인증 토큰은 [AuthInterceptor]가 Supabase 세션에서 자동 첨부한다.
/// [ApiDiaryRepository] 스타일을 미러링한다.
class ApiResolutionRepository implements ResolutionRepository {
  ApiResolutionRepository(this._dio);

  final Dio _dio;

  @override
  Future<Resolution> create({
    required String title,
    required DateTime startDate,
    String? reminderTime,
  }) async {
    try {
      // 신규 리소스라 서버는 201로 응답하지만 success=true라 동일하게 처리한다.
      final res = await _dio.post(
        '/resolutions',
        data: ResolutionDto.createRequest(
          title: title,
          startDate: startDate,
          reminderTime: reminderTime,
        ),
      );
      return _unwrap(
        res.data,
        (json) => ResolutionDto.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<CursorPage<ResolutionSummaryItem>> getList(
    ResolutionStatus? status, {
    int? cursor,
    int size = 20,
  }) async {
    try {
      final res = await _dio.get(
        '/resolutions/me',
        queryParameters: {
          // unknown이면 apiValue가 null → 널-어웨어 엔트리로 자동 생략(필터 미적용).
          'status': ?status?.apiValue,
          'cursor': ?cursor,
          'size': size,
        },
      );
      return _unwrap(
        res.data,
        (json) => CursorPage<ResolutionSummaryItem>.fromJson(
          json as Map<String, dynamic>,
          (e) => ResolutionDto.summaryFromJson(e as Map<String, dynamic>),
        ),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<List<ResolutionCalendarDay>> getCalendar(String yearMonth) async {
    try {
      final res = await _dio.get(
        '/resolutions/me/calendar',
        queryParameters: {'yearMonth': yearMonth},
      );
      return _unwrap(
        res.data,
        (json) => (json as List<dynamic>)
            .map((e) => ResolutionDto.calendarDayFromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<Resolution> getById(int id) async {
    try {
      final res = await _dio.get('/resolutions/$id');
      return _unwrap(
        res.data,
        (json) => ResolutionDto.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      // 없는 결심(또는 남의 결심)이면 404 → 도메인 NOT_FOUND로 매핑.
      if (e.response?.statusCode == 404) {
        throw _toFailure(e, fallbackCode: 'RESOLUTION_NOT_FOUND');
      }
      throw _toFailure(e);
    }
  }

  @override
  Future<Resolution> completeToday(int id) async {
    try {
      final res = await _dio.post('/resolutions/$id/checks/today');
      return _unwrap(
        res.data,
        (json) => ResolutionDto.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      // 409: RESOLUTION_NOT_ACTIVE(진행 중 아님)/CHECK_NOT_TODAY(오늘 체크 없음) 등.
      throw _toFailure(e);
    }
  }

  @override
  Future<Resolution> extend(int id, {String? reminderTime}) async {
    try {
      final res = await _dio.post(
        '/resolutions/$id/extend',
        data: ResolutionDto.extendRequest(reminderTime: reminderTime),
      );
      return _unwrap(
        res.data,
        (json) => ResolutionDto.fromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      // 409: NOT_EXTENDABLE(성공 상태 아님)/ALREADY_EXTENDED(이미 연장됨) 등.
      throw _toFailure(e);
    }
  }

  @override
  Future<void> cancel(int id) async {
    try {
      final res = await _dio.delete('/resolutions/$id');
      _unwrapVoid(res.data);
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  // ── 유틸 ────────────────────────────────────────────────────

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
  /// 가능하면 응답 바디의 error.code/message(409의 RESOLUTION_NOT_ACTIVE·
  /// CHECK_NOT_TODAY·NOT_EXTENDABLE·ALREADY_EXTENDED, 404의 NOT_FOUND 등)를 추출한다.
  Failure _toFailure(DioException e, {String fallbackCode = 'NETWORK_ERROR'}) {
    final body = e.response?.data;
    if (body is Map<String, dynamic>) {
      final error = body['error'];
      if (error is Map<String, dynamic>) {
        return Failure(
          error['code'] as String? ?? fallbackCode,
          error['message'] as String? ?? '요청을 처리하지 못했어요.',
        );
      }
    }
    return Failure(
      fallbackCode,
      e.message ?? '네트워크 오류가 발생했어요.',
    );
  }
}
