package com.recordapp.domain.resolution.vo;

/**
 * 일별 체크(resolution_checks) 상태. V9 {@code chk_resolution_checks_status} CHECK 와 동일 집합.
 * <p>PENDING(미완료) → DONE(완료, completed_at 필수) | MISSED(그 날 미완료 확정, 자정 배치 — 이번 범위 밖).
 */
public enum CheckStatus {
	PENDING,
	DONE,
	MISSED
}
