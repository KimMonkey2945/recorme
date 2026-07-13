package com.recordapp.domain.diary.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.recordapp.domain.diary.DeltaImages;
import com.recordapp.domain.diary.DiaryConstraints;
import com.recordapp.domain.diary.dto.DiaryListItem;
import com.recordapp.domain.diary.dto.DiaryResponse;
import com.recordapp.domain.diary.dto.DiaryRow;
import com.recordapp.domain.diary.dto.DiarySummaryDay;
import com.recordapp.domain.diary.dto.DiarySummaryResponse;
import com.recordapp.domain.diary.dto.DiaryUpsertCommand;
import com.recordapp.domain.diary.dto.DiaryUpsertResult;
import com.recordapp.domain.diary.dto.ImageUploadResponse;
import com.recordapp.domain.diary.dto.SaveDiaryRequest;
import com.recordapp.domain.diary.dto.SharedDiaryResponse;
import com.recordapp.domain.diary.dto.UpdateDiaryRequest;
import com.recordapp.domain.diary.dto.UpdateVisibilityRequest;
import com.recordapp.domain.diary.mapper.DiaryMapper;
import com.recordapp.domain.emotion.service.EmotionAnalysisService;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.infra.storage.StorageService;
import java.time.LocalDate;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.multipart.MultipartFile;

/**
 * 기록 서비스. 소유권은 항상 SecurityContext 의 userId 로만 식별한다(IDOR 차단).
 * 파일 IO(저장/삭제)는 트랜잭션 밖에서 수행하며, 실패 시 보상 삭제 / 커밋 성공 후 회수 전략을 따른다.
 * (UserService.updateAvatar 와 동일한 인프라 IO 분리 패턴.)
 *
 * <p>기록 본문(content)은 Quill Delta JSON 으로 인라인 이미지를 직접 임베드하며, content 가 이미지의
 * 단일 진실 공급원이다(별도 diary_images 테이블 없음). 본문에서 빠지거나 기록 삭제로 더 이상
 * 참조되지 않는 이미지 파일은 content 를 파싱해 커밋 후(afterCommit) 디스크에서 회수한다.
 */
@Service
public class DiaryService {

	private static final Logger log = LoggerFactory.getLogger(DiaryService.class);

	private final DiaryMapper diaryMapper;
	private final StorageService storageService;
	private final ObjectMapper objectMapper;
	private final EmotionAnalysisService emotionAnalysisService;

	public DiaryService(DiaryMapper diaryMapper,
			StorageService storageService,
			ObjectMapper objectMapper,
			EmotionAnalysisService emotionAnalysisService) {
		this.diaryMapper = diaryMapper;
		this.storageService = storageService;
		this.objectMapper = objectMapper;
		// 단방향 의존(DiaryService → EmotionAnalysisService). 분석 서비스는 DiaryService 를 모름(순환참조 회피).
		this.emotionAnalysisService = emotionAnalysisService;
	}

