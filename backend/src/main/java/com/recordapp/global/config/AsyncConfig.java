package com.recordapp.global.config;

import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.concurrent.Executor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.aop.interceptor.AsyncUncaughtExceptionHandler;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.AsyncConfigurer;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

/**
 * 비동기 인프라. 감정 분석(LLM 호출)은 트랜잭션 밖에서 별도 스레드풀로 수행한다.
 *
 * <p>void {@code @Async} 메서드의 예외는 호출자에게 전파되지 않으므로
 * {@link #getAsyncUncaughtExceptionHandler()}로 반드시 로깅한다(유실 방지).
 */
@Configuration
@EnableAsync
public class AsyncConfig implements AsyncConfigurer {

	private static final Logger log = LoggerFactory.getLogger(AsyncConfig.class);

	/**
	 * 감정 분석 전용 스레드풀.
	 * 큐가 가득 차면 {@code CallerRunsPolicy}로 제출 스레드가 직접 실행해 백프레셔를 건다
	 * (작업 유실 대신 처리량을 자연스럽게 조절).
	 */
	@Bean("emotionAnalysisExecutor")
	public Executor emotionAnalysisExecutor() {
		ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
		executor.setCorePoolSize(2);
		executor.setMaxPoolSize(4);
		executor.setQueueCapacity(100);
		executor.setThreadNamePrefix("emotion-");
		executor.setRejectedExecutionHandler(
				new java.util.concurrent.ThreadPoolExecutor.CallerRunsPolicy());
		executor.initialize();
		return executor;
	}

	/**
	 * 작심삼일 푸시 발송 전용 스레드풀. 성공 훅(afterCommit)·실패 배치·리마인더 스케줄러의 FCM 발송을
	 * 트랜잭션·요청 스레드·스케줄러 드레인 루프 밖에서 처리한다. 큐가 차면 {@code CallerRunsPolicy} 로
	 * 제출 스레드가 직접 실행해 백프레셔를 건다(발송 유실 대신 처리량 조절).
	 */
	@Bean("pushExecutor")
	public Executor pushExecutor() {
		ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
		executor.setCorePoolSize(2);
		executor.setMaxPoolSize(4);
		executor.setQueueCapacity(100);
		executor.setThreadNamePrefix("push-");
		executor.setRejectedExecutionHandler(
				new java.util.concurrent.ThreadPoolExecutor.CallerRunsPolicy());
		executor.initialize();
		return executor;
	}

	@Override
	public AsyncUncaughtExceptionHandler getAsyncUncaughtExceptionHandler() {
		return new LoggingAsyncUncaughtExceptionHandler();
	}

	/** void @Async 예외를 삼키지 않고 메서드·인자와 함께 로깅한다. */
	private static final class LoggingAsyncUncaughtExceptionHandler implements AsyncUncaughtExceptionHandler {
		@Override
		public void handleUncaughtException(Throwable ex, Method method, Object... params) {
			log.error("비동기 작업 실패: {}#{} args={}",
					method.getDeclaringClass().getSimpleName(), method.getName(), Arrays.toString(params), ex);
		}
	}
}
