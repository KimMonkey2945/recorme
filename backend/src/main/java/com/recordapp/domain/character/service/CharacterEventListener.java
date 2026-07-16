package com.recordapp.domain.character.service;

import com.recordapp.global.event.DiaryConfirmedEvent;
import com.recordapp.global.event.ResolutionProgressEvent;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * 보상 도메인 이벤트 구독자 — 단방향 디커플링의 character 쪽 끝.
 *
 * <p>diary·resolution 도메인이 발행한 이벤트를 <b>커밋 이후</b>({@link TransactionalEventListener} 기본
 * phase = AFTER_COMMIT) 에 받아, 별도 스레드({@code @Async("characterExecutor")})에서 멱등 보상 엔진을 돌린다.
 * <ul>
 *   <li><b>AFTER_COMMIT</b> — 기록/결심이 실제로 커밋된 뒤에만 보상이 나간다(롤백된 트랜잭션엔 코인이 붙지 않는다).</li>
 *   <li><b>@Async</b> — 보상 처리가 원 요청 스레드·트랜잭션을 붙잡지 않는다. 보상 로직 예외는
 *       {@code CharacterRewardService} 의 REQUIRES_NEW 트랜잭션 안에서 격리되고, 여기 void @Async 로 전파돼
 *       AsyncConfig 의 UncaughtExceptionHandler 가 로깅한다(적립 유실은 백스톱 폴러가 보정).</li>
 * </ul>
 * 유실 보정은 {@code CharacterRewardBackfillPoller} 가 담당하며, 게이트가 멱등하므로 리스너·폴러가
 * 동시에 돌아도 중복 적립은 불가능하다.
 */
@Component
public class CharacterEventListener {

	private final CharacterRewardService rewardService;

	public CharacterEventListener(CharacterRewardService rewardService) {
		this.rewardService = rewardService;
	}

	/** 기록 확정 → 코인 적립·진척·연속 마일스톤·리액션. */
	@Async("characterExecutor")
	@TransactionalEventListener
	public void onDiaryConfirmed(DiaryConfirmedEvent event) {
		rewardService.handleDiaryConfirmed(event.userId(), event.diaryId(), event.writtenDate());
	}

	/** 작심삼일 1·2일차 달성 / 완주 → 코인 적립·진척·리액션. */
	@Async("characterExecutor")
	@TransactionalEventListener
	public void onResolutionProgress(ResolutionProgressEvent event) {
		rewardService.handleResolutionProgress(
				event.userId(), event.resolutionId(), event.dayOrdinal(), event.completed(), event.streakSeq());
	}
}