	/**
	 * 하루 1기록 upsert. 같은 날짜 재작성은 SQL 의 ON CONFLICT 로 UPDATE 전환된다.
	 * cmd 의 RETURNING(id·inserted)으로 신규/갱신을 판정한 뒤 단건 재조회해 반환한다.
	 * <p>이미지 한도 초과면 DB 변경 전에 예외로 롤백한다. 같은 날짜를 UPDATE 로 덮어쓰는 경우,
	 * 수정 전 content 의 이미지 중 새 content 에서 빠진 파일은 커밋 후 디스크에서 회수한다.
	 */
	@Transactional
	public DiaryUpsertResult upsert(Long userId, SaveDiaryRequest req) {
		validateContentFormat(req.content());
		// 과도한 과거 소급 차단(미래는 @PastOrPresent 가 차단). 임의 과거 날짜 대량 확정 표면 축소.
		if (req.writtenDate().isBefore(LocalDate.now().minusDays(DiaryConstraints.MAX_BACKDATE_DAYS))) {
			throw new BusinessException(ErrorCode.VALIDATION_ERROR, "너무 오래된 날짜의 기록은 저장할 수 없어요.");
		}
		List<String> newUrls = extractImageUrls(req.content());
		if (newUrls.size() > DiaryConstraints.IMAGE_MAX_PER_DIARY) {
			throw new BusinessException(ErrorCode.IMAGE_LIMIT_EXCEEDED);
		}

		// 같은 날짜 기존 기록(UPDATE 전환 시)의 content 를 미리 확보 — 빠진 이미지 파일 회수용.
		// 신규 INSERT 면 existing 이 null 이라 oldUrls 는 비어 있다.
		DiaryRow existing = diaryMapper.findByDateAndUser(userId, req.writtenDate());
		// 이미 확정(DRAFT 아님)된 기록은 수정 불가 — DB 변경 전에 조기 차단.
		if (existing != null && !"DRAFT".equals(existing.analysisStatus())) {
			throw new BusinessException(ErrorCode.DIARY_ALREADY_CONFIRMED);
		}
		// 확정(감정 분석 트리거) 시에만 일일 상한 검사 — LLM(Gemini) 비용 폭탄 방어(공개 노출 대비).
		// 여기까지 왔다면 대상은 DRAFT/신규라 이번 확정이 실제 신규 분석 1건이 된다.
		if (Boolean.TRUE.equals(req.confirm())
				&& diaryMapper.countRecentConfirmations(userId) >= DiaryConstraints.DAILY_CONFIRM_LIMIT) {
			throw new BusinessException(ErrorCode.DIARY_DAILY_LIMIT);
		}
		List<String> oldUrls = existing == null ? List.of() : extractImageUrls(existing.content());

		// confirm=true 면 '오늘을 기억하기'(PENDING·분석), 아니면 등록(DRAFT 유지).
		DiaryUpsertCommand cmd = new DiaryUpsertCommand(
				userId, req.content(), req.contentText(), req.writtenDate(), req.visibility(),
				Boolean.TRUE.equals(req.confirm()));
		diaryMapper.upsert(cmd); // 실행 후 cmd 에 id·inserted 가 채워진다

		// 경합 백스톱: 조회~upsert 사이 타 요청이 같은 날짜를 확정하면 ON CONFLICT WHERE 가드가 0행 →
		// RETURNING 이 비어 id 가 null 로 남는다. 이 경우 확정 충돌로 보고 차단한다.
		if (cmd.getId() == null) {
			throw new BusinessException(ErrorCode.DIARY_ALREADY_CONFIRMED);
		}

		DiaryRow row = diaryMapper.findByIdAndUser(cmd.getId(), userId);
		if (row == null) {
			// upsert 와 재조회 사이 동시 삭제 등 비정상 상황 방어
			throw new BusinessException(ErrorCode.DIARY_NOT_FOUND);
		}

		// 본문에서 빠진 이미지 파일만 커밋 후 회수(재참조 파일은 보존).
		reclaimFilesAfterCommit(removed(oldUrls, newUrls));
		// 확정(confirm=true)이면 PENDING → 커밋 후 비동기 감정 분석 트리거. DRAFT(등록)면 PENDING 아님 → 스킵.
		triggerAnalysisIfPending(row);
		return new DiaryUpsertResult(toResponse(row), cmd.isInserted());
	}

	/**
	 * 인라인 이미지 업로드. 작성 중(기록 미저장) 호출되므로 diaryId 에 비종속이며 파일 IO 만 수행한다(DB 미접근).
	 * 반환 URL 을 클라이언트가 본문 Delta 에 끼워 넣고, 저장(upsert/update) 시 content 에 그대로 임베드된다.
	 * 매직바이트 검증은 StorageService.store 가 수행한다.
	 *
	 * <p>편집을 취소하면 본문에 끼워지지 못한 업로드 파일이 미참조 고아로 남을 수 있다(MVP 허용).
	 */
	public ImageUploadResponse uploadImage(Long userId, MultipartFile file) {
		if (file == null || file.isEmpty()) {
			throw new BusinessException(ErrorCode.INVALID_FILE, "업로드할 사진이 없습니다.");
		}
		// TODO: 미참조 업로드 파일 GC 배치(향후) — 작성 취소 등으로 본문에 끼워지지 못한 파일 회수.
		String url = storageService.store(file, "diaries");
		return new ImageUploadResponse(url);
	}

