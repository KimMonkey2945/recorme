// 친구 기능 테스트(Task 015-1).
// - DTO fromJson(Friend/FriendRequest/FriendSearchResult/relation/FriendRequestResult).
// - FriendsListPage: 로딩→데이터(닉네임 표시), 빈 상태.
// - AddFriendPage: 친구코드 카드 표시, 닉네임 검색 결과 렌더 + '추가'.
// - FriendRequestsPage: 받은 요청 수락이 저장소로 위임.
//
// Supabase/네트워크 없이 friendRepositoryProvider(+myProfileProvider)를 Fake로 override해 검증한다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:record/features/friend/data/dto/friend_dto.dart';
import 'package:record/features/friend/domain/friend_repository.dart';
import 'package:record/features/friend/presentation/add_friend_page.dart';
import 'package:record/features/friend/presentation/friend_requests_page.dart';
import 'package:record/features/friend/presentation/friends_list_page.dart';
import 'package:record/features/friend/presentation/providers/friend_providers.dart';
import 'package:record/features/friend/presentation/widgets/search_result_tile.dart';
import 'package:record/features/profile/presentation/providers/profile_providers.dart';
import 'package:record/shared/models/cursor_page.dart';
import 'package:record/shared/models/user.dart';

/// 결정적 테스트용 가짜 FriendRepository.
class _FakeFriendRepository implements FriendRepository {
  _FakeFriendRepository({
    this.friends = const [],
    this.incoming = const [],
    this.searchResults = const [],
  });

  List<Friend> friends;
  List<FriendRequest> incoming;
  List<FriendRequest> outgoing = const [];
  List<FriendSearchResult> searchResults;

  final List<int> acceptedIds = [];
  final List<int> rejectedIds = [];
  final List<String> requestedUuids = [];
  final List<String> requestedCodes = [];
  final List<String> removedUuids = [];

  @override
  Future<FriendRequestResult> requestByCode(String friendCode) async {
    requestedCodes.add(friendCode);
    return const FriendRequestResult(requestId: 1, status: 'PENDING');
  }

  @override
  Future<FriendRequestResult> requestByUuid(String targetUuid) async {
    requestedUuids.add(targetUuid);
    return const FriendRequestResult(requestId: 1, status: 'PENDING');
  }

  @override
  Future<void> accept(int requestId) async => acceptedIds.add(requestId);

  @override
  Future<void> reject(int requestId) async => rejectedIds.add(requestId);

  @override
  Future<CursorPage<Friend>> getFriends({int? cursor, int size = 20}) async =>
      CursorPage(items: friends, hasNext: false);

  @override
  Future<CursorPage<FriendRequest>> getRequests({
    String direction = 'incoming',
    int? cursor,
    int size = 20,
  }) async =>
      CursorPage(
        items: direction == 'outgoing' ? outgoing : incoming,
        hasNext: false,
      );

  @override
  Future<List<FriendSearchResult>> search(String query) async => searchResults;

  @override
  Future<void> remove(String userUuid, {bool block = false}) async =>
      removedUuids.add(userUuid);
}

const _me = User(uuid: 'me', nickname: '나', friendCode: 'ABCD1234');

Widget _wrap(Widget child, _FakeFriendRepository repo) => ProviderScope(
      overrides: [
        friendRepositoryProvider.overrideWithValue(repo),
        myProfileProvider.overrideWith((ref) async => _me),
      ],
      child: MaterialApp(home: child),
    );

