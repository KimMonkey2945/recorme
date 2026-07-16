package com.recordapp.domain.character.service;

import com.recordapp.domain.character.dto.ConfirmedDiaryRef;
import com.recordapp.domain.character.mapper.CharacterRewardMapper;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 코인 적립 백스톱 폴러 — 즉시 경로(확정 커밋 후 이벤트) 유실·재시작·다중 인스턴스 보강용.
 * {@code EmotionAnalysisPoller} 와 동일 철학이며, 확정(analysis_status &lt;&gt; 'DRAFT')됐으나
 * DIARY_CONFIRM 게이트가 없는 기록을 주기적으로 스캔해 {@link CharacterRewardService#handleDiaryConfirmed}
 * 를 재호출한다.
 *
 * <p><b>게이트가 멱등하므로 폴러가 돌아도, 리스너와 동시에 돌아도 중복 적립은 불가능하다</b>
 * (uq_character_events_key). 그래서 SKIP LOCKED 없이도 안전하다 — 두 실행이 같은 기록을 집어도
 * insertGate 는 하나만 1행을 얻고 나머지는 0행으로 즉시 no-op 이다.
 *
 * <p>cron 이 "-"(테스트 프로파일)면 @Scheduled 는 비활성이고, 테스트가 {@link #backfill()} 를 직접 호출한다
 * (ResolutionFailurePoller 와 동일 관례).
 */
@Component
public class CharacterRewardBackfillPoller {

	private static final Logger log = LoggerFactory.getLogger(CharacterRewardBackfillPoller.class);

	/** 한 번의 폴링에서 드레인 루프를 도는 최대 횟수(폭주 방지 상한). 남은 백로그는 다음 tick 이 잇는다. */
	private static final int MAX_DRAIN_ITERATIONS = 20;

	private final CharacterRewardMapper mapper;
	private final CharacterRewardService rewardService;
	private final int batchSize;

	public CharacterRewardBackfillPoller(CharacterRewardMapper mapper,
			CharacterRewardService rewardService,
			@Value("${record.character.reward.backfill-batch-size:100}") int batchSize) {
		this.mapper = mapper;
		this.rewardService = rewardService;
		this.batchSize = batchSize;
	}

	/**
	 * 미적립 확정 기록을 배치로 보정한다. 한 tick 에서 배치가 가득 차면 다음 배치를 이어(드레인) 처리하되,
	 * 상한(MAX_DRAIN_ITERATIONS)까지만 돈다. 개별 기록 처리 실패는 로깅 후 건너뛴다(전체 폴링을 멈추지 않게).
	 */
	@Scheduled(cron = "${record.character.reward.backfill-cron}", zone = "Asia/Seoul")
	public void backfill() {
		int totalProcessed = 0;
		for (int iteration = 0; iteration < MAX_DRAIN_ITERATIONS; iteration++) {
			List<ConfirmedDiaryRef> refs = mapper.findUnrewardedConfirmedDiaries(batchSize);
			if (refs.isEmpty()) {
				break;
			}
			for (ConfirmedDiaryRef ref : refs) {
				try {
					// REQUIRES_NEW 격리 + 멱등 게이트 → 이미 처리된 기록이면 no-op.
					rewardService.handleDiaryConfirmed(ref.userId(), ref.diaryId(), ref.writtenDate());
					totalProcessed++;
				} catch (Exception e) {
					log.warn("보상 백필 실패(건너뜀) diaryId={}: {}", ref.diaryId(), e.getMessage());
				}
			}
			if (refs.size() < batchSize) {
				break; // 마지막 배치 — 더 없음
			}
		}
		if (totalProcessed > 0) {
			log.info("코인 적립 백필 보정 {}건", totalProcessed);
		}
	}
}
