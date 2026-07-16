package com.recordapp.domain.character.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.recordapp.domain.character.config.CharacterCoinProperties;
import com.recordapp.domain.character.dto.AckRewardsResponse;
import com.recordapp.domain.character.dto.RewardEventRow;
import com.recordapp.domain.character.dto.RewardResponse;
import com.recordapp.domain.character.dto.UserProgressRow;
import com.recordapp.domain.character.dto.WalletResponse;
import com.recordapp.domain.character.mapper.CharacterRewardMapper;
import com.recordapp.domain.character.mapper.UserCharacterMapper;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import java.time.LocalDate;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * ★ 멱등 보상 엔진(Task 028). 기록 확정·작심삼일 진척·출석을 트리거로 <b>코인 적립 · 진척도 갱신 ·
 * 연속 마일스톤 · 리액션 대사 생성</b>을 수행한다. 아이템 지급(미션 보상)은 아직 범위 밖이다
 * (아이템이 확정되면 {@link #grant} 뒤에 소유 부여 한 줄만 추가하면 된다 — 훅 지점만 남겨 둔다).
 *
 * <h3>불변식</h3>
 * <ol>
 *   <li><b>단일 멱등 관문</b> — 모든 부작용은 {@code character_events} 게이트({@code INSERT … ON CONFLICT
 *       DO NOTHING}) 를 통과해야만 발생한다. 0행이면 즉시 no-op. 재전달·폴러 중복·더블탭이 전부 흡수된다.</li>
 *   <li><b>REQUIRES_NEW 격리</b> — 리스너의 @Async 스레드에서 독립 트랜잭션으로 돈다. 보상이 터져도
 *       기록/결심 저장 트랜잭션은 이미 커밋돼 있어 롤백되지 않는다(단방향).</li>
 *   <li><b>순서 고정</b> — 게이트 → 코인 적립 → (진척도) → 대사 → payload. 진척도 갱신은 게이트 통과 뒤에만.</li>
 * </ol>
 *
 * <p>적립 기준값은 {@link CharacterCoinProperties}(= application.yml = docs/coin-rewards.md)에서 온다.
 * 값을 0 으로 두면 해당 트리거는 이벤트를 만들지 않는다(= 보상 끄기).
 */
@Service
public class CharacterRewardService {

	private static final Logger log = LoggerFactory.getLogger(CharacterRewardService.class);

	private final CharacterRewardMapper mapper;
	private final UserCharacterMapper userCharacterMapper;
	private final CharacterService characterService;
	private final LineService lineService;
	private final CharacterCoinProperties coin;
	private final ObjectMapper objectMapper;

	public CharacterRewardService(CharacterRewardMapper mapper,
			UserCharacterMapper userCharacterMapper,
			CharacterService characterService,
			LineService lineService,
			CharacterCoinProperties coin,
			ObjectMapper objectMapper) {
		this.mapper = mapper;
		this.userCharacterMapper = userCharacterMapper;
		this.characterService = characterService;
		this.lineService = lineService;
		this.coin = coin;
		this.objectMapper = objectMapper;
	}

	// ===== 트리거: 기록 확정 =====

	/**
	 * 기록 확정 보상. 코인 적립 + 확정 수·연속일 갱신 + (연속 마일스톤 파생 지급) + CONFIRM 대사.
	 * event_key = {@code DIARY_CONFIRM:{diaryId}} 이라 재전달·백필 중복에도 정확히 1회.
	 */
	@Transactional(propagation = Propagation.REQUIRES_NEW)
	public void handleDiaryConfirmed(long userId, long diaryId, LocalDate writtenDate) {
		characterService.ensureState(userId); // JIT(멱등) — 지갑·진척 행 보장

		String eventKey = "DIARY_CONFIRM:" + diaryId;
		if (mapper.insertGate(userId, eventKey, "DIARY_CONFIRM", coin.diary(), diaryId) == 0) {
			return; // 이미 적립된 확정
		}
		Integer balance = creditIfPositive(userId, coin.diary());
		// 게이트 통과 뒤에만 진척 증가(정확히 1회). 반환 스냅샷으로 연속 마일스톤을 판정한다.
		UserProgressRow progress = mapper.upsertDiaryProgress(userId, writtenDate);

		finalizeReaction(userId, eventKey, "CONFIRM", coin.diary(), balance);

		// 연속 기록 마일스톤(7/30/60 …) — 오늘 연속일에 정확히 도달했으면 계정당 1회 지급.
		grantStreakMilestoneIfReached(userId, progress.consecutiveDays());
	}

	/** 현재 연속일이 설정된 마일스톤과 정확히 일치하면 별도 이벤트로 1회 지급(STREAK:{days} 게이트). */
	private void grantStreakMilestoneIfReached(long userId, int consecutiveDays) {
		int reward = coin.streakCoin(consecutiveDays);
		if (reward <= 0) {
			return; // 마일스톤 아님
		}
		String eventKey = "STREAK:" + consecutiveDays;
		if (mapper.insertGate(userId, eventKey, "STREAK", reward, null) == 0) {
			return; // 이미 받은 마일스톤
		}
		Integer balance = creditIfPositive(userId, reward);
		// 7일 이상은 STREAK_7 맥락 대사, 그 미만(향후 추가 시)은 STREAK_3.
		String context = consecutiveDays >= 7 ? "STREAK_7" : "STREAK_3";
		finalizeReaction(userId, eventKey, context, reward, balance);
	}

	// ===== 트리거: 작심삼일 진척(1·2일차 / 완주) =====

	/**
	 * 작심삼일 진척 보상. 완주(completed)면 완주 코인 + 완주 수·최대 streak 갱신, 아니면 해당 일차 코인.
	 * event_key 는 완주 {@code RESOLUTION_SUCCESS:{id}} / 일차 {@code RESOLUTION_DAY:{id}:{day}} 로 갈린다.
	 */
	@Transactional(propagation = Propagation.REQUIRES_NEW)
	public void handleResolutionProgress(long userId, long resolutionId,
			int dayOrdinal, boolean completed, int streakSeq) {
		characterService.ensureState(userId);

		if (completed) {
			String eventKey = "RESOLUTION_SUCCESS:" + resolutionId;
			if (mapper.insertGate(userId, eventKey, "RESOLUTION_SUCCESS", coin.resolutionComplete(), null) == 0) {
				return;
			}
			Integer balance = creditIfPositive(userId, coin.resolutionComplete());
			mapper.bumpResolutionProgress(userId, streakSeq);
			finalizeReaction(userId, eventKey, "CONFIRM", coin.resolutionComplete(), balance);
			return;
		}

		int reward = (dayOrdinal == 1) ? coin.resolutionDay1() : coin.resolutionDay2();
		String eventKey = "RESOLUTION_DAY:" + resolutionId + ":" + dayOrdinal;
		if (mapper.insertGate(userId, eventKey, "RESOLUTION_DAY", reward, null) == 0) {
			return;
		}
		Integer balance = creditIfPositive(userId, reward);
		finalizeReaction(userId, eventKey, "CONFIRM", reward, balance);
	}

	// ===== 트리거: 출석(앱 접속) =====

	/** 출석 적립 결과(앱이 배지·리액션 표시에 쓴다). granted=false 면 오늘 이미 출석했거나 보상 0. */
	public record AttendanceResult(boolean granted, int coin, int balance) {
	}

	/**
	 * 출석 보상(하루 1회). event_key = {@code ATTENDANCE:{date}}. 사용자가 직접 부르는 동기 경로라
	 * REQUIRES_NEW 가 아닌 일반 트랜잭션으로 처리하고 결과를 즉시 돌려준다.
	 */
	@Transactional
	public AttendanceResult grantAttendance(long userId, LocalDate date) {
		characterService.ensureState(userId);
		int reward = coin.attendance();
		int current = currentBalance(userId);
		if (reward <= 0) {
			return new AttendanceResult(false, 0, current); // 출석 보상 꺼짐
		}
		String eventKey = "ATTENDANCE:" + date;
		if (mapper.insertGate(userId, eventKey, "ATTENDANCE", reward, null) == 0) {
			return new AttendanceResult(false, reward, current); // 오늘 이미 출석
		}
		int balance = mapper.creditWallet(userId, reward);
		finalizeReaction(userId, eventKey, "IDLE", reward, balance);
		return new AttendanceResult(true, reward, balance);
	}

	// ===== 조회(지갑·보상함·리액션) =====

	/** 코인 잔액 + 미확인 보상 수. */
	@Transactional
	public WalletResponse getWallet(long userId) {
		characterService.ensureState(userId);
		Integer balance = userCharacterMapper.findWalletBalance(userId);
		int unacked = userCharacterMapper.countUnackedRewards(userId);
		return new WalletResponse(balance == null ? 0 : balance, unacked);
	}

	/** 미확인 보상함(커서 페이징, id DESC). size+1 조회로 hasNext 를 판정한다. */
	@Transactional
	public PageResponse<RewardResponse> getRewards(long userId, CursorRequest req) {
		characterService.ensureState(userId);
		int size = req.safeSize();
		List<RewardEventRow> rows = mapper.findUnackedRewards(userId, req.cursor(), size + 1);

		boolean hasNext = rows.size() > size;
		List<RewardResponse> items = (hasNext ? rows.subList(0, size) : rows).stream()
				.map(this::toRewardResponse)
				.toList();
		Long nextCursor = items.isEmpty() ? null : items.get(items.size() - 1).id();
		return PageResponse.of(items, hasNext ? nextCursor : null, hasNext);
	}

	/** 미확인 보상 전체 확인 처리(뱃지 리셋). */
	@Transactional
	public AckRewardsResponse ackRewards(long userId) {
		characterService.ensureState(userId);
		int acked = mapper.ackAllRewards(userId);
		return new AckRewardsResponse(acked, 0);
	}

	/**
	 * 확정 직후 리액션 조회(폴링 불필요 — 확정 즉시 생성). 해당 기록의 DIARY_CONFIRM payload 를 돌려준다.
	 * 아직 적립 이벤트가 안 생겼으면(비동기 처리 직전) null 을 반환한다(앱은 잠깐 뒤 재조회하거나 생략).
	 */
	@Transactional(readOnly = true)
	public RewardResponse getReaction(long userId, long diaryId) {
		RewardEventRow row = mapper.findReaction(userId, diaryId);
		return row == null ? null : toRewardResponse(row);
	}

	private RewardResponse toRewardResponse(RewardEventRow row) {
		return new RewardResponse(row.id(), row.eventType(), row.coinDelta(), row.balanceAfter(),
				parsePayload(row.payload()), row.createdAt());
	}

	/** payload(JSONB ::text)를 JsonNode 로 파싱. null/파싱 실패는 null 로 견고하게 처리(조회가 깨지지 않게). */
	private JsonNode parsePayload(String payload) {
		if (payload == null) {
			return null;
		}
		try {
			return objectMapper.readTree(payload);
		} catch (Exception e) {
			log.warn("리액션 payload 파싱 실패(무시): {}", e.getMessage());
			return null;
		}
	}

	// ===== 공통 =====

	/** delta>0 이면 적립 후 잔액, 아니면 현재 잔액(코인 0 이벤트는 balance_after NULL 로 남긴다). */
	private Integer creditIfPositive(long userId, int delta) {
		return delta > 0 ? mapper.creditWallet(userId, delta) : null;
	}

	private int currentBalance(long userId) {
		Integer b = userCharacterMapper.findWalletBalance(userId); // 순수 조회(쓰기 없음)
		return b == null ? 0 : b;
	}

	/**
	 * 게이트 행에 리액션 페이로드를 확정한다. 대사는 선택 캐릭터·맥락으로 뽑고(없으면 대사 없이 코인만),
	 * balance_after 스냅샷과 함께 payload(JSONB)로 되쓴다 — 앱 리액션·보상함의 단일 소스.
	 */
	private void finalizeReaction(long userId, String eventKey, String context, int coinDelta, Integer balance) {
		String selected = characterService.selectedCharacterOf(userId);
		LineService.PickedLine line = lineService.pick(selected, context);

		ObjectNode payload = objectMapper.createObjectNode();
		payload.put("context", context);
		payload.put("coin", coinDelta);
		if (balance != null) {
			payload.put("balance", balance);
		}
		if (line != null) {
			payload.put("line", line.lineKo());
			if (line.riveTrigger() != null) {
				payload.put("riveTrigger", line.riveTrigger());
			}
		}
		mapper.finalizeEvent(userId, eventKey, balance, toJson(payload));
	}

	private String toJson(ObjectNode node) {
		try {
			return objectMapper.writeValueAsString(node);
		} catch (Exception e) {
			// payload 직렬화 실패는 적립 자체를 되돌리지 않는다(코인·게이트는 이미 반영). 대사만 유실.
			log.warn("리액션 payload 직렬화 실패 — 대사 없이 진행: {}", e.getMessage());
			return null;
		}
	}
}
