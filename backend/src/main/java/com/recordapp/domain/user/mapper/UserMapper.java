package com.recordapp.domain.user.mapper;

import com.recordapp.domain.user.dto.UserJitCommand;
import com.recordapp.domain.user.dto.UserProfileResponse;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * users 테이블 매퍼. JIT 프로비저닝과 프로필 조회/수정 메서드를 둔다.
 */
@Mapper
public interface UserMapper {

	/** supabase_uid로 내부 PK 조회(없으면 null). 탈퇴 여부와 무관하게 매핑 키로 조회. */
	Long findIdBySupabaseUid(@Param("supabaseUid") String supabaseUid);

	/**
	 * JIT INSERT. supabase_uid 충돌 시 DO NOTHING(동시 최초요청 race-safe).
	 * INSERT가 수행되면 {@link UserJitCommand#getId()}에 생성된 PK가 채워지고,
	 * 충돌로 무시되면 id는 null로 남는다(호출 측이 재조회).
	 */
	void insertOnConflictNothing(UserJitCommand command);

	/** 내부 PK로 활성 회원의 프로필 조회(없으면 null). 외부 노출용 uuid를 반환한다. */
	UserProfileResponse findProfileByUserId(@Param("userId") Long userId);

	/**
	 * 내부 PK 기준 프로필 수정. 소유권은 userId로만 식별(요청 바디에 id 없음 → IDOR 차단).
	 *
	 * @return 갱신된 행 수(0이면 대상 부재/탈퇴)
	 */
	int updateProfile(@Param("userId") Long userId,
			@Param("nickname") String nickname,
			@Param("profileImageUrl") String profileImageUrl,
			@Param("bio") String bio);
}
