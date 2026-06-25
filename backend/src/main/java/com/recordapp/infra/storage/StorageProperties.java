package com.recordapp.infra.storage;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/**
 * 파일 스토리지 설정(record.storage.*).
 *
 * @param root    파일을 저장할 로컬 디렉터리 루트(상대/절대 모두 허용, 내부에서 절대경로화).
 *                운영에서는 영속 볼륨 경로로 주입한다.
 * @param urlPath 정적 서빙 경로 prefix. 저장 파일은 {@code {urlPath}/{directory}/...}로 노출된다.
 */
@ConfigurationProperties(prefix = "record.storage")
public record StorageProperties(
		@DefaultValue("./var/storage") String root,
		@DefaultValue("/files") String urlPath) {
}
