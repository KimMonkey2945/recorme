package com.recordapp.domain.character.vo;

/**
 * 아이템 획득 경로. V15 {@code chk_item_groups_acquire} CHECK 와 동일 집합.
 *
 * <p>DEFAULT=가입 시 기본 지급(JIT), MISSION=미션 달성으로만 해금, COIN=상점 구매(Task 028).
 * 해금·구매는 Task 028 소관이며, 이 Task 는 DEFAULT 기본 지급과 조회·착용까지만 다룬다.
 */
public enum AcquireType {
	DEFAULT,
	MISSION,
	COIN
}
