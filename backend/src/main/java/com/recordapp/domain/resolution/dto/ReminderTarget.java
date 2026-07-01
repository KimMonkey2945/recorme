package com.recordapp.domain.resolution.dto;

/**
 * 리마인더 발송 대상(오늘 알림 스케줄러용 내부 DTO). {@code claimDueReminders} 의 원자적
 * {@code UPDATE ... RETURNING} 이 하루 1회 선점(reminded_on 마킹)과 동시에 채워 반환한다.
 *
 * @param resolutionId 결심 id (딥링크 payload 용)
 * @param userId       소유자 id (토큰 팬아웃용)
 * @param title        할일 제목 (알림 본문에 삽입)
 */
public record ReminderTarget(long resolutionId, long userId, String title) {
}
