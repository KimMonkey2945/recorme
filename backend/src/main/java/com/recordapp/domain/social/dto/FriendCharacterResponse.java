package com.recordapp.domain.social.dto;

import com.recordapp.domain.character.dto.EquippedItemResponse;
import com.recordapp.domain.character.dto.SelectedCharacterResponse;
import java.util.List;

/**
 * 친구 둘러보기 — 캐릭터 홈 응답(읽기 전용).
 *
 * <p>내부 필드는 {@code MyCharacterResponse} 와 같은 DTO 를 재사용하되 <b>코인 잔액·미확인 보상 수는
 * 의도적으로 제외</b>한다. 0 으로 채워 내리지 않고 타입에서 아예 없앤 이유는, 나중에 누군가 값을 채워 넣는
 * 회귀를 컴파일 단계에서 막기 위해서다(응답 계약에 없는 필드는 만들지 않는다).
 *
 * <p>친구가 아직 캐릭터를 고르지 않았으면 {@code character = null} 이고 {@code equipment} 는 빈 목록이다
 * (404 가 아니라 200 + 빈 상태 — 본인 조회 규약과 동일).
 */
public record FriendCharacterResponse(
		SelectedCharacterResponse character,
		List<EquippedItemResponse> equipment) {
}
