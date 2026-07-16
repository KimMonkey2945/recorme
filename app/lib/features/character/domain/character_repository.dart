import '../../../shared/models/cursor_page.dart';
import 'character.dart';
import 'item_group.dart';
import 'my_character.dart';
import 'retrospect.dart';
import 'reward.dart';

/// 캐릭터 데이터 접근 추상화.
///
/// [FakeCharacterRepository]가 인메모리 더미로 구현하고, 실제 환경에서는
/// 동일 인터페이스의 [ApiCharacterRepository](실제 API)로 교체한다.
/// 메서드 시그니처는 백엔드 `CharacterController`의 엔드포인트와 1:1로 대응한다.
/// (경로는 dio baseUrl에 `/api/v1`이 포함되므로 `/characters...`만 쓴다.)
abstract class CharacterRepository {
  /// 선택 가능한 캐릭터 목록(+ 현재 선택 코드).
  /// GET /characters
  Future<CharacterList> fetchCharacters();

  /// 내 캐릭터 상태. **미선택자도 200이며 `character == null`로 내려온다**(404 아님).
  /// GET /characters/me
  Future<MyCharacter> fetchMyCharacter();

  /// 캐릭터 선택(온보딩 확정). 미보유 코드면 `CHARACTER_NOT_OWNED` 실패.
  /// PUT /characters/me/selection
  Future<MyCharacter> selectCharacter(String code);

  /// 아이템 그룹 목록(옷장·상점 공용). [slot] 지정 시 해당 슬롯만, 생략 시 전체.
  /// 이미지·renderMeta는 내 선택 캐릭터 기준으로 해석돼 내려온다.
  /// GET /characters/items?slot=
  Future<List<ItemGroup>> fetchItems({String? slot});

  /// 착용 배치 교체 — [equipment]가 착용 **전체 스냅샷**이다(빈 배열 = 전 슬롯 비움).
  /// 미보유 아이템이 섞이면 `ITEM_NOT_OWNED`(전체 롤백), variant 미제작이면
  /// `ITEM_VARIANT_MISSING`으로 실패한다.
  /// PUT /characters/me/equipment
  Future<MyCharacter> replaceEquipment(List<EquipmentSelection> equipment);

  /// 미확인 보상함(커서 페이징, 최신순). [cursor] 생략 시 첫 페이지.
  /// GET /characters/me/rewards?cursor=&size=
  Future<CursorPage<Reward>> fetchRewards({int? cursor, int? size});

  /// 미확인 보상 전체 확인(뱃지 리셋). 확인된 개수를 돌려준다.
  /// POST /characters/me/rewards/ack
  Future<int> ackRewards();

  /// 출석 적립(하루 1회). 이미 출석했으면 granted=false.
  /// POST /characters/me/attendance
  Future<AttendanceResult> markAttendance();

  /// 코인으로 아이템(group) 구매. 성공 시 갱신된 내 캐릭터(잔액·소유 반영).
  /// 잔액 부족이면 `COIN_INSUFFICIENT`, 구매 게이팅 off 면 `FEATURE_DISABLED`.
  /// POST /characters/items/{groupCode}/purchase
  Future<MyCharacter> purchaseItem(String groupCode);

  /// 확정 직후 리액션(대사·코인). **확정 즉시 생성되므로 폴링이 필요 없다.**
  /// 아직 적립 이벤트가 안 생겼으면 `null`(앱은 기본 대사로 대체하거나 오버레이를 생략).
  /// GET /characters/me/reaction?diaryId=
  Future<Reward?> getReaction(int diaryId);

  /// 월간 회고(기록·연속일·감정 분포·획득 코인·획득 아이템). [yearMonth]는 `YYYY-MM`.
  /// 기록이 없는 달도 빈 집계로 정상 응답한다.
  /// GET /characters/me/retrospect?yearMonth=
  Future<Retrospect> getRetrospect(String yearMonth);
}
