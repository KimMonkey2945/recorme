package com.recordapp.domain.resolution.service;

import com.recordapp.domain.resolution.ResolutionConstraints;
import com.recordapp.domain.resolution.dto.CreateResolutionRequest;
import com.recordapp.domain.resolution.dto.ExtendResolutionRequest;
import com.recordapp.domain.resolution.dto.ResolutionCalendarDay;
import com.recordapp.domain.resolution.dto.ResolutionCheckView;
import com.recordapp.domain.resolution.dto.ResolutionDetailResponse;
import com.recordapp.domain.resolution.dto.ResolutionInsertCommand;
import com.recordapp.domain.resolution.dto.ResolutionListItem;
import com.recordapp.domain.resolution.dto.ResolutionRow;
import com.recordapp.domain.resolution.dto.UpdateResolutionRequest;
import com.recordapp.domain.resolution.mapper.ResolutionMapper;
import com.recordapp.domain.resolution.vo.CheckStatus;
import com.recordapp.domain.resolution.vo.ResolutionStatus;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.List;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 작심삼일 서비스. 소유권은 항상 SecurityContext 의 userId 로만 식별한다(IDOR 차단).
 * 날짜 판정은 시스템 기본 타임존이 아니라 KST(Asia/Seoul) 벽시계 기준으로 통일한다.
 *
 * <p>상태 전이 규칙: 생성=ONGOING(체크 3행 PENDING 프리생성), 완료체크=오늘 체크 DONE→3일 완주 시 SUCCESS(조건부 1회),
 * 연장=성공한 결심의 '다음 3일'을 같은 streak_group 으로 신규 생성, 취소=soft delete.
 * SUCCESS 전이 시 커밋 후(afterCommit) 완주 축하 푸시를 발송한다(발송은 ResolutionPushNotifier 가 @Async 로 처리).
 * (자정 실패배치·오늘 리마인더는 ResolutionFailurePoller·ResolutionReminderScheduler 가 담당.)
 */
@Service
public class ResolutionService {

	/** 모든 날짜 판정 기준 타임존(서버 기본 타임존과 무관하게 KST 벽시계로 통일). */
	private static final ZoneId KST = ZoneId.of("Asia/Seoul");

	private final ResolutionMapper resolutionMapper;
	private final ResolutionPushNotifier pushNotifier;

	public ResolutionService(ResolutionMapper resolutionMapper, ResolutionPushNotifier pushNotifier) {
		this.resolutionMapper = resolutionMapper;
		this.pushNotifier = pushNotifier;
	}

	/**
	 * 작심삼일 생성. 시작일은 오늘/미래만 허용(과거면 검증 실패로 롤백 — @FutureOrPresent 가 1차 방어).
	 * 결심 INSERT 후 일별 체크 3행(PENDING)을 프리생성하고, 상세를 재조회해 반환한다.
	 */
	@Transactional
	public ResolutionDetailResponse create(Long userId, CreateResolutionRequest req) {
		LocalDate today = LocalDate.now(KST);
		if (req.startDate().isBefore(today)) {
			throw new BusinessException(ErrorCode.VALIDATION_ERROR, "시작일은 오늘 이후여야 해요.");
		}
		LocalDate endDate = req.startDate().plusDays(ResolutionConstraints.DURATION_DAYS - 1);

		// streakGroupId=null → SQL 이 gen_random_uuid() 로 새 체인 생성, streakSeq=1(첫 도전).
		ResolutionInsertCommand cmd = new ResolutionInsertCommand(
				userId, req.title(), req.startDate(), endDate, req.reminderTime(), null, (short) 1);
		resolutionMapper.insertResolution(cmd);
		resolutionMapper.insertChecks(cmd.getId(), req.startDate());
		return buildDetail(userId, cmd.getId());
	}

	/**
	 * 내 결심 목록(커서 페이징, id DESC). status(진행/성공/실패) 필터는 optional.
	 * hasNext 판정을 위해 size+1 을 조회해 초과분이 있으면 잘라내고 hasNext=true 로 본다.
	 */
	@Transactional(readOnly = true)
	public PageResponse<ResolutionListItem> getList(Long userId, String status, CursorRequest req) {
		int size = req.safeSize();
		String statusFilter = (status == null || status.isBlank()) ? null : status;
		List<ResolutionListItem> rows = resolutionMapper.findList(userId, statusFilter, req.cursor(), size + 1);

		boolean hasNext = rows.size() > size;
		List<ResolutionListItem> items = hasNext ? rows.subList(0, size) : rows;
		Long nextCursor = items.isEmpty() ? null : items.get(items.size() - 1).id();
		return PageResponse.of(items, hasNext ? nextCursor : null, hasNext);
	}

