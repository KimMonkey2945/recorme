package com.recordapp.domain.character.vo;

import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;

/**
 * 착용 부위. V15 {@code chk_item_groups_slot} / V17 {@code chk_user_equipment_slot} CHECK 와 동일 집합.
 *
 * <p>ROOM_PROP 만 0~5 여섯 칸 다중 진열이고(Rive {@code roomProp0..5} 와 1:1), 나머지는 0번 한 칸뿐이다.
 * DB 도 {@code chk_user_equipment_slot_index}(ROOM_PROP 이 아니면 index=0)로 같은 규칙을 강제하지만,
 * 서비스가 먼저 400 으로 걸러 SQLException 이 새지 않게 한다.
 */
public enum ItemSlot {
	HAT,
	OUTFIT,
	GLASSES,
	PROP,
	ROOM_PROP,
	BACKGROUND;

	/** 다중 진열 슬롯 여부(ROOM_PROP 만 true). */
	public boolean isMulti() {
		return this == ROOM_PROP;
	}

	/** 허용되는 최대 slot_index(단일 슬롯=0, ROOM_PROP=5). */
	public int maxSlotIndex() {
		return isMulti() ? 5 : 0;
	}

	/** 요청 문자열 → 슬롯. 미지의 값은 400 VALIDATION_ERROR(500 로 새지 않게). */
	public static ItemSlot from(String raw) {
		try {
			return valueOf(raw);
		} catch (IllegalArgumentException | NullPointerException e) {
			throw new BusinessException(ErrorCode.VALIDATION_ERROR, "알 수 없는 슬롯입니다: " + raw);
		}
	}
}
