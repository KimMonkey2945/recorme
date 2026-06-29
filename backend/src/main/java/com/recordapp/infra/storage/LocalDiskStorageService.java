package com.recordapp.infra.storage;

import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.time.LocalDate;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

/**
 * 로컬 디스크 기반 {@link StorageService} 구현.
 *
 * <p>저장 경로: {@code {root}/{directory}/{yyyy}/{MM}/{uuid}.{ext}} — 연/월 분할로 단일 폴더 폭주 방지.
 * 파일명은 서버 생성 UUID이며 확장자는 매직바이트 탐지 결과에서 도출한다(클라이언트 파일명·Content-Type 미신뢰).
 *
 * <p>⚠️ 단일 인스턴스/단일 디스크 전제. 배포(컨테이너 ephemeral) 시 S3 구현으로 교체하거나 영속 볼륨을 마운트한다.
 */
@Service
public class LocalDiskStorageService implements StorageService {

	private static final Logger log = LoggerFactory.getLogger(LocalDiskStorageService.class);

	/** 허용 이미지 시그니처(매직바이트). 확장자는 탐지 결과에서만 부여한다. */
	private enum ImageType {
		JPEG("jpg"), PNG("png"), WEBP("webp");

		private final String ext;

		ImageType(String ext) {
			this.ext = ext;
		}
	}

	private final Path root;
	private final String urlPath;

	public LocalDiskStorageService(StorageProperties properties) {
		this.root = Paths.get(properties.root()).toAbsolutePath().normalize();
		// 트레일링 슬래시 제거(경로 조립 시 슬래시 중복 방지)
		String path = properties.urlPath();
		this.urlPath = path.endsWith("/") ? path.substring(0, path.length() - 1) : path;
	}

	@Override
	public String store(MultipartFile file, String directory) {
		if (file == null || file.isEmpty()) {
			throw new BusinessException(ErrorCode.INVALID_FILE, "빈 파일은 업로드할 수 없습니다.");
		}

		byte[] header = readHeader(file);
		ImageType type = detectImageType(header);
		if (type == null) {
			throw new BusinessException(ErrorCode.INVALID_FILE, "이미지 파일(jpg/png/webp)만 업로드할 수 있습니다.");
		}

		String filename = UUID.randomUUID() + "." + type.ext;
		LocalDate today = LocalDate.now();
		// 상대 경로 세그먼트(저장/URL 공통)
		String relativeDir = String.format("%s/%04d/%02d", directory, today.getYear(), today.getMonthValue());

		Path targetDir = root.resolve(relativeDir).normalize();
		// 2차 방어: directory에 ../ 등이 섞여도 루트 밖으로 못 나가게 한다.
		if (!targetDir.startsWith(root)) {
			throw new BusinessException(ErrorCode.INVALID_FILE, "잘못된 저장 경로입니다.");
		}
		Path target = targetDir.resolve(filename);

		try {
			Files.createDirectories(targetDir);
			try (InputStream in = file.getInputStream()) {
				Files.copy(in, target, StandardCopyOption.REPLACE_EXISTING);
			}
		} catch (IOException e) {
			log.error("파일 저장 실패: {}", target, e);
			throw new BusinessException(ErrorCode.INTERNAL_ERROR, "파일 저장에 실패했습니다.");
		}

		return urlPath + "/" + relativeDir + "/" + filename;
	}

	@Override
	public void deleteByUrl(String url) {
		// 외부 URL(http...)·null·이 스토리지 소유가 아닌 경로는 삭제하지 않는다.
		if (url == null || !url.startsWith(urlPath + "/")) {
			return;
		}
		String relative = url.substring(urlPath.length() + 1); // urlPath + "/" 제거
		Path target = root.resolve(relative).normalize();
		if (!target.startsWith(root)) {
			log.warn("스토리지 루트 밖 삭제 시도 무시: {}", url);
			return;
		}
		try {
			Files.deleteIfExists(target);
		} catch (IOException e) {
			// best-effort: 삭제 실패가 프로필 갱신을 막지 않도록 로깅만 한다.
			log.warn("구 파일 삭제 실패(무시): {}", target, e);
		}
	}

	@Override
	public java.util.Optional<LoadedImage> loadByUrl(String url) {
		// deleteByUrl과 동일한 소유/루트 검증으로 외부 URL·null·루트 밖을 차단한다.
		if (url == null || !url.startsWith(urlPath + "/")) {
			return java.util.Optional.empty();
		}
		String relative = url.substring(urlPath.length() + 1); // urlPath + "/" 제거
		Path target = root.resolve(relative).normalize();
		if (!target.startsWith(root)) {
			log.warn("스토리지 루트 밖 읽기 시도 무시: {}", url);
			return java.util.Optional.empty();
		}
		String mediaType = mediaTypeOf(relative);
		if (mediaType == null || !Files.exists(target)) {
			return java.util.Optional.empty();
		}
		try {
			byte[] data = Files.readAllBytes(target);
			return java.util.Optional.of(new LoadedImage(data, mediaType));
		} catch (IOException e) {
			log.warn("이미지 읽기 실패(무시): {}", target, e);
			return java.util.Optional.empty();
		}
	}

	/** 확장자로 MIME 도출. 미지원 확장자는 null. */
	private String mediaTypeOf(String path) {
		int dot = path.lastIndexOf('.');
		if (dot < 0) {
			return null;
		}
		return switch (path.substring(dot + 1).toLowerCase()) {
			case "jpg", "jpeg" -> "image/jpeg";
			case "png" -> "image/png";
			case "webp" -> "image/webp";
			default -> null;
		};
	}

	/** 앞부분 12바이트만 읽어 시그니처 판별에 사용. */
	private byte[] readHeader(MultipartFile file) {
		try (InputStream in = file.getInputStream()) {
			return in.readNBytes(12);
		} catch (IOException e) {
			throw new BusinessException(ErrorCode.INVALID_FILE, "파일을 읽을 수 없습니다.");
		}
	}

	/** 매직바이트로 이미지 종류 판별. 미지원이면 null. */
	private ImageType detectImageType(byte[] b) {
		if (b.length >= 3 && (b[0] & 0xFF) == 0xFF && (b[1] & 0xFF) == 0xD8 && (b[2] & 0xFF) == 0xFF) {
			return ImageType.JPEG;
		}
		if (b.length >= 8 && (b[0] & 0xFF) == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G'
				&& (b[4] & 0xFF) == 0x0D && (b[5] & 0xFF) == 0x0A && (b[6] & 0xFF) == 0x1A && (b[7] & 0xFF) == 0x0A) {
			return ImageType.PNG;
		}
		if (b.length >= 12 && b[0] == 'R' && b[1] == 'I' && b[2] == 'F' && b[3] == 'F'
				&& b[8] == 'W' && b[9] == 'E' && b[10] == 'B' && b[11] == 'P') {
			return ImageType.WEBP;
		}
		return null;
	}
}
