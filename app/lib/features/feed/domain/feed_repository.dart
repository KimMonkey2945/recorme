import '../../../shared/models/cursor_page.dart';
import '../data/dto/feed_dto.dart';

/// 피드 데이터 접근 추상화. 테스트는 이 provider를 Fake로 override한다.
/// 메서드는 `docs/api-contract.md`의 `/feed`·`/feed/{id}`와 1:1 대응한다.
abstract class FeedRepository {
  /// 피드 목록(본인+PUBLIC+수락친구 FRIENDS 감정 카드, id DESC 커서). GET /feed
  Future<CursorPage<FeedItem>> getFeed({int? cursor, int size});

  /// 피드 카드 전문 조회(viewer-aware). GET /feed/{id}
  Future<FeedDetail> getDetail(int id);

  /// 공감 추가(멱등). POST /diaries/{id}/reactions
  Future<ReactionResult> react(int diaryId);

  /// 공감 취소(멱등). DELETE /diaries/{id}/reactions
  Future<ReactionResult> unreact(int diaryId);
}
