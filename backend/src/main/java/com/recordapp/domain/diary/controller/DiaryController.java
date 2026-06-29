package com.recordapp.domain.diary.controller;

import com.recordapp.domain.diary.dto.DiaryResponse;
import com.recordapp.domain.diary.dto.DiarySummaryResponse;
import com.recordapp.domain.diary.dto.DiaryUpsertResult;
import com.recordapp.domain.diary.dto.ImageUploadResponse;
import com.recordapp.domain.diary.dto.SaveDiaryRequest;
import com.recordapp.domain.diary.dto.UpdateDiaryRequest;
import com.recordapp.domain.diary.service.DiaryService;
import com.recordapp.global.common.ApiResponse;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.security.SecurityUser;
import jakarta.validation.Valid;
import java.time.LocalDate;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * 기록 API. 컨텍스트 경로(/api/v1) 하위 /diaries.
 * 본인 식별은 인증 principal의 userId로만 수행한다(요청 바디·경로에 사용자 식별자 없음, IDOR 차단).
 * <p>이 컨트롤러만 일부 메서드에서 {@link ResponseEntity}를 사용한다 — upsert 의 신규(201)/갱신(200)을
 * 구분하기 위함이다(기존 컨트롤러는 항상 200 이라 {@link ApiResponse}를 직접 반환).
 * 정적 경로(/me/summary·/by-date/{date})는 {@code /{id}}(Long) 와 타입이 달라 충돌하지 않는다.
 */
@RestController
@RequestMapping("/diaries")
public class DiaryController {

	private final DiaryService diaryService;

	public DiaryController(DiaryService diaryService) {
		this.diaryService = diaryService;
	}

	/**
	 * POST /diaries — 기록 저장(하루 1기록 upsert).
	 * 신규 생성이면 201, 같은 날짜 재작성(UPDATE)이면 200 으로 응답한다 —
	 * 그래서 이 메서드만 {@link ResponseEntity}로 상태코드를 분기한다.
	 */
	@PostMapping
	public ResponseEntity<ApiResponse<DiaryResponse>> save(
			@AuthenticationPrincipal SecurityUser principal,
			@Valid @RequestBody SaveDiaryRequest request) {
		DiaryUpsertResult result = diaryService.upsert(principal.userId(), request);
		ApiResponse<DiaryResponse> body = ApiResponse.ok(result.diary());
		return result.inserted()
				? ResponseEntity.status(HttpStatus.CREATED).body(body)
				: ResponseEntity.ok(body);
	}

	/**
	 * GET /diaries/me — 내 기록 목록.
	 * <ul>
	 *   <li>{@code yearMonth=yyyy-MM} 지정 시: 해당 월 전체 목록(written_date 역순, 커서 없음). 데이터 {@code List<DiaryListItem>}.
	 *   <li>미지정 시: 커서 페이징(id DESC). cursor 생략 시 첫 페이지, size 기본 20·최대 50. 데이터 {@code PageResponse<DiaryListItem>}.
	 * </ul>
	 * 응답 형태가 분기되므로 반환 타입은 {@code ApiResponse<?>}. 정적 경로라 {@code /{id}} 와 충돌 없음.
	 */
	@GetMapping("/me")
	public ApiResponse<?> getMyDiaries(
			@AuthenticationPrincipal SecurityUser principal,
			@RequestParam(required = false) String yearMonth,
			@RequestParam(required = false) Long cursor,
			@RequestParam(required = false) Integer size) {
		if (yearMonth != null && !yearMonth.isBlank()) {
			return ApiResponse.ok(diaryService.getMonthList(principal.userId(), yearMonth));
		}
		return ApiResponse.ok(diaryService.getList(principal.userId(), new CursorRequest(cursor, size)));
	}

	/** GET /diaries/me/summary — 해당 월 작성일 요약(캘린더 표시용). yearMonth="yyyy-MM". */
	@GetMapping("/me/summary")
	public ApiResponse<DiarySummaryResponse> getSummary(
			@AuthenticationPrincipal SecurityUser principal,
			@RequestParam String yearMonth) {
		return ApiResponse.ok(diaryService.getSummary(principal.userId(), yearMonth));
	}

	/** GET /diaries/by-date/{date} — 날짜 단건 조회(yyyy-MM-dd). */
	@GetMapping("/by-date/{date}")
	public ApiResponse<DiaryResponse> getByDate(
			@AuthenticationPrincipal SecurityUser principal,
			@PathVariable @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) {
		return ApiResponse.ok(diaryService.getByDate(principal.userId(), date));
	}

	/** GET /diaries/{id} — 내부 PK 단건 조회. */
	@GetMapping("/{id}")
	public ApiResponse<DiaryResponse> getById(
			@AuthenticationPrincipal SecurityUser principal,
			@PathVariable Long id) {
		return ApiResponse.ok(diaryService.getById(principal.userId(), id));
	}

	/** PUT /diaries/{id} — 본문/공개범위 수정. 본문 변경 시 재분석 트리거(서비스 책임). */
	@PutMapping("/{id}")
	public ApiResponse<DiaryResponse> update(
			@AuthenticationPrincipal SecurityUser principal,
			@PathVariable Long id,
			@Valid @RequestBody UpdateDiaryRequest request) {
		return ApiResponse.ok(diaryService.update(principal.userId(), id, request));
	}

	/** DELETE /diaries/{id} — 기록 소프트 삭제(첨부 사진 회수 포함). */
	@DeleteMapping("/{id}")
	public ApiResponse<Void> delete(
			@AuthenticationPrincipal SecurityUser principal,
			@PathVariable Long id) {
		diaryService.delete(principal.userId(), id);
		return ApiResponse.ok();
	}

	/**
	 * POST /diaries/images — 인라인 이미지 업로드(multipart, part name="file").
	 * <p>작성 중 호출되어 어떤 기록에도 종속되지 않는다(diaryId 비종속). 반환 {@code {"url": ...}} 을
	 * 클라이언트가 본문 Delta 에 끼워 넣고, 저장(POST/PUT /diaries) 시 content 에 그대로 임베드된다.
	 * 정적 경로(/images)라 {@code /{id}}(Long) 와 충돌하지 않는다.
	 */
	@PostMapping(value = "/images", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
	public ApiResponse<ImageUploadResponse> uploadImage(
			@AuthenticationPrincipal SecurityUser principal,
			@RequestPart("file") MultipartFile file) {
		return ApiResponse.ok(diaryService.uploadImage(principal.userId(), file));
	}
}
