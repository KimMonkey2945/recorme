package com.recordapp.domain.character.dto;

import java.time.OffsetDateTime;

/** user_missions 1행(달성 이력). (user_id, mission_code) PK 가 "미션당 1회 달성" 을 강제한다. */
public record UserMissionRow(
		String missionCode,
		OffsetDateTime achievedAt) {
}
