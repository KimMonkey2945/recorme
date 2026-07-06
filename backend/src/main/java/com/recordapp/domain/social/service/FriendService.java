package com.recordapp.domain.social.service;

import com.recordapp.domain.social.dto.FriendItem;
import com.recordapp.domain.social.dto.FriendRequestItem;
import com.recordapp.domain.social.dto.FriendRequestResponse;
import com.recordapp.domain.social.dto.FriendSearchItem;
import com.recordapp.domain.social.dto.FriendshipInsertCommand;
import com.recordapp.domain.social.dto.FriendshipRow;
import com.recordapp.domain.social.dto.SendFriendRequest;
import com.recordapp.domain.social.mapper.FriendshipMapper;
import com.recordapp.domain.user.mapper.UserMapper;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import java.util.List;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 친구 서비스. 소유권·본인 식별은 항상 principal 의 userId 로만 수행한다(IDOR 차단).
 * 대상 사용자는 친구코드/외부 uuid 로만 지정받아 내부 PK 로 해석한다(내부 PK 비노출).
 *
 * <p>관계는 무방향 정렬쌍(uq_friendship_pair)으로 1행만 존재한다. 요청 생성은 기존 관계를 먼저 판정하고
 * (이미 친구/차단/중복 요청 차단, 역방향 대기요청은 자동 수락), 경합은 DuplicateKeyException → 재조회로 흡수한다.
 */
@Service
public class FriendService {

	/** 검색 결과 상한(커서 없이 상위 N건만). */
	private static final int SEARCH_LIMIT = 20;

	private final FriendshipMapper friendshipMapper;
	private final UserMapper userMapper;

	public FriendService(FriendshipMapper friendshipMapper, UserMapper userMapper) {
		this.friendshipMapper = friendshipMapper;
		this.userMapper = userMapper;
	}

	/**
	 * 친구 요청. 대상은 친구코드 또는 uuid 로 지정. 관계 상태에 따라 분기:
	 * 이미 친구→FRIEND_ALREADY, 차단→FRIEND_BLOCKED, 내가 보낸 대기요청 중복→FRIEND_REQUEST_ALREADY_SENT,
     * 상대가 보낸 대기요청 존재→자동 수락(ACCEPTED). 그 외 신규 PENDING 요청 생성.
	 */
	@Transactional
	public FriendRequestResponse sendRequest(Long userId, SendFriendRequest req) {
		Long targetId = resolveTarget(req);
		if (targetId.equals(userId)) {
			throw new BusinessException(ErrorCode.FRIEND_SELF);
		}

		FriendshipRow relation = friendshipMapper.findRelation(userId, targetId);
		if (relation != null) {
			return handleExistingRelation(userId, relation);
		}

		try {
			FriendshipInsertCommand cmd =
					new FriendshipInsertCommand(userId, targetId, "PENDING", null);
			friendshipMapper.insert(cmd);
			return new FriendRequestResponse(cmd.getId(), "PENDING");
		} catch (DuplicateKeyException e) {
			// 동시 요청 경합(양쪽이 동시에 요청) → 재조회 후 기존 관계 규칙으로 처리.
			FriendshipRow raced = friendshipMapper.findRelation(userId, targetId);
			if (raced == null) {
				throw new BusinessException(ErrorCode.INTERNAL_ERROR);
			}
			return handleExistingRelation(userId, raced);
		}
	}

	/** 기존 관계가 있을 때의 요청 분기(자동 수락 포함). */
	private FriendRequestResponse handleExistingRelation(Long userId, FriendshipRow relation) {
		switch (relation.status()) {
			case "ACCEPTED":
				throw new BusinessException(ErrorCode.FRIEND_ALREADY);
			case "BLOCKED":
				throw new BusinessException(ErrorCode.FRIEND_BLOCKED);
			case "PENDING":
				if (relation.requesterId().equals(userId)) {
					throw new BusinessException(ErrorCode.FRIEND_REQUEST_ALREADY_SENT);
				}
				// 상대가 나에게 보낸 대기요청 → 자동 수락(상호 요청 = 친구 성립).
				friendshipMapper.acceptRequest(relation.id(), userId);
				return new FriendRequestResponse(relation.id(), "ACCEPTED");
			default:
				throw new BusinessException(ErrorCode.INTERNAL_ERROR);
		}
	}

	/** 받은 요청 수락. 수신자 본인 가드(affected=0 → 부재/타인/이미처리 은닉 404). */
	@Transactional
	public void accept(Long userId, Long requestId) {
		if (friendshipMapper.acceptRequest(requestId, userId) == 0) {
			throw new BusinessException(ErrorCode.FRIEND_REQUEST_NOT_FOUND);
		}
	}

