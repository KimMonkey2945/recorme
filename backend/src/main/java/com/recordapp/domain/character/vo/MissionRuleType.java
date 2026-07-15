package com.recordapp.domain.character.vo;

/**
 * 미션 판정 규칙 타입. V18 {@code chk_missions_rule_type} CHECK 와 동일 집합(★ 감정·레벨 규칙 없음).
 *
 * <p>각 타입은 진행률 산출 시 {@code user_progress} 의 정확히 한 컬럼만 본다 — O(1).
 * <ul>
 *   <li>{@code DIARY_COUNT}        → user_progress.confirmed_diary_count</li>
 *   <li>{@code CONSECUTIVE_DAYS}   → user_progress.consecutive_days</li>
 *   <li>{@code RESOLUTION_SUCCESS} → user_progress.resolution_success_count</li>
 *   <li>{@code RESOLUTION_STREAK}  → user_progress.max_streak_seq</li>
 * </ul>
 * 임계값 키는 타입마다 다르지만(count/days/seq), 매퍼가 {@code threshold} 하나로 정규화해 내려준다.
 */
public enum MissionRuleType {
	DIARY_COUNT,
	CONSECUTIVE_DAYS,
	RESOLUTION_SUCCESS,
	RESOLUTION_STREAK
}