void main() {
  group('친구 DTO', () {
    test('Friend.fromJson', () {
      final f = Friend.fromJson({
        'friendshipId': 7,
        'userUuid': 'u-1',
        'nickname': '앨리스',
        'profileImageUrl': null,
      });
      expect(f.friendshipId, 7);
      expect(f.nickname, '앨리스');
    });

    test('FriendRequest.fromJson (createdAt 파싱)', () {
      final r = FriendRequest.fromJson({
        'requestId': 3,
        'userUuid': 'u-2',
        'nickname': '밥',
        'createdAt': '2026-07-06T10:00:00Z',
      });
      expect(r.requestId, 3);
      expect(r.createdAt, isNotNull);
    });

    test('FriendSearchResult relation 매핑', () {
      FriendRelation rel(String? code) =>
          FriendSearchResult.fromJson({'userUuid': 'u', 'nickname': 'n', 'relation': code})
              .relation;
      expect(rel('FRIEND'), FriendRelation.friend);
      expect(rel('REQUESTED'), FriendRelation.requested);
      expect(rel('INCOMING'), FriendRelation.incoming);
      expect(rel('BLOCKED'), FriendRelation.blocked);
      expect(rel(null), FriendRelation.none);
      expect(rel('WEIRD'), FriendRelation.none);
    });

    test('FriendRequestResult.autoAccepted', () {
      expect(const FriendRequestResult(requestId: 1, status: 'ACCEPTED').autoAccepted,
          isTrue);
      expect(const FriendRequestResult(requestId: 1, status: 'PENDING').autoAccepted,
          isFalse);
    });
  });

  group('FriendsListPage', () {
    testWidgets('친구가 있으면 닉네임을 표시', (tester) async {
      final repo = _FakeFriendRepository(friends: const [
        Friend(friendshipId: 1, userUuid: 'u-1', nickname: '앨리스'),
        Friend(friendshipId: 2, userUuid: 'u-2', nickname: '보라미'),
      ]);
      await tester.pumpWidget(_wrap(const FriendsListPage(), repo));
      await tester.pumpAndSettle();

      // 닉네임 텍스트는 타일에 표시(이니셜 아바타는 첫 글자만이라 전체 닉네임과 겹치지 않음).
      expect(find.text('앨리스'), findsOneWidget);
      expect(find.text('보라미'), findsOneWidget);
    });

    testWidgets('친구가 없으면 빈 상태 안내', (tester) async {
      final repo = _FakeFriendRepository();
      await tester.pumpWidget(_wrap(const FriendsListPage(), repo));
      await tester.pumpAndSettle();

      expect(find.text('아직 친구가 없어요'), findsOneWidget);
    });
  });

  group('AddFriendPage', () {
    testWidgets('내 친구코드를 표시한다', (tester) async {
      final repo = _FakeFriendRepository();
      await tester.pumpWidget(_wrap(const AddFriendPage(), repo));
      await tester.pumpAndSettle();

      expect(find.text('ABCD1234'), findsOneWidget);
    });

    testWidgets('닉네임 검색 결과를 렌더하고 추가 요청을 위임', (tester) async {
      final repo = _FakeFriendRepository(searchResults: const [
        FriendSearchResult(userUuid: 'u-9', nickname: '찰리'),
      ]);
      await tester.pumpWidget(_wrap(const AddFriendPage(), repo));
      await tester.pumpAndSettle();

      // 검색 필드에 입력 → 디바운스(350ms) 경과 후 결과 조회.
      await tester.enterText(find.byType(TextField).last, '차니', );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // 검색 결과 타일 내부의 '추가' 버튼(코드 섹션 '추가'와 구분)이 렌더되면 결과 표시.
      final addInTile = find.descendant(
        of: find.byType(SearchResultTile),
        matching: find.widgetWithText(FilledButton, '추가'),
      );
      expect(addInTile, findsOneWidget);

      await tester.tap(addInTile);
      await tester.pumpAndSettle();
      expect(repo.requestedUuids, contains('u-9'));
    });
  });

  group('FriendRequestsPage', () {
    testWidgets('받은 요청 수락이 저장소로 위임된다', (tester) async {
      final repo = _FakeFriendRepository(incoming: const [
        FriendRequest(requestId: 42, userUuid: 'u-7', nickname: '데이브'),
      ]);
      await tester.pumpWidget(_wrap(const FriendRequestsPage(), repo));
      await tester.pumpAndSettle();

      expect(find.text('데이브'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '수락'));
      await tester.pumpAndSettle();

      expect(repo.acceptedIds, contains(42));
    });
  });
}
