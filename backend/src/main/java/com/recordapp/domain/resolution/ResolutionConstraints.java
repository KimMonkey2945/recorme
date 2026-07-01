package com.recordapp.domain.resolution;

/**
 * 작심삼일 도메인 공통 제약 상수.
 * <p>DB(V9 {@code chk_resolutions_title_len} CHECK 1~100, {@code chk_resolutions_span} end=start+2)·
 * 앱 입력 제한과 동일한 단일 상수원으로 사용한다. 값을 바꿀 때는 마이그레이션 CHECK·앱 제한도 함께 맞춰야 한다.
 */
public final class ResolutionConstraints {

	/** 할일 제목 최대 길이(글자 수). V9 title CHECK·앱 maxLength 와 동일. */
	public static final int TITLE_MAX = 100;

	/** 결심 기간(일). '작심삼일' = 3일. 종료일 = 시작일 + (DURATION_DAYS - 1). V9 span CHECK 와 동일. */
	public static final int DURATION_DAYS = 3;

	private ResolutionConstraints() {
		// 인스턴스화 방지(상수 전용 클래스)
	}
}
