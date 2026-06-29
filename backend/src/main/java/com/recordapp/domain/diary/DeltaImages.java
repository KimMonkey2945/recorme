package com.recordapp.domain.diary;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Quill Delta 본문(JSON)에서 인라인 이미지 URL 을 추출하는 공용 유틸.
 *
 * <p>기록 본문(content)이 이미지의 단일 진실 공급원이라 여러 곳에서 같은 추출이 필요하다
 * (파일 회수: {@code DiaryService}, 감정 분석용 이미지 준비: {@code DiaryImagePreparer}).
 * 중복을 막기 위해 추출 규칙을 이 한 곳으로 모은다 — 동작은 기존 DiaryService 로직과 동일하다.
 */
public final class DeltaImages {

	private static final Logger log = LoggerFactory.getLogger(DeltaImages.class);

	private DeltaImages() {
	}

	/**
	 * 본문 Delta(JSON 문자열)에서 인라인 이미지 URL 을 등장 순서대로 추출한다(중복 제거, 순서 보존).
	 * Quill Delta 의 {@code ops[].insert.image}(문자열 URL)만 대상으로 한다.
	 * <p>파싱 실패/형식 불일치는 빈 목록으로 견고하게 처리한다 — 본문 저장/분석 자체를 막지 않기 위함이다.
	 *
	 * @param objectMapper Jackson 매퍼
	 * @param deltaJson    Quill Delta JSON 문자열(null/blank 허용)
	 * @return 이미지 URL 목록(없으면 빈 리스트)
	 */
	public static List<String> extractImageUrls(ObjectMapper objectMapper, String deltaJson) {
		List<String> urls = new ArrayList<>();
		if (deltaJson == null || deltaJson.isBlank()) {
			return urls;
		}
		try {
			JsonNode ops = objectMapper.readTree(deltaJson).path("ops");
			if (ops.isArray()) {
				for (JsonNode op : ops) {
					JsonNode insert = op.path("insert");
					if (insert.isObject()) {
						JsonNode image = insert.path("image");
						if (image.isTextual()) {
							String url = image.asText();
							if (!url.isBlank() && !urls.contains(url)) {
								urls.add(url);
							}
						}
					}
				}
			}
		} catch (RuntimeException | com.fasterxml.jackson.core.JsonProcessingException e) {
			// 견고성: 파싱 실패 시 이미지 추출만 생략한다.
			log.warn("본문 Delta JSON 파싱 실패 — 인라인 이미지 추출을 생략한다.", e);
		}
		return urls;
	}
}
