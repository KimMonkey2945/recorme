package com.recordapp.domain.character.service;

import com.recordapp.domain.character.dto.LineRow;
import com.recordapp.domain.character.mapper.CharacterRewardMapper;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;
import org.springframework.stereotype.Service;

/**
 * 리액션 대사 선택기. (선택 캐릭터, 맥락 context)에 맞는 character_lines 후보 중 하나를 가중 랜덤으로 고른다.
 *
 * <p><b>전용 우선 → 공용 폴백.</b> 선택 캐릭터 전용 대사가 하나라도 있으면 그 안에서 고르고,
 * 없으면 공용(character_code IS NULL) 대사에서 고른다(캐릭터 색을 살리되 빈 대사를 피한다).
 * 후보가 아예 없으면 null 을 반환한다(payload 에 대사 없이 코인만 실린다).
 *
 * <p>context 는 감정이 아니라 <b>맥락</b>이다: CONFIRM(기록 확정)·STREAK_3·STREAK_7(연속 마일스톤)·
 * MISSION 등. (LEVEL_UP 은 레벨 폐기로 사용하지 않는다.)
 */
@Service
public class LineService {

	private final CharacterRewardMapper mapper;

	public LineService(CharacterRewardMapper mapper) {
		this.mapper = mapper;
	}

	/** 선택된 대사 한 줄(텍스트 + 모션 트리거). 트리거는 없을 수 있다(null=기본 모션). */
	public record PickedLine(String lineKo, String riveTrigger) {
	}

	/**
	 * (characterCode, context) 대사 1줄 선택. characterCode 가 null(미선택)이면 공용 대사만 후보다.
	 * 후보 없음 → null.
	 */
	public PickedLine pick(String characterCode, String context) {
		List<LineRow> all = mapper.findLines(characterCode, context);
		if (all.isEmpty()) {
			return null;
		}
		// 전용 대사가 하나라도 있으면 전용만, 없으면 공용으로 폴백.
		List<LineRow> specific = all.stream().filter(l -> l.characterCode() != null).toList();
		List<LineRow> pool = specific.isEmpty() ? all : specific;

		LineRow chosen = weightedPick(pool);
		return new PickedLine(chosen.lineKo(), chosen.riveTrigger());
	}

	/** 가중 랜덤 선택(weight 합에서 누적 구간으로 하나 뽑기). 모든 weight 는 DB CHECK 로 >0 이 보장된다. */
	private LineRow weightedPick(List<LineRow> pool) {
		int total = pool.stream().mapToInt(LineRow::weight).sum();
		int r = ThreadLocalRandom.current().nextInt(total);
		int acc = 0;
		for (LineRow line : pool) {
			acc += line.weight();
			if (r < acc) {
				return line;
			}
		}
		// 부동 없음(정수 누적) — 방어적으로 마지막 항목 반환.
		return pool.get(pool.size() - 1);
	}
}
