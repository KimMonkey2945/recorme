import '../../character/domain/equipment_item.dart';
import '../../character/domain/my_character.dart';
import '../../diary/data/dto/diary_dto.dart';

/// 친구의 캐릭터 홈 데이터(`GET /friends/{uuid}/character`).
///
/// [MyCharacter]와 달리 **코인 잔액·미확인 보상이 없다** — 서버가 아예 내려주지 않는다.
/// 남의 지갑은 남의 것이므로 타입에서부터 뺐다.
class FriendCharacter {
  const FriendCharacter({this.character, this.equipment = const []});

  /// 친구가 선택한 캐릭터. **null이면 아직 캐릭터를 고르지 않은 것**(에러 아님).
  final SelectedCharacter? character;

  /// 착용 중인 아이템(z순 오버레이 렌더용).
  final List<EquipmentItem> equipment;
}

/// 친구 캘린더의 하루(`GET /friends/{uuid}/diaries/summary`).
///
/// 본인용 [DiarySummaryDay]에 [diaryId]가 더해진 형태다. 본인 캘린더는 날짜를 탭할 때
/// `getByDate`로 id를 다시 조회하지만 그 API는 본인 전용이라, 친구 캘린더는 여기 실린 id로
/// 곧장 `/feed/diary/:id`(viewer-aware 상세)로 이동한다.
///
/// 공개 기록(FRIENDS·PUBLIC)만 내려오므로, PRIVATE 기록이 있는 날은 이 목록에 없다
/// = 앱에서는 기록이 없는 날과 구분되지 않는다.
class FriendDiaryDay {
  const FriendDiaryDay({required this.diaryId, required this.summary});

  final int diaryId;

  /// 캘린더 렌더용 요약. 기존 [CalendarMonthView]가 이 타입을 그대로 받으므로 위젯 수정이 없다.
  final DiarySummaryDay summary;

  /// 'yyyy-MM-dd' 문자열.
  String get date => summary.date;
}
