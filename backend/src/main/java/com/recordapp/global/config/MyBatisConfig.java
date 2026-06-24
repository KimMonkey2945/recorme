package com.recordapp.global.config;

import org.mybatis.spring.annotation.MapperScan;
import org.springframework.context.annotation.Configuration;

/**
 * MyBatis 매퍼 스캔 설정.
 * snake_case → camelCase 매핑은 application.yml(mybatis.configuration.map-underscore-to-camel-case)에서 활성화.
 * 도메인별 mapper 인터페이스(@Mapper)는 com.recordapp.domain.*.mapper 패키지에서 스캔한다.
 */
@Configuration
@MapperScan("com.recordapp.domain.**.mapper")
public class MyBatisConfig {
}
