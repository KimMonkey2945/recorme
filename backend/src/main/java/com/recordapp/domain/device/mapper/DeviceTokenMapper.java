package com.recordapp.domain.device.mapper;

import java.util.List;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * device_tokens 매퍼. FCM 등록 토큰의 upsert·소유 해제·무효 회수를 둔다.
 * 토큰은 전역 유일(uq_device_tokens_token)이라 upsert 로 소유가 재귀속되고,
 * 무효 토큰은 물리 DELETE 로 회수한다(soft delete 없음).
 */
@Mapper
public interface DeviceTokenMapper {

	/**
	 * 기기 토큰 upsert. token 충돌 시 user_id·platform 을 갱신해 소유를 재귀속하고 last_seen_at 을 갱신한다
	 * (재로그인/재설치/기기 소유 이전 흡수).
	 *
	 * @return 영향 행 수(INSERT/UPDATE 모두 1)
	 */
	int upsert(@Param("userId") long userId,
			@Param("token") String token,
			@Param("platform") String platform);

	/**
	 * 특정 사용자 소유의 토큰 1건 삭제(로그아웃/기기 해제). 소유권은 userId 로 검증한다.
	 *
	 * @return 삭제된 행 수(0이면 대상 부재/타인 소유)
	 */
	int deleteByToken(@Param("userId") long userId, @Param("token") String token);

	/**
	 * 무효 토큰 일괄 삭제(회수). 발송 경로에서 FCM UNREGISTERED/INVALID_ARGUMENT 로 판정된 토큰을 정리한다.
	 * 소유와 무관하게 토큰 값으로 삭제한다(이미 죽은 토큰이므로). 빈 리스트면 무동작.
	 *
	 * @return 삭제된 행 수
	 */
	int deleteTokens(@Param("tokens") List<String> tokens);

	/**
	 * 특정 사용자의 모든 기기 토큰 조회(푸시 팬아웃). 작심삼일 성공/실패/리마인더 발송 시
	 * user_id → 토큰들로 멀티캐스트한다(idx_device_tokens_user 사용).
	 *
	 * @return 등록 토큰 목록(없으면 빈 리스트)
	 */
	List<String> findTokensByUserId(@Param("userId") long userId);
}
