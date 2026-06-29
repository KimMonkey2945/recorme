package com.recordapp;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.recordapp.domain.auth.service.UserProvisioningService;
import com.recordapp.domain.diary.dto.DiaryListItem;
import com.recordapp.domain.diary.dto.DiaryResponse;
import com.recordapp.domain.diary.dto.DiaryUpsertResult;
import com.recordapp.domain.diary.dto.SaveDiaryRequest;
import com.recordapp.domain.diary.dto.UpdateDiaryRequest;
import com.recordapp.domain.diary.service.DiaryService;
import com.recordapp.global.common.CursorRequest;
import com.recordapp.global.common.PageResponse;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.global.security.SupabaseClaims;
import com.recordapp.infra.storage.StorageProperties;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import javax.sql.DataSource;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * auth·diary 도메인 횡단 통합 시나리오 테스트(Testcontainers PostgreSQL 18).
 *
 * <p>단위 성격의 {@code DiaryServiceTest}/{@code UserServiceTest}가 서비스별 분기를 검증한다면,
 * 본 테스트는 <b>JIT 프로비저닝 → 일기 CRUD → 인라인 이미지 → 커서 페이징 → 삭제·재작성</b>으로
 * 이어지는 사용자 여정 전체를 한 흐름으로 묶어, 도메인 간 경계(소유권/IDOR, 프로비저닝 멱등성)가
 * 실제 DB·디스크에서 일관되게 동작하는지를 검증한다. 본문은 리치 텍스트(Quill Delta JSON)이며
 * 인라인 이미지를 직접 임베드한다(content 가 단일 진실원). 이미지는 업로드 URL 을 본문 Delta 에 끼워 넣고 저장한다.
 *
 * <p>⚠️ 클래스/메서드에 {@code @Transactional}을 두지 않는다(DiaryServiceTest·UserServiceTest 동일).
 * delete()/update 의 디스크 파일 회수는 afterCommit 동기화로 동작하므로, 테스트가 트랜잭션으로
 * 감싸지면 커밋이 일어나지 않아 afterCommit 콜백이 호출되지 않는다.
 */
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class DiaryIntegrationTest {

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

	// ===== 헬퍼(DiaryServiceTest 와 동일 패턴) =====

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

	/** 인라인 이미지 1장 업로드 후 접근 URL 반환. */
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

	/** 등록(미확정·DRAFT) 저장 요청 — confirm=false. 등록된 일기는 수정 가능·미분석 상태로 출발한다. */
	private SaveDiaryRequest register(String content, String text, LocalDate date, String visibility) {
		return new SaveDiaryRequest(content, text, date, visibility, false);
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

	/** content(Delta)에 임베드된 인라인 이미지 개수(jsonb 파싱). */
	private int imageCountInContent(long userId, long diaryId) {
		String content = diaryService.getById(userId, diaryId).content();
		Integer n = jdbc().queryForObject(
				"SELECT count(*)::int FROM jsonb_array_elements(?::jsonb -> 'ops') AS op "
						+ "WHERE op->'insert'->>'image' IS NOT NULL",
				Integer.class, content);
		return n == null ? 0 : n;
	}

	private int userRowCount(String supabaseUid) {
		Integer n = jdbc().queryForObject(
				"SELECT count(*) FROM users WHERE supabase_uid = ?", Integer.class, supabaseUid);
		return n == null ? 0 : n;
	}

	// ===== 1) 전체 여정: 프로비저닝 → CRUD → 인라인 이미지 → 페이징 → 삭제·재작성 =====

	@Test
	void fullJourney_provisionToDiaryCrudToImagesToPaging() {
		// --- (a) JIT 프로비저닝: 신규 supabase_uid 최초 요청 시 users 1행 자동 생성 ---
		String sub = UUID.randomUUID().toString();
		long userId = provision(sub, "journey@example.com", Map.of("name", "여정"));
		assertThat(userRowCount(sub)).as("JIT 가입으로 users 1행 생성").isEqualTo(1);

		// --- (b) 일기 작성(신규) → PK·날짜 두 경로로 조회 ---
		LocalDate day = LocalDate.of(2026, 1, 10);
		DiaryUpsertResult created = diaryService.upsert(userId,
				register(deltaOf("오늘의 기록"), "오늘의 기록", day, "PRIVATE"));
		assertThat(created.inserted()).as("최초 작성은 INSERT").isTrue();
		long diaryId = created.diary().id();

		assertThat(diaryService.getById(userId, diaryId).contentText()).isEqualTo("오늘의 기록");
		assertThat(diaryService.getByDate(userId, day).id()).isEqualTo(diaryId);
		// 등록(confirm 없음)이므로 저장 직후 상태는 DRAFT(미확정·미분석). 이후 수정이 가능하다.
		assertThat(created.diary().analysisStatus()).isEqualTo("DRAFT");

		// --- (c) 본문 수정 반영 ---
		DiaryResponse updated = diaryService.update(userId, diaryId,
				new UpdateDiaryRequest(deltaOf("내용을 고쳐 적었다"), "내용을 고쳐 적었다", "PRIVATE"));
		assertThat(updated.contentText()).isEqualTo("내용을 고쳐 적었다");
		assertThat(diaryService.getById(userId, diaryId).contentText()).isEqualTo("내용을 고쳐 적었다");

		// --- (d) 인라인 이미지 2장(업로드 → 본문 Delta 에 삽입 → 저장) ---
		String u1 = upload(userId);
		String u2 = upload(userId);
		DiaryResponse withImages = diaryService.update(userId, diaryId,
				new UpdateDiaryRequest(deltaWithImages("내용을 고쳐 적었다", List.of(u1, u2)),
						"내용을 고쳐 적었다", "PRIVATE"));
		assertThat(withImages.content()).contains(u1).contains(u2); // content 에 임베드
		assertThat(Files.exists(resolveStored(u1))).isTrue();
		assertThat(Files.exists(resolveStored(u2))).isTrue();
		assertThat(imageCountInContent(userId, diaryId)).isEqualTo(2);

		// --- (e) 본문에서 1장 제거 → content 1장, 해당 디스크 파일만 회수 ---
		Path removedPath = resolveStored(u1);
		Path keptPath = resolveStored(u2);
		diaryService.update(userId, diaryId,
				new UpdateDiaryRequest(deltaWithImages("내용을 고쳐 적었다", List.of(u2)),
						"내용을 고쳐 적었다", "PRIVATE"));

		String afterRemoval = diaryService.getById(userId, diaryId).content();
		assertThat(afterRemoval).contains(u2).doesNotContain(u1);
		assertThat(imageCountInContent(userId, diaryId)).isEqualTo(1);
		assertThat(Files.exists(removedPath)).as("제거한 사진 파일 회수").isFalse();
		assertThat(Files.exists(keptPath)).as("남은 사진 파일 유지").isTrue();

		// --- (f) 여러 날짜 일기 생성 → 커서 페이징(첫/다음 페이지 연속, hasNext) ---
		// 기존 1건(day) + 추가 4건 = 총 5건. 작성일을 다르게 하여 하루 1기록 제약 회피.
		LocalDate base = LocalDate.of(2026, 2, 1);
		for (int i = 0; i < 4; i++) {
			diaryService.upsert(userId,
					register(deltaOf("추가 " + i), "추가 " + i, base.plusDays(i), "PRIVATE"));
		}

		PageResponse<DiaryListItem> first = diaryService.getList(userId, new CursorRequest(null, 2));
		assertThat(first.items()).hasSize(2);
		assertThat(first.hasNext()).isTrue();
		assertThat(first.nextCursor()).isNotNull();

		PageResponse<DiaryListItem> second =
				diaryService.getList(userId, new CursorRequest(first.nextCursor(), 2));
		assertThat(second.items()).hasSize(2);
		// 페이지 간 중복 없음(커서 경계가 id < nextCursor 로 이어짐)
		assertThat(second.items()).extracting(DiaryListItem::id)
				.doesNotContainAnyElementsOf(first.items().stream().map(DiaryListItem::id).toList());
		assertThat(second.hasNext()).as("5건 중 4건 소비 → 1건 남음").isTrue();

		// --- (g) 일기 삭제 → 부재화 + 남은 사진 디스크 회수 + 같은 날짜 재작성 허용 ---
		diaryService.delete(userId, diaryId);

		assertThatThrownBy(() -> diaryService.getById(userId, diaryId))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.DIARY_NOT_FOUND));
		assertThat(Files.exists(keptPath)).as("일기 삭제 시 남은 사진 파일도 회수").isFalse();

		// 소프트삭제이므로 같은 날짜 재작성은 새 INSERT 로 허용된다(부분 유니크에서 제외)
		DiaryUpsertResult rewritten = diaryService.upsert(userId,
				register(deltaOf("같은 날 다시 적기"), "같은 날 다시 적기", day, "PRIVATE"));
		assertThat(rewritten.inserted()).isTrue();
		assertThat(rewritten.diary().id()).isNotEqualTo(diaryId);
		assertThat(diaryService.getByDate(userId, day).contentText()).isEqualTo("같은 날 다시 적기");
	}

	// ===== 2) 소유권/IDOR: 타인 일기에 대한 모든 접근 차단 =====

	@Test
	void authz_otherUserCannotAccess() {
		long owner = newUser();
		long other = newUser();
		long diaryId = diaryService.upsert(owner,
				register(deltaOf("A의 비밀"), "A의 비밀", LocalDate.of(2026, 3, 1), "PRIVATE"))
				.diary().id();

		// 소유권은 userId 로만 식별 → 타인 PK 접근은 모두 부재와 동일하게 차단(IDOR)
		assertThatThrownBy(() -> diaryService.getById(other, diaryId))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.DIARY_NOT_FOUND));
		assertThatThrownBy(() -> diaryService.update(other, diaryId,
				new UpdateDiaryRequest(deltaOf("탈취 시도"), "탈취 시도", "PRIVATE")))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.DIARY_NOT_FOUND));
		assertThatThrownBy(() -> diaryService.delete(other, diaryId))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.DIARY_NOT_FOUND));

		// 차단 후에도 소유자 데이터는 온전해야 한다
		assertThat(diaryService.getById(owner, diaryId).contentText()).isEqualTo("A의 비밀");
	}

	// ===== 3) 프로비저닝 멱등성: 같은 supabase_uid 재요청은 중복 가입 없음 =====

	@Test
	void provisioning_sameSupabaseUid_idempotent() {
		String sub = UUID.randomUUID().toString();

		long firstId = provision(sub, "dup@example.com", Map.of("name", "최초"));
		// 같은 uid 로 재요청(닉네임이 달라도 기존 매핑을 그대로 반환해야 함)
		long secondId = provision(sub, "dup@example.com", Map.of("name", "재요청"));

		assertThat(secondId).as("동일 uid 는 동일 내부 userId 반환").isEqualTo(firstId);
		assertThat(userRowCount(sub)).as("JIT 중복 가입 없이 users 1행 유지").isEqualTo(1);
	}

	// ===== 4) 인라인 이미지 한도: Delta 의 이미지 개수가 한도를 넘으면 차단(롤백) =====

	@Test
	void imageLimit_enforcedOnSave() {
		long userId = newUser();
		LocalDate date = LocalDate.of(2026, 4, 1);
		List<String> five = new ArrayList<>();
		for (int i = 0; i < 5; i++) {
			five.add(upload(userId));
		}

		// 1차로 5장(한도)까지 채운다
		long diaryId = diaryService.upsert(userId,
				register(deltaWithImages("사진 한도", five), "사진 한도", date, "PRIVATE"))
				.diary().id();
		assertThat(imageCountInContent(userId, diaryId)).isEqualTo(5);

		// 6장 Delta 로 수정 시도 → 한도 초과(저장 전 검증, DB 변경 전 롤백)
		List<String> six = new ArrayList<>(five);
		six.add(upload(userId));
		assertThatThrownBy(() -> diaryService.update(userId, diaryId,
				new UpdateDiaryRequest(deltaWithImages("사진 한도", six), "사진 한도", "PRIVATE")))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.IMAGE_LIMIT_EXCEEDED));
		assertThat(imageCountInContent(userId, diaryId)).as("한도 초과 요청은 기존 5장 유지(롤백)").isEqualTo(5);
	}
}
