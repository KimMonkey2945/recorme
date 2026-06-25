package com.recordapp;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.test.context.ActiveProfiles;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 애플리케이션 컨텍스트가 Testcontainers PostgreSQL 위에서 정상 기동하는지 검증한다.
 * datasource + Flyway 마이그레이션 + MyBatis + Security 와이어링 전체를 확인한다.
 * (test 프로파일: 로컬 datasource를 비우고 @ServiceConnection으로 컨테이너 연결 주입)
 */
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
class RecordApplicationTests {

	@Container
	@ServiceConnection
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

	@Test
	void contextLoads() {
		// 컨텍스트 로드 + Flyway 마이그레이션 성공 자체가 검증 목적
	}
}
