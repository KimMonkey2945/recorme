package com.recordapp.infra.push;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 서버 푸시 설정(record.push.*).
 *
 * <p>자격증명은 환경변수(FCM_CREDENTIALS)로만 주입한다(코드·git 금지). firebaseCredentials가 비어 있으면
 * {@code PushConfig}가 자동으로 {@link StubPushService}를 선택해 로컬/CI 무키 동작을 보장한다.
 *
 * @param firebaseCredentials 서비스 계정 JSON 파일 경로 또는 Base64 인코딩된 JSON 문자열(비어 있을 수 있음)
 */
@ConfigurationProperties(prefix = "record.push")
public record PushProperties(String firebaseCredentials) {
}
