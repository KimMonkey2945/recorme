package com.recordapp.domain.emotion.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.recordapp.domain.emotion.dto.AnalysisTarget;
import com.recordapp.domain.emotion.dto.DiaryAnalysisResult;
import com.recordapp.domain.emotion.mapper.EmotionAnalysisMapper;
import com.recordapp.infra.llm.LlmImage;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

/**
 * 감정 분석 비동기 오케스트레이터. 일기 저장/수정 커밋 후(또는 폴러 백스톱) PENDING 일기를 받아
 * 트랜잭션 밖에서 LLM 분석을 수행하고 결과를 조건부 UPDATE 로 반영한다.
 *
 * <p>설계 원칙:
 * <ul>
 *   <li><b>긴 트랜잭션 금지</b>: {@code analyzeAsync} 는 @Transactional 을 두지 않는다. LLM 호출
 *       (수 초~수십 초)이 DB 커넥션·잠금을 점유하지 않도록, 매퍼 호출(findTarget/updateResult/
 *       updateFailed)이 각자 짧은 자동커밋 트랜잭션으로 끝난다.</li>
 *   <li><b>낙관적 반영</b>: updateResult/updateFailed 의 WHERE 가 {@code PENDING}+{@code content_text}
 *       일치를 요구하므로, 분석 중 사용자가 수정·삭제하면 0행(폐기)으로 안전하게 무시된다.</li>
 *   <li><b>역의존 없음</b>: DiaryService 를 의존하지 않고 EmotionAnalysisMapper 로 직접 재조회한다
 *       (DiaryService → 본 서비스 단방향, 순환참조 회피).</li>
 * </ul>
 */
@Service
public class EmotionAnalysisService {

	private static final Logger log = LoggerFactory.getLogger(EmotionAnalysisService.class);

	private final EmotionAnalysisMapper mapper;
	private final EmotionAnalyzer analyzer;
	private final DiaryImagePreparer imagePreparer;
	private final ObjectMapper objectMapper;

	public EmotionAnalysisService(EmotionAnalysisMapper mapper,
			EmotionAnalyzer analyzer,
			DiaryImagePreparer imagePreparer,
			ObjectMapper objectMapper) {
		this.mapper = mapper;
		this.analyzer = analyzer;
		this.imagePreparer = imagePreparer;
		this.objectMapper = objectMapper;
	}

	/**
	 * 단일 일기 비동기 감정 분석. 전용 풀(emotionAnalysisExecutor)에서 실행된다.
	 * 다른 빈(DiaryService afterCommit·Poller)에서 호출되므로 프록시가 정상 적용된다(self-invocation 아님).
	 *
	 * <p>흐름:
	 * <ol>
	 *   <li>findTarget — PENDING 활성 아니면 즉시 종료(이미 처리/삭제/수정).</li>
	 *   <li>이미지 준비 → analyzer.analyze(LLM, 실패는 내부에서 NEUTRAL 흡수) → scores 직렬화.</li>
	 *   <li>updateResult(DONE). 0행이면 분석 중 수정·삭제(stale)로 결과 폐기(debug).</li>
	 *   <li>예외(이미지/직렬화/매퍼 등) → updateFailed(FAILED+NEUTRAL) + ERROR 로그.</li>
	 * </ol>
	 */
	@Async("emotionAnalysisExecutor")
	public void analyzeAsync(long diaryId) {
		AnalysisTarget target = mapper.findTarget(diaryId);
		if (target == null) {
			// 이미 DONE/FAILED 거나 삭제·수정으로 PENDING 이 아님 — 할 일 없음.
			return;
		}

		try {
			List<LlmImage> images = imagePreparer.prepare(target.content());
			DiaryAnalysisResult result = analyzer.analyze(target.contentText(), images);
			String scoresJson = objectMapper.writeValueAsString(result.scores());

			int updated = mapper.updateResult(
					diaryId,
					target.contentText(),
					result.primaryEmotion().name(), // enum.name() → 컬럼 코드
					result.backgroundColor(),
					result.textColor(),
					result.accentColor(),
					result.aiComment(),
					result.aiTitle(),
					result.moodEmoji(),
					scoresJson);

			if (updated == 0) {
				// 분석 도중 본문 수정·삭제로 조건부 WHERE 불일치 → 낡은 결과 폐기.
				log.debug("감정 분석 결과 폐기(stale): diaryId={} — 분석 중 수정/삭제됨", diaryId);
			}
		} catch (JsonProcessingException | RuntimeException e) {
			// analyzer.analyze 는 LLM 실패를 NEUTRAL 로 흡수하므로, 여기 도달은 이미지/직렬화/매퍼 등
			// 예기치 못한 예외다 → FAILED+NEUTRAL 로 반영(CHECK 통과 + 앱 중립 렌더).
			handleFailure(diaryId, target.contentText(), e);
		}
	}

	/** 실패 반영도 best-effort: FAILED UPDATE 자체가 또 실패해도 분석 스레드를 죽이지 않는다. */
	private void handleFailure(long diaryId, String analyzedText, Exception cause) {
		log.error("감정 분석 실패 — FAILED+NEUTRAL 반영: diaryId={}", diaryId, cause);
		try {
			mapper.updateFailed(diaryId, analyzedText);
		} catch (RuntimeException e) {
			log.error("FAILED 상태 반영마저 실패: diaryId={}", diaryId, e);
		}
	}
}
