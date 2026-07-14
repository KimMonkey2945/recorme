package com.recordapp.domain.character;

/**
 * 캐릭터 도메인 상수(ResolutionConstraints 관례).
 *
 * <p>레벨 곡선은 보상 엔진(Task 028)이 exp 적립과 함께 확정한다. 이 Task 는 조회 응답의
 * {@code expToNext} 를 채우기 위한 최소 규약(레벨당 고정 임계값)만 둔다 — 곡선이 바뀌면 여기만 고친다.
 */
public final class CharacterConstants {

	/** 다음 레벨까지 필요한 경험치(레벨당 고정). Task 028 이 곡선을 바꾸면 이 상수만 교체한다. */
	public static final int EXP_PER_LEVEL = 100;

	/** 배치 착용 요청 최대 항목 수(단일 슬롯 5종 + BACKGROUND + ROOM_PROP 6칸 = 12). */
	public static final int EQUIPMENT_MAX_ITEMS = 12;

	private CharacterConstants() {
	}
}