	/** 사용자+날짜 단건 조회. 없으면 DIARY_NOT_FOUND. 인라인 이미지는 content(Delta)에 포함된다. */
	@Transactional(readOnly = true)
	public DiaryResponse getByDate(Long userId, LocalDate date) {
		DiaryRow row = diaryMapper.findByDateAndUser(userId, date);
		if (row == null) {
			throw new BusinessException(ErrorCode.DIARY_NOT_FOUND);
		}
		return toResponse(row);
	}

	/** 내부 PK+사용자 단건 조회. 없으면 DIARY_NOT_FOUND. 인라인 이미지는 content(Delta)에 포함된다. */
	@Transactional(readOnly = true)
	public DiaryResponse getById(Long userId, Long id) {
		DiaryRow row = diaryMapper.findByIdAndUser(id, userId);
		if (row == null) {
			throw new BusinessException(ErrorCode.DIARY_NOT_FOUND);
		}
		return toResponse(row);
	}

	/** 해당 월(yyyy-MM) 내 기록 목록(written_date 역순). 하루 1기록이라 커서 없이 한 번에 반환. */
	@Transactional(readOnly = true)
	public List<DiaryListItem> getMonthList(Long userId, String yearMonth) {
		return diaryMapper.findByMonth(userId, yearMonth);
	}

	/**
	 * 기록 스칼라 row 를 단건 응답으로 매핑한다(인라인 이미지는 content 에 임베드되어 별도 조립 불필요).
	 * 감정 분석 테마 필드(primaryEmotion~moodEmoji)는 DONE 일 때만 채워지고 그 외엔 NULL 그대로 전달된다.
	 */
	private DiaryResponse toResponse(DiaryRow row) {
		return new DiaryResponse(row.id(), row.shareToken(), row.content(), row.contentText(),
				row.writtenDate(), row.visibility(), row.analysisStatus(),
				row.primaryEmotion(), row.backgroundColor(), row.textColor(), row.accentColor(),
				row.aiComment(), row.aiTitle(), row.moodEmoji());
	}

	/**
	 * 내 기록 목록(커서 페이징, id DESC 최신순).
	 * <p>hasNext 판정을 위해 {@code size+1} 건을 조회해, 초과분이 있으면 잘라내고 hasNext=true 로 본다.
	 * nextCursor 는 잘라낸 items 의 마지막 id(다음 페이지는 {@code id < nextCursor}). 빈 결과면 둘 다 없음.
	 */
	@Transactional(readOnly = true)
	public PageResponse<DiaryListItem> getList(Long userId, CursorRequest req) {
		int size = req.safeSize();
		List<DiaryListItem> rows = diaryMapper.findList(userId, req.cursor(), size + 1); // +1로 다음 페이지 존재 탐지

		boolean hasNext = rows.size() > size;
		List<DiaryListItem> items = hasNext ? rows.subList(0, size) : rows;
		Long nextCursor = items.isEmpty() ? null : items.get(items.size() - 1).id();
		return PageResponse.of(items, hasNext ? nextCursor : null, hasNext);
	}

	/** 해당 월 일자별 요약(캘린더 표시용 — 날짜별 감정색·무드 이모지 포함). */
	@Transactional(readOnly = true)
	public DiarySummaryResponse getSummary(Long userId, String yearMonth) {
		List<DiarySummaryDay> days = diaryMapper.findSummaryDays(userId, yearMonth);
		return new DiarySummaryResponse(yearMonth, days);
	}

