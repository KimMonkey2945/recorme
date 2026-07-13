package com.recordapp.domain.diary.mapper;

import com.recordapp.domain.diary.dto.DiaryFeedItem;
import com.recordapp.domain.diary.dto.DiaryListItem;
import com.recordapp.domain.diary.dto.DiaryRow;
import com.recordapp.domain.diary.dto.DiarySummaryDay;
import com.recordapp.domain.diary.dto.DiaryUpsertCommand;
import com.recordapp.domain.diary.dto.FeedDetailResponse;
import com.recordapp.domain.diary.dto.SharedDiaryResponse;
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
	 * 내 기록 목록(커서 페이징, id DESC). 활성 행만 대상으로 한다.
	 * <p>cursor 가 null 이면 첫 페이지(최신부터), 아니면 id &lt; cursor 인 다음 페이지를 가져온다.
	 * hasNext 판정을 위해 서비스가 실제 size+1 을 limit 으로 넘긴다.
	 * 각 항목은 대표 이미지·총 장수를 content(Delta) jsonb 파싱으로 채운다(컬렉션 미포함).
	 */
	List<DiaryListItem> findList(@Param("userId") Long userId,
			@Param("cursor") Long cursor,
			@Param("limit") int limit);

	/**
	 * 해당 월(yearMonth "yyyy-MM")의 내 기록 목록(written_date DESC, id DESC). 활성 행만 대상.
	 * 하루 1기록이라 한 달 ≤31건 → 커서 페이징 없이 한 번에 반환한다. 각 항목은 대표 이미지·총 장수만 포함.
	 */
	List<DiaryListItem> findByMonth(@Param("userId") Long userId, @Param("yearMonth") String yearMonth);

	/** 사용자+날짜로 활성 기록 단건 조회(없으면 null). 인라인 이미지는 content(Delta)에 포함된다. */
	DiaryRow findByDateAndUser(@Param("userId") Long userId, @Param("date") LocalDate date);

	/** 내부 PK+사용자로 활성 기록 단건 조회(없으면 null). 인라인 이미지는 content(Delta)에 포함된다. */
	DiaryRow findByIdAndUser(@Param("id") Long id, @Param("userId") Long userId);

	/** 해당 기록이 사용자 소유의 활성 기록인지 여부. */
	boolean existsOwned(@Param("id") Long id, @Param("userId") Long userId);

	/**
	 * 최근 24시간 내 확정(감정 분석 트리거)된 기록 수. 확정 시 analysis_status 가 DRAFT 를 벗어나고
	 * updated_at 이 now() 로 갱신되므로, {@code analysis_status <> 'DRAFT' AND updated_at >= now()-24h}
	 * 로 확정 횟수를 근사한다. LLM 비용 상한(사용자별 일일 확정 한도) 판정에 쓴다.
	 */
	int countRecentConfirmations(@Param("userId") Long userId);

	/**
	 * 해당 월(yearMonth "yyyy-MM")에 활성 기록이 존재하는 날짜별 요약 목록(written_date 오름차순).
	 * 캘린더 표시용 — 각 항목은 날짜·분석상태와 감정색·무드 이모지용 필드를 담는다.
	 * 하루 1기록이라 날짜당 1건이며 한 달 ≤31건 → 페이징 없이 한 번에 반환한다.
	 */
	List<DiarySummaryDay> findSummaryDays(@Param("userId") Long userId, @Param("yearMonth") String yearMonth);

	/**
	 * 내부 PK+사용자 기준 본문/공개범위 수정. {@code analysis_status='DRAFT'} 인 기록(미확정)만
	 * 대상으로 하며 상태는 그대로 DRAFT 로 유지한다(수정만으로 재분석을 트리거하지 않는다).
	 * 감정 분석 트리거는 확정 경로({@code upsert confirm=true})에서만 발생한다.
	 *
	 * @return 갱신된 행 수(0이면 대상 부재/타인 소유/삭제됨/이미 확정됨)
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

	/**
	 * 내부 PK+사용자 기준 공개범위(visibility)만 수정. 본문·analysis_status 는 건드리지 않으므로
	 * 확정(DRAFT 아님) 기록도 대상이 된다(본문 불변성과 분리). 활성 소유 행만.
	 *
	 * @return 갱신된 행 수(0이면 대상 부재/타인 소유/삭제됨)
	 */
	int updateVisibilityByIdAndUser(@Param("id") Long id,
			@Param("userId") Long userId,
			@Param("visibility") String visibility);

	/**
	 * 공유 토큰으로 공개 조회(비인증). 활성·확정(DRAFT 아님)·PRIVATE 아님 기록만 반환(없으면 null).
	 * 내부 PK·소유자 식별자·공감 정보는 노출하지 않고 작성자 표시명·본문·감정 테마만 담는다.
	 */
	SharedDiaryResponse findByShareToken(@Param("shareToken") String shareToken);

	/**
	 * 피드 목록(커서 페이징, id DESC). viewer 가 볼 수 있는 DONE 기록만:
	 * 본인 OR PUBLIC OR (FRIENDS AND 수락 친구). 차단(BLOCKED) 상대 기록은 제외.
	 * 전문(content) 대신 감정 카드 요약(content_text 미리보기·감정색·공감 요약)만 싣는다.
	 * <p>hasNext 판정을 위해 서비스가 size+1 을 limit 으로 넘긴다.
	 */
	List<DiaryFeedItem> findFeed(@Param("viewerId") long viewerId,
			@Param("cursor") Long cursor,
			@Param("limit") int limit);

	/**
	 * 피드 카드 탭 시 전문 조회(viewer-aware, 없으면 null → 404).
	 * 본인 글은 상태 무관, 그 외는 확정(DRAFT 아님)·활성·볼 수 있는(PUBLIC 또는 FRIENDS-친구) 글만.
	 * 차단(BLOCKED) 상대 글은 제외. 작성자 표시 정보 + 본문 + 감정 테마를 담는다.
	 */
	FeedDetailResponse findViewableById(@Param("viewerId") long viewerId, @Param("id") long id);
}
