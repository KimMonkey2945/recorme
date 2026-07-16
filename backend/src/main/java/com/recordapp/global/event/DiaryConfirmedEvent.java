package com.recordapp.global.event;

import java.time.LocalDate;

/**
 * 기록 확정('오늘을 기억하기') 도메인 이벤트.
 *
 * <p><b>단방향 디커플링의 핵심.</b> diary 도메인은 character(보상) 도메인을 <b>모른다</b> —
 * {@code DiaryService} 는 이 이벤트를 발행(publish)만 하고, 보상 적립은 character 도메인의
 * {@code CharacterEventListener} 가 {@code @TransactionalEventListener(AFTER_COMMIT)} 로 구독해 처리한다.
 * 이벤트 클래스가 global/event 에 있어 어느 도메인도 상대 패키지를 import 하지 않는다.
 *
 * <p>AFTER_COMMIT 이므로 <b>기록이 실제로 커밋된 뒤에만</b> 보상이 나간다(롤백된 기록엔 코인이 붙지 않는다).
 * event_key 규약은 {@code DIARY_CONFIRM:{diaryId}} 이며, 하루 1기록이라 diaryId 는 (사용자, 날짜)당 유일하다.
 *
 * @param userId      확정한 사용자 내부 PK
 * @param diaryId     확정된 기록 PK(멱등 키 + 리액션 조회 키)
 * @param writtenDate 기록이 속한 날짜(연속 확정일 계산 기준)
 */
public record DiaryConfirmedEvent(long userId, long diaryId, LocalDate writtenDate) {
}