	/**
	 * 본문/공개범위 수정. 영향행 0이면 대상 부재/타인 소유 → DIARY_NOT_FOUND.
	 * <p>이미지 한도 초과면 DB 변경 전에 예외로 롤백한다. 수정 전 content 를 먼저 확보해, 새 content 에서
	 * 빠진 이미지 파일을 커밋 후 디스크에서 회수한다(재참조 파일은 보존).
	 */
	@Transactional
	public DiaryResponse update(Long userId, Long id, UpdateDiaryRequest req) {
		validateContentFormat(req.content());
		List<String> newUrls = extractImageUrls(req.content());
		if (newUrls.size() > DiaryConstraints.IMAGE_MAX_PER_DIARY) {
			throw new BusinessException(ErrorCode.IMAGE_LIMIT_EXCEEDED);
		}

		// 수정 전 기존 content 확보(빠진 이미지 회수용). 부재/타인 소유면 DIARY_NOT_FOUND.
		DiaryRow before = diaryMapper.findByIdAndUser(id, userId);
		if (before == null) {
			throw new BusinessException(ErrorCode.DIARY_NOT_FOUND);
		}
		// 이미 확정(DRAFT 아님)된 기록은 수정 불가 — DB 변경 전에 조기 차단.
		if (!"DRAFT".equals(before.analysisStatus())) {
			throw new BusinessException(ErrorCode.DIARY_ALREADY_CONFIRMED);
		}
		List<String> oldUrls = extractImageUrls(before.content());

		int updated = diaryMapper.updateByIdAndUser(id, userId, req.content(), req.contentText(), req.visibility());
		if (updated == 0) {
			// before 조회와 update 사이 동시 삭제 방어
			throw new BusinessException(ErrorCode.DIARY_NOT_FOUND);
		}

		// 본문에서 빠진 이미지 파일만 커밋 후 회수.
		reclaimFilesAfterCommit(removed(oldUrls, newUrls));
		DiaryRow after = diaryMapper.findByIdAndUser(id, userId);
		if (after == null) {
			// update 와 재조회 사이 동시 삭제 방어 — null 이면 toResponse 에서 NPE 가 발생하므로 명시적 차단.
			throw new BusinessException(ErrorCode.DIARY_NOT_FOUND);
		}
		// 수정 가능한 기록은 항상 DRAFT(미분석)이며 update 가 상태를 바꾸지 않으므로 after 는 PENDING 이 아니다 →
		// triggerAnalysisIfPending 는 스킵된다(확정은 upsert confirm=true 경로에서만 발생). 방어적으로 호출 유지.
		triggerAnalysisIfPending(after);
		return toResponse(after);
	}

	/** 허용 공개범위 값 집합(DB CHECK 와 동일). */
	private static final List<String> VISIBILITIES = List.of("PRIVATE", "FRIENDS", "PUBLIC");

	/**
	 * 공개범위(visibility)만 변경한다. 본문·analysis_status 를 건드리지 않으므로 확정 기록도 허용한다
	 * (본문 불변성과 분리). 잘못된 enum 값은 VALIDATION_ERROR, 대상 부재/타인 소유면 DIARY_NOT_FOUND.
	 */
	@Transactional
	public DiaryResponse changeVisibility(Long userId, Long id, UpdateVisibilityRequest req) {
		String visibility = req.visibility() == null ? null : req.visibility().trim();
		if (!VISIBILITIES.contains(visibility)) {
			throw new BusinessException(ErrorCode.VALIDATION_ERROR, "공개범위 값이 올바르지 않습니다.");
		}
		int updated = diaryMapper.updateVisibilityByIdAndUser(id, userId, visibility);
		if (updated == 0) {
			throw new BusinessException(ErrorCode.DIARY_NOT_FOUND);
		}
		DiaryRow row = diaryMapper.findByIdAndUser(id, userId);
		if (row == null) {
			throw new BusinessException(ErrorCode.DIARY_NOT_FOUND);
		}
		return toResponse(row);
	}

	/**
	 * 공유 링크 단건 공개 조회(비인증). 활성·확정·PRIVATE 아님 기록만 반환하며,
	 * 없거나 조건 미충족(DRAFT/삭제/PRIVATE)이면 DIARY_NOT_FOUND(존재 은닉).
	 */
	@Transactional(readOnly = true)
	public SharedDiaryResponse getShared(String shareToken) {
		SharedDiaryResponse shared = diaryMapper.findByShareToken(shareToken);
		if (shared == null) {
			throw new BusinessException(ErrorCode.DIARY_NOT_FOUND);
		}
		return shared;
	}

	/**
	 * 기록 소프트 삭제 + 본문에 임베드된 이미지 파일 회수.
	 * <p>DB 작업(기록 soft delete)은 트랜잭션으로 원자성을 보장하고, 디스크 파일 회수는 afterCommit
	 * 콜백에서 수행한다 — 커밋이 확정된 뒤에만 파일을 지워 롤백 시 파일이 보존되도록 한다.
	 * 회수 대상 URL 은 soft delete 전 content(Delta)에서 추출한다(삭제 후엔 조회 불가).
	 */
	@Transactional
	public void delete(Long userId, Long id) {
		DiaryRow row = diaryMapper.findByIdAndUser(id, userId);
		if (row == null) {
			throw new BusinessException(ErrorCode.DIARY_NOT_FOUND);
		}
		// 디스크 회수 대상 URL 을 soft delete 전 content 에서 확보.
		List<String> urls = extractImageUrls(row.content());

		int deleted = diaryMapper.softDeleteByIdAndUser(id, userId);
		if (deleted == 0) {
			// 조회와 soft delete 사이 동시 삭제 → 예외로 롤백
			throw new BusinessException(ErrorCode.DIARY_NOT_FOUND);
		}

		// 커밋 성공 후에만 파일 회수(롤백 시 파일 보존). 동기화가 없으면 즉시 삭제로 폴백.
		reclaimFilesAfterCommit(urls);
	}

