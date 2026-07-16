package com.recordapp.domain.character;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.recordapp.domain.auth.service.UserProvisioningService;
import com.recordapp.domain.character.service.CharacterRewardService;
import com.recordapp.domain.character.service.CharacterService;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.global.security.SupabaseClaims;
import java.util.Map;
import java.util.UUID;
import javax.sql.DataSource;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 상점 구매 게이팅(FEATURE_DISABLED) 검증 — {@code record.character.coin.coin-enabled=false} 로 오버라이드한
 * 별도 컨텍스트. 운영 기본은 on 이라 이 케이스만 프로퍼티를 뒤집어 확인한다. 적립은 게이팅과 무관하다.
 */
@SpringBootTest
@Testcontainers
@ActiveProfiles("test")
@TestPropertySource(properties = "record.character.coin.coin-enabled=false")
class CharacterPurchaseDisabledTest {

	@Container
	@ServiceConnection
	static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");

	@Autowired
	CharacterRewardService rewardService;

	@Autowired
	CharacterService characterService;

	@Autowired
	UserProvisioningService provisioningService;

	@Autowired
	DataSource dataSource;

	@Test
	void purchase_whenCoinDisabled_throwsFeatureDisabled_andBalanceUnchanged() {
		String sub = UUID.randomUUID().toString();
		long userId = provisioningService.provision(
				new SupabaseClaims(sub, sub + "@example.com", Map.of("name", "t"), Map.of("sub", sub)))
				.userId();
		characterService.ensureState(userId);
		new JdbcTemplate(dataSource).update("UPDATE user_wallets SET balance = 100 WHERE user_id = ?", userId);

		assertThatThrownBy(() -> rewardService.purchase(userId, "HAT_CAP_BLACK"))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.FEATURE_DISABLED));

		Integer balance = new JdbcTemplate(dataSource).queryForObject(
				"SELECT balance FROM user_wallets WHERE user_id = ?", Integer.class, userId);
		assertThat(balance).as("게이팅 차단 → 차감 없음").isEqualTo(100);
	}
}
