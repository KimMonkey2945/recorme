package com.recordapp.domain.character.dto;

/**
 * 미션 해금 아이템의 잠금 정보(옷장·상점의 해금 진행률 바).
 * {@code acquireType=MISSION} 이고 아직 미보유일 때만 채워지고, 그 외에는 null 이다.
 */
public record MissionLockResponse(
		String missionCode,
		String title,
		int progress,
		int threshold) {
}
