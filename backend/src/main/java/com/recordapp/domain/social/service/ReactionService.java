package com.recordapp.domain.social.service;

import com.recordapp.domain.social.dto.ReactionResponse;
import com.recordapp.domain.social.mapper.ReactionMapper;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 공감(리액션) 서비스. 1인 1회 공감(멱등)이며, 볼 수 없는 글엔 공감할 수 없다.
 * 공감 수 캐시(diaries.reaction_count)는 리액션 INSERT/DELETE 와 같은 트랜잭션에서 원자 증감한다.
 */
@Service
public class ReactionService {

	/** MVP 단일 공감 타입(향후 이모지 다종 확장 시 파라미터화). */
	private static final String EMPATHY = "EMPATHY";

	private final ReactionMapper reactionMapper;

	public ReactionService(ReactionMapper reactionMapper) {
		this.reactionMapper = reactionMapper;
	}

	/**
	 * 공감 추가(멱등). 볼 수 없는 글이면 DIARY_NOT_FOUND(존재 은닉).
	 * 실제 삽입된 경우에만 공감 수 캐시를 +1 한다(중복 요청은 무해).
	 */
	@Transactional
	public ReactionResponse react(Long userId, Long diaryId) {
		if (!reactionMapper.isViewable(diaryId, userId)) {
			throw new BusinessException(ErrorCode.DIARY_NOT_FOUND);
		}
		int inserted = reactionMapper.insertIgnore(diaryId, userId, EMPATHY);
		if (inserted == 1) {
			reactionMapper.incrementCount(diaryId);
		}
		return new ReactionResponse(reactionMapper.countByDiary(diaryId), true);
	}

	/**
	 * 공감 취소(멱등). 자기 리액션 제거는 항상 안전하므로 가시성 검증이 불필요하다.
	 * 실제 삭제된 경우에만 공감 수 캐시를 -1 한다.
	 */
	@Transactional
	public ReactionResponse cancel(Long userId, Long diaryId) {
		int deleted = reactionMapper.deleteMine(diaryId, userId);
		if (deleted == 1) {
			reactionMapper.decrementCount(diaryId);
		}
		return new ReactionResponse(reactionMapper.countByDiary(diaryId), false);
	}
}
