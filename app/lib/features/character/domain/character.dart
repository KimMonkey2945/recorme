/// 캐릭터 도메인 모델.
///
/// 백엔드 `character` 도메인 응답과 1:1 대응한다. JSON 파싱은 데이터 계층
/// (`data/dto/character_dto.dart`)이 담당하고, 여기에는 순수 도메인 타입만 둔다.
/// (resolution/diary 도메인의 순수성 관례를 따른다.)
library;

/// 선택 가능한 캐릭터 1종(온보딩 캐러셀 카드 1장).
///
/// [thumbnailUrl]은 URL이 아니라 로컬 에셋 경로('assets/characters/monkey.png')다.
/// → 화면에서는 `Image.asset()`으로 로드한다.
/// [tagline]은 성격 소개 문구로, 원숭이/레서판다의 성격 대비를 드러내는 핵심 카피다.
class Character {
  const Character({
    required this.code,
    required this.nameKo,
    required this.tagline,
    required this.thumbnailUrl,
    required this.owned,
    required this.selected,
  });

  /// 서버 캐릭터 코드(MONKEY/RED_PANDA). 선택 API의 요청 키다.
  final String code;

  /// 표시용 한국어 이름.
  final String nameKo;

  /// 성격 소개 한 줄.
  final String tagline;

  /// 로컬 에셋 경로(Image.asset으로 로드).
  final String thumbnailUrl;

  /// 보유 여부(미보유 캐릭터 선택 시 서버가 CHARACTER_NOT_OWNED로 거절).
  final bool owned;

  /// 현재 선택된 캐릭터인지 여부.
  final bool selected;
}

/// `GET /characters` 응답 전체.
///
/// [selectedCharacter]는 현재 선택된 캐릭터 코드이며, 미선택이면 null이다.
class CharacterList {
  const CharacterList({
    required this.items,
    this.selectedCharacter,
  });

  /// 선택된 캐릭터 코드(미선택이면 null).
  final String? selectedCharacter;

  /// 선택 가능한 캐릭터 목록(온보딩 캐러셀 순서 그대로).
  final List<Character> items;
}
