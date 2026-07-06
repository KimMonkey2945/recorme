package com.recordapp.domain.social.mapper;

import com.recordapp.domain.social.dto.FriendItem;
import com.recordapp.domain.social.dto.FriendRequestItem;
import com.recordapp.domain.social.dto.FriendSearchItem;
import com.recordapp.domain.social.dto.FriendshipInsertCommand;
import com.recordapp.domain.social.dto.FriendshipRow;
import java.util.List;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * friendships 매퍼. 관계는 무방향 정렬쌍(LEAST/GREATEST)으로 단건 판정하고,
 * 방향(requester/addressee)은 "누가 신청했나" 의미로 보존한다. 소유권 가드는 서비스가 userId 로만 건다.
 */
@Mapper
public interface FriendshipMapper {

	/** 두 사용자 사이의 관계 행(무방향 정렬쌍 단건, 없으면 null). status/방향 판정용. */
	FriendshipRow findRelation(@Param("userA") long userA, @Param("userB") long userB);

	/** 친구 관계 INSERT(요청 PENDING 또는 차단 BLOCKED). 생성 PK를 command.id 로 회수. */
	void insert(FriendshipInsertCommand command);

	/** 받은 요청 수락: PENDING → ACCEPTED. addressee(수신자)가 본인일 때만. 갱신 행수 반환. */
	int acceptRequest(@Param("id") long id, @Param("addresseeId") long addresseeId);

	/** 받은 요청 거절: PENDING 행 삭제. addressee(수신자)가 본인일 때만. 삭제 행수 반환. */
	int rejectRequest(@Param("id") long id, @Param("addresseeId") long addresseeId);

	/** 두 사용자 관계 행 삭제(친구 삭제·요청 취소, 상태 무관, 무방향). 삭제 행수 반환(멱등). */
	int deletePair(@Param("userA") long userA, @Param("userB") long userB);

	/** 기존 관계 행을 BLOCKED 로 전이(차단 주체 기록). 갱신 행수 반환(0이면 행 없음 → insert 로 폴백). */
	int updateToBlocked(@Param("blockerId") long blockerId, @Param("otherId") long otherId);

	/** 수락된 친구 목록(커서=friendship.id DESC). 상대 user 조인. */
	List<FriendItem> findAcceptedFriends(@Param("viewerId") long viewerId,
			@Param("cursor") Long cursor, @Param("limit") int limit);

	/** 받은 친구 요청 목록(addressee=본인, PENDING, 커서=friendship.id DESC). 요청자 조인. */
	List<FriendRequestItem> findIncomingRequests(@Param("viewerId") long viewerId,
			@Param("cursor") Long cursor, @Param("limit") int limit);

	/** 보낸 친구 요청 목록(requester=본인, PENDING, 커서=friendship.id DESC). 수신자 조인. */
	List<FriendRequestItem> findOutgoingRequests(@Param("viewerId") long viewerId,
			@Param("cursor") Long cursor, @Param("limit") int limit);

	/**
	 * 친구코드 정확일치 + 닉네임 부분일치 후보 검색(본인·탈퇴 제외, 상한 limit).
	 * relation 은 검색자 관점 관계 라벨(NONE/REQUESTED/INCOMING/FRIEND/BLOCKED).
	 */
	List<FriendSearchItem> searchCandidates(@Param("viewerId") long viewerId,
			@Param("query") String query, @Param("limit") int limit);
}
