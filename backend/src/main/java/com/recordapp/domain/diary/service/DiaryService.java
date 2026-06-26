package com.recordapp.domain.diary.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.recordapp.domain.diary.DiaryConstraints;
import com.recordapp.domain.diary.dto.DiaryListItem;
import com.recordapp.domain.diary.dto.DiaryResponse;
import com.recordapp.domain.diary.dto.DiaryRow;
import com.recordapp.domain.diary.dto.DiarySummaryResponse;
import com.recordapp.domain.diary.dto.DiaryUpsertCommand;
import com.recordapp.domain.diary.dto.DiaryUpsertResult;
import com.recordapp.domain.diary.dto.ImageUploadResponse;
import com.recordapp.domain.diary.dto.SaveDiaryRequest;
import com.recordapp.domain.diary.dto.UpdateDiaryRequest;
import com.recordapp.domain.diary.mapper.DiaryMapper;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.infra.storage.StorageService;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.multipart.MultipartFile;

/**
 * 일기 서비스. 소유권은 항상 SecurityContext 의 userId 로만 식별한다(IDOR 차단).
 * 파일 IO(저장/삭제)는 트랜잭션 밖에서 수행하며, 실패 시 보상 삭제 / 커밋 성공 후 회수 전략을 따른다.
 * (UserService.updateAvatar 와 동일한 인프라 IO 분리 패턴.)
 *
 * <p>일기 본문(content)은 Quill Delta JSON 으로 인라인 이미지를 직접 임베드하며, content 가 이미지의
 * 단일 진실 공급원이다(별도 diary_images 테이블 없음). 본문에서 빠지거나 일기 삭제로 더 이상
 * 참조되지 않는 이미지 파일은 content 를 파싱해 커밋 후(afterCommit) 디스크에서 회수한다.
 */
@Service
public class DiaryService {

	private static final Logger log = LoggerFactory.getLogger(DiaryService.class);

	private final DiaryMapper diaryMapper;
	private final StorageService storageService;
	private final ObjectMapper objectMapper;

	public DiaryService(DiaryMapper diaryMapper,
			StorageService storageService,
			ObjectMapper objectMapper) {
		this.diaryMapper = diaryMapper;
		this.storageService = storageService;
		this.objectMapper = objectMapper;
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
		List<String> newUrls = extractImageUrls(req.content());
		if (newUrls.size() > DiaryConstraints.IMAGE_MAX_PER_DIARY) {
			throw new BusinessException(ErrorCode.IMAGE_LIMIT_EXCEEDED);
		}

		// 같은 날짜 기존 일기(UPDATE 전환 시)의 content 를 미리 확보 — 빠진 이미지 파일 회수용.
		// 신규 INSERT 면 existing 이 null 이라 oldUrls 는 비어 있다.
		DiaryRow existing = diaryMapper.findByDateAndUser(userId, req.writtenDate());
		List<String> oldUrls = existing == null ? List.of() : extractImageUrls(existing.content());

		DiaryUpsertCommand cmd = new DiaryUpsertCommand(
				userId, req.content(), req.contentText(), req.writtenDate(), req.visibility());
		diaryMapper.upsert(cmd); // 실행 후 cmd 에 id·inserted 가 채워진다

		DiaryRow row = diaryMapper.findByIdAndUser(cmd.getId(), userId);
		if (row == null) {
			// upsert 와 재조회 사이 동시 삭제 등 비정상 상황 방어
			throw new BusinessException(ErrorCode.DIARY_NOT_FOUND);
		}

		// 본문에서 빠진 이미지 파일만 커밋 후 회수(재참조 파일은 보존).
		reclaimFilesAfterCommit(removed(oldUrls, newUrls));
		return new DiaryUpsertResult(toResponse(row), cmd.isInserted());
	}

	/**
	 * 인라인 이미지 업로드. 작성 중(일기 미저장) 호출되므로 diaryId 에 비종속이며 파일 IO 만 수행한다(DB 미접근).
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

	/** 해당 월(yyyy-MM) 내 일기 목록(written_date 역순). 하루 1기록이라 커서 없이 한 번에 반환. */
	@Transactional(readOnly = true)
	public List<DiaryListItem> getMonthList(Long userId, String yearMonth) {
		return diaryMapper.findByMonth(userId, yearMonth);
	}

	/** 일기 스칼라 row 를 단건 응답으로 매핑한다(인라인 이미지는 content 에 임베드되어 별도 조립 불필요). */
	private DiaryResponse toResponse(DiaryRow row) {
		return new DiaryResponse(row.id(), row.shareToken(), row.content(), row.contentText(),
				row.writtenDate(), row.visibility(), row.analysisStatus());
	}

	/**
	 * 내 일기 목록(커서 페이징, id DESC 최신순).
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

	/** 해당 월 작성일 요약(캘린더 표시용). */
	@Transactional(readOnly = true)
	public DiarySummaryResponse getSummary(Long userId, String yearMonth) {
		List<String> dates = diaryMapper.findSummaryDates(userId, yearMonth);
		return new DiarySummaryResponse(yearMonth, dates);
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
		List<String> oldUrls = extractImageUrls(before.content());

		int updated = diaryMapper.updateByIdAndUser(id, userId, req.content(), req.contentText(), req.visibility());
		if (updated == 0) {
			// before 조회와 update 사이 동시 삭제 방어
			throw new BusinessException(ErrorCode.DIARY_NOT_FOUND);
		}

		// 본문에서 빠진 이미지 파일만 커밋 후 회수.
		reclaimFilesAfterCommit(removed(oldUrls, newUrls));
		return toResponse(diaryMapper.findByIdAndUser(id, userId));
	}

	/**
	 * 일기 소프트 삭제 + 본문에 임베드된 이미지 파일 회수.
	 * <p>DB 작업(일기 soft delete)은 트랜잭션으로 원자성을 보장하고, 디스크 파일 회수는 afterCommit
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
		List<String> urls = new ArrayList<>();
		if (deltaJson == null || deltaJson.isBlank()) {
			return urls;
		}
		try {
			JsonNode ops = objectMapper.readTree(deltaJson).path("ops");
			if (ops.isArray()) {
				for (JsonNode op : ops) {
					JsonNode insert = op.path("insert");
					if (insert.isObject()) {
						JsonNode image = insert.path("image");
						if (image.isTextual()) {
							String url = image.asText();
							if (!url.isBlank() && !urls.contains(url)) {
								urls.add(url);
							}
						}
					}
				}
			}
		} catch (RuntimeException | com.fasterxml.jackson.core.JsonProcessingException e) {
			// 견고성: 파싱 실패 시 이미지 추출만 생략하고 본문 저장은 진행한다.
			log.warn("본문 Delta JSON 파싱 실패 — 인라인 이미지 추출을 생략한다.", e);
		}
		return urls;
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
