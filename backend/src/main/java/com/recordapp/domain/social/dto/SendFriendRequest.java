package com.recordapp.domain.social.dto;

/**
 * 친구 요청 바디. 대상은 친구코드 또는 외부 uuid 중 하나로 지정한다(내부 PK 비노출).
 * 둘 다 비었으면 서비스가 VALIDATION_ERROR 로 거른다.
 */
public record SendFriendRequest(String friendCode, String targetUuid) {

	/** 친구코드가 제공됐는지(공백 제외). */
	public boolean hasFriendCode() {
		return friendCode != null && !friendCode.isBlank();
	}

	/** 대상 uuid가 제공됐는지(공백 제외). */
	public boolean hasTargetUuid() {
		return targetUuid != null && !targetUuid.isBlank();
	}
}
