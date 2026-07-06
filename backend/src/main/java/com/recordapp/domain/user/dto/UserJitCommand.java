package com.recordapp.domain.user.dto;

/**
 * JIT 프로비저닝 INSERT 입력. MyBatis가 useGeneratedKeys로 {@link #id}를 채운다.
 * (ON CONFLICT DO NOTHING으로 INSERT가 무시되면 id는 null로 남고, 호출 측이 재조회한다.)
 */
public class UserJitCommand {

	private Long id; // 생성된 PK(useGeneratedKeys 대상). 충돌로 INSERT 무시 시 null
	private final String supabaseUid;
	private final String nickname;
	private final String email;            // nullable
	private final String profileImageUrl;  // nullable
	private final String friendCode;       // 8자리 친구코드(생성 시 발급, uq_users_friend_code 로 유일)

	public UserJitCommand(String supabaseUid, String nickname, String email, String profileImageUrl,
			String friendCode) {
		this.supabaseUid = supabaseUid;
		this.nickname = nickname;
		this.email = email;
		this.profileImageUrl = profileImageUrl;
		this.friendCode = friendCode;
	}

	public Long getId() {
		return id;
	}

	public void setId(Long id) {
		this.id = id;
	}

	public String getSupabaseUid() {
		return supabaseUid;
	}

	public String getNickname() {
		return nickname;
	}

	public String getEmail() {
		return email;
	}

	public String getProfileImageUrl() {
		return profileImageUrl;
	}

	public String getFriendCode() {
		return friendCode;
	}
}
