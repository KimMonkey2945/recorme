package com.recordapp.domain.character.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.recordapp.domain.character.dto.CharacterItemRow;
import com.recordapp.domain.character.dto.CharacterRow;
import com.recordapp.domain.character.dto.ItemGroupRow;
import com.recordapp.domain.character.dto.MissionRow;
import com.recordapp.domain.character.dto.ResolvedVariant;
import com.recordapp.domain.character.mapper.CharacterCatalogMapper;
import com.recordapp.domain.character.mapper.MissionMapper;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * 카탈로그 메모리 캐시 — characters·item_groups·character_items·missions.
 *
 * <p>전부 마스터(변경 빈도 ~0, 마이그레이션으로만 바뀜)라 매 요청 SQL 을 태울 이유가 없다.
 * 최초 접근 시 1회 적재하고(지연 로딩 — 기동 순서·Flyway 의존을 만들지 않는다) 이후엔 메모리에서 읽는다.
 * JSONB(render_meta) 파싱도 적재 시 1회만 수행해 {@link ResolvedVariant} 로 굳힌다.
 *
 * <p>스냅샷은 <b>불변</b> 객체를 volatile 참조로 통째 교체한다 — 읽기 경로에 락이 없고,
 * {@link #reload()}(시드 변경 후 수동 갱신용) 중에도 읽는 쪽은 이전 스냅샷을 일관되게 본다.
 *
 * <p>★ variant 해석: {@code (group_code, 선택 캐릭터)} → 캐릭터 전용 variant 우선, 없으면
 * 공용(character_code IS NULL) 폴백, 그것도 없으면 빈 값(호출자가 409 ITEM_VARIANT_MISSING).
 * DB 의 uq_variant(NULLS NOT DISTINCT)가 쌍당 1행을 보장하므로 색인은 단순 Map 으로 충분하다.
 * (착용 조회 경로는 같은 규칙을 SQL 조인으로도 수행한다 — UserCharacterMapper.findEquippedItems)
 */
@Component
public class CatalogCache {

	private static final Logger log = LoggerFactory.getLogger(CatalogCache.class);

	/** 공용 variant(character_code IS NULL)의 색인 키. 캐릭터 코드와 충돌하지 않는 값. */
	private static final String COMMON_VARIANT_KEY = "*";

	private final CharacterCatalogMapper catalogMapper;
	private final MissionMapper missionMapper;
	private final ObjectMapper objectMapper;

	private volatile Snapshot snapshot;

	public CatalogCache(CharacterCatalogMapper catalogMapper,
			MissionMapper missionMapper,
			ObjectMapper objectMapper) {
		this.catalogMapper = catalogMapper;
		this.missionMapper = missionMapper;
		this.objectMapper = objectMapper;
	}

	// ===== 조회 =====

	/** 활성 캐릭터 목록(sort_order 순). */
	public List<CharacterRow> characters() {
		return snapshot().characters();
	}

	/** 캐릭터 단건(없거나 비활성이면 null). */
	public CharacterRow character(String code) {
		return code == null ? null : snapshot().characterByCode().get(code);
	}

	/** 활성 아이템 그룹 목록(slot, sort_order 순). */
	public List<ItemGroupRow> itemGroups() {
		return snapshot().itemGroups();
	}

	/** 아이템 그룹 단건(없거나 비활성이면 null). */
	public ItemGroupRow itemGroup(String code) {
		return code == null ? null : snapshot().itemGroupByCode().get(code);
	}

	/** 활성 미션 목록(sort_order 순). */
	public List<MissionRow> missions() {
		return snapshot().missions();
	}

	/**
	 * ★ (group_code + 선택 캐릭터) → 렌더 variant 해석.
	 * 캐릭터 전용 variant 우선, 없으면 공용 폴백. 어느 쪽도 없으면 null(호출자가 409 로 판정).
	 *
	 * @param characterCode 선택 캐릭터(미선택이면 null → 공용 variant 만 해석)
	 */
	public ResolvedVariant resolveVariant(String groupCode, String characterCode) {
		Map<String, ResolvedVariant> byCharacter = snapshot().variants().get(groupCode);
		if (byCharacter == null) {
			return null;
		}
		if (characterCode != null) {
			ResolvedVariant specific = byCharacter.get(characterCode);
			if (specific != null) {
				return specific;
			}
		}
		return byCharacter.get(COMMON_VARIANT_KEY);
	}

	/** JSONB 원문(::text) → JsonNode. 파싱 불가·NULL 이면 null(렌더 메타는 선택 정보라 조회를 깨지 않는다). */
	public JsonNode toJson(String raw) {
		if (raw == null || raw.isBlank()) {
			return null;
		}
		try {
			return objectMapper.readTree(raw);
		} catch (JsonProcessingException e) {
			log.warn("카탈로그 JSON 파싱 실패(무시하고 null 로 내려보냄): {}", raw, e);
			return null;
		}
	}

	/** 시드·마스터 변경 후 수동 갱신(운영 중 재기동 없이 반영). 읽기 경로는 교체 전 스냅샷을 계속 본다. */
	public void reload() {
		snapshot = load();
	}

	// ===== 내부 =====

	/** 지연 로딩(최초 1회). 동시 최초접근 시 중복 적재될 수 있으나 결과가 동일해 무해하다(idempotent). */
	private Snapshot snapshot() {
		Snapshot current = snapshot;
		if (current == null) {
			current = load();
			snapshot = current;
		}
		return current;
	}

	private Snapshot load() {
		List<CharacterRow> characters = List.copyOf(catalogMapper.findCharacters());
		List<ItemGroupRow> itemGroups = List.copyOf(catalogMapper.findItemGroups());
		List<MissionRow> missions = List.copyOf(missionMapper.findMissions());

		Map<String, CharacterRow> characterByCode = new LinkedHashMap<>();
		characters.forEach(c -> characterByCode.put(c.code(), c));

		Map<String, ItemGroupRow> itemGroupByCode = new LinkedHashMap<>();
		itemGroups.forEach(g -> itemGroupByCode.put(g.code(), g));

		// group_code → (캐릭터 코드 | COMMON) → 파싱 완료된 variant
		Map<String, Map<String, ResolvedVariant>> variants = new LinkedHashMap<>();
		for (CharacterItemRow row : catalogMapper.findCharacterItems()) {
			String key = row.characterCode() == null ? COMMON_VARIANT_KEY : row.characterCode();
			variants.computeIfAbsent(row.groupCode(), k -> new LinkedHashMap<>())
					.put(key, new ResolvedVariant(row.imageUrl(), row.riveSlot(), toJson(row.renderMeta())));
		}

		log.info("캐릭터 카탈로그 캐시 적재: 캐릭터 {}종, 아이템그룹 {}종, variant {}그룹, 미션 {}종",
				characters.size(), itemGroups.size(), variants.size(), missions.size());
		return new Snapshot(characters, Map.copyOf(characterByCode), itemGroups,
				Map.copyOf(itemGroupByCode), Map.copyOf(variants), missions);
	}

	/** 불변 스냅샷(통째 교체 대상). */
	private record Snapshot(
			List<CharacterRow> characters,
			Map<String, CharacterRow> characterByCode,
			List<ItemGroupRow> itemGroups,
			Map<String, ItemGroupRow> itemGroupByCode,
			Map<String, Map<String, ResolvedVariant>> variants,
			List<MissionRow> missions) {
	}
}
