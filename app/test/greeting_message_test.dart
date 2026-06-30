import 'package:flutter_test/flutter_test.dart';
import 'package:record/features/diary/presentation/main_calendar_page.dart';

/// 캘린더 헤더 감성 문구 [diaryCountGreeting] 분기 검증.
/// 단계: 0 / 1 / 2~중반 / 절반~ / 꽉 참, 그리고 현재 달 vs 과거 달 톤.
void main() {
  group('diaryCountGreeting — 현재 달 톤', () {
    String g(int count, {int days = 30}) => diaryCountGreeting(
          count: count,
          daysInMonth: days,
          isCurrentMonth: true,
          month: 6,
        );

    test('0개 — 권유 문구', () {
      expect(g(0), contains('아직 이번 달엔 기록된 기억이 없어요'));
      expect(g(0), contains('적어볼까요?'));
    });

    test('1개 — 첫 기억', () {
      expect(g(1), '이번 달 첫 기억을 남겼어요 ✨');
    });

    test('2~중반 — N개 안내', () {
      expect(g(5), '이번 달의 기록된 기억은 5개예요.');
    });

    test('절반 이상 — 쌓였어요', () {
      // 30일 → 절반 임계 15
      expect(g(15), '벌써 15개의 기억이 쌓였어요.');
      expect(g(20), '벌써 20개의 기억이 쌓였어요.');
    });

    test('꽉 참(일수와 동일) — 수고 메시지', () {
      expect(g(30, days: 30), contains('정말 많은 일들이 있었네요'));
      expect(g(30, days: 30), contains('수고했어요'));
    });
  });

  group('diaryCountGreeting — 과거 달 톤', () {
    String g(int count, {int days = 31, int month = 5}) => diaryCountGreeting(
          count: count,
          daysInMonth: days,
          isCurrentMonth: false,
          month: month,
        );

    test('0개 — N월엔 기억 없음', () {
      expect(g(0), '5월엔 기록된 기억이 없어요.');
    });

    test('여러 개 — N월엔 기억 N개', () {
      expect(g(3), '5월엔 기억 3개를 남겼어요.');
    });

    test('꽉 참 — N월은 많은 일들', () {
      expect(g(31, days: 31), contains('5월은 정말 많은 일들이 있었네요'));
    });
  });

  group('경계값', () {
    // 28일 달(2월 가정) 절반 임계 = (28+1)~/2 = 14
    test('28일 달의 절반 경계', () {
      expect(
        diaryCountGreeting(
            count: 14, daysInMonth: 28, isCurrentMonth: true, month: 2),
        '벌써 14개의 기억이 쌓였어요.',
      );
      expect(
        diaryCountGreeting(
            count: 13, daysInMonth: 28, isCurrentMonth: true, month: 2),
        '이번 달의 기록된 기억은 13개예요.',
      );
    });
  });
}
