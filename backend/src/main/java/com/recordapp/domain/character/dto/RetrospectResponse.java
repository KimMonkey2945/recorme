package com.recordapp.domain.character.dto;

import java.util.List;

/**
 * 월간 회고(Task 032 — 락인). 감정이 실제로 쓰이는 유일한 통계 지점이며, 캐릭터 성장(코인·획득 아이템)을 나란히 보여 준다.
 *
 * <p>성장 지표는 <b>코인 획득 + 획득 아이템</b>으로만 표현한다(경험치/레벨은 보상 재설계로 폐기 — V18).
 * 빈 달(기록 0건)도 정상 응답이다(모든 수치 0 + 빈 리스트).
 *
 * @param yearMonth              대상 월(YYYY-MM)
 * @param confirmedCount         이달 확정 기록 수
 * @param consecutiveDaysMax     이달 안에서의 최장 연속 기록일
 * @param resolutionSuccessCount 이달 작심삼일 완주 수
 * @param emotions               감정 분포(프리셋 + 직접 입력 라벨 혼재, 많은 순)
 * @param coinEarned             이달 획득 코인 합(소비 제외)
 * @param unlockedItems          이달 획득(구매·해금) 아이템(내 캐릭터 기준 이미지)
 */
public record RetrospectResponse(
		String yearMonth,
		int confirmedCount,
		int consecutiveDaysMax,
		int resolutionSuccessCount,
		List<EmotionStat> emotions,
		int coinEarned,
		List<UnlockedItem> unlockedItems) {
}
