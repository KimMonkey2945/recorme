package com.recordapp.domain.resolution.service;

import com.recordapp.domain.resolution.dto.OverdueCheck;
import java.time.LocalDate;
import java.time.ZoneId;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 자정 실패 배치 폴러. KST 자정 직후 하루가 지난 미완료 체크(check_date &lt; today, PENDING)를
 * MISSED 로, 그 결심을 FAILED 로 전이한다(하루라도 놓치면 실패). 상태 전이는 DB 트리거가 아니라 이 배치가 수행한다.
 *
 * <p>드레인 루프: {@link ResolutionBatchTx#failOverdueBatch}(짧은 @Transactional, FOR UPDATE SKIP LOCKED)를
 * 남는 대상이 없을 때까지 반복 호출한다. 자기호출 @Transactional 우회를 위해 배치 로직은 별도 빈(ResolutionBatchTx)에
 * 두고 주입받아 호출한다. 실패 알림(옵션)은 배치 커밋 후 트랜잭션 밖에서 @Async 로 발송한다.
 */
@Component
public class ResolutionFailurePoller {

	private static final Logger log = LoggerFactory.getLogger(ResolutionFailurePoller.class);

	/** 날짜 판정 기준 타임존(서버 기본과 무관하게 KST 벽시계로 통일). */
	private static final ZoneId KST = ZoneId.of("Asia/Seoul");

	private final ResolutionBatchTx batchTx;
	private final ResolutionPushNotifier notifier;
	private final int batchSize;
	private final boolean failureNotify;

	public ResolutionFailurePoller(ResolutionBatchTx batchTx,
			ResolutionPushNotifier notifier,
			@Value("${record.resolution.batch-size:100}") int batchSize,
			@Value("${record.resolution.failure-notify:true}") boolean failureNotify) {
		this.batchTx = batchTx;
		this.notifier = notifier;
		this.batchSize = batchSize;
		this.failureNotify = failureNotify;
	}

	/**
	 * KST 자정 직후(기본 00:05) 초과 미완료 체크를 실패 처리한다. cron 은 6필드(초 분 시 일 월 요일), zone=KST.
	 * (자정 정각을 피해 00:05 로 두어 당일 마지막 완료 요청과의 경계 경합 여지를 줄인다.)
	 */
	@Scheduled(cron = "${record.resolution.failure-cron:0 5 0 * * *}", zone = "Asia/Seoul")
	public void run() {
		LocalDate today = LocalDate.now(KST);
		int total = 0;
		while (true) {
			ResolutionBatchTx.FailureBatch batch = batchTx.failOverdueBatch(today, batchSize);
			if (batch.fetched() == 0) {
				break;
			}
			total += batch.fetched();
			if (failureNotify) {
				for (OverdueCheck t : batch.newlyFailed()) {
					// 커밋된 배치의 대상 — @Async 로 트랜잭션·루프 밖 발송.
					notifier.sendFailure(t.userId(), t.resolutionId());
				}
			}
			// 배치보다 적게 잡혔으면 더 남은 게 없음 → 불필요한 빈 조회 회피.
			if (batch.fetched() < batchSize) {
				break;
			}
		}
		if (total > 0) {
			log.info("작심삼일 실패 배치: 초과 체크 {}건 MISSED 처리(today={})", total, today);
		}
	}
}
