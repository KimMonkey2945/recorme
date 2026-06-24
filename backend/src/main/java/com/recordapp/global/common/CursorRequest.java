package com.recordapp.global.common;

/**
 * 커서 페이징 요청 파라미터(?cursor=&size=).
 * 첫 페이지는 cursor 생략, size 기본 20 / 최대 50.
 */
public record CursorRequest(Long cursor, Integer size) {

	public static final int DEFAULT_SIZE = 20;
	public static final int MAX_SIZE = 50;

	/** null·범위 밖 size를 안전한 값으로 보정 */
	public int safeSize() {
		if (size == null || size <= 0) {
			return DEFAULT_SIZE;
		}
		return Math.min(size, MAX_SIZE);
	}
}
