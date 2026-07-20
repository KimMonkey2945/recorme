import '../../character/domain/my_character.dart';
import '../../diary/data/dto/diary_dto.dart';
import '../../resolution/domain/resolution.dart';
import '../domain/friend_browse.dart';
import '../domain/friend_browse_repository.dart';

/// 테스트·오프라인 프리뷰용 가짜 친구 둘러보기 저장소.
///
/// 기본값은 "캐릭터를 고른 친구 + 공개 기록 2건 + 진행중 결심 1건"이다.
/// 생성자 인자로 각 축을 갈아끼워 빈 상태·미선택 캐릭터 같은 분기를 검증한다.
class FakeFriendBrowseRepository implements FriendBrowseRepository {
  FakeFriendBrowseRepository({
    this.character = const SelectedCharacter(
      code: 'MONKEY',
      nameKo: '몽키',
      thumbnailUrl: 'assets/characters/monkey.png',
    ),
    this.diaryDays,
    this.resolutions,
  });

  /// null이면 아직 캐릭터를 고르지 않은 친구(빈 상태 분기 검증용).
  final SelectedCharacter? character;
  final List<FriendDiaryDay>? diaryDays;
  final List<ResolutionSummaryItem>? resolutions;

  @override
  Future<FriendCharacter> getCharacter(String userUuid) async =>
      FriendCharacter(character: character);

  @override
  Future<List<FriendDiaryDay>> getDiarySummary(
          String userUuid, String yearMonth) async =>
      diaryDays ??
      [
        // PRIVATE 기록은 서버가 애초에 안 내려주므로 Fake도 공개 기록만 담는다.
        FriendDiaryDay(
          diaryId: 101,
          summary: DiarySummaryDay(
            date: '$yearMonth-05',
            analysisStatus: 'DONE',
            primaryEmotion: 'JOY',
          ),
        ),
        FriendDiaryDay(
          diaryId: 102,
          summary: DiarySummaryDay(
            date: '$yearMonth-12',
            analysisStatus: 'DONE',
            primaryEmotion: 'CALM',
          ),
        ),
      ];

  @override
  Future<List<ResolutionSummaryItem>> getResolutions(
    String userUuid, {
    ResolutionStatus? status,
  }) async =>
      resolutions ??
      [
        ResolutionSummaryItem(
          id: 1,
          title: '매일 산책하기',
          startDate: DateTime(2026, 7, 1),
          endDate: DateTime(2026, 7, 3),
          status: ResolutionStatus.ongoing,
          streakSeq: 1,
          dayStatuses: const [CheckStatus.done, CheckStatus.pending],
        ),
      ];
}
