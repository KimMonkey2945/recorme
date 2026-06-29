// FakeDiaryRepository 동작 단위 테스트 (Phase 2 더미 데이터 레이어).
// upsert(같은 날짜 UPDATE / 신규 INSERT), 소프트 삭제, 커서 페이징을 검증한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:record/core/error/failure.dart';
import 'package:record/features/diary/data/fake_diary_repository.dart';

void main() {
  group('FakeDiaryRepository', () {
    test('getList: 첫 페이지는 id 내림차순 + hasNext/nextCursor', () async {
      final repo = FakeDiaryRepository();
      final page = await repo.getList(size: 5);

      expect(page.items.length, 5);
      expect(page.hasNext, true);
      expect(page.nextCursor, page.items.last.id);
      // id 내림차순 정렬 확인
      for (var i = 0; i < page.items.length - 1; i++) {
        expect(page.items[i].id, greaterThan(page.items[i + 1].id));
      }
    });

    test('getList: cursor로 다음 페이지를 이어서 조회', () async {
      final repo = FakeDiaryRepository();
      final p1 = await repo.getList(size: 5);
      final p2 = await repo.getList(cursor: p1.nextCursor, size: 5);

      expect(p2.items.first.id, lessThan(p1.items.last.id));
    });

    test('upsert: 같은 날짜는 UPDATE(같은 id, 내용 변경)', () async {
      final repo = FakeDiaryRepository();
      // 시드 데이터는 DONE(수정 불가)이므로 비어 있는 미래 날짜를 사용한다.
      // 먼저 DRAFT로 INSERT한 뒤 같은 날짜로 UPDATE해 id 보존을 확인한다.
      final testDate = DateTime(2030, 1, 1);
      expect(await repo.getByDate(testDate), isNull);

      final created = await repo.upsert(
        date: testDate,
        content: '초기 내용',
        contentText: '초기 내용',
      );
      expect(created.analysisStatus, 'DRAFT');

      // 같은 날짜로 다시 upsert → UPDATE(id 유지, 내용 교체).
      final updated = await repo.upsert(
        date: testDate,
        content: '수정된 내용',
        contentText: '수정된 내용',
      );
      expect(updated.id, created.id, reason: 'INSERT가 아닌 UPDATE라 id 유지');
      expect(updated.content, '수정된 내용');

      final after = await repo.getByDate(testDate);
      expect(after!.content, '수정된 내용');
    });

    test('upsert: 없는 날짜는 새 id로 INSERT', () async {
      final repo = FakeDiaryRepository();
      final newDate = DateTime(2030, 2, 1);
      expect(await repo.getByDate(newDate), isNull);

      final created = await repo.upsert(
        date: newDate,
        content: '새 일기',
        contentText: '새 일기',
      );
      expect(created.content, '새 일기');
      // confirm=false(기본값)이면 DRAFT로 임시 저장된다.
      expect(created.analysisStatus, 'DRAFT');

      final fetched = await repo.getByDate(newDate);
      expect(fetched, isNotNull);
      expect(fetched!.id, created.id);
    });

    test('delete: 소프트 삭제 후 해당 날짜는 비고, 재작성 허용', () async {
      final repo = FakeDiaryRepository();
      final today = DateTime.now();
      final diary = await repo.getByDate(today);
      expect(diary, isNotNull);

      await repo.delete(diary!.id);
      expect(await repo.getByDate(today), isNull);
      // 삭제된 id 조회 시 DIARY_NOT_FOUND
      expect(
        () => repo.getById(diary.id),
        throwsA(isA<Failure>()),
      );

      // 같은 날짜 재작성 허용
      final recreated = await repo.upsert(
        date: today,
        content: '다시 쓴 일기',
        contentText: '다시 쓴 일기',
      );
      expect(recreated.content, '다시 쓴 일기');
    });

    test('getMonthlySummary: 해당 월의 작성 날짜 목록 반환', () async {
      final repo = FakeDiaryRepository();
      final now = DateTime.now();
      final ym = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}';
      final summary = await repo.getMonthlySummary(ym);

      expect(summary.yearMonth, ym);
      // days: 해당 월 일기가 포함되어 비어 있지 않아야 함
      expect(summary.days, isNotEmpty);
      // 모든 항목 날짜가 해당 연월로 시작하는지 확인
      expect(summary.days.every((d) => d.date.startsWith(ym)), true);
    });
  });
}
