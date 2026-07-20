import 'package:dio/dio.dart';

import '../../../core/error/failure.dart';
import '../../../shared/models/api_response.dart';
import '../../character/data/dto/character_dto.dart';
import '../../diary/data/dto/diary_dto.dart';
import '../../resolution/data/dto/resolution_dto.dart';
import '../../resolution/domain/resolution.dart';
import '../domain/friend_browse.dart';
import '../domain/friend_browse_repository.dart';

/// Dio 기반 친구 둘러보기 저장소. 표준 응답 래퍼(`{success, data, error}`)를 언랩한다.
/// Dio baseUrl이 `/api/v1`을 포함하므로 경로는 `/friends...`만 쓴다.
///
/// 응답 파싱은 기존 DTO 매퍼를 그대로 재사용한다 — 친구용 응답이 본인용과 같은 스키마이기 때문이다
/// (캐릭터·착용 아이템·작심삼일). 캘린더만 `diaryId`가 더 실려 있어 여기서 조립한다.
class ApiFriendBrowseRepository implements FriendBrowseRepository {
  ApiFriendBrowseRepository(this._dio);

  final Dio _dio;

  @override
  Future<FriendCharacter> getCharacter(String userUuid) async {
    try {
      final res = await _dio.get('/friends/$userUuid/character');
      return _unwrap(res.data, (json) {
        final map = json as Map<String, dynamic>;
        final rawCharacter = map['character'] as Map<String, dynamic>?;
        final rawEquipment = map['equipment'] as List<dynamic>? ?? const [];
        return FriendCharacter(
          character: rawCharacter == null
              ? null
              : CharacterDto.selectedCharacterFromJson(rawCharacter),
          equipment: rawEquipment
              .map((e) =>
                  CharacterDto.equipmentFromJson(e as Map<String, dynamic>))
              .toList(),
        );
      });
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<List<FriendDiaryDay>> getDiarySummary(
      String userUuid, String yearMonth) async {
    try {
      final res = await _dio.get(
        '/friends/$userUuid/diaries/summary',
        queryParameters: {'yearMonth': yearMonth},
      );
      return _unwrap(res.data, (json) {
        final days = (json as Map<String, dynamic>)['days'] as List<dynamic>? ??
            const [];
        return days.map((e) {
          final map = e as Map<String, dynamic>;
          return FriendDiaryDay(
            diaryId: (map['diaryId'] as num).toInt(),
            summary: DiarySummaryDay.fromJson(map),
          );
        }).toList();
      });
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<List<ResolutionSummaryItem>> getResolutions(
    String userUuid, {
    ResolutionStatus? status,
  }) async {
    try {
      final res = await _dio.get(
        '/friends/$userUuid/resolutions',
        queryParameters: {'status': ?status?.apiValue},
      );
      return _unwrap(res.data, (json) {
        final items =
            (json as Map<String, dynamic>)['items'] as List<dynamic>? ?? const [];
        return items
            .map((e) =>
                ResolutionDto.summaryFromJson(e as Map<String, dynamic>))
            .toList();
      });
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  // ── 유틸(ApiFriendRepository 미러링) ──────────────────────────

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
