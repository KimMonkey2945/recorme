package com.recordapp.domain.resolution.mapper;

import com.recordapp.domain.resolution.dto.OverdueCheck;
import com.recordapp.domain.resolution.dto.ReminderTarget;
import com.recordapp.domain.resolution.dto.ResolutionCalendarDay;
import com.recordapp.domain.resolution.dto.ResolutionCheckView;
import com.recordapp.domain.resolution.dto.ResolutionInsertCommand;
import com.recordapp.domain.resolution.dto.ResolutionListItem;
import com.recordapp.domain.resolution.dto.ResolutionRow;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * resolutions·resolution_checks 매퍼. 작심삼일 생성·조회·완료체크·연장·취소를 둔다.
 * 모든 조회/수정은 user_id 로 소유권을 식별하고 활성 행(deleted_at IS NULL)만 대상으로 한다(IDOR 차단).
 */
@Mapper
public interface ResolutionMapper {

	/**
	 * 결심 1건 INSERT. 실행 후 {@link ResolutionInsertCommand#getId()} 에 PK 가 RETURNING 으로 채워진다.
	 * streakGroupId 가 null 이면 {@code gen_random_uuid()} 로 새 체인을 만들고, 있으면 그 체인에 이어 붙인다.
	 */
	void insertResolution(ResolutionInsertCommand command);

	/**
	 * 일별 체크 3행 프리생성. {@code generate_series(0,2)} 로 check_date=startDate+0/1/2, day_index=1/2/3,
	 * status='PENDING' 을 한 번에 INSERT 한다. user_id 는 부모 결심 행에서 승계한다(비정규화 컬럼).
	 */
	void insertChecks(@Param("resolutionId") Long resolutionId, @Param("startDate") LocalDate startDate);

	/** 내부 PK+사용자로 활성 결심 단건 조회(없으면 null). */
	ResolutionRow findByIdAndUser(@Param("id") Long id, @Param("userId") Long userId);

	/**
	 * 내 결심 목록(커서 페이징, id DESC 최신순). 활성 행만 대상.
	 * <p>status 가 null/빈값이면 전체, 값이 있으면 해당 상태만. cursor 가 null 이면 첫 페이지,
	 * 아니면 id &lt; cursor 인 다음 페이지. hasNext 판정을 위해 서비스가 size+1 을 limit 으로 넘긴다.
	 */
	List<ResolutionListItem> findList(@Param("userId") Long userId,
			@Param("status") String status,
			@Param("cursor") Long cursor,
			@Param("limit") int limit);

	/** 해당 결심의 일별 체크 목록(day_index 오름차순, 3행). */
	List<ResolutionCheckView> findChecks(@Param("resolutionId") Long resolutionId);

	/**
	 * 해당 월(yearMonth "yyyy-MM")의 캘린더 항목((날짜, 결심)당 1행). 활성 결심의 체크만 대상.
	 * user_id·check_date range scan 으로 월 구간을 한 번에 조회한다.
	 */
	List<ResolutionCalendarDay> findCalendar(@Param("userId") Long userId, @Param("yearMonth") String yearMonth);

	/** 해당 결심의 특정 날짜 체크 단건(없으면 null). 완료체크 멱등 판정용. */
	ResolutionCheckView findCheck(@Param("resolutionId") Long resolutionId, @Param("date") LocalDate date);

	/**
	 * 같은 체인에 지정 순번(streakSeq)의 결심이 이미 있는지 여부. 연장 전 이중 연장 선검사용
	 * (최종 방어는 uq_resolutions_streak_seq 제약).
	 */
	boolean existsExtensionInGroup(@Param("streakGroupId") String streakGroupId, @Param("streakSeq") short streakSeq);

	/**
	 * 오늘자 체크를 DONE 으로 전이. {@code check_date=today AND status='PENDING'} 인 행만 대상.
	 *
	 * @return 갱신된 행 수(0이면 오늘 체크 없음/미래 시작/이미 DONE·MISSED)
	 */
	int markCheckDone(@Param("resolutionId") Long resolutionId, @Param("today") LocalDate today);

	/**
	 * 3일 체크가 모두 DONE 이면 결심을 SUCCESS 로 전이. {@code status='ONGOING'} 가드로 정확히 1회만 전이한다.
	 *
	 * @return 갱신된 행 수(0이면 아직 미완료 체크 존재/이미 터미널 상태)
	 */
	int markResolutionSuccessIfAllDone(@Param("id") Long id);

	/**
	 * 내부 PK+사용자 기준 소프트 삭제(deleted_at=now()). 활성 행만 대상.
	 *
	 * @return 갱신된 행 수(0이면 대상 부재/타인 소유/이미 삭제됨)
	 */
	int softDelete(@Param("id") Long id, @Param("userId") Long userId);

	// ===== 스케줄러(자정 실패 배치 / 오늘 리마인더) 전용 =====

	/**
	 * 기한 초과 미완료 체크 선점(자정 실패 배치). {@code check_date < today} 인데 아직 PENDING 이고,
	 * 부모 결심이 ONGOING·활성인 행을 {@code FOR UPDATE OF c SKIP LOCKED} 로 집어 온다
	 * (다중 인스턴스에서 서로 다른 배치가 겹치지 않게 잠긴 행은 건너뛴다). 짧은 트랜잭션에서 호출한다.
	 *
	 * @param today KST 기준 오늘(이 날짜 이전 체크가 대상)
	 * @param limit 1회 선점 최대 건수
	 * @return 선점한 초과 체크들(빈 리스트면 처리할 대상 없음)
	 */
	List<OverdueCheck> findOverduePendingChecks(@Param("today") LocalDate today, @Param("limit") int limit);

	/**
	 * 체크를 MISSED 로 전이. PENDING 행만 대상이라 이미 다른 상태면 0행(멱등).
	 *
	 * @return 갱신된 행 수
	 */
	int markCheckMissed(@Param("checkId") long checkId);

	/**
	 * 결심을 FAILED 로 전이. {@code status='ONGOING'} 가드로 정확히 1회만 전이한다
	 * (같은 결심의 여러 체크가 한 배치에서 초과돼도 첫 건만 1행 → 실패 알림 1회).
	 *
	 * @return 갱신된 행 수(1이면 이 호출이 ONGOING→FAILED 를 확정, 0이면 이미 터미널)
	 */
	int markResolutionFailed(@Param("resolutionId") long resolutionId);

	/**
	 * 오늘 리마인더 대상을 원자적으로 선점(마킹)해 반환. 단일 {@code UPDATE ... RETURNING} 안에서
	 * {@code FOR UPDATE OF c SKIP LOCKED} 로 오늘·PENDING·미발송({@code reminded_on IS DISTINCT FROM today})·
	 * {@code reminder_time <= now} 인 체크를 집어 {@code reminded_on=today} 로 마킹하고 발송 정보를 돌려준다.
	 * 마킹과 선점이 한 문장이라 하루 1회 멱등이 보장되고, 발송(외부 IO)은 이 트랜잭션 밖에서 수행한다.
	 * {@code reminder_time IS NULL} 인 결심은 대상에서 제외한다(알림 없음).
	 *
	 * @param today KST 오늘, @param now KST 현재 벽시계, @param limit 1회 선점 최대 건수
	 * @return 발송 대상들(빈 리스트면 지금 발송할 대상 없음)
	 */
	List<ReminderTarget> claimDueReminders(@Param("today") LocalDate today,
			@Param("now") LocalTime now,
			@Param("limit") int limit);
}