	/** 월별 캘린더((날짜, 결심)당 1행). 활성 결심의 체크만. */
	@Transactional(readOnly = true)
	public List<ResolutionCalendarDay> getCalendar(Long userId, String yearMonth) {
		return resolutionMapper.findCalendar(userId, yearMonth);
	}

	/** 결심 단건 상세(헤더 + 3일 체크). 없으면 RESOLUTION_NOT_FOUND. */
	@Transactional(readOnly = true)
	public ResolutionDetailResponse getDetail(Long userId, Long id) {
		return buildDetail(userId, id);
	}

	/**
	 * 오늘자 완료 체크. status 가 ONGOING 이 아니면 RESOLUTION_NOT_ACTIVE.
	 * <p>오늘 PENDING 체크를 DONE 으로 전이한다. 0행이면 원인을 findCheck 로 판정한다 —
	 * 체크가 없거나(미래 시작/오늘 없음) 상태가 DONE 이 아니면 RESOLUTION_CHECK_NOT_TODAY,
	 * 이미 DONE 이면 멱등 통과(재요청 200). 이후 3일 완주면 SUCCESS 로 조건부 전이(정확히 1회).
	 */
	@Transactional
	public ResolutionDetailResponse completeToday(Long userId, Long id) {
		LocalDate today = LocalDate.now(KST);
		ResolutionRow row = resolutionMapper.findByIdAndUser(id, userId);
		if (row == null) {
			throw new BusinessException(ErrorCode.RESOLUTION_NOT_FOUND);
		}
		if (!ResolutionStatus.ONGOING.name().equals(row.status())) {
			throw new BusinessException(ErrorCode.RESOLUTION_NOT_ACTIVE);
		}

		int updated = resolutionMapper.markCheckDone(id, today);
		if (updated == 0) {
			// PENDING 전이 실패 원인 판정: 오늘 체크 없음/미래 시작 vs 이미 DONE(멱등).
			ResolutionCheckView check = resolutionMapper.findCheck(id, today);
			if (check == null || !CheckStatus.DONE.name().equals(check.status())) {
				throw new BusinessException(ErrorCode.RESOLUTION_CHECK_NOT_TODAY);
			}
			// 이미 DONE → 멱등 통과(중복 완료 요청 허용).
		}

		// 3일 모두 DONE 이면 SUCCESS 로 조건부 전이(status='ONGOING' 가드로 정확히 1회).
		// 1행 반환 = 이 요청이 ONGOING→SUCCESS 를 확정 → 커밋 후 완주 축하 푸시 1회 발송.
		if (resolutionMapper.markResolutionSuccessIfAllDone(id) == 1) {
			registerSuccessPushAfterCommit(userId, id);
		}
		return buildDetail(userId, id);
	}