	/** 받은 요청 거절(행 삭제). 수신자 본인 가드(affected=0 → 404). */
	@Transactional
	public void reject(Long userId, Long requestId) {
		if (friendshipMapper.rejectRequest(requestId, userId) == 0) {
			throw new BusinessException(ErrorCode.FRIEND_REQUEST_NOT_FOUND);
		}
	}

	/**
	 * 친구 삭제 또는 차단(멱등 200). block=true 면 BLOCKED 로 전이(없으면 생성),
	 * false 면 관계 행 삭제. 대상 uuid 부재 시 USER_NOT_FOUND.
	 */
	@Transactional
	public void remove(Long userId, String targetUuid, boolean block) {
		Long targetId = userMapper.findIdByUuid(targetUuid);
		if (targetId == null) {
			throw new BusinessException(ErrorCode.USER_NOT_FOUND);
		}
		if (targetId.equals(userId)) {
			throw new BusinessException(ErrorCode.FRIEND_SELF);
		}
		if (block) {
			if (friendshipMapper.updateToBlocked(userId, targetId) == 0) {
				// 기존 관계 없음 → BLOCKED 행 신규 생성(requester=차단자, blocker=차단자).
				friendshipMapper.insert(
						new FriendshipInsertCommand(userId, targetId, "BLOCKED", userId));
			}
		} else {
			friendshipMapper.deletePair(userId, targetId); // 멱등: 관계 없어도 무해
		}
	}

	/** 친구 목록(커서 페이징, friendship.id DESC). */
	@Transactional(readOnly = true)
	public PageResponse<FriendItem> getFriends(Long userId, CursorRequest req) {
		int size = req.safeSize();
		List<FriendItem> rows = friendshipMapper.findAcceptedFriends(userId, req.cursor(), size + 1);
		return toPage(rows, size);
	}

	/** 받은/보낸 친구 요청 목록(커서 페이징). direction="outgoing" 이면 보낸 요청, 그 외 받은 요청. */
	@Transactional(readOnly = true)
	public PageResponse<FriendRequestItem> getRequests(Long userId, String direction, CursorRequest req) {
		int size = req.safeSize();
		boolean outgoing = "outgoing".equalsIgnoreCase(direction);
		List<FriendRequestItem> rows = outgoing
				? friendshipMapper.findOutgoingRequests(userId, req.cursor(), size + 1)
				: friendshipMapper.findIncomingRequests(userId, req.cursor(), size + 1);
		boolean hasNext = rows.size() > size;
		List<FriendRequestItem> items = hasNext ? rows.subList(0, size) : rows;
		Long nextCursor = items.isEmpty() ? null : items.get(items.size() - 1).requestId();
		return PageResponse.of(items, hasNext ? nextCursor : null, hasNext);
	}

	/** 친구 검색(친구코드 정확 + 닉네임 부분, 본인 제외, 상한 20). 빈 질의는 빈 목록. */
	@Transactional(readOnly = true)
	public List<FriendSearchItem> search(Long userId, String query) {
		if (query == null || query.isBlank()) {
			return List.of();
		}
		return friendshipMapper.searchCandidates(userId, query.trim(), SEARCH_LIMIT);
	}

	/** 대상 사용자 해석: 친구코드 우선, 없으면 uuid. 둘 다 없으면 검증 실패, 미존재면 USER_NOT_FOUND. */
	private Long resolveTarget(SendFriendRequest req) {
		Long targetId;
		if (req.hasFriendCode()) {
			targetId = userMapper.findIdByFriendCode(req.friendCode().trim());
		} else if (req.hasTargetUuid()) {
			targetId = userMapper.findIdByUuid(req.targetUuid().trim());
		} else {
			throw new BusinessException(ErrorCode.VALIDATION_ERROR, "친구코드 또는 대상 사용자가 필요해요.");
		}
		if (targetId == null) {
			throw new BusinessException(ErrorCode.USER_NOT_FOUND);
		}
		return targetId;
	}

	/** size+1 조회 결과를 hasNext/nextCursor 로 절단(friendship.id 커서). */
	private PageResponse<FriendItem> toPage(List<FriendItem> rows, int size) {
		boolean hasNext = rows.size() > size;
		List<FriendItem> items = hasNext ? rows.subList(0, size) : rows;
		Long nextCursor = items.isEmpty() ? null : items.get(items.size() - 1).friendshipId();
		return PageResponse.of(items, hasNext ? nextCursor : null, hasNext);
	}
}
