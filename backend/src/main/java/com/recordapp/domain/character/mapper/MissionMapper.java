package com.recordapp.domain.character.mapper;

import com.recordapp.domain.character.dto.MissionRow;
import com.recordapp.domain.character.dto.UserMissionRow;
import java.util.List;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * 미션 매퍼 — missions(마스터, 캐시 대상) + user_missions(달성 이력).
 * 달성 처리(INSERT)는 보상 엔진(Task 028) 소관이고, 여기서는 조회만 한다.
 */
@Mapper
public interface MissionMapper {

	/**
	 * 활성 미션 전체(sort_order 순). rule(JSONB)의 타입별 임계값 키(count/days/seq/level)를
	 * {@code threshold} 하나로 정규화해 읽는다 — 서비스는 (타입, 임계값)만으로 진행률을 O(1) 산출한다.
	 */
	List<MissionRow> findMissions();

	/** 내가 달성한 미션 이력(코드 + 달성 시각). */
	List<UserMissionRow> findAchievedMissions(@Param("userId") Long userId);
}
