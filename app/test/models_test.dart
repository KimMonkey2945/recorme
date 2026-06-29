import 'package:flutter_test/flutter_test.dart';
import 'package:record/features/diary/data/dto/diary_dto.dart';
import 'package:record/shared/models/api_response.dart';
import 'package:record/shared/models/cursor_page.dart';

void main() {
  group('ApiResponse', () {
    test('성공 응답을 data 변환기로 파싱한다', () {
      final json = {
        'success': true,
        'data': {
          'yearMonth': '2026-06',
          'days': [
            {
              'date': '2026-06-01',
              'analysisStatus': 'DONE',
              'primaryEmotion': 'JOY',
              'moodEmoji': '😊',
            }
          ],
        },
        'error': null,
      };

      final res = ApiResponse<DiarySummary>.fromJson(
        json,
        (o) => DiarySummary.fromJson(o as Map<String, dynamic>),
      );

      expect(res.success, isTrue);
      expect(res.error, isNull);
      expect(res.data!.yearMonth, '2026-06');
      // days 파싱 검증: 날짜·상태·감정 코드 확인
      expect(res.data!.days.length, 1);
      expect(res.data!.days.first.date, '2026-06-01');
      expect(res.data!.days.first.isDone, isTrue);
      expect(res.data!.days.first.primaryEmotion, 'JOY');
      expect(res.data!.days.first.moodEmoji, '😊');
    });

    test('실패 응답의 error를 파싱한다', () {
      final json = {
        'success': false,
        'data': null,
        'error': {'code': 'DIARY_NOT_FOUND', 'message': '일기를 찾을 수 없습니다.'},
      };

      final res = ApiResponse<DiarySummary>.fromJson(json, (o) => throw StateError('호출 안 됨'));

      expect(res.success, isFalse);
      expect(res.data, isNull);
      expect(res.error!.code, 'DIARY_NOT_FOUND');
    });
  });

  group('CursorPage', () {
    test('items/nextCursor/hasNext를 파싱한다', () {
      final json = {
        'items': [
          {
            'id': 10,
            'content': '오늘',
            'writtenDate': '2026-06-15',
            'visibility': 'PRIVATE',
            'analysisStatus': 'PENDING',
          },
        ],
        'nextCursor': 10,
        'hasNext': true,
      };

      final page = CursorPage<Diary>.fromJson(
        json,
        (o) => Diary.fromJson(o as Map<String, dynamic>),
      );

      expect(page.items, hasLength(1));
      expect(page.items.first.id, 10);
      expect(page.nextCursor, 10);
      expect(page.hasNext, isTrue);
    });
  });
}
