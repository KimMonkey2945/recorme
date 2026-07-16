package com.recordapp.domain.character.dto;

import java.time.LocalDate;

/**
 * 백스톱 폴러가 보정 대상(확정됐으나 코인 적립 게이트가 없는 기록)으로 집어 온 참조.
 * 폴러는 이 참조로 {@code CharacterRewardService.handleDiaryConfirmed} 를 재호출하며,
 * 멱등 게이트가 이미 있으면 no-op 이므로 중복 적립은 불가능하다.
 *
 * <p>⚠️ constructor 매핑 — {@code <arg>} 순서 = 표준 생성자 순서.
 */
public record ConfirmedDiaryRef(long userId, long diaryId, LocalDate writtenDate) {
}