	/**
	 * 본문 content 가 Quill Delta 오브젝트({@code {"ops":[...]}}) 형식인지 저장 전 검증한다.
	 * 목록 SQL 의 {@code content::jsonb} 캐스트와 jsonb 파싱이 깨지지 않도록 형식을 강제한다
	 * (정상 클라이언트는 항상 이 형식으로 보내며, 직접 API 호출 등 비정상 입력을 차단한다).
	 */
	private void validateContentFormat(String content) {
		try {
			JsonNode root = objectMapper.readTree(content);
			if (!root.isObject() || !root.path("ops").isArray()) {
				throw new BusinessException(ErrorCode.VALIDATION_ERROR, "본문 형식이 올바르지 않습니다.");
			}
		} catch (com.fasterxml.jackson.core.JsonProcessingException e) {
			throw new BusinessException(ErrorCode.VALIDATION_ERROR, "본문 형식이 올바르지 않습니다.");
		}
	}

	/** oldUrls 중 newUrls 에 없는 URL(본문에서 빠진 이미지)만 추린다 — 디스크 회수 대상. */
	private List<String> removed(List<String> oldUrls, List<String> newUrls) {
		return oldUrls.stream().filter(u -> !newUrls.contains(u)).toList();
	}

	/**
	 * 본문 Delta(JSON 문자열)에서 인라인 이미지 URL 을 등장 순서대로 추출한다(중복 제거, 순서 보존).
	 * Quill Delta 의 {@code ops[].insert.image}(문자열 URL)만 대상으로 한다.
	 * <p>파싱 실패/형식 불일치는 빈 목록으로 견고하게 처리한다 — 본문 저장 자체를 막지 않기 위함이다.
	 */
	private List<String> extractImageUrls(String deltaJson) {
		// 추출 규칙은 공용 유틸(DeltaImages)로 일원화 — 감정 분석용 이미지 준비와 동일 로직을 공유한다.
		return DeltaImages.extractImageUrls(objectMapper, deltaJson);
	}

	/**
	 * analysis_status 가 PENDING 인 기록에 한해 비동기 감정 분석을 커밋 이후에 트리거한다.
	 * <p>커밋 전에 dispatch 하면 @Async 스레드가 미커밋 행을 PENDING 으로 못 보거나(stale) 롤백된 기록을
	 * 분석할 수 있으므로, 파일 회수와 동일하게 afterCommit 으로 미룬다. 동기화 비활성 시 즉시 호출 폴백.
	 */
	private void triggerAnalysisIfPending(DiaryRow row) {
		if (row == null || !"PENDING".equals(row.analysisStatus())) {
			return;
		}
		long diaryId = row.id();
		if (TransactionSynchronizationManager.isSynchronizationActive()) {
			TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
				@Override
				public void afterCommit() {
					emotionAnalysisService.analyzeAsync(diaryId);
				}
			});
		} else {
			emotionAnalysisService.analyzeAsync(diaryId);
		}
	}

	/**
	 * 디스크 파일 회수를 커밋 이후로 미룬다(롤백 시 파일 보존). 트랜잭션 동기화가 비활성이면 즉시 회수로 폴백.
	 * 빈 목록이면 아무것도 하지 않는다.
	 */
	private void reclaimFilesAfterCommit(List<String> urls) {
		if (urls == null || urls.isEmpty()) {
			return;
		}
		if (TransactionSynchronizationManager.isSynchronizationActive()) {
			TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
				@Override
				public void afterCommit() {
					urls.forEach(storageService::deleteByUrl);
				}
			});
		} else {
			urls.forEach(storageService::deleteByUrl);
		}
	}
}
