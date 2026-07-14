package com.recordapp.domain.character.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

/**
 * 배치 착용 요청의 항목 1개. 아이템은 언제나 {@code groupCode}(소유·착용 단위)로 지정한다 —
 * 캐릭터별 variant(이미지)는 서버가 선택 캐릭터로 해석하므로 클라이언트는 알 필요가 없다.
 *
 * <p>{@code slotIndex} 는 단일 슬롯이면 0, ROOM_PROP 만 0~5. 범위(0~5)는 여기서 1차 방어하고,
 * "단일 슬롯인데 index &gt; 0" 같은 조합 규칙은 서비스가 슬롯 메타를 보고 판정한다(400 VALIDATION_ERROR).
 */
public record EquipmentItemRequest(
		@NotBlank String slot,
		@NotNull @Min(0) @Max(5) Short slotIndex,
		@NotBlank String groupCode) {
}
