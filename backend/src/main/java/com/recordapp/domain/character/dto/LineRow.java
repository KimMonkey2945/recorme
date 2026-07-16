package com.recordapp.domain.character.dto;

/**
 * character_lines 후보 1행(맥락 대사). 리액션 대사 선택의 입력이다.
 * character_code 가 null 이면 공용 대사, 아니면 특정 캐릭터 전용 대사다
 * ({@code LineService} 가 전용을 우선하고 없으면 공용으로 폴백해 가중 랜덤 선택).
 *
 * <p>⚠️ constructor 매핑 — {@code <arg>} 순서 = 표준 생성자 순서.
 *
 * @param characterCode 전용 대사의 캐릭터(공용이면 null)
 * @param lineKo        대사 텍스트
 * @param riveTrigger   재생할 모션 트리거(없으면 null → 기본 모션)
 * @param weight        가중치(클수록 자주 뽑힘, >0)
 */
public record LineRow(String characterCode, String lineKo, String riveTrigger, int weight) {
}
