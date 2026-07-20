package com.recordapp.domain.social.service;

import com.recordapp.domain.character.dto.MyCharacterResponse;
import com.recordapp.domain.character.service.CharacterService;
import com.recordapp.domain.diary.dto.FriendDiarySummaryDay;
import com.recordapp.domain.diary.mapper.DiaryMapper;
import com.recordapp.domain.resolution.dto.ResolutionListItem;
import com.recordapp.domain.resolution.service.ResolutionService;
import com.recordapp.domain.social.dto.FriendCharacterResponse;
import com.recordapp.domain.social.dto.FriendDiarySummaryResponse;
import com.recordapp.domain.social.dto.FriendshipRow;
import com.recordapp.domain.social.mapper.FriendshipMapper;
import com.recordapp.domain.user.mapper.UserMapper;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 친구 둘러보기 서비스(읽기 전용). 친구의 캐릭터 홈·캘린더·작심삼일을 조회한다.
 *
 * <p><b>권한 게이트는 {@link #resolveFriendId} 단 하나</b>다. 모든 조회는 이 메서드를 먼저 통과해
 * 대상 uuid 를 내부 PK 로 바꾸며, 수락된 친구(ACCEPTED)가 아니면 전부 404 로 은닉한다.
 *
 * <p>차단(BLOCKED)을 따로 검사하지 않는 이유: {@code uq_friendship_pair} UNIQUE 인덱스가
 * (LEAST, GREATEST) 로 <b>쌍당 1행</b>을 강제하므로, status 가 ACCEPTED 면 그 쌍에 BLOCKED 행이
 * 존재할 수 없다. 즉 "친구인가?" 판정 한 번이 "차단되지 않았나?"를 포함한다.
 * (피드는 여러 작성자를 한 쿼리에 섞어야 해서 SQL fragment 로 판정하지만, 둘러보기는 대상이
 * 단일 사용자로 고정이라 Java 레벨 단건 판정으로 충분하다.)
 */
@Service
public class FriendBrowseService {

	private final FriendshipMapper friendshipMapper;
	private final UserMapper userMapper;
	private final CharacterService characterService;
	private final DiaryMapper diaryMapper;
	private final ResolutionService resolutionService;

	public FriendBrowseService(FriendshipMapper friendshipMapper, UserMapper userMapper,
			CharacterService characterService, DiaryMapper diaryMapper,
			ResolutionService resolutionService) {
		this.friendshipMapper = friendshipMapper;
		this.userMapper = userMapper;
		this.characterService = characterService;
		this.diaryMapper = diaryMapper;
		this.resolutionService = resolutionService;
	}

	/**
	 * GET /friends/{userUuid}/character — 친구의 캐릭터·착용 아이템.
	 *
	 * <p>{@code buildMyCharacter} 는 ensureState 를 호출하지 않는 순수 조회라 타인 userId 로 안전하며,
	 * 착용 아이템의 variant 해석(캐릭터별 이미지 재선택)도 매퍼 조인이 그대로 수행한다.
	 * 코인·미확인 보상은 여기서 버린다(친구에게 노출 금지).
	 */
	@Transactional(readOnly = true)
	public FriendCharacterResponse getCharacter(Long viewerId, String targetUuid) {
		Long friendId = resolveFriendId(viewerId, targetUuid);
		MyCharacterResponse full = characterService.buildMyCharacter(friendId);
		return new FriendCharacterResponse(full.character(), full.equipment());
	}

	/**
	 * GET /friends/{userUuid}/diaries/summary — 친구의 월별 캘린더 요약.
	 *
	 * <p>공개 기록(FRIENDS·PUBLIC)만 내려간다. PRIVATE·DRAFT 는 목록에서 빠지므로 열람자에게는
	 * 기록이 없는 날과 구분되지 않는다.
	 */
	@Transactional(readOnly = true)
	public FriendDiarySummaryResponse getDiarySummary(Long viewerId, String targetUuid, String yearMonth) {
		Long friendId = resolveFriendId(viewerId, targetUuid);
		List<FriendDiarySummaryDay> days = diaryMapper.findFriendSummaryDays(friendId, yearMonth);
		return new FriendDiarySummaryResponse(yearMonth, days);
	}

	/**
	 * GET /friends/{userUuid}/resolutions — 친구의 작심삼일 목록(커서 페이징).
	 *
	 * <p>{@code ResolutionService.getList} 는 이미 userId 를 파라미터로 받는 순수 조회라 그대로 재사용한다
	 * (커서 절단 로직 중복 없음).
	 */
	@Transactional(readOnly = true)
	public PageResponse<ResolutionListItem> getResolutions(Long viewerId, String targetUuid,
			String status, CursorRequest req) {
		Long friendId = resolveFriendId(viewerId, targetUuid);
		return resolutionService.getList(friendId, status, req);
	}

	/**
	 * 대상 uuid → 내부 PK. 수락된 친구가 아니면 {@link ErrorCode#USER_NOT_FOUND}(404).
	 *
	 * <p>친구 아님·대기중(PENDING)·차단·탈퇴·없는 uuid·잘못된 uuid 형식·자기 자신을 <b>모두 같은 404</b> 로
	 * 응답한다. 403 을 쓰면 "이 uuid 는 실존한다"는 사실이 새어나가므로, 기존 피드 규약("볼 수 없으면 404")을
	 * 따라 존재 자체를 은닉한다. 같은 이유로 NOT_FRIEND 같은 전용 에러코드를 만들지 않는다.
	 */
	private Long resolveFriendId(Long viewerId, String targetUuid) {
		if (!isUuid(targetUuid)) {
			// uuid 형식이 아니면 매퍼의 ::uuid 캐스팅이 500(invalid input syntax)을 내므로 여기서 차단한다.
			throw new BusinessException(ErrorCode.USER_NOT_FOUND);
		}
		Long targetId = userMapper.findIdByUuid(targetUuid); // 탈퇴(deleted_at) 회원은 null
		if (targetId == null || targetId.equals(viewerId)) {
			throw new BusinessException(ErrorCode.USER_NOT_FOUND);
		}
		FriendshipRow relation = friendshipMapper.findRelation(viewerId, targetId);
		if (relation == null || !"ACCEPTED".equals(relation.status())) {
			throw new BusinessException(ErrorCode.USER_NOT_FOUND);
		}
		return targetId;
	}

	private boolean isUuid(String value) {
		if (value == null) {
			return false;
		}
		try {
			UUID.fromString(value);
			return true;
		} catch (IllegalArgumentException e) {
			return false;
		}
	}
}
