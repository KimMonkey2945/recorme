package com.recordapp;

import com.recordapp.domain.character.config.CharacterCoinProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

// 코인 적립 기준값(record.character.coin.*)을 @ConfigurationProperties 로 바인딩한다.
// 값 조정·보상 추가/제거를 코드 변경 없이 application.yml 만으로 하기 위한 배선(docs/coin-rewards.md).
@SpringBootApplication
@ConfigurationPropertiesScan(basePackageClasses = CharacterCoinProperties.class)
public class RecordApplication {

	public static void main(String[] args) {
		SpringApplication.run(RecordApplication.class, args);
	}

}
