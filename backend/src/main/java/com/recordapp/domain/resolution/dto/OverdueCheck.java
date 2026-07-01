package com.recordapp.domain.resolution.dto;

/**
 * 기한 초과 미완료 체크(자정 실패 배치용 내부 DTO). check_date &lt; today 인데 아직 PENDING 인 행을
 * {@code FOR UPDATE SKIP LOCKED} 로 선점해 담는다.
 *
 * <p>{@code userId} 는 실패 알림 팬아웃용(부모 결심에서 조인). {@code resolutionId} 로 결심을 FAILED 로 전이한다.
 *
 * @param checkId      resolution_checks.id (MISSED 로 전이할 대상)
 * @param resolutionId 부모 결심 id (FAILED 로 전이할 대상)
 * @param userId       소유자 id (실패 푸시 대상)
 */
public record OverdueCheck(long checkId, long resolutionId, long userId) {
}
