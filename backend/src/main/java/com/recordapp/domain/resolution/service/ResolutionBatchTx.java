package com.recordapp.domain.resolution.service;

import com.recordapp.domain.resolution.dto.OverdueCheck;
import com.recordapp.domain.resolution.dto.ReminderTarget;
import com.recordapp.domain.resolution.mapper.ResolutionMapper;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.List;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 스케줄러 드레인 루프가 반복 호출하는 <b>짧은 트랜잭션 배치 메서드</b> 모음.
 *
 * <p><b>자기호출 @Transactional 우회</b>: 스케줄러(@Scheduled)가 자기 클래스의 배치 메서드를 루프에서
 * 직접 호출하면 프록시를 우회해 @Transactional 이 적용되지 않는다. 따라서 배치 로직을 별도 빈으로 분리해
 * 스케줄러가 <b>주입받아 호출</b>하도록 한다(EmotionAnalysisPoller 가 EmotionAnalysisService 를 주입해
 * @Async 를 프록시로 태우는 것과 동일한 방향). 각 배치 호출은 독립된 짧은 트랜잭션으로 커밋되며
 * {@code FOR UPDATE SKIP LOCKED} 잠금을 즉시 푼다 — 외부 IO(푸시)는 이 트랜잭션 밖에서 수행한다.
 */
@Component
public class ResolutionBatchTx {

	private final ResolutionMapper mapper;

	public ResolutionBatchTx(ResolutionMapper mapper) {
		this.mapper = mapper;
	}

	/**
	 * 자정 실패 배치 1회분. 초과 미완료 체크를 선점→MISSED 로 전이하고, 부모 결심을 FAILED 로 전이한다.
	 * 같은 결심의 여러 체크가 함께 초과돼도 {@code markResolutionFailed} 의 ONGOING 가드로 첫 건만 1행이므로
	 * {@code newlyFailed} 엔 (결심당) 1건만 담긴다(실패 알림 1회).
	 *
	 * @return {@link FailureBatch}(선점 건수 fetched, 이번에 FAILED 로 전이된 결심들 newlyFailed)
	 */
	@Transactional
	public FailureBatch failOverdueBatch(LocalDate today, int limit) {
		List<OverdueCheck> overdue = mapper.findOverduePendingChecks(today, limit); // FOR UPDATE SKIP LOCKED
		if (overdue.isEmpty()) {
			return new FailureBatch(0, List.of());
		}
		List<OverdueCheck> newlyFailed = new ArrayList<>();
		for (OverdueCheck c : overdue) {
			mapper.markCheckMissed(c.checkId());
			if (mapper.markResolutionFailed(c.resolutionId()) == 1) {
				// 이 호출이 ONGOING→FAILED 를 확정 → 실패 알림 대상(결심당 1회).
				newlyFailed.add(c);
			}
		}
		return new FailureBatch(overdue.size(), newlyFailed);
	}

	/**
	 * 오늘 리마인더 배치 1회분. 단일 {@code UPDATE ... RETURNING} 으로 대상을 원자적으로 선점(reminded_on 마킹)해
	 * 반환한다(하루 1회 멱등). 실제 발송은 호출자가 이 트랜잭션 커밋 후 트랜잭션 밖에서 수행한다.
	 *
	 * @return 이번에 선점된 발송 대상들(빈 리스트면 지금 발송할 대상 없음 → 드레인 종료)
	 */
	@Transactional
	public List<ReminderTarget> claimReminderBatch(LocalDate today, LocalTime now, int limit) {
		return mapper.claimDueReminders(today, now, limit);
	}

	/**
	 * 실패 배치 1회 결과.
	 *
	 * @param fetched     선점(처리)한 초과 체크 수(드레인 루프 종료 판정용)
	 * @param newlyFailed 이번 배치에서 ONGOING→FAILED 로 전이된 결심들(실패 알림 대상)
	 */
	public record FailureBatch(int fetched, List<OverdueCheck> newlyFailed) {
	}
}
