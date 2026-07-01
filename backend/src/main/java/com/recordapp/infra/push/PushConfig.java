package com.recordapp.infra.push;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.FirebaseMessaging;
import java.io.ByteArrayInputStream;
import java.io.FileInputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Base64;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * 푸시 발송 빈 선택. LLM {@code LlmConfig}의 무키 폴백 패턴을 복제한다 —
 * 자격증명이 없거나 초기화에 실패하면 {@link StubPushService}로 폴백해 로컬/CI 무영향을 보장한다.
 *
 * <p>{@code FirebaseMessaging} 빈은 만들지 않는다({@link FcmPushService} 내부에서만 참조).
 * FirebaseApp 초기화는 {@code FirebaseApp.getApps().isEmpty()} 가드로 중복 초기화를 방지한다.
 */
@Configuration
@EnableConfigurationProperties(PushProperties.class)
public class PushConfig {

	private static final Logger log = LoggerFactory.getLogger(PushConfig.class);

	/** FirebaseApp 인스턴스 이름 — 중복 초기화 가드/조회에 사용. */
	private static final String APP_NAME = "record-push";

	@Bean
	PushService pushService(PushProperties props) {
		String credentials = props.firebaseCredentials();
		if (credentials == null || credentials.isBlank()) {
			log.info("Push service = Stub (firebase-credentials absent)");
			return new StubPushService();
		}

		try {
			FirebaseApp app = firebaseApp(credentials.trim());
			log.info("Push service = FCM (app={})", app.getName());
			return new FcmPushService(FirebaseMessaging.getInstance(app));
		} catch (Exception e) {
			// 초기화 실패를 삼키지 않고 로그로 남긴 뒤 Stub로 폴백한다(로컬 안전·기동 보장).
			log.warn("Push service = Stub (FCM 초기화 실패로 폴백)", e);
			return new StubPushService();
		}
	}

	/** 중복 초기화를 피하며 명명된 FirebaseApp을 확보한다(이미 있으면 재사용). */
	private FirebaseApp firebaseApp(String credentials) throws Exception {
		for (FirebaseApp existing : FirebaseApp.getApps()) {
			if (APP_NAME.equals(existing.getName())) {
				return existing;
			}
		}
		try (InputStream in = openCredentials(credentials)) {
			FirebaseOptions options = FirebaseOptions.builder()
					.setCredentials(GoogleCredentials.fromStream(in))
					.build();
			return FirebaseApp.initializeApp(options, APP_NAME);
		}
	}

	/**
	 * 자격증명 소스를 연다. 실제 파일 경로면 {@link FileInputStream}, 아니면 Base64 JSON 으로 보고 디코드한다.
	 * 두 형식 모두 배포 환경(경로 마운트 / 시크릿 변수)에서 흔히 쓰인다.
	 */
	private InputStream openCredentials(String credentials) throws Exception {
		Path path = Path.of(credentials);
		if (Files.isRegularFile(path)) {
			return new FileInputStream(path.toFile());
		}
		byte[] decoded = Base64.getDecoder().decode(credentials.getBytes(StandardCharsets.UTF_8));
		return new ByteArrayInputStream(decoded);
	}
}
