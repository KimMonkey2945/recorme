// 보상함/출석 로직 테스트(Task 030 앱 보상 배선).
// - RewardsNotifier: 첫 페이지 로드 + loadMore 커서 누적.
// - AckRewardsController: 전체 확인 후 개수 반환 + 보상함 비움.
// - AttendanceController: 하루 1회(두 번째 호출은 granted=false).
//
// 네트워크 없이 characterRepositoryProvider를 Fake로 override해 ProviderContainer로 검증한다(feed_test 패턴).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:record/features/character/data/fake_character_repository.dart';
import 'package:record/features/character/domain/reward.dart';
import 'package:record/features/character/presentation/providers/character_providers.dart';
import 'package:record/shared/models/cursor_page.dart';

/// 보상 목록을 미리 채운 Fake — fetchRewards가 id DESC 커서 페이징을 흉내낸다(지연 없음).
class _SeededRewardsRepo extends FakeCharacterRepository {
  _SeededRewardsRepo(this._seed) : super(selectedCode: 'MONKEY');

  List<Reward> _seed;

  @override
  Future<CursorPage<Reward>> fetchRewards({int? cursor, int? size}) async {
    final sorted = [..._seed]..sort((a, b) => b.id.compareTo(a.id));
    final rest =
        cursor == null ? sorted : sorted.where((r) => r.id < cursor).toList();
    final page = rest.take(size ?? 20).toList();
    return CursorPage(
      items: page,
      nextCursor: page.isEmpty ? null : page.last.id,
      hasNext: rest.length > page.length,
    );
  }

  @override
  Future<int> ackRewards() async {
    final n = _seed.length;
    _seed = [];
    return n;
  }
}

Reward _reward(int id) => Reward(
      id: id,
      eventType: 'DIARY_CONFIRM',
      coinDelta: 10,
      balanceAfter: id * 10,
      line: '오늘도 기록했네!',
      context: 'CONFIRM',
      createdAt: DateTime(2026, 7, 16),
    );

void main() {
  ProviderContainer containerWith(FakeCharacterRepository repo) {
    final container = ProviderContainer(
      overrides: [characterRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('RewardsNotifier: 첫 페이지 20건 + loadMore로 나머지 5건 누적', () async {
    // 25건 → 첫 페이지 20 + 다음 5.
    final seed = [for (var i = 1; i <= 25; i++) _reward(i)];
    final container = containerWith(_SeededRewardsRepo(seed));

    final first = await container.read(rewardsProvider.future);
    expect(first.items.length, 20);
    expect(first.hasNext, isTrue);
    expect(first.items.first.id, 25); // 최신순(id DESC)

    await container.read(rewardsProvider.notifier).loadMore();
    final after = container.read(rewardsProvider).value!;
    expect(after.items.length, 25);
    expect(after.hasNext, isFalse);
    expect(after.items.last.id, 1);
  });

  test('RewardsNotifier: 빈 보상함 → items 비고 hasNext=false', () async {
    final container = containerWith(_SeededRewardsRepo([]));
    final state = await container.read(rewardsProvider.future);
    expect(state.items, isEmpty);
    expect(state.hasNext, isFalse);
  });

  test('AckRewardsController: 전체 확인 → 개수 반환', () async {
    final seed = [for (var i = 1; i <= 3; i++) _reward(i)];
    final container = containerWith(_SeededRewardsRepo(seed));

    final acked = await container.read(ackRewardsControllerProvider.notifier).ack();
    expect(acked, 3);
    // ack 후 보상함을 다시 읽으면 비어 있다(invalidate 반영).
    final state = await container.read(rewardsProvider.future);
    expect(state.items, isEmpty);
  });

  test('AttendanceController: 하루 1회 — 첫 호출 granted, 재호출은 미적립', () async {
    final container = containerWith(FakeCharacterRepository(selectedCode: 'MONKEY'));

    final first = await container.read(attendanceControllerProvider.notifier).mark();
    expect(first?.granted, isTrue);
    expect(first?.coin, 10);

    final second = await container.read(attendanceControllerProvider.notifier).mark();
    expect(second?.granted, isFalse);
  });
}
