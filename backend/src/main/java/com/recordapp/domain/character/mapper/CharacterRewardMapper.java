package com.recordapp.domain.character.mapper;

import com.recordapp.domain.character.dto.ConfirmedDiaryRef;
import com.recordapp.domain.character.dto.LineRow;
import com.recordapp.domain.character.dto.RewardEventRow;
import com.recordapp.domain.character.dto.UserProgressRow;
import java.time.LocalDate;
import java.util.List;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * 보상 엔진(Task 028) 전용 매퍼 — 멱등 게이트·코인 원장·진척도 갱신·대사·보상함.
 * 모든 쓰기는 SecurityContext 에서 온 내부 {@code userId} 로만 대상을 좁힌다(IDOR 차단).
 *
 * <p><b>★ 부작용의 유일한 진입 조건 = {@link #insertGate}</b>. 0행이면 이미 처리된 이벤트이므로
 * 서비스는 즉시 no-op 으로 빠진다. 재전달·폴러 중복·더블탭이 전부 여기서 흡수된다
 * (uq_character_events_key UNIQUE 가 물리적 근거).
 */
@Mapper
public interface CharacterRewardMapper {

	/**
	 * ★ 멱등 게이트. {@code INSERT … ON CONFLICT (user_id, event_key) DO NOTHING}.
	 *
	 * @return 1 = 이번에 처음 꽂힘(부작용 진행), 0 = 이미 처리된 이벤트(호출부는 즉시 return)
	 */
	int insertGate(@Param("userId") long userId,
			@Param("eventKey") String eventKey,
			@Param("eventType") String eventType,
			@Param("coinDelta") int coinDelta,
			@Param("diaryId") Long diaryId);

	/**
	 * 코인 적립(경합 안전). {@code UPDATE … SET balance = balance + delta … RETURNING balance}.
	 * delta 는 적립(+)만 사용한다(소비/구매는 이번 범위 밖). RETURNING 이라 {@code <select>} 로 매핑한다.
	 *
	 * @return 적립 후 잔액 스냅샷(원장의 balance_after 로 되쓴다)
	 */
	int creditWallet(@Param("userId") long userId, @Param("delta") int delta);

	/** 게이트 행의 원장 확정: balance_after 스냅샷 + payload(리액션 페이로드) 기록. */
	void finalizeEvent(@Param("userId") long userId,
			@Param("eventKey") String eventKey,
			@Param("balanceAfter") Integer balanceAfter,
			@Param("payload") String payload);

	/**
	 * 코인 소비(경합 안전). {@code UPDATE … SET balance = balance - price WHERE balance >= price RETURNING balance}.
	 * 잔액 부족이면 0행이라 null 을 돌려주고, 호출부는 COIN_INSUFFICIENT 로 던져 트랜잭션(게이트 포함)을 롤백한다.
	 *
	 * @return 차감 후 잔액(부족이면 null)
	 */
	Integer deductWallet(@Param("userId") long userId, @Param("price") int price);

	/** 구매한 group 소유 부여(멱등). */
	int insertOwnedGroup(@Param("userId") long userId, @Param("groupCode") String groupCode);

	/** 특정 이벤트를 확인 처리(구매는 '보상'이 아니므로 미확인 배지에 잡히지 않게 즉시 ack). */
	void markEventAcked(@Param("userId") long userId, @Param("eventKey") String eventKey);

	/**
	 * 기록 확정 진척 UPSERT + 연속일 계산 후 스냅샷 RETURNING.
	 * <ul>
	 *   <li>confirmed_diary_count += 1</li>
	 *   <li>consecutive_days: last == 오늘이면 불변 / last == 어제면 +1 / 그 외 1 로 리셋</li>
	 *   <li>last_confirmed_date = 이번 확정일(과거로 후퇴하지 않게 GREATEST)</li>
	 * </ul>
	 * ⚠️ 게이트 통과(1행) 뒤에만 호출해야 정확히 1회 증가한다.
	 */
	UserProgressRow upsertDiaryProgress(@Param("userId") long userId,
			@Param("writtenDate") LocalDate writtenDate);

	/**
	 * 작심삼일 완주 진척 갱신: resolution_success_count += 1, max_streak_seq = GREATEST(현재, streakSeq).
	 * ⚠️ 완주 게이트 통과 뒤에만 호출.
	 */
	void bumpResolutionProgress(@Param("userId") long userId, @Param("streakSeq") int streakSeq);

	// ===== 대사 =====

	/** (context, 선택 캐릭터) 후보 대사 — 전용 + 공용 전부. 선택/폴백·가중 랜덤은 LineService 가 Java 로 수행. */
	List<LineRow> findLines(@Param("characterCode") String characterCode,
			@Param("context") String context);

	// ===== 보상함 / 리액션 =====

	/** 확정 직후 리액션 조회 — 그 기록의 DIARY_CONFIRM 이벤트 payload(없으면 null). 폴링 불필요(확정 즉시 생성). */
	RewardEventRow findReaction(@Param("userId") long userId, @Param("diaryId") long diaryId);

	/** 미확인 보상함(acked_at IS NULL) 커서 목록(id DESC). size+1 조회로 hasNext 판정. */
	List<RewardEventRow> findUnackedRewards(@Param("userId") long userId,
			@Param("cursor") Long cursor,
			@Param("limit") int limit);

	/** 미확인 보상 전체 확인 처리(acked_at = now()). @return 확인된 행 수. */
	int ackAllRewards(@Param("userId") long userId);

	// ===== 백스톱 폴러 =====

	/**
	 * 확정(analysis_status <> 'DRAFT')됐으나 DIARY_CONFIRM 게이트가 없는 기록.
	 * 즉시 적립(커밋 후 이벤트)이 유실된 경우의 보정 대상이다. 게이트가 멱등하므로 재적립은 불가능하다.
	 */
	List<ConfirmedDiaryRef> findUnrewardedConfirmedDiaries(@Param("limit") int limit);
}
