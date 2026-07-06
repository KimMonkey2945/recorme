package com.recordapp.domain.social.dto;

/**
 * friendships INSERT 입력. MyBatis가 useGeneratedKeys로 {@link #id}를 채운다.
 * 친구 요청(status=PENDING, blockerId=null)과 차단(status=BLOCKED, blockerId=요청자)에 공용.
 */
public class FriendshipInsertCommand {

	private Long id; // 생성된 PK(useGeneratedKeys 대상)
	private final Long requesterId;
	private final Long addresseeId;
	private final String status;
	private final Long blockerId; // BLOCKED 일 때만 값(차단 주체)

	public FriendshipInsertCommand(Long requesterId, Long addresseeId, String status, Long blockerId) {
		this.requesterId = requesterId;
		this.addresseeId = addresseeId;
		this.status = status;
		this.blockerId = blockerId;
	}

	public Long getId() {
		return id;
	}

	public void setId(Long id) {
		this.id = id;
	}

	public Long getRequesterId() {
		return requesterId;
	}

	public Long getAddresseeId() {
		return addresseeId;
	}

	public String getStatus() {
		return status;
	}

	public Long getBlockerId() {
		return blockerId;
	}
}
