import 'character.dart';
import 'my_character.dart';

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
}
