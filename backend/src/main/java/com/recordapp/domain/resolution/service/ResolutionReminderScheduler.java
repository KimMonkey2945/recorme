package com.recordapp.domain.resolution.service;

import com.recordapp.domain.resolution.dto.ReminderTarget;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 오늘 리마인더 스케줄러. KST 벽시계로 {@code reminder_time <= now} 가 된 오늘 미완료 체크에
 * "아직 안 했어요" 푸시를 하루 1회 보낸다. {@code reminder_time IS NULL} 인 결심은 제외한다(알림 없음).
 *
 * <p>드레인 루프: {@link ResolutionBatchTx#claimReminderBatch}(짧은 @Transactional, 단일
 * {@code UPDATE ... RETURNING} + FOR UPDATE SKIP LOCKED)로 대상을 원자적으로 선점(reminded_on 마킹)하고,
 * 커밋 후 트랜잭션 밖에서 @Async 발송한다. 선점·마킹이 한 문장이라 다중 인스턴스에서도 중복 발송이 없다.
 * 자기호출 @Transactional 우회를 위해 배치 로직은 별도 빈(ResolutionBatchTx)에 두고 주입받아 호출한다.
 */
@Component
public class ResolutionReminderScheduler {

	private static final Logger log = LoggerFactory.getLogger(ResolutionReminderScheduler.class);

	/** 날짜·시각 판정 기준 타임존(서버 기본과 무관하게 KST 벽시계로 통일). */
	private static final ZoneId KST = ZoneId.of("Asia/Seoul");

	private final ResolutionBatchTx batchTx;
	private final ResolutionPushNotifier notifier;
	private final int batchSize;

	public ResolutionReminderScheduler(ResolutionBatchTx batchTx,
			ResolutionPushNotifier notifier,
			@Value("${record.resolution.batch-size:100}") int batchSize) {
		this.batchTx = batchTx;
		this.notifier = notifier;
		this.batchSize = batchSize;
	}

	/**
	 * 15분마다(기본) 발송 시각이 도래한 오늘 리마인더를 선점·발송한다. cron 6필드(초 분 시 일 월 요일), zone=KST.
	 * 사용자가 지정한 reminder_time(예: 09:00) 이후 첫 tick 에서 그날 1회만 발송된다(reminded_on 멱등).
	 */
	@Scheduled(cron = "${record.resolution.reminder-cron:0 */15 * * * *}", zone = "Asia/Seoul")
	public void run() {
		LocalDate today = LocalDate.now(KST);
		LocalTime now = LocalTime.now(KST);
		int total = 0;
		while (true) {
			List<ReminderTarget> targets = batchTx.claimReminderBatch(today, now, batchSize);
			if (targets.isEmpty()) {
				break;
			}
			total += targets.size();
			for (ReminderTarget t : targets) {
				// 이미 reminded_on 마킹·커밋된 대상 — @Async 로 트랜잭션·루프 밖 발송.
				notifier.sendReminder(t.userId(), t.resolutionId(), t.title());
			}
			if (targets.size() < batchSize) {
				break;
			}
		}
		if (total > 0) {
			log.info("작심삼일 리마인더: {}건 발송(today={}, now={})", total, today, now);
		}
	}
}
