package com.recordapp.domain.character.config;

import java.util.Map;
import java.util.TreeMap;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 코인 적립 기준값(단일 정의처는 {@code docs/coin-rewards.md}).
 *
 * <p><b>값을 바꾸거나 보상을 추가/제거하려면 여기(application.yml)만 고친다 — 코드 변경 없이.</b>
 * 고정 금액 트리거(출석·기록·작심삼일)는 정수 필드로, 연속 기록 마일스톤은 {@code streak} 맵으로 둔다.
 * 마일스톤 추가/삭제는 맵에 줄을 넣고 빼는 것으로 끝난다(예: {@code streak: {7: 200, 30: 500}}).
 *
 * <p>⚠️ yaml 키 {@code diary} 는 coin-rewards.md 의 {@code daily.record} 에 대응한다
 * ({@code record} 가 Java 예약어라 필드명으로 못 써서 {@code diary} 로 명명).
 *
 * <p>{@code coinEnabled} 는 상점 구매(코인 <b>소비</b>) 게이팅용이며 <b>적립과 무관</b>하다
 * (적립은 항상 동작). 구매 API 는 아직 범위 밖이라 현재는 참조되지 않지만, 기준 문서와의 정합을 위해 남긴다.
 *
 * @param coinEnabled       상점 구매 활성화(적립엔 영향 없음). 기본 false.
 * @param attendance        출석(앱 접속) 적립액 — 하루 1회
 * @param diary             기록 확정 적립액 — 하루 1회
 * @param resolutionDay1    작심삼일 1일차 달성 적립액
 * @param resolutionDay2    작심삼일 2일차 달성 적립액
 * @param resolutionComplete 작심삼일 완주 적립액
 * @param streak            연속 기록 마일스톤(연속일 → 적립액). 계정당 최초 1회.
 */
@ConfigurationProperties(prefix = "record.character.coin")
public record CharacterCoinProperties(
		boolean coinEnabled,
		int attendance,
		int diary,
		int resolutionDay1,
		int resolutionDay2,
		int resolutionComplete,
		Map<Integer, Integer> streak) {

	public CharacterCoinProperties {
		// null·미설정 방어 + 순회 순서 안정화(작은 임계값부터). 바인딩 실패해도 엔진이 NPE 없이 0 적립으로 견딘다.
		streak = (streak == null) ? Map.of() : new TreeMap<>(streak);
	}

	/** 연속 확정일 {@code days} 에 정확히 도달했을 때 줄 코인(마일스톤 아니면 0). */
	public int streakCoin(int days) {
		return streak.getOrDefault(days, 0);
	}
}
