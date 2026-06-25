package com.recordapp.global.config;

import com.recordapp.infra.storage.StorageProperties;
import java.nio.file.Path;
import java.nio.file.Paths;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * 업로드 파일 정적 서빙 설정. 저장 루트({@code record.storage.root})를 {@code {urlPath}/**}로 노출한다.
 *
 * <p>주의: 컨텍스트 경로(/api/v1)가 핸들러 패턴에도 자동 prefix되어 외부 접근 URL은
 * {@code /api/v1/files/...}가 된다. DB에는 호스트·컨텍스트 없는 상대 경로(/files/...)만 저장하고,
 * 클라이언트가 {@code apiBaseUrl + 상대경로}로 절대 URL을 조립한다.
 * GET 공개 여부는 {@code SecurityConfig}에서 {@code /files/**} permitAll로 허용한다.
 */
@Configuration
@EnableConfigurationProperties(StorageProperties.class)
public class WebMvcConfig implements WebMvcConfigurer {

	private final String urlPath;
	private final String location;

	public WebMvcConfig(StorageProperties properties) {
		String path = properties.urlPath();
		this.urlPath = path.endsWith("/") ? path.substring(0, path.length() - 1) : path;
		Path root = Paths.get(properties.root()).toAbsolutePath().normalize();
		// addResourceLocations는 디렉터리 표기(트레일링 슬래시) 필수. Path.toUri()는 디렉터리가
		// 아직 없으면(지연 생성) 슬래시를 붙이지 않으므로(특히 Linux) 직접 보장한다.
		String uri = root.toUri().toString();
		this.location = uri.endsWith("/") ? uri : uri + "/";
	}

	@Override
	public void addResourceHandlers(ResourceHandlerRegistry registry) {
		registry.addResourceHandler(urlPath + "/**")
				.addResourceLocations(location);
	}
}
