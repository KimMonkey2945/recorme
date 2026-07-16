import 'package:dio/dio.dart';

import '../../../core/error/failure.dart';
import '../../../shared/models/api_response.dart';
import '../../../shared/models/cursor_page.dart';
import '../domain/character.dart';
import '../domain/character_repository.dart';
import '../domain/item_group.dart';
import '../domain/my_character.dart';
import '../domain/reward.dart';
import 'dto/character_dto.dart';

/// Dio 기반 캐릭터 저장소. 표준 응답 래퍼(`{success, data, error}`)를 언랩한다.
///
/// Dio baseUrl이 `/api/v1`을 포함하므로 경로는 `/characters...`만 쓴다.
/// 인증 토큰은 [AuthInterceptor]가 Supabase 세션에서 자동 첨부한다.
/// [ApiResolutionRepository] 스타일을 미러링한다.
class ApiCharacterRepository implements CharacterRepository {
  ApiCharacterRepository(this._dio);

  final Dio _dio;

  @override
  Future<CharacterList> fetchCharacters() async {
    try {
      final res = await _dio.get('/characters');
      return _unwrap(
        res.data,
        (json) => CharacterDto.listFromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<MyCharacter> fetchMyCharacter() async {
    try {
      // 미선택자도 200 + character:null로 응답한다(404가 아니다).
      final res = await _dio.get('/characters/me');
      return _unwrap(
        res.data,
        (json) => CharacterDto.myCharacterFromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<MyCharacter> selectCharacter(String code) async {
    try {
      final res = await _dio.put(
        '/characters/me/selection',
        data: CharacterDto.selectionRequest(code),
      );
      return _unwrap(
        res.data,
        (json) => CharacterDto.myCharacterFromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      // 미보유 캐릭터 선택 시 CHARACTER_NOT_OWNED가 error.code로 내려온다.
      throw _toFailure(e);
    }
  }

  @override
  Future<List<ItemGroup>> fetchItems({String? slot}) async {
    try {
      final res = await _dio.get(
        '/characters/items',
        queryParameters: {'slot': ?slot},
      );
      return _unwrap(
        res.data,
        (json) => CharacterDto.itemGroupsFromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<MyCharacter> replaceEquipment(
      List<EquipmentSelection> equipment) async {
    try {
      final res = await _dio.put(
        '/characters/me/equipment',
        data: CharacterDto.equipmentRequest(equipment),
      );
      return _unwrap(
        res.data,
        (json) => CharacterDto.myCharacterFromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      // 미보유면 ITEM_NOT_OWNED, 캐릭터용 variant 미제작이면 ITEM_VARIANT_MISSING.
      throw _toFailure(e);
    }
  }

  @override
  Future<CursorPage<Reward>> fetchRewards({int? cursor, int? size}) async {
    try {
      final res = await _dio.get(
        '/characters/me/rewards',
        queryParameters: {'cursor': ?cursor, 'size': ?size},
      );
      return _unwrap(
        res.data,
        (json) => CharacterDto.rewardsPageFromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<int> ackRewards() async {
    try {
      final res = await _dio.post('/characters/me/rewards/ack');
      return _unwrap(
        res.data,
        (json) => ((json as Map<String, dynamic>)['acked'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<AttendanceResult> markAttendance() async {
    try {
      final res = await _dio.post('/characters/me/attendance');
      return _unwrap(
        res.data,
        (json) => CharacterDto.attendanceFromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      throw _toFailure(e);
    }
  }

  @override
  Future<MyCharacter> purchaseItem(String groupCode) async {
    try {
      final res = await _dio.post('/characters/items/$groupCode/purchase');
      return _unwrap(
        res.data,
        (json) => CharacterDto.myCharacterFromJson(json as Map<String, dynamic>),
      );
    } on DioException catch (e) {
      // 잔액 부족이면 COIN_INSUFFICIENT, 게이팅 off 면 FEATURE_DISABLED 가 error.code 로 내려온다.
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

  /// DioException을 도메인 [Failure]로 변환한다.
  /// 가능하면 응답 바디의 error.code/message(CHARACTER_NOT_OWNED 등)를 추출한다.
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
