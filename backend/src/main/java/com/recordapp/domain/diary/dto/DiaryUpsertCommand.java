package com.recordapp.domain.diary.dto;

import java.time.LocalDate;

/**
 * 기록 upsert(INSERT ... ON CONFLICT ... DO UPDATE) 입력/출력 겸용 명령 객체.
 * <p>MyBatis 가 RETURNING 다중 컬럼을 useGeneratedKeys 로 회수하기 위해 가변 객체로 둔다.
 * {@link #id}(생성/갱신된 PK)와 {@link #inserted}((xmax=0) — 신규 INSERT 면 true, UPDATE 면 false)는
 * 실행 후 MyBatis 가 keyProperty 로 채운다. (record 는 setter 가 없어 keyProperty 회수가 불가하므로 가변 클래스 사용.)
 */
public class DiaryUpsertCommand {

	// ===== 입력 =====
	private final Long userId;
	private final String content;      // 리치 텍스트(Quill Delta JSON 문자열)
	private final String contentText;  // 순수 텍스트(길이 제약·미리보기·LLM 입력·재분석 트리거 기준)
	private final LocalDate writtenDate;
	private final String visibility; // nullable — SQL 에서 COALESCE(..., 'PRIVATE')
	private final boolean confirm;   // '오늘을 기억하기'(확정) 여부 — true 면 confirmStatus 로 전이, false 면 DRAFT 유지
	// 확정 시 전이할 상태(감정 분석 flag 에 따라 서비스가 결정): on='PENDING'(분석 대기), off='DONE'(즉시 확정).
	private final String confirmStatus;
	private final String emotion;      // 사용자 프리셋 감정 코드(primary_emotion) — nullable
	private final String emotionLabel; // 사용자 자유 텍스트 감정(emotion_label) — nullable

	// ===== 출력(MyBatis keyProperty 회수 대상) =====
	private Long id;
	private boolean inserted;

	public DiaryUpsertCommand(Long userId, String content, String contentText,
			LocalDate writtenDate, String visibility, boolean confirm,
			String confirmStatus, String emotion, String emotionLabel) {
		this.userId = userId;
		this.content = content;
		this.contentText = contentText;
		this.writtenDate = writtenDate;
		this.visibility = visibility;
		this.confirm = confirm;
		this.confirmStatus = confirmStatus;
		this.emotion = emotion;
		this.emotionLabel = emotionLabel;
	}

	public Long getUserId() {
		return userId;
	}

	public String getContent() {
		return content;
	}

	public String getContentText() {
		return contentText;
	}

	public LocalDate getWrittenDate() {
		return writtenDate;
	}

	public String getVisibility() {
		return visibility;
	}

	public boolean isConfirm() {
		return confirm;
	}

	public String getConfirmStatus() {
		return confirmStatus;
	}

	public String getEmotion() {
		return emotion;
	}

	public String getEmotionLabel() {
		return emotionLabel;
	}

	public Long getId() {
		return id;
	}

	public void setId(Long id) {
		this.id = id;
	}

	public boolean isInserted() {
		return inserted;
	}

	public void setInserted(boolean inserted) {
		this.inserted = inserted;
	}
}
