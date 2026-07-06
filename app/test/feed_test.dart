// 피드 기능 테스트(Task 015-3).
// - FeedItem/FeedDetail fromJson.
// - FeedPage: 로딩→데이터(카드 렌더), 빈 상태.
// - FeedNotifier.loadMore: 커서 페이징 누적.
//
// Supabase/네트워크 없이 feedRepositoryProvider를 Fake로 override해 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:record/features/feed/data/dto/feed_dto.dart';
import 'package:record/features/feed/domain/feed_repository.dart';
import 'package:record/features/feed/presentation/feed_page.dart';
import 'package:record/features/feed/presentation/providers/feed_providers.dart';
import 'package:record/features/feed/presentation/widgets/feed_diary_card.dart';
import 'package:record/shared/models/cursor_page.dart';
import 'package:record/shared/widgets/reaction_button.dart';

/// 결정적 테스트용 가짜 FeedRepository.
class _FakeFeedRepository implements FeedRepository {
  _FakeFeedRepository({this.firstPage = const [], this.secondPage = const []});

  final List<FeedItem> firstPage;
  final List<FeedItem> secondPage;

  @override
  Future<CursorPage<FeedItem>> getFeed({int? cursor, int size = 20}) async {
    if (cursor == null) {
      return CursorPage(
        items: firstPage,
        nextCursor: firstPage.isNotEmpty ? firstPage.last.id : null,
        hasNext: secondPage.isNotEmpty,
      );
    }
    return CursorPage(items: secondPage, nextCursor: null, hasNext: false);
  }

  @override
  Future<FeedDetail> getDetail(int id) async => FeedDetail(
        id: id,
        authorUuid: 'u',
        authorNickname: '작성자',
        content: '{"ops":[{"insert":"본문\\n"}]}',
        writtenDate: DateTime(2026, 7, 1),
        visibility: 'PUBLIC',
      );

  final List<int> reacted = [];
  final List<int> unreacted = [];

  @override
  Future<ReactionResult> react(int diaryId) async {
    reacted.add(diaryId);
    return const ReactionResult(reactionCount: 1, reacted: true);
  }

  @override
  Future<ReactionResult> unreact(int diaryId) async {
    unreacted.add(diaryId);
    return const ReactionResult(reactionCount: 0, reacted: false);
  }
}

FeedItem _item(int id, String nickname, {String? title}) => FeedItem(
      id: id,
      authorUuid: 'u$id',
      authorNickname: nickname,
      aiTitle: title,
      preview: '미리보기 $id',
      writtenDate: DateTime(2026, 7, id),
      visibility: 'PUBLIC',
      primaryEmotion: 'JOY',
    );

Widget _wrap(_FakeFeedRepository repo) => ProviderScope(
      overrides: [feedRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: FeedPage()),
    );

void main() {
  group('피드 DTO', () {
    test('FeedItem.fromJson', () {
      final f = FeedItem.fromJson({
        'id': 5,
        'authorUuid': 'u-1',
        'authorNickname': '앨리스',
        'moodEmoji': '😊',
        'aiTitle': '제목',
        'preview': '미리보기',
        'writtenDate': '2026-07-01',
        'visibility': 'PUBLIC',
        'primaryEmotion': 'JOY',
        'reactionCount': 3,
        'reactedByMe': true,
      });
      expect(f.id, 5);
      expect(f.authorNickname, '앨리스');
      expect(f.reactionCount, 3);
      expect(f.reactedByMe, isTrue);
    });

    test('FeedDetail.fromJson', () {
      final d = FeedDetail.fromJson({
        'id': 9,
        'authorUuid': 'u-2',
        'authorNickname': '밥',
        'content': '{"ops":[]}',
        'contentText': '본문',
        'writtenDate': '2026-07-02',
        'visibility': 'FRIENDS',
      });
      expect(d.id, 9);
      expect(d.content, '{"ops":[]}');
      expect(d.reactionCount, 0); // 015-4 전 기본값
    });
  });

  group('FeedPage', () {
    testWidgets('카드를 렌더한다(작성자·제목)', (tester) async {
      final repo = _FakeFeedRepository(
        firstPage: [_item(2, '앨리스', title: '즐거운 하루')],
      );
      await tester.pumpWidget(_wrap(repo));
      await tester.pumpAndSettle();

      expect(find.byType(FeedDiaryCard), findsOneWidget);
      expect(find.text('앨리스'), findsOneWidget);
      expect(find.text('즐거운 하루'), findsOneWidget);
    });

    testWidgets('비어 있으면 빈 상태 안내', (tester) async {
      await tester.pumpWidget(_wrap(_FakeFeedRepository()));
      await tester.pumpAndSettle();

      expect(find.text('아직 피드에 올라온 기록이 없어요'), findsOneWidget);
    });
  });

  group('FeedNotifier.loadMore', () {
    test('다음 페이지를 이어 붙인다', () async {
      final repo = _FakeFeedRepository(
        firstPage: [_item(10, 'A'), _item(9, 'B')],
        secondPage: [_item(8, 'C')],
      );
      final container = ProviderContainer(
        overrides: [feedRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final first = await container.read(feedProvider.future);
      expect(first.items.length, 2);
      expect(first.hasNext, isTrue);

      await container.read(feedProvider.notifier).loadMore();
      final after = container.read(feedProvider).asData!.value;
      expect(after.items.length, 3); // 2 + 1 누적
      expect(after.hasNext, isFalse);
    });
  });

  group('FeedNotifier.toggleReaction', () {
    test('공감 시 저장소 호출 + 목록 항목 갱신', () async {
      final repo = _FakeFeedRepository(firstPage: [_item(10, 'A')]);
      final container = ProviderContainer(
        overrides: [feedRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final state = await container.read(feedProvider.future);
      final target = state.items.first; // reactedByMe=false, count=0
      await container.read(feedProvider.notifier).toggleReaction(target);

      expect(repo.reacted, contains(10));
      final after = container.read(feedProvider).asData!.value.items.first;
      expect(after.reactedByMe, isTrue);
      expect(after.reactionCount, 1);
    });
  });

  group('ReactionButton', () {
    testWidgets('카운트를 표시하고 탭 시 콜백', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ReactionButton(
            reacted: false,
            count: 3,
            onTap: () => tapped = true,
          ),
        ),
      ));

      expect(find.text('3'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      await tester.tap(find.byType(ReactionButton));
      expect(tapped, isTrue);
    });

    testWidgets('reacted=true면 채워진 하트', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ReactionButton(reacted: true, count: 1),
        ),
      ));
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });
  });
}
