package com.recordapp.domain.character.service;

import com.recordapp.domain.character.dto.MissionListResponse;
import com.recordapp.domain.character.dto.MissionResponse;
import com.recordapp.domain.character.dto.MissionRow;
import com.recordapp.domain.character.dto.UserCharacterStateRow;
import com.recordapp.domain.character.dto.UserMissionRow;
import com.recordapp.domain.character.dto.UserProgressRow;
import com.recordapp.domain.character.mapper.MissionMapper;
import com.recordapp.domain.character.mapper.UserCharacterMapper;
import com.recordapp.domain.character.vo.MissionRuleType;
import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 미션 조회 서비스(달성 여부 + 진행률).
 *
 * <p><b>진행률은 O(1)</b>이다 — 매 조회마다 diaries/resolutions 를 세지 않고 {@code user_progress}
 * (+ 레벨) 스냅샷의 컬럼 하나만 본다. 미션 수만큼의 SQL 도 없다(카탈로그는 캐시, 사용자 상태는 쿼리 3개).
 *
 * <p>달성 판정·보상 지급(user_missions INSERT·코인)은 <b>보상 엔진(Task 028)</b> 소관이다.
 * 여기서는 이미 기록된 달성 이력과 현재 진행률만 보여준다 — {@link #progressOf}(순수 함수)는
 * Task 028 의 MissionEvaluator 가 그대로 재사용할 수 있도록 static 으로 분리해 둔다.
 */
@Service
public class MissionService {

	private final MissionMapper missionMapper;
	private final UserCharacterMapper userCharacterMapper;
	private final CatalogCache catalog;
	private final CharacterService characterService;

	public MissionService(MissionMapper missionMapper,
			UserCharacterMapper userCharacterMapper,
			CatalogCache catalog,
			CharacterService characterService) {
		this.missionMapper = missionMapper;
		this.userCharacterMapper = userCharacterMapper;
		this.catalog = catalog;
		this.characterService = characterService;
	}

	/** GET /missions — 미션 목록 + 달성 여부 + 진행률. */
	@Transactional
	public MissionListResponse getMissions(Long userId) {
		characterService.ensureState(userId);
		return new MissionListResponse(buildMissions(userId));
	}

	/**
	 * 미션 응답 목록 조립(옷장 목록의 lockedBy 도 이 결과를 재사용한다 — 같은 진행률을 두 번 계산하지 않는다).
	 * 상태 행은 ensureState 이후라 존재하지만, 방어적으로 null 이면 0/레벨1 스냅샷으로 취급한다.
	 */
	List<MissionResponse> buildMissions(Long userId) {
		UserProgressRow progress = userCharacterMapper.findProgress(userId);
		if (progress == null) {
			progress = UserProgressRow.zero();
		}
		UserCharacterStateRow state = userCharacterMapper.findState(userId);
		int level = state == null ? 1 : state.level();

		Map<String, OffsetDateTime> achieved = new HashMap<>();
		for (UserMissionRow row : missionMapper.findAchievedMissions(userId)) {
			achieved.put(row.missionCode(), row.achievedAt());
		}

		final UserProgressRow snapshot = progress;
		return catalog.missions().stream()
				.map(m -> toResponse(m, snapshot, level, achieved))
				.toList();
	}

	private MissionResponse toResponse(MissionRow m, UserProgressRow progress, int level,
			Map<String, OffsetDateTime> achievedAtByCode) {
		int current = progressOf(m.ruleType(), progress, level);
		OffsetDateTime achievedAt = achievedAtByCode.get(m.code());
		// achieved 는 '이력이 있는가'로만 판정한다 — 임계값 도달만으로 달성 처리하지 않는다(지급은 Task 028).
		return new MissionResponse(
				m.code(), m.title(), m.description(),
				new MissionResponse.Rule(m.ruleType(), m.threshold()),
				current, m.threshold(),
				achievedAt != null, achievedAt,
				m.coinReward(), m.itemGroupReward());
	}

	/**
	 * ★ 진행률 산출(순수 함수). 규칙 타입별로 스냅샷의 컬럼 하나만 읽는다 — O(1), 부작용 없음.
	 * (Task 028 의 MissionEvaluator 가 {@code progressOf(...) >= threshold} 로 달성을 판정하면 된다.)
	 */
	public static int progressOf(MissionRuleType type, UserProgressRow progress, int level) {
		return switch (type) {
			case DIARY_COUNT -> progress.confirmedDiaryCount();
			case CONSECUTIVE_DAYS -> progress.consecutiveDays();
			case RESOLUTION_SUCCESS -> progress.resolutionSuccessCount();
			case RESOLUTION_STREAK -> progress.maxStreakSeq();
			case LEVEL -> level;
		};
	}
}
