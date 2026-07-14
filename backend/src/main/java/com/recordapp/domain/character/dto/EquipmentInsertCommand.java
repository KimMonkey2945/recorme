package com.recordapp.domain.character.dto;

/**
 * user_equipment INSERT 1행(배치 착용 교체용 내부 커맨드).
 * 검증(슬롯 일치·소유·variant 존재)을 모두 통과한 항목만 여기까지 온다.
 */
public record EquipmentInsertCommand(
		String slot,
		short slotIndex,
		String groupCode) {
}
