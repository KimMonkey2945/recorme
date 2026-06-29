package com.recordapp.domain.emotion.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.recordapp.domain.diary.DeltaImages;
import com.recordapp.infra.llm.LlmImage;
import com.recordapp.infra.llm.LlmProperties;
import com.recordapp.infra.storage.LoadedImage;
import com.recordapp.infra.storage.StorageService;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.Image;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import javax.imageio.ImageIO;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * 일기 본문(Quill Delta)의 인라인 이미지를 LLM 비전 입력({@link LlmImage})으로 준비한다.
 *
 * <p>URL 추출은 {@link DeltaImages} 공용 유틸로 일원화(파일 회수용 DiaryService 와 동일 로직).
 * 토큰 절약을 위해 긴 변이 {@code imageMaxEdgePx}(기본 512)를 넘으면 JDK 내장 ImageIO 로
 * 비율 유지 축소 후 JPEG 재인코딩한다(새 의존성 없음).
 *
 * <p>견고성: 어떤 단계 실패도 일기 분석을 막지 않는다.
 * <ul>
 *   <li>스토리지에서 못 읽으면 skip</li>
 *   <li>ImageIO 디코드 불가(WEBP 등 {@code read==null}) → 원본 bytes·원본 mediaType 폴백</li>
 *   <li>이미 ≤ maxEdge → 원본 유지</li>
 *   <li>인코딩 실패/예외 → 원본 폴백</li>
 * </ul>
 */
@Component
public class DiaryImagePreparer {

	private static final Logger log = LoggerFactory.getLogger(DiaryImagePreparer.class);

	private final StorageService storageService;
	private final LlmProperties props;
	private final ObjectMapper objectMapper;

	public DiaryImagePreparer(StorageService storageService,
			LlmProperties props,
			ObjectMapper objectMapper) {
		this.storageService = storageService;
		this.props = props;
		this.objectMapper = objectMapper;
	}

	/**
	 * 본문에서 이미지 URL 을 추출해 최대 {@code maxImages}장까지 LLM 입력으로 변환한다.
	 *
	 * @param contentDeltaJson Quill Delta 본문 JSON
	 * @return 비전 입력 목록(없으면 빈 리스트)
	 */
	public List<LlmImage> prepare(String contentDeltaJson) {
		List<String> urls = DeltaImages.extractImageUrls(objectMapper, contentDeltaJson);
		List<LlmImage> result = new ArrayList<>();
		int max = props.maxImages();
		for (String url : urls) {
			if (result.size() >= max) {
				break;
			}
			Optional<LoadedImage> loaded = storageService.loadByUrl(url);
			if (loaded.isEmpty()) {
				continue; // 외부 URL·미존재·미지원 확장자 등은 건너뛴다.
			}
			result.add(downscale(loaded.get()));
		}
		return result;
	}

	/**
	 * 긴 변이 한도를 넘으면 비율 유지 축소 후 JPEG 재인코딩한다. 디코드 불가/이미 작음/실패는 원본 폴백.
	 */
	private LlmImage downscale(LoadedImage src) {
		int maxEdge = props.imageMaxEdgePx();
		try {
			BufferedImage image = ImageIO.read(new ByteArrayInputStream(src.data()));
			if (image == null) {
				// ImageIO 가 디코드 불가(WEBP 등) → 원본 그대로 LLM 에 넘긴다.
				return new LlmImage(src.data(), src.mediaType());
			}
			int w = image.getWidth();
			int h = image.getHeight();
			int longEdge = Math.max(w, h);
			if (longEdge <= maxEdge) {
				return new LlmImage(src.data(), src.mediaType()); // 이미 충분히 작음
			}

			double scale = (double) maxEdge / longEdge;
			int nw = Math.max(1, (int) Math.round(w * scale));
			int nh = Math.max(1, (int) Math.round(h * scale));

			BufferedImage scaled = new BufferedImage(nw, nh, BufferedImage.TYPE_INT_RGB);
			Graphics2D g = scaled.createGraphics();
			try {
				// JPEG 은 알파 미지원 → 투명 배경을 흰색으로 평탄화(검은 배경 방지).
				g.setColor(Color.WHITE);
				g.fillRect(0, 0, nw, nh);
				g.setRenderingHint(RenderingHints.KEY_INTERPOLATION,
						RenderingHints.VALUE_INTERPOLATION_BILINEAR);
				g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
				g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
				g.drawImage(image.getScaledInstance(nw, nh, Image.SCALE_SMOOTH), 0, 0, null);
			} finally {
				g.dispose();
			}

			ByteArrayOutputStream out = new ByteArrayOutputStream();
			boolean ok = ImageIO.write(scaled, "jpeg", out);
			if (!ok || out.size() == 0) {
				return new LlmImage(src.data(), src.mediaType()); // 인코더 부재 등 → 원본 폴백
			}
			return new LlmImage(out.toByteArray(), "image/jpeg");
		} catch (Exception e) {
			// IO/디코드/메모리 등 어떤 실패든 원본으로 폴백한다.
			log.warn("이미지 다운스케일 실패 — 원본으로 폴백한다. mediaType={}", src.mediaType(), e);
			return new LlmImage(src.data(), src.mediaType());
		}
	}
}
