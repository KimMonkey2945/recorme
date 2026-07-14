package com.recordapp.domain.character.dto;

import com.recordapp.domain.character.vo.MissionRuleType;
import java.time.OffsetDateTime;

/**
 * 미션 항목(달성 여부 + 진행률). 진행률은 {@code user_progress}(+레벨) 기반 O(1) 산출이다.
 *
 * <p>{@code rule} 은 DB rule(JSONB)의 타입별 상이한 임계값 키(count/days/seq/level)를
 * {@code (type, threshold)} 로 정규화한 형태다. {@code progress} 는 threshold 를 넘어도 잘라내지 않고
 * 실제 값을 준다(예: 12/10) — 앱이 진행률 바를 그릴 때 min(progress/threshold, 1) 로 클램프한다.
 */
public record MissionResponse(
		String code,
		String title,
		String description,
		Rule rule,
		int progress,
		int threshold,
		boolean achieved,
		OffsetDateTime achievedAt,
		int coinReward,
		String itemGroupReward) {

	/** 정규화된 판정 규칙(감정 규칙은 존재하지 않는다). */
	public record Rule(MissionRuleType type, int threshold) {
	}
}
