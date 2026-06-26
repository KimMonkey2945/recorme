package com.recordapp.domain.diary.mapper;

import com.recordapp.domain.diary.dto.DiaryListItem;
import com.recordapp.domain.diary.dto.DiaryRow;
import com.recordapp.domain.diary.dto.DiaryUpsertCommand;
import java.time.LocalDate;
import java.util.List;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * diaries 테이블 매퍼. 하루 1기록 upsert·조회·요약·수정·소프트삭제를 둔다.
 * 모든 조회/수정은 user_id 로 소유권을 식별하고 활성 행(deleted_at IS NULL)만 대상으로 한다(IDOR 차단).
 */
@Mapper
public interface DiaryMapper {

	/**
	 * 하루 1기록 upsert. user_id+written_date(활성) 충돌 시 UPDATE 로 전환한다.
	 * 본문이 바뀐 경우에만 analysis_status 를 PENDING 으로 되돌려 재분석을 트리거한다.
	 * <p>실행 후 {@link DiaryUpsertCommand#getId()} 에 PK 가, {@link DiaryUpsertCommand#isInserted()} 에
	 * 신규 INSERT 여부(xmax=0)가 RETURNING 으로 채워진다.
	 */
	void upsert(DiaryUpsertCommand command);

	/**
	 * 내 일기 목록(커서 페이징, id DESC). 활성 행만 대상으로 한다.
	 * <p>cursor 가 null 이면 첫 페이지(최신부터), 아니면 id &lt; cursor 인 다음 페이지를 가져온다.
	 * hasNext 판정을 위해 서비스가 실제 size+1 을 limit 으로 넘긴다.
	 * 각 항목은 대표 이미지·총 장수를 content(Delta) jsonb 파싱으로 채운다(컬렉션 미포함).
	 */
	List<DiaryListItem> findList(@Param("userId") Long userId,
			@Param("cursor") Long cursor,
			@Param("limit") int limit);

	/**
	 * 해당 월(yearMonth "yyyy-MM")의 내 일기 목록(written_date DESC, id DESC). 활성 행만 대상.
	 * 하루 1기록이라 한 달 ≤31건 → 커서 페이징 없이 한 번에 반환한다. 각 항목은 대표 이미지·총 장수만 포함.
	 */
	List<DiaryListItem> findByMonth(@Param("userId") Long userId, @Param("yearMonth") String yearMonth);

	/** 사용자+날짜로 활성 일기 단건 조회(없으면 null). 인라인 이미지는 content(Delta)에 포함된다. */
	DiaryRow findByDateAndUser(@Param("userId") Long userId, @Param("date") LocalDate date);

	/** 내부 PK+사용자로 활성 일기 단건 조회(없으면 null). 인라인 이미지는 content(Delta)에 포함된다. */
	DiaryRow findByIdAndUser(@Param("id") Long id, @Param("userId") Long userId);

	/** 해당 일기가 사용자 소유의 활성 일기인지 여부. */
	boolean existsOwned(@Param("id") Long id, @Param("userId") Long userId);

	/**
	 * 해당 월(yearMonth "yyyy-MM")에 활성 일기가 존재하는 날짜 목록("yyyy-MM-dd", DISTINCT, 오름차순).
	 * 캘린더 표시용.
	 */
	List<String> findSummaryDates(@Param("userId") Long userId, @Param("yearMonth") String yearMonth);

	/**
	 * 내부 PK+사용자 기준 본문/공개범위 수정. 순수 텍스트(content_text)가 바뀐 경우에만
	 * analysis_status 를 PENDING 으로 되돌린다(서식·이미지만 바뀌면 재분석 불필요).
	 *
	 * @return 갱신된 행 수(0이면 대상 부재/타인 소유/삭제됨)
	 */
	int updateByIdAndUser(@Param("id") Long id,
			@Param("userId") Long userId,
			@Param("content") String content,
			@Param("contentText") String contentText,
			@Param("visibility") String visibility);

	/**
	 * 내부 PK+사용자 기준 소프트 삭제(deleted_at=now()).
	 *
	 * @return 갱신된 행 수(0이면 대상 부재/타인 소유/이미 삭제됨)
	 */
	int softDeleteByIdAndUser(@Param("id") Long id, @Param("userId") Long userId);
}
