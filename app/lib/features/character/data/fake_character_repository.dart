import '../../../core/error/failure.dart';
import '../domain/character.dart';
import '../domain/character_repository.dart';
import '../domain/my_character.dart';

/// 인메모리 더미 캐릭터 저장소(테스트/웹 프리뷰용).
///
/// 실제 백엔드 없이 목록 조회·내 캐릭터 조회·선택을 시뮬레이션한다.
/// `--dart-define=USE_FAKE_CHARACTER_REPO=true`로 켜면 웹(`flutter run -d chrome`)에서
/// 백엔드 없이 온보딩 화면을 그대로 확인할 수 있다.
/// 실제 환경에서는 이 클래스만 [ApiCharacterRepository]로 교체하면 화면 코드는 그대로 동작한다.
/// (FakeResolutionRepository 스타일을 미러링한다.)
class FakeCharacterRepository implements CharacterRepository {
  FakeCharacterRepository({String? selectedCode}) : _selectedCode = selectedCode;

  /// 현재 선택된 캐릭터 코드(null이면 미선택 = 온보딩 대상).
  String? _selectedCode;

  /// 네트워크 지연 흉내.
  static const _latency = Duration(milliseconds: 300);

  /// 백엔드 시드(V15)와 동일한 2종. 썸네일은 로컬 에셋 경로다.
  static const _catalog = [
    (
      code: 'MONKEY',
      nameKo: '원숭이',
      tagline: '뭐든 천천히, 오늘도 느긋하게. 여유가 특기인 친구예요.',
      thumbnailUrl: 'assets/characters/monkey.png',
      riveArtboard: 'monkey',
    ),
    (
      code: 'RED_PANDA',
      nameKo: '레서판다',
      tagline: '부지런히 곁을 지켜요. 정 많고 애착이 강한 친구예요.',
      thumbnailUrl: 'assets/characters/red_panda.png',
      riveArtboard: 'red_panda',
    ),
  ];

  @override
  Future<CharacterList> fetchCharacters() async {
    await Future<void>.delayed(_latency);
    return CharacterList(
      selectedCharacter: _selectedCode,
      items: [
        for (final c in _catalog)
          Character(
            code: c.code,
            nameKo: c.nameKo,
            tagline: c.tagline,
            thumbnailUrl: c.thumbnailUrl,
            // 기본 2종은 모두 보유 상태다.
            owned: true,
            selected: c.code == _selectedCode,
          ),
      ],
    );
  }

  @override
  Future<MyCharacter> fetchMyCharacter() async {
    await Future<void>.delayed(_latency);
    return _myCharacter();
  }

  @override
  Future<MyCharacter> selectCharacter(String code) async {
    await Future<void>.delayed(_latency);
    final owned = _catalog.any((c) => c.code == code);
    if (!owned) {
      throw const Failure('CHARACTER_NOT_OWNED', '아직 보유하지 않은 캐릭터예요.');
    }
    _selectedCode = code;
    return _myCharacter();
  }

  // ── 유틸 ────────────────────────────────────────────────────

  /// 현재 선택 상태 기준의 내 캐릭터 응답을 만든다(미선택이면 character=null).
  MyCharacter _myCharacter() {
    final selected = _selectedCode;
    final matches = _catalog.where((c) => c.code == selected);
    final entry = matches.isEmpty ? null : matches.first;
    return MyCharacter(
      character: entry == null
          ? null
          : SelectedCharacter(
              code: entry.code,
              nameKo: entry.nameKo,
              thumbnailUrl: entry.thumbnailUrl,
              riveArtboard: entry.riveArtboard,
            ),
      level: 1,
      exp: 0,
      expToNext: 100,
      coinBalance: 0,
      unackedRewardCount: 0,
      equipment: const [],
    );
  }
}
