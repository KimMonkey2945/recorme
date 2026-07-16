package com.recordapp.domain.character;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.recordapp.domain.character.controller.RetrospectController;
import com.recordapp.domain.character.dto.RetrospectResponse;
import com.recordapp.domain.character.service.RetrospectService;
import com.recordapp.global.exception.BusinessException;
import com.recordapp.global.exception.ErrorCode;
import com.recordapp.global.security.SecurityUser;
import java.time.YearMonth;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.Test;

/**
 * RetrospectController 의 yearMonth 파싱 단위 테스트(웹 계층 없이 직접 호출).
 * 형식이 잘못되면 400 VALIDATION_ERROR, 올바르면 파싱된 YearMonth 로 서비스에 위임한다.
 */
class RetrospectControllerTest {

	private static final SecurityUser PRINCIPAL = new SecurityUser(1L, "sub-uuid");

	@Test
	void 잘못된_yearMonth_형식은_400_VALIDATION_ERROR() {
		RetrospectController controller = new RetrospectController(failingService());

		assertThatThrownBy(() -> controller.getRetrospect(PRINCIPAL, "2026/07"))
				.isInstanceOf(BusinessException.class)
				.satisfies(e -> assertThat(((BusinessException) e).getErrorCode())
						.isEqualTo(ErrorCode.VALIDATION_ERROR));

		assertThatThrownBy(() -> controller.getRetrospect(PRINCIPAL, "not-a-month"))
				.isInstanceOf(BusinessException.class);
	}

	@Test
	void 올바른_yearMonth_는_파싱돼_서비스로_위임된다() {
		AtomicReference<YearMonth> captured = new AtomicReference<>();
		RetrospectService service = new RetrospectService(null, null, null) {
			@Override
			public RetrospectResponse getRetrospect(long userId, YearMonth yearMonth) {
				captured.set(yearMonth);
				return new RetrospectResponse(yearMonth.toString(), 0, 0, 0, List.of(), 0, List.of());
			}
		};
		RetrospectController controller = new RetrospectController(service);

		controller.getRetrospect(PRINCIPAL, "2026-07");

		assertThat(captured.get()).isEqualTo(YearMonth.of(2026, 7));
	}

	/** 형식 오류 경로에선 서비스가 호출되지 않아야 한다(호출되면 테스트 실패). */
	private RetrospectService failingService() {
		return new RetrospectService(null, null, null) {
			@Override
			public RetrospectResponse getRetrospect(long userId, YearMonth yearMonth) {
				throw new AssertionError("형식 오류 시 서비스가 호출되면 안 됨");
			}
		};
	}
}
