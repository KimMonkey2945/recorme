package com.recordapp.infra.storage;

import org.springframework.web.multipart.MultipartFile;

/**
 * 파일 저장 추상화. 외부 IO를 격리해 구현체(로컬 디스크 → S3 등)를 교체할 수 있게 한다.
 * (음악 {@code MusicSource}·LLM {@code LlmClient}와 동일한 인프라 격리 패턴.)
 *
 * <p>DB에는 바이너리가 아니라 이 인터페이스가 반환하는 <b>접근 경로(상대 URL)</b>만 저장한다.
 * 호스트/CDN 도메인은 클라이언트(또는 직렬화 계층)가 조립하므로 구현체는 호스트를 포함하지 않는다.
 */
public interface StorageService {

	/**
	 * 이미지 파일을 검증 후 저장하고 접근용 <b>상대 경로</b>를 반환한다.
	 * 파일명은 서버가 UUID로 생성하므로 클라이언트 파일명은 사용하지 않는다(경로 탐색 차단).
	 *
	 * @param file      업로드 파일(비어 있으면 안 됨)
	 * @param directory 논리 구분 디렉터리(예: "avatars")
	 * @return 상대 경로(예: {@code /files/avatars/2026/06/{uuid}.png})
	 * @throws com.recordapp.global.exception.BusinessException 검증 실패(INVALID_FILE) 또는 저장 실패(INTERNAL_ERROR)
	 */
	String store(MultipartFile file, String directory);

	/**
	 * 이 스토리지가 관리하는 경로일 때만 파일을 삭제한다. 외부 URL(http...)이나 null은 no-op.
	 * best-effort — 삭제 실패는 예외를 던지지 않고 로깅만 한다(프로필 갱신을 막지 않기 위함).
	 *
	 * @param url 삭제할 접근 경로(store가 반환했던 상대 경로)
	 */
	void deleteByUrl(String url);

	/**
	 * 이 스토리지가 관리하는 경로의 이미지를 원본 bytes로 읽어온다.
	 * 외부 URL(http...)·null·루트 밖 경로·미지원 확장자·미존재 파일은 {@code Optional.empty()}.
	 * 다운스케일은 하지 않는다(원본 그대로 — 다운스케일은 호출자 책임).
	 *
	 * @param url 읽을 접근 경로(store가 반환했던 상대 경로)
	 * @return 이미지 bytes + MIME, 읽을 수 없으면 empty
	 */
	java.util.Optional<LoadedImage> loadByUrl(String url);
}
