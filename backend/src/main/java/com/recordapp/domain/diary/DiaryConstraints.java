package com.recordapp.domain.diary;

/**
 * 일기 도메인 공통 제약 상수.
 * <p>DB(V2 {@code chk_diaries_content_len} CHECK 1~500)·앱 maxLength 와 동일한 단일 상수원으로 사용한다.
 * 값을 바꿀 때는 마이그레이션 CHECK·앱 입력 제한도 함께 맞춰야 한다.
 */
public final class DiaryConstraints {

	/** 일기 본문 최대 길이(글자 수). V2 content CHECK·앱 maxLength 와 동일. */
	public static final int CONTENT_MAX = 500;

	/** 일기 1개당 첨부 사진 최대 장수. 서비스 레이어에서 검증(DB 트리거 미사용). */
	public static final int IMAGE_MAX_PER_DIARY = 5;

	private DiaryConstraints() {
		// 인스턴스화 방지(상수 전용 클래스)
	}
}
