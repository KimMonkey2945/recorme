package com.recordapp.domain.feed.service;

import com.recordapp.domain.diary.dto.DiaryFeedItem;
import com.recordapp.domain.diary.dto.FeedDetailResponse;
import com.recordapp.domain.diary.mapper.DiaryMapper;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 피드 서비스. viewer 가 볼 수 있는 기록(본인·PUBLIC·수락친구 FRIENDS)을 커서 페이징으로 조립한다.
 * 조회 대상은 diaries 이므로 DiaryMapper 를 재사용하되, 피드 조립 책임은 DiaryService 와 분리한다.
 * 소유권·본인 식별은 principal 의 userId 로만 수행한다(IDOR 차단).
 */
@Service
public class FeedService {

	private final DiaryMapper diaryMapper;

	public FeedService(DiaryMapper diaryMapper) {
		this.diaryMapper = diaryMapper;
	}

	/**
	 * 피드 목록(감정 카드, id DESC 커서 페이징). DONE 기록만·비차단.
	 * hasNext 판정을 위해 size+1 을 조회해 초과분을 잘라낸다(DiaryService.getList 관례 동일).
	 */
	@Transactional(readOnly = true)
	public PageResponse<DiaryFeedItem> getFeed(Long viewerId, CursorRequest req) {
		int size = req.safeSize();
		List<DiaryFeedItem> rows = diaryMapper.findFeed(viewerId, req.cursor(), size + 1);

		boolean hasNext = rows.size() > size;
		List<DiaryFeedItem> items = hasNext ? rows.subList(0, size) : rows;
		Long nextCursor = items.isEmpty() ? null : items.get(items.size() - 1).id();
		return PageResponse.of(items, hasNext ? nextCursor : null, hasNext);
	}

	/**
	 * 피드 카드 탭 시 전문 조회(viewer-aware). 볼 수 없으면 DIARY_NOT_FOUND(존재 은닉).
	 * 기존 GET /diaries/{id}(owner-only)는 그대로 두고, 타인 글 열람은 이 경로로만 허용한다.
	 */
	@Transactional(readOnly = true)
	public FeedDetailResponse getDetail(Long viewerId, Long id) {
		FeedDetailResponse detail = diaryMapper.findViewableById(viewerId, id);
		if (detail == null) {
			throw new BusinessException(ErrorCode.DIARY_NOT_FOUND);
		}
		return detail;
	}
}
