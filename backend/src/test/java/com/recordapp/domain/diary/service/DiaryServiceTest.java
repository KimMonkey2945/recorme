package com.recordapp.domain.diary.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.recordapp.domain.auth.service.UserProvisioningService;
import com.recordapp.domain.diary.DiaryConstraints;
import com.recordapp.domain.diary.dto.DiaryListItem;
import com.recordapp.domain.diary.dto.DiaryResponse;
import com.recordapp.domain.diary.dto.DiarySummaryResponse;
import com.recordapp.domain.diary.dto.DiaryUpsertResult;
import com.recordapp.domain.diary.dto.SaveDiaryRequest;
import com.recordapp.domain.diary.dto.UpdateDiaryRequest;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.global.security.SupabaseClaims;
import com.recordapp.infra.storage.StorageProperties;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Stream;
import javax.sql.DataSource;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.dao.DataAccessException;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * DiaryService 통합 테스트(Testcontainers PostgreSQL 18).
 * upsert(하루 1기록·소프트삭제 후 재작성), 소유권(IDOR) 조회·수정·삭제, 월 요약,
 * 인라인 이미지 한도·본문에서 빠진 파일 회수, 일기 삭제 시 디스크 파일 회수를 검증한다.
 *
 * <p>본문은 리치 텍스트(Quill Delta JSON)이며 인라인 이미지를 직접 임베드한다(content 가 단일 진실원).
 * 이미지는 먼저 {@code uploadImage} 로 업로드한 URL 을 본문 Delta 에 끼워 넣고 upsert/update 시 저장된다.
 * 목록의 썸네일·장수는 content 를 jsonb 파싱해 산출한다.
 *
 * <p>⚠️ 클래스/메서드에 {@code @Transactional} 을 두지 않는다(UserServiceTest 와 동일).
 * delete()/update 의 디스크 파일 회수는 afterCommit 동기화로 동작하므로, 테스트가 트랜잭션으로
 * 감싸지면 커밋이 일어나지 않아 afterCommit 콜백이 호출되지 않는다.
 */
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class DiaryServiceTest {

	@Container
	@ServiceConnection
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

	@Autowired
	DiaryService diaryService;

	@Autowired
	UserProvisioningService provisioningService;

	@Autowired
	DataSource dataSource;

	@Autowired
	StorageProperties storageProperties;

	// ===== 헬퍼(UserServiceTest 와 동일 패턴) =====

	/** 저장 URL(상대경로 /files/...)을 디스크 실제 경로로 환산. */
	private Path resolveStored(String url) {
		String urlPath = storageProperties.urlPath(); // "/files"
		String relative = url.substring(urlPath.length() + 1); // urlPath + "/" 제거
		return Paths.get(storageProperties.root()).toAbsolutePath().normalize().resolve(relative);
	}

	/** 유효한 PNG 매직바이트로 시작하는 가짜 이미지. */
	private MockMultipartFile pngFile() {
		byte[] png = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0};
		return new MockMultipartFile("file", "a.png", MediaType.IMAGE_PNG_VALUE, png);
	}

	/** 이미지가 아닌 텍스트 파일(매직바이트 검증 실패 유도). */
	private MockMultipartFile txtFile() {
		return new MockMultipartFile("file", "a.txt", MediaType.TEXT_PLAIN_VALUE, "hello".getBytes());
	}

	/** 인라인 이미지 1장 업로드 후 접근 URL 반환(파일은 디스크에 즉시 저장됨). */
	private String upload(long userId) {
		return diaryService.uploadImage(userId, pngFile()).url();
	}

	/** 순수 텍스트만 담은 Quill Delta JSON. */
	private String deltaOf(String text) {
		return "{\"ops\":[{\"insert\":\"" + text + "\\n\"}]}";
	}

	/** 이미지 URL들(등장 순서) + 텍스트를 담은 Quill Delta JSON. */
	private String deltaWithImages(String text, List<String> urls) {
		StringBuilder sb = new StringBuilder("{\"ops\":[");
		for (String u : urls) {
			sb.append("{\"insert\":{\"image\":\"").append(u).append("\"}},");
		}
		sb.append("{\"insert\":\"").append(text).append("\\n\"}]}");
		return sb.toString();
	}

	private JdbcTemplate jdbc() {
		return new JdbcTemplate(dataSource);
	}

	/** JIT로 회원 1명 생성 후 내부 PK 반환. */
	private long provision(String sub, String email, Map<String, Object> metadata) {
		return provisioningService.provision(
				new SupabaseClaims(sub, email, metadata, Map.of("sub", sub))).userId();
	}

	/** 임의 회원 1명 생성(테스트별 고유). */
	private long newUser() {
		String sub = UUID.randomUUID().toString();
		return provision(sub, sub + "@example.com", Map.of("name", "tester"));
	}

	/** diaries 첨부 사진 저장 루트(root/diaries) 하위의 정규 파일 수(디스크 고아 검증용). */
	private long diaryFileCount() throws IOException {
		Path dir = Paths.get(storageProperties.root()).toAbsolutePath().normalize().resolve("diaries");
		if (!Files.exists(dir)) {
			return 0;
		}
		try (Stream<Path> s = Files.walk(dir)) {
			return s.filter(Files::isRegularFile).count();
		}
	}

	/** content(Delta)에 임베드된 인라인 이미지 개수(jsonb 파싱). */
	private int imageCountInContent(long userId, long diaryId) {
		String content = diaryService.getById(userId, diaryId).content();
		Integer n = jdbc().queryForObject(
				"SELECT count(*)::int FROM jsonb_array_elements(?::jsonb -> 'ops') AS op "
						+ "WHERE op->'insert'->>'image' IS NOT NULL",
				Integer.class, content);
		return n == null ? 0 : n;
	}

	/**
	 * 같은 유저로 일기 count 건 생성(서로 다른 written_date — 하루 1기록 제약 회피).
	 * 작성일은 baseDate 부터 하루씩 늘려, 생성 순서대로 id 가 증가한다(목록은 id DESC 로 역순 반환).
	 * @return 생성된 일기 id 목록(생성 순서, 즉 오름차순)
	 */
	private List<Long> createDiaries(long userId, int count) {
		LocalDate base = LocalDate.of(2026, 1, 1);
		List<Long> ids = new ArrayList<>(count);
		for (int i = 0; i < count; i++) {
			long id = diaryService.upsert(userId,
					new SaveDiaryRequest(deltaOf("일기 " + i), "일기 " + i, base.plusDays(i), "PRIVATE"))
					.diary().id();
			ids.add(id);
		}
		return ids;
	}

	// ===== upsert =====

	@Test
	void upsert_create_returnsInsertedTrueAndPersists() {
		long userId = newUser();
		LocalDate date = LocalDate.of(2026, 1, 10);

		DiaryUpsertResult result = diaryService.upsert(userId,
				new SaveDiaryRequest(deltaOf("첫 일기"), "첫 일기", date, "PRIVATE"));

		assertThat(result.inserted()).isTrue();
		assertThat(result.diary().contentText()).isEqualTo("첫 일기");
		assertThat(result.diary().content()).contains("첫 일기"); // content 는 Delta JSON(텍스트 포함)
		assertThat(result.diary().writtenDate()).isEqualTo(date);

		// 날짜·PK 두 경로로 동일 행이 조회되는지 확인
		assertThat(diaryService.getByDate(userId, date).contentText()).isEqualTo("첫 일기");
		assertThat(diaryService.getById(userId, result.diary().id()).writtenDate()).isEqualTo(date);
	}

	@Test
	void upsert_sameDate_updatesSameRow() {
		long userId = newUser();
		LocalDate date = LocalDate.of(2026, 2, 5);

		DiaryUpsertResult first = diaryService.upsert(userId,
				new SaveDiaryRequest(deltaOf("원본"), "원본", date, "PRIVATE"));
		// 같은 사용자+날짜 재작성 → ON CONFLICT 로 UPDATE 전환
		DiaryUpsertResult second = diaryService.upsert(userId,
				new SaveDiaryRequest(deltaOf("수정본"), "수정본", date, "PRIVATE"));

		assertThat(second.inserted()).isFalse();
		assertThat(second.diary().id()).isEqualTo(first.diary().id()); // 같은 행
		assertThat(second.diary().contentText()).isEqualTo("수정본");
	}

	@Test
	void upsert_afterSoftDelete_allowsNewInsert() {
		long userId = newUser();
		LocalDate date = LocalDate.of(2026, 3, 1);

		DiaryUpsertResult first = diaryService.upsert(userId,
				new SaveDiaryRequest(deltaOf("삭제 대상"), "삭제 대상", date, "PRIVATE"));
		diaryService.delete(userId, first.diary().id()); // 소프트 삭제 → 부분 유니크에서 제외

		DiaryUpsertResult again = diaryService.upsert(userId,
				new SaveDiaryRequest(deltaOf("새로 작성"), "새로 작성", date, "PRIVATE"));

		assertThat(again.inserted()).isTrue();
		assertThat(again.diary().id()).isNotEqualTo(first.diary().id()); // 새 행
		assertThat(diaryService.getByDate(userId, date).contentText()).isEqualTo("새로 작성");
	}

	// ===== 조회(소유권/부재) =====

	@Test
	void getById_nonExistent_throwsDiaryNotFound() {
		long userId = newUser();
		assertThatThrownBy(() -> diaryService.getById(userId, -1L))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.DIARY_NOT_FOUND));
	}

	@Test
	void getByDate_nonExistent_throwsDiaryNotFound() {
		long userId = newUser();
		assertThatThrownBy(() -> diaryService.getByDate(userId, LocalDate.of(2000, 1, 1)))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.DIARY_NOT_FOUND));
	}

	@Test
	void getById_otherUser_throwsDiaryNotFound() {
		long owner = newUser();
		long stranger = newUser();
		DiaryUpsertResult diary = diaryService.upsert(owner,
				new SaveDiaryRequest(deltaOf("내 일기"), "내 일기", LocalDate.of(2026, 4, 1), "PRIVATE"));

		// 소유권은 userId 로만 식별 → 타인 PK 조회는 부재와 동일하게 차단(IDOR)
		assertThatThrownBy(() -> diaryService.getById(stranger, diary.diary().id()))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.DIARY_NOT_FOUND));
	}

	// ===== 수정 =====

	@Test
	void update_changesContentAndResetsAnalysis() {
		long userId = newUser();
		DiaryUpsertResult created = diaryService.upsert(userId,
				new SaveDiaryRequest(deltaOf("분석 전"), "분석 전", LocalDate.of(2026, 5, 2), "PRIVATE"));
		long id = created.diary().id();
		// 분석 완료 상태로 만든 뒤 순수 텍스트 수정이 PENDING 으로 되돌리는지 검증
		jdbc().update("UPDATE diaries SET analysis_status = 'DONE' WHERE id = ?", id);

		DiaryResponse updated = diaryService.update(userId, id,
				new UpdateDiaryRequest(deltaOf("내용 변경됨"), "내용 변경됨", "PRIVATE"));

		assertThat(updated.contentText()).isEqualTo("내용 변경됨");
		assertThat(updated.analysisStatus()).isEqualTo("PENDING"); // 순수 텍스트 변경 → 재분석 트리거
		String db = jdbc().queryForObject(
				"SELECT analysis_status FROM diaries WHERE id = ?", String.class, id);
		assertThat(db).isEqualTo("PENDING");
	}

	@Test
	void update_sameTextDifferentFormatting_keepsAnalysis() {
		long userId = newUser();
		DiaryUpsertResult created = diaryService.upsert(userId,
				new SaveDiaryRequest(deltaOf("고정 텍스트"), "고정 텍스트", LocalDate.of(2026, 5, 9), "PRIVATE"));
		long id = created.diary().id();
		jdbc().update("UPDATE diaries SET analysis_status = 'DONE' WHERE id = ?", id);

		// content(Delta)는 바뀌지만 content_text 는 동일 → 재분석 트리거 없음(DONE 유지)
		DiaryResponse updated = diaryService.update(userId, id,
				new UpdateDiaryRequest("{\"ops\":[{\"insert\":{\"image\":\"x\"}}]}", "고정 텍스트", "PRIVATE"));

		// 위 update 는 content_text 동일이라 analysis_status 그대로. (image "x" 는 스토리지 소유 아님 → 회수 no-op)
		assertThat(updated.analysisStatus()).isEqualTo("DONE");
	}

	@Test
	void update_nonExistent_throwsDiaryNotFound() {
		long userId = newUser();
		assertThatThrownBy(() -> diaryService.update(userId, -1L,
				new UpdateDiaryRequest(deltaOf("x"), "x", "PRIVATE")))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.DIARY_NOT_FOUND));
	}

	// ===== 삭제 =====

	@Test
	void delete_nonExistentOrOther_throwsDiaryNotFound() {
		long owner = newUser();
		long stranger = newUser();
		DiaryUpsertResult diary = diaryService.upsert(owner,
				new SaveDiaryRequest(deltaOf("내 일기"), "내 일기", LocalDate.of(2026, 6, 1), "PRIVATE"));

		// 없는 id
		assertThatThrownBy(() -> diaryService.delete(owner, -1L))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.DIARY_NOT_FOUND));
		// 타인 소유
		assertThatThrownBy(() -> diaryService.delete(stranger, diary.diary().id()))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.DIARY_NOT_FOUND));
	}

	// ===== 월 요약 =====

	@Test
	void getSummary_returnsActiveDatesInMonth() {
		long userId = newUser();
		LocalDate d1 = LocalDate.of(2026, 7, 3);
		LocalDate d2 = LocalDate.of(2026, 7, 20);
		LocalDate other = LocalDate.of(2026, 8, 1); // 다른 달
		LocalDate removed = LocalDate.of(2026, 7, 28); // 소프트삭제 대상

		diaryService.upsert(userId, new SaveDiaryRequest(deltaOf("a"), "a", d1, "PRIVATE"));
		diaryService.upsert(userId, new SaveDiaryRequest(deltaOf("b"), "b", d2, "PRIVATE"));
		diaryService.upsert(userId, new SaveDiaryRequest(deltaOf("c"), "c", other, "PRIVATE"));
		DiaryUpsertResult toRemove = diaryService.upsert(userId,
				new SaveDiaryRequest(deltaOf("d"), "d", removed, "PRIVATE"));
		diaryService.delete(userId, toRemove.diary().id()); // 요약에서 제외돼야 함

		DiarySummaryResponse summary = diaryService.getSummary(userId, "2026-07");

		assertThat(summary.yearMonth()).isEqualTo("2026-07");
		// 해당 월 활성 날짜만, 오름차순(소프트삭제·타월 제외)
		assertThat(summary.dates()).containsExactly("2026-07-03", "2026-07-20");
	}

	// ===== 인라인 이미지(content 단일 진실원) =====

	@Test
	void inlineImages_persistedInContentAndCountedInList() {
		long userId = newUser();
		List<String> urls = List.of(upload(userId), upload(userId), upload(userId));
		LocalDate date = LocalDate.of(2026, 9, 1);
		long diaryId = diaryService.upsert(userId,
				new SaveDiaryRequest(deltaWithImages("사진 일기", urls), "사진 일기", date, "PRIVATE"))
				.diary().id();

		// content(Delta)에 이미지 URL 이 등장 순서대로 임베드되고, 파일은 디스크에 존재한다
		String content = diaryService.getById(userId, diaryId).content();
		urls.forEach(u -> assertThat(content).contains(u));
		urls.forEach(u -> {
			assertThat(u).startsWith("/files/diaries/");
			assertThat(Files.exists(resolveStored(u))).isTrue();
		});

		// 목록은 content jsonb 파싱으로 대표 1장(첫 임베드)·총 장수를 산출한다
		DiaryListItem item = diaryService.getMonthList(userId, "2026-09").stream()
				.filter(it -> it.id() == diaryId).findFirst().orElseThrow();
		assertThat(item.imageCount()).isEqualTo(3);
		assertThat(item.thumbnailUrl()).isEqualTo(urls.get(0));
	}

	@Test
	void inlineImages_overLimit_throwsAndRollsBack() {
		long userId = newUser();
		LocalDate date = LocalDate.of(2026, 9, 2);
		List<String> urls = new ArrayList<>();
		for (int i = 0; i < DiaryConstraints.IMAGE_MAX_PER_DIARY + 1; i++) { // 6장
			urls.add(upload(userId));
		}

		// 한도 초과 → 트랜잭션 전체 롤백(일기 미생성)
		assertThatThrownBy(() -> diaryService.upsert(userId,
				new SaveDiaryRequest(deltaWithImages("한도", urls), "한도", date, "PRIVATE")))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.IMAGE_LIMIT_EXCEEDED));

		assertThatThrownBy(() -> diaryService.getByDate(userId, date))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.DIARY_NOT_FOUND));
	}

	@Test
	void uploadImage_nonImage_throwsInvalidFileAndStoresNothing() throws IOException {
		long userId = newUser();
		long before = diaryFileCount();

		assertThatThrownBy(() -> diaryService.uploadImage(userId, txtFile()))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.INVALID_FILE));

		assertThat(diaryFileCount()).as("비이미지는 저장되지 않아 고아 0").isEqualTo(before);
	}

	@Test
	void inlineImages_removingFromDelta_reclaimsFile() {
		long userId = newUser();
		String u1 = upload(userId);
		String u2 = upload(userId);
		long diaryId = diaryService.upsert(userId,
				new SaveDiaryRequest(deltaWithImages("두 장", List.of(u1, u2)), "두 장",
						LocalDate.of(2026, 9, 5), "PRIVATE")).diary().id();
		Path p1 = resolveStored(u1);
		Path p2 = resolveStored(u2);
		assertThat(Files.exists(p1)).isTrue();

		// u1 을 본문에서 제거 → update 가 빠진 파일을 afterCommit 회수, u2 는 보존
		diaryService.update(userId, diaryId,
				new UpdateDiaryRequest(deltaWithImages("두 장", List.of(u2)), "두 장", "PRIVATE"));

		String content = diaryService.getById(userId, diaryId).content();
		assertThat(content).contains(u2).doesNotContain(u1);
		assertThat(imageCountInContent(userId, diaryId)).isEqualTo(1);
		assertThat(Files.exists(p1)).as("제거된 이미지 파일은 회수").isFalse();
		assertThat(Files.exists(p2)).as("남은 이미지 파일은 보존").isTrue();
	}

	// ===== 일기 삭제 시 디스크 파일 동반 회수(afterCommit) =====

	@Test
	void delete_diaryAlsoRemovesDiskFiles() {
		long userId = newUser();
		String u1 = upload(userId);
		String u2 = upload(userId);
		long diaryId = diaryService.upsert(userId,
				new SaveDiaryRequest(deltaWithImages("동반 삭제", List.of(u1, u2)), "동반 삭제",
						LocalDate.of(2026, 9, 6), "PRIVATE")).diary().id();
		List<Path> diskPaths = List.of(resolveStored(u1), resolveStored(u2));
		diskPaths.forEach(p -> assertThat(Files.exists(p)).isTrue());

		diaryService.delete(userId, diaryId); // 커밋 후 afterCommit 에서 content 의 이미지 파일 회수

		// (a) content 에 임베드됐던 디스크 파일 전부 회수(고아 0)
		diskPaths.forEach(p -> assertThat(Files.exists(p))
				.as("일기 삭제 시 첨부 파일도 회수돼야 함").isFalse());
		// (b) 일기 본문은 소프트삭제(deleted_at NOT NULL)
		Timestamp deletedAt = jdbc().queryForObject(
				"SELECT deleted_at FROM diaries WHERE id = ?", Timestamp.class, diaryId);
		assertThat(deletedAt).isNotNull();
	}

	// ===== 목록 커서 페이징 =====

	@Test
	void getList_firstPage_returnsDescAndHasNext() {
		long userId = newUser();
		List<Long> ids = createDiaries(userId, 5); // 오름차순 생성 → id 증가
		List<Long> descAll = ids.reversed(); // 기대 정렬: 최신(가장 큰 id)부터

		PageResponse<DiaryListItem> page = diaryService.getList(userId, new CursorRequest(null, 2));

		assertThat(page.hasNext()).isTrue();
		assertThat(page.items()).extracting(DiaryListItem::id)
				.containsExactly(descAll.get(0), descAll.get(1)); // id DESC 상위 2건
		assertThat(page.nextCursor()).isEqualTo(descAll.get(1)); // 마지막 항목 id
	}

	@Test
	void getList_nextPage_continues() {
		long userId = newUser();
		List<Long> descAll = createDiaries(userId, 5).reversed();

		PageResponse<DiaryListItem> first = diaryService.getList(userId, new CursorRequest(null, 2));
		PageResponse<DiaryListItem> second =
				diaryService.getList(userId, new CursorRequest(first.nextCursor(), 2));

		// 첫 페이지[0,1] 다음으로 [2,3] 이 이어지고 중복 없음
		assertThat(second.items()).extracting(DiaryListItem::id)
				.containsExactly(descAll.get(2), descAll.get(3));
		assertThat(second.hasNext()).isTrue();
		assertThat(second.items()).extracting(DiaryListItem::id)
				.doesNotContainAnyElementsOf(first.items().stream().map(DiaryListItem::id).toList());
	}

	@Test
	void getList_lastPage_hasNextFalse() {
		long userId = newUser();
		List<Long> descAll = createDiaries(userId, 5).reversed();

		// 2,2 까지 소비하고 마지막 1건만 남은 페이지 조회
		Long afterFour = descAll.get(3); // 앞 4건의 마지막 id
		PageResponse<DiaryListItem> last = diaryService.getList(userId, new CursorRequest(afterFour, 2));

		assertThat(last.items()).extracting(DiaryListItem::id).containsExactly(descAll.get(4));
		assertThat(last.hasNext()).isFalse();
		assertThat(last.nextCursor()).isNull();
	}

	@Test
	void getList_size1_boundary() {
		long userId = newUser();
		List<Long> descAll = createDiaries(userId, 3).reversed();

		PageResponse<DiaryListItem> page = diaryService.getList(userId, new CursorRequest(null, 1));

		assertThat(page.items()).extracting(DiaryListItem::id).containsExactly(descAll.get(0));
		assertThat(page.hasNext()).isTrue();
		assertThat(page.nextCursor()).isEqualTo(descAll.get(0));
	}

	@Test
	void getList_empty_returnsEmpty() {
		long userId = newUser(); // 일기 0건

		PageResponse<DiaryListItem> page = diaryService.getList(userId, new CursorRequest(null, 20));

		assertThat(page.items()).isEmpty();
		assertThat(page.hasNext()).isFalse();
		assertThat(page.nextCursor()).isNull();
	}

	@Test
	void getList_excludesSoftDeleted() {
		long userId = newUser();
		List<Long> ids = createDiaries(userId, 3);
		diaryService.delete(userId, ids.get(1)); // 중간 1건 소프트 삭제

		PageResponse<DiaryListItem> page = diaryService.getList(userId, new CursorRequest(null, 20));

		assertThat(page.items()).extracting(DiaryListItem::id)
				.containsExactly(ids.get(2), ids.get(0)) // 삭제 행 제외, id DESC
				.doesNotContain(ids.get(1));
		assertThat(page.hasNext()).isFalse();
	}

	@Test
	void getList_includesThumbnailAndCountAndTextPreview() {
		long userId = newUser();
		List<Long> ids = createDiaries(userId, 2); // contentText: "일기 0", "일기 1"
		long withImages = ids.get(0);
		long withoutImages = ids.get(1);
		// withImages 본문에 인라인 이미지 2장 추가(순수 텍스트는 그대로 유지)
		List<String> urls = List.of(upload(userId), upload(userId));
		diaryService.update(userId, withImages,
				new UpdateDiaryRequest(deltaWithImages("일기 0", urls), "일기 0", "PRIVATE"));

		PageResponse<DiaryListItem> page = diaryService.getList(userId, new CursorRequest(null, 20));

		DiaryListItem hasImg = page.items().stream()
				.filter(it -> it.id() == withImages).findFirst().orElseThrow();
		DiaryListItem noImg = page.items().stream()
				.filter(it -> it.id() == withoutImages).findFirst().orElseThrow();

		// 목록 미리보기 텍스트는 순수 텍스트(content_text)다(Delta JSON 아님)
		assertThat(hasImg.content()).isEqualTo("일기 0");
		assertThat(noImg.content()).isEqualTo("일기 1");
		assertThat(hasImg.imageCount()).isEqualTo(2);
		assertThat(hasImg.thumbnailUrl()).isNotNull().startsWith("/files/diaries/");
		assertThat(noImg.imageCount()).isZero();
		assertThat(noImg.thumbnailUrl()).isNull();
	}

	// ===== 본문 길이 제약(content_text) =====

	@Test
	void contentText_over500_rejected() {
		long userId = newUser();
		String tooLong = "가".repeat(DiaryConstraints.CONTENT_MAX + 1); // 501자

		// 서비스 직접 호출 시 @Size(컨트롤러 계층) 미적용 → DB CHECK(chk_diaries_content_text_len, 23514)가
		// MyBatis 예외 변환을 통해 DataAccessException(DataIntegrityViolationException)으로 표출된다.
		assertThatThrownBy(() -> diaryService.upsert(userId,
				new SaveDiaryRequest(deltaOf("x"), tooLong, LocalDate.of(2026, 9, 7), "PRIVATE")))
				.isInstanceOf(DataAccessException.class);
	}
}
