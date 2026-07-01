package com.recordapp.domain.resolution.vo;

/**
 * 결심(resolutions) 상태. V9 {@code chk_resolutions_status} CHECK 와 동일 집합.
 * <p>ONGOING(진행) → SUCCESS(3일 완주) | FAILED(하루라도 미완료, 자정 배치가 전이 — 이번 범위 밖) 로 흐르는 터미널 상태다.
 * '예정'(미래 시작)은 별도 상태가 아니라 {@code start_date > today} 로 파생한다.
 */
public enum ResolutionStatus {
	ONGOING,
	SUCCESS,
	FAILED
}
