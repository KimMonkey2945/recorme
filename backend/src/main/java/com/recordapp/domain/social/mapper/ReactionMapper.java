package com.recordapp.domain.social.mapper;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * diary_reactions 매퍼. 1인 1회 공감(멱등)과 공감 수 캐시(diaries.reaction_count) 원자 증감을 둔다.
 * 볼 수 있는 글 판정(isViewable)은 DiaryMapper 의 가시성 SQL fragment 를 재사용한다(규칙 단일원).
 */
@Mapper
public interface ReactionMapper {

	/**
	 * viewer 가 볼 수 있는 활성·DONE 기록인지: 본인 OR PUBLIC OR (FRIENDS AND 수락 친구), 비차단.
	 * findFeed 와 동일한 가시성 규칙(DiaryMapper 의 acceptedFriendIds·notBlockedByPair fragment 재사용).
	 */
	boolean isViewable(@Param("diaryId") long diaryId, @Param("viewerId") long viewerId);

	/** 공감 INSERT(멱등, ON CONFLICT DO NOTHING). 실제 삽입된 행 수 반환(1=신규, 0=이미 공감). */
	int insertIgnore(@Param("diaryId") long diaryId, @Param("userId") long userId,
			@Param("type") String type);

	/** 내 공감 DELETE. 삭제된 행 수 반환(1=취소됨, 0=원래 없음). */
	int deleteMine(@Param("diaryId") long diaryId, @Param("userId") long userId);

	/** 공감 수 캐시 +1(신규 공감 시). */
	int incrementCount(@Param("diaryId") long diaryId);

	/** 공감 수 캐시 -1(취소 시, reaction_count>0 가드로 음수 방지). */
	int decrementCount(@Param("diaryId") long diaryId);

	/** 실제 공감 수(diary_reactions COUNT — 응답 정확성용). */
	int countByDiary(@Param("diaryId") long diaryId);
}
