package com.recordapp.domain.emotion.service;

import com.recordapp.domain.emotion.mapper.EmotionAnalysisMapper;
import com.recordapp.infra.llm.LlmProperties;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * 감정 분석 백스톱 폴러. 즉시 경로(기록 커밋 후 @Async 트리거)가 유실되는 경우를 보강한다:
 * 애플리케이션 재시작 중 큐 유실, afterCommit 콜백 실패, 다중 인스턴스 분산, 키 투입 전 쌓인 PENDING 등.
 *
 * <p>잠금 전략: {@code findStalePendingIds} 가 {@code FOR UPDATE SKIP LOCKED} 로 PENDING 행을 선점하고,
 * 본 메서드의 <b>짧은 트랜잭션</b>이 dispatch 직후 커밋되며 잠금을 푼다. 실제 LLM 호출은 @Async 라
 * 트랜잭션·잠금 밖에서 일어난다(긴 작업이 커넥션을 점유하지 않음).
 *
 * <p><b>감정 분석 flag(Task 024)</b>: {@code record.analysis.enabled=true} 일 때만 빈으로 등록된다.
 * off(운영 기본)면 스케줄러 자체가 미등록돼 백스톱 폴링이 돌지 않는다.
 */
@Component
@ConditionalOnProperty(name = "record.analysis.enabled", havingValue = "true")
public class EmotionAnalysisPoller {

	private static final Logger log = LoggerFactory.getLogger(EmotionAnalysisPoller.class);

	private final EmotionAnalysisMapper mapper;
	private final EmotionAnalysisService analysisService;
	private final LlmProperties props;
	private final int batchSize;

	public EmotionAnalysisPoller(EmotionAnalysisMapper mapper,
			EmotionAnalysisService analysisService,
			LlmProperties props,
			@Value("${record.analysis.batch-size:20}") int batchSize) {
		this.mapper = mapper;
		this.analysisService = analysisService;
		this.props = props;
		this.batchSize = batchSize;
	}

	/**
	 * 주기적으로 미처리 PENDING 기록을 집어 비동기 분석으로 dispatch 한다.
	 * fixedDelay 라 이전 실행 종료 후 간격을 둔다(겹치지 않음). 분석 자체는 @Async 라 즉시 반환된다.
	 */
	@Scheduled(
			fixedDelayString = "${record.analysis.poll-interval-ms:60000}",
			initialDelayString = "${record.analysis.initial-delay-ms:30000}")
	@Transactional
	public void pollPending() {
		// batch 모드 확장점: 실제 Message Batches API 제출(custom_id 매핑·완료 폴링)은 후속 작업(012-D).
		// 현재는 분기만 두고 immediate 경로로 폴백한다(API 키·실트래픽 시점에 구현).
		if ("batch".equalsIgnoreCase(props.mode())) {
			log.info("batch 모드는 후속 구현 예정 — 현재 immediate 폴백으로 처리한다.");
		}

		List<Long> ids = mapper.findStalePendingIds(batchSize); // FOR UPDATE SKIP LOCKED
		if (ids.isEmpty()) {
			return;
		}
		log.info("감정 분석 폴러: PENDING {}건 dispatch", ids.size());
		for (Long id : ids) {
			// @Async → 즉시 반환. 트랜잭션 커밋(메서드 종료)으로 행 잠금 해제, 실제 분석은 잠금 밖.
			analysisService.analyzeAsync(id);
		}
	}
}
