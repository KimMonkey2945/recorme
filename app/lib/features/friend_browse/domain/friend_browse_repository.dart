import '../../resolution/domain/resolution.dart';
import 'friend_browse.dart';

/// 친구 둘러보기 저장소(읽기 전용).
///
/// 모든 메서드는 대상 친구를 **외부 노출 uuid**로만 지정한다(내부 PK 비노출).
/// 친구가 아니거나 차단·탈퇴한 상대면 서버가 404로 은닉하므로 `Failure('USER_NOT_FOUND', ...)`가 던져진다.
/// (경로는 dio baseUrl에 `/api/v1`이 포함되므로 `/friends...`만 쓴다.)
///
/// ⚠️ 쓰기 메서드는 의도적으로 없다 — 남의 recorme는 구경만 한다.
abstract class FriendBrowseRepository {
  /// `GET /friends/{uuid}/character` — 친구의 캐릭터·착용 아이템.
  Future<FriendCharacter> getCharacter(String userUuid);

  /// `GET /friends/{uuid}/diaries/summary?yearMonth=` — 친구의 월별 캘린더(공개 기록만).
  Future<List<FriendDiaryDay>> getDiarySummary(String userUuid, String yearMonth);

  /// `GET /friends/{uuid}/resolutions?status=` — 친구의 작심삼일 목록(첫 페이지).
  Future<List<ResolutionSummaryItem>> getResolutions(
    String userUuid, {
    ResolutionStatus? status,
  });
}