	/**
	 * 완주 축하 푸시를 커밋 이후로 미룬다(롤백 시 오발송 방지 — DiaryService.triggerAnalysisIfPending 과 동일 패턴).
	 * 발송 자체는 {@link ResolutionPushNotifier} 가 @Async("pushExecutor") 로 트랜잭션·요청 스레드 밖에서 처리한다.
	 * 트랜잭션 동기화가 비활성이면 즉시 발송으로 폴백한다.
	 */
	private void registerSuccessPushAfterCommit(Long userId, Long resolutionId) {
		if (TransactionSynchronizationManager.isSynchronizationActive()) {
			TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
				@Override
				public void afterCommit() {
					pushNotifier.sendSuccess(userId, resolutionId);
				}
			});
		} else {
			pushNotifier.sendSuccess(userId, resolutionId);
		}
	}

	/**
	 * 연장. 성공(SUCCESS)한 결심만 연장 가능(아니면 RESOLUTION_NOT_EXTENDABLE).
	 * 이전 결심의 '다음 3일'을 같은 streak_group 에 streak_seq+1 로 신규 생성한다. 시작일은
	 * {@code max(prev.endDate+1, today)}(과거로 처지지 않게). 알림 시각은 요청값 우선, 없으면 이전 값 승계.
	 * <p>동시 이중 연장은 선검사(existsExtensionInGroup) + uq(streak_group_id, streak_seq) 제약으로 막고,
	 * 경합으로 제약 위반이 나면 RESOLUTION_ALREADY_EXTENDED 로 변환한다.
	 */
	@Transactional
	public ResolutionDetailResponse extend(Long userId, Long id, ExtendResolutionRequest req) {
		LocalDate today = LocalDate.now(KST);
		ResolutionRow prev = resolutionMapper.findByIdAndUser(id, userId);
		if (prev == null) {
			throw new BusinessException(ErrorCode.RESOLUTION_NOT_FOUND);
		}
		if (!ResolutionStatus.SUCCESS.name().equals(prev.status())) {
			throw new BusinessException(ErrorCode.RESOLUTION_NOT_EXTENDABLE);
		}

		short newSeq = (short) (prev.streakSeq() + 1);
		// 선검사: 이미 다음 순번이 있으면 이중 연장(경합은 아래 제약이 최종 방어).
		if (resolutionMapper.existsExtensionInGroup(prev.streakGroupId(), newSeq)) {
			throw new BusinessException(ErrorCode.RESOLUTION_ALREADY_EXTENDED);
		}

		LocalDate newStart = prev.endDate().plusDays(1);
		if (newStart.isBefore(today)) {
			newStart = today;
		}
		LocalDate newEnd = newStart.plusDays(ResolutionConstraints.DURATION_DAYS - 1);
		LocalTime reminder = req.reminderTime() != null ? req.reminderTime() : prev.reminderTime();

		ResolutionInsertCommand cmd = new ResolutionInsertCommand(
				userId, prev.title(), newStart, newEnd, reminder, prev.streakGroupId(), newSeq);
		try {
			resolutionMapper.insertResolution(cmd);
		} catch (DuplicateKeyException e) {
			// uq(streak_group_id, streak_seq) 위반 — 동시 이중 연장 경합. 롤백 후 충돌로 응답.
			throw new BusinessException(ErrorCode.RESOLUTION_ALREADY_EXTENDED);
		}
		resolutionMapper.insertChecks(cmd.getId(), newStart);
		return buildDetail(userId, cmd.getId());
	}

	/**
	 * 수정. 진행 중(ONGOING) 결심의 제목·알림 시각만 갱신한다(시작일 변경은 미지원 — 삭제 후 재작성으로 유도).
	 * 대상 부재/타인 소유면 RESOLUTION_NOT_FOUND, 성공/실패 등 진행 중이 아니면 RESOLUTION_NOT_ACTIVE.
	 */
	@Transactional
	public ResolutionDetailResponse update(Long userId, Long id, UpdateResolutionRequest req) {
		ResolutionRow row = resolutionMapper.findByIdAndUser(id, userId);
		if (row == null) {
			throw new BusinessException(ErrorCode.RESOLUTION_NOT_FOUND);
		}
		if (!ResolutionStatus.ONGOING.name().equals(row.status())) {
			throw new BusinessException(ErrorCode.RESOLUTION_NOT_ACTIVE);
		}
		// 0행이면 선검증과 write 사이에 상태가 바뀐 것(예: 경합하는 completeToday 로 SUCCESS 전이).
		// 매퍼의 status='ONGOING' 가드로 조용히 스킵되므로, completeToday/cancel 과 동일하게 실패로 알린다.
		int updated = resolutionMapper.updateResolution(id, userId, req.title(), req.reminderTime());
		if (updated == 0) {
			throw new BusinessException(ErrorCode.RESOLUTION_NOT_ACTIVE);
		}
		return buildDetail(userId, id);
	}

	/** 취소(소프트 삭제). 0행이면 대상 부재/타인 소유 → RESOLUTION_NOT_FOUND. */
	@Transactional
	public void cancel(Long userId, Long id) {
		int deleted = resolutionMapper.softDelete(id, userId);
		if (deleted == 0) {
			throw new BusinessException(ErrorCode.RESOLUTION_NOT_FOUND);
		}
	}

	/** 결심 헤더 row + 3일 체크를 조립해 상세 응답으로 매핑한다. 없으면 RESOLUTION_NOT_FOUND. */
	private ResolutionDetailResponse buildDetail(Long userId, Long id) {
		ResolutionRow row = resolutionMapper.findByIdAndUser(id, userId);
		if (row == null) {
			throw new BusinessException(ErrorCode.RESOLUTION_NOT_FOUND);
		}
		List<ResolutionCheckView> checks = resolutionMapper.findChecks(id);
		return new ResolutionDetailResponse(row.id(), row.title(), row.startDate(), row.endDate(),
				row.status(), row.reminderTime(), row.streakSeq(), checks);
	}
}
