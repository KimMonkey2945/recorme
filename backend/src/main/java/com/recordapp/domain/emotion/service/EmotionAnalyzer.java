package com.recordapp.domain.emotion.service;

import com.recordapp.domain.emotion.dto.DiaryAnalysisResult;
import com.recordapp.infra.llm.LlmImage;
import java.util.List;

/**
 * 멀티모달 감정 분석 추상화. provider(LLM 종류)를 격리해 구현체를 교체할 수 있게 한다
 * (스토리지 {@code StorageService}·LLM {@code LlmClient}와 동일한 인프라 격리 패턴).
 *
 * <p>구현체는 예외를 던지지 않고 비정상 응답을 {@link DiaryAnalysisResult#neutralFallback()} 으로
 * 흡수한다 — 분석 실패가 일기 저장/표시를 막지 않도록 한다.
 */
public interface EmotionAnalyzer {

	/**
	 * 일기 본문 텍스트와 (선택)인라인 이미지로 감정을 분석한다.
	 *
	 * @param contentText 분석 대상 본문 평문(Delta 가 아닌 추출 텍스트)
	 * @param images      비전 보조 입력(없으면 빈 리스트)
	 * @return 분석 결과(실패 시 NEUTRAL 폴백)
	 */
	DiaryAnalysisResult analyze(String contentText, List<LlmImage> images);
}
