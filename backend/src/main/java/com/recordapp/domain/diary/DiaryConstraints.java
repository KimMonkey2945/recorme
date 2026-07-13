package com.recordapp.domain.diary;

/**
 * 기록 도메인 공통 제약 상수.
 * <p>DB(V2 {@code chk_diaries_content_len} CHECK 1~500)·앱 maxLength 와 동일한 단일 상수원으로 사용한다.
 * 값을 바꿀 때는 마이그레이션 CHECK·앱 입력 제한도 함께 맞춰야 한다.
 */
public final class DiaryConstraints {

	/** 기록 본문 최대 길이(글자 수). V2 content CHECK·앱 maxLength 와 동일. */
	public static final int CONTENT_MAX = 500;

	/** 기록 1개당 첨부 사진 최대 장수. 서비스 레이어에서 검증(DB 트리거 미사용). */
	public static final int IMAGE_MAX_PER_DIARY = 5;

	/**
	 * 사용자별 24시간 확정(감정 분석 트리거) 횟수 상한. 공개 노출 시 LLM(Gemini) 비용 폭탄 방어.
	 * 하루 1기록이 정상 사용이므로 20은 넉넉한 여유값이며, 과거 날짜 대량 확정 남용만 차단한다.
	 */
	public static final int DAILY_CONFIRM_LIMIT = 20;

	/**
	 * 확정 가능한 작성일(writtenDate)의 최대 소급 일수. 임의 과거 날짜 대량 생성·확정 표면을 축소한다.
	 * 미래 날짜는 {@code SaveDiaryRequest} 의 {@code @PastOrPresent} 가 차단한다.
	 */
	public static final int MAX_BACKDATE_DAYS = 366;

	private DiaryConstraints() {
		// 인스턴스화 방지(상수 전용 클래스)
	}
}
