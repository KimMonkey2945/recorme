package com.recordapp.global.common;

import java.util.List;

/**
 * 커서 페이징 응답.
 * data: { "items": [...], "nextCursor": 1234, "hasNext": true }
 * 정렬은 id DESC(최신순), OFFSET 미사용.
 */
public record PageResponse<T>(List<T> items, Long nextCursor, boolean hasNext) {

	public static <T> PageResponse<T> of(List<T> items, Long nextCursor, boolean hasNext) {
		return new PageResponse<>(items, nextCursor, hasNext);
	}
}
