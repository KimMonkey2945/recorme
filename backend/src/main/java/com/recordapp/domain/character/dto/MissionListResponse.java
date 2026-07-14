package com.recordapp.domain.character.dto;

import java.util.List;

/** GET /missions 응답(정렬: sort_order). */
public record MissionListResponse(
		List<MissionResponse> items) {
}
