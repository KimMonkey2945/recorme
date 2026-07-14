package com.recordapp.domain.character.mapper;

import com.recordapp.domain.character.dto.CharacterItemRow;
import com.recordapp.domain.character.dto.CharacterRow;
import com.recordapp.domain.character.dto.ItemGroupRow;
import java.util.List;
import org.apache.ibatis.annotations.Mapper;

/**
 * 카탈로그(마스터) 매퍼 — characters·item_groups·character_items.
 * 전부 변경 빈도가 낮은 마스터라 {@code CatalogCache} 가 기동 시 1회 적재하고 요청마다 조회하지 않는다.
 * (사용자별 상태는 {@link UserCharacterMapper}, 미션은 {@link MissionMapper} 소관.)
 */
@Mapper
public interface CharacterCatalogMapper {

	/** 활성 캐릭터 전체(sort_order 순). 온보딩 목록의 원본. */
	List<CharacterRow> findCharacters();

	/** 활성 아이템 그룹 전체(slot, sort_order 순). 옷장·상점 목록의 원본. */
	List<ItemGroupRow> findItemGroups();

	/**
	 * 캐릭터별 렌더 variant 전체(공용 variant 포함, {@code character_code IS NULL}).
	 * 캐시가 (group_code, character_code) 로 색인해 메모리에서 해석한다 — uq_variant 가 쌍당 1행을 보장한다.
	 */
	List<CharacterItemRow> findCharacterItems();
}
