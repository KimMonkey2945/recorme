package com.recordapp.domain.character.dto;

import com.recordapp.domain.character.vo.MissionRuleType;

/**
 * missions 마스터 1행(카탈로그 캐시 원본).
 *
 * <p>rule(JSONB)의 임계값 키는 타입마다 다르지만(count/days/seq/level) 매퍼가 {@code threshold}
 * 하나로 정규화해 읽는다 — 서비스는 (타입, 임계값) 두 값만으로 진행률을 O(1) 산출한다.
 */
public record MissionRow(
		String code,
		String title,
		String description,
		MissionRuleType ruleType,
		int threshold,
		int coinReward,
		String itemGroupReward) {
}
