package com.recordapp.domain.character.dto;

import com.recordapp.domain.character.CharacterConstants;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.List;

/**
 * 착용 <b>배치 교체</b> 요청. 보낸 배열이 착용 <b>전체 스냅샷</b>이 된다(부분 PATCH 아님).
 *
 * <p>해제는 그 슬롯을 배열에서 빼면 되고, 빈 배열이면 전 슬롯 비움이다(별도 DELETE 엔드포인트 없음).
 * 검증을 전부 통과한 경우에만 DELETE→INSERT 를 한 트랜잭션에서 수행하므로 <b>원자적</b>이다
 * (5개 중 3번째가 미보유면 1·2번도 반영되지 않는다).
 */
public record UpdateEquipmentRequest(
		@NotNull @Size(max = CharacterConstants.EQUIPMENT_MAX_ITEMS) @Valid List<EquipmentItemRequest> equipment) {
}
