package com.recordapp.domain.emotion.dto;

/**
 * 감정 분석 대상 일기의 최소 스냅샷. 비동기 분석 스레드가 {@code EmotionAnalysisMapper.findTarget} 으로
 * 직접 재조회해 채운다(DiaryService 에 역의존하지 않기 위함 — 순환참조 회피).
 *
 * @param id          일기 내부 PK
 * @param content     리치 본문(Quill Delta JSON) — 인라인 이미지 추출용
 * @param contentText 순수 텍스트 — LLM 입력이자 조건부 UPDATE 의 stale 판정 기준
 */
public record AnalysisTarget(long id, String content, String contentText) {
}
