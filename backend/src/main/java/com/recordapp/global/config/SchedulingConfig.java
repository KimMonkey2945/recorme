package com.recordapp.global.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * 스케줄링 활성화. 감정 분석 백스톱 폴러({@code EmotionAnalysisPoller})의 @Scheduled 를 구동한다.
 * (비동기 실행은 {@link AsyncConfig} 의 @EnableAsync 가 담당 — 관심사 분리.)
 */
@Configuration
@EnableScheduling
public class SchedulingConfig {
}
