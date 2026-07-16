package com.recordapp.domain.character.mapper;

import com.recordapp.domain.character.dto.EmotionCountRow;
import com.recordapp.domain.character.dto.MonthlyEventAggRow;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * 월간 회고(Task 032) 집계 매퍼. 전부 내부 {@code userId} 로만 대상을 좁힌다(IDOR 차단).
 *
 * <p>기록 기반 집계(확정일·감정)는 {@code diaries.written_date}(DATE) 로, 보상 기반 집계(코인·완주)는
 * {@code character_events.created_at}(TIMESTAMPTZ) 로 월 범위를 자른다 — 두 축의 시간 타입이 다르므로
 * 서비스가 각각에 맞는 경계값을 넘긴다.
 */
@Mapper
public interface RetrospectMapper {

	/**
	 * 이달 확정 기록의 written_date 목록(오름차순). 확정 수와 최장 연속일 계산의 원천이다.
	 * 하루 1기록(uq_diary_user_day)이라 날짜는 유일하다.
	 */
	List<LocalDate> findConfirmedDates(@Param("userId") long userId,
			@Param("monthStart") LocalDate monthStart,
			@Param("nextMonth") LocalDate nextMonth);

	/**
	 * 이달 감정 분포(프리셋 + 직접 입력, 많은 순). 감정 미입력 기록은 어느 쪽에도 잡히지 않는다.
	 */
	List<EmotionCountRow> aggregateEmotions(@Param("userId") long userId,
			@Param("monthStart") LocalDate monthStart,
			@Param("nextMonth") LocalDate nextMonth);

	/**
	 * 이달 획득 코인 합 + 완주 수(character_events.created_at 월 범위). 기록이 없어도 0/0 을 반환한다.
	 */
	MonthlyEventAggRow aggregateEvents(@Param("userId") long userId,
			@Param("monthStart") OffsetDateTime monthStart,
			@Param("nextMonth") OffsetDateTime nextMonth);

	/**
	 * 이달 획득(구매·해금)한 아이템 group 코드(acquired_at 월 범위, 최신순). 이미지·이름은 카탈로그로 해석한다.
	 */
	List<String> findAcquiredGroupCodes(@Param("userId") long userId,
			@Param("monthStart") OffsetDateTime monthStart,
			@Param("nextMonth") OffsetDateTime nextMonth);
}
