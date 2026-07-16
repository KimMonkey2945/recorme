package com.recordapp.domain.character;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

/**
 * 단방향 아키텍처 정적 검증 — diary·resolution 도메인은 character(보상) 도메인을 <b>import 하지 않는다</b>.
 *
 * <p>보상 결합은 오직 {@code global/event} 의 이벤트 클래스를 통해서만 이뤄진다
 * ({@code DiaryService}/{@code ResolutionService} → publish, character 리스너 → 구독).
 * 두 서비스가 {@code com.recordapp.domain.character} 를 직접 참조하면 단방향이 깨진 것이므로 실패시킨다.
 * (imports 는 런타임에 지워져 리플렉션으로 못 보므로 소스 파일을 직접 스캔한다 — 모듈 루트 상대경로.)
 */
class OneWayDependencyTest {

	private static final String SRC = "src/main/java/com/recordapp/domain/";

	@Test
	void diaryServiceDoesNotImportCharacter() throws IOException {
		assertNoCharacterImport(SRC + "diary/service/DiaryService.java");
	}

	@Test
	void resolutionServiceDoesNotImportCharacter() throws IOException {
		assertNoCharacterImport(SRC + "resolution/service/ResolutionService.java");
	}

	private void assertNoCharacterImport(String relativePath) throws IOException {
		Path path = Path.of(relativePath);
		assertThat(Files.exists(path)).as("소스 파일 존재: " + relativePath).isTrue();
		String source = Files.readString(path);
		assertThat(source)
				.as(relativePath + " 는 character 도메인을 import 하면 안 된다(단방향 — 이벤트로만 결합)")
				.doesNotContain("import com.recordapp.domain.character");
	}
}
