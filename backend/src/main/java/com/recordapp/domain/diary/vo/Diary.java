package com.recordapp.domain.diary.vo;

import java.time.LocalDate;
import java.time.OffsetDateTime;

/**
 * diaries 테이블 행 매핑 VO. 컬럼 전체를 담는 가변 컨테이너다.
 * <p>MyBatis 가 채우는 매핑 대상이라 기본 생성자 + getter/setter 를 둔다
 * (snake_case 컬럼 → camelCase 프로퍼티 자동 매핑). 외부 응답에는 그대로 노출하지 않고
 * {@code DiaryResponse} 등 DTO 로 변환해 사용한다.
 */
public class Diary {

	private Long id;
	private String shareToken;          // share_token (UUID) — 외부 노출 식별자
	private Long userId;
	private String content;              // 리치 텍스트(Quill Delta JSON 문자열)
	private String contentText;          // content_text — 순수 텍스트(미리보기·길이 제약·LLM 입력)
	private LocalDate writtenDate;
	private String visibility;          // PRIVATE/FRIENDS/PUBLIC
	private String analysisStatus;      // PENDING/DONE/FAILED
	private OffsetDateTime createdAt;
	private OffsetDateTime updatedAt;
	private OffsetDateTime deletedAt;   // soft delete 시각(null 이면 활성)

	public Long getId() {
		return id;
	}

	public void setId(Long id) {
		this.id = id;
	}

	public String getShareToken() {
		return shareToken;
	}

	public void setShareToken(String shareToken) {
		this.shareToken = shareToken;
	}

	public Long getUserId() {
		return userId;
	}

	public void setUserId(Long userId) {
		this.userId = userId;
	}

	public String getContent() {
		return content;
	}

	public void setContent(String content) {
		this.content = content;
	}

	public String getContentText() {
		return contentText;
	}

	public void setContentText(String contentText) {
		this.contentText = contentText;
	}

	public LocalDate getWrittenDate() {
		return writtenDate;
	}

	public void setWrittenDate(LocalDate writtenDate) {
		this.writtenDate = writtenDate;
	}

	public String getVisibility() {
		return visibility;
	}

	public void setVisibility(String visibility) {
		this.visibility = visibility;
	}

	public String getAnalysisStatus() {
		return analysisStatus;
	}

	public void setAnalysisStatus(String analysisStatus) {
		this.analysisStatus = analysisStatus;
	}

	public OffsetDateTime getCreatedAt() {
		return createdAt;
	}

	public void setCreatedAt(OffsetDateTime createdAt) {
		this.createdAt = createdAt;
	}

	public OffsetDateTime getUpdatedAt() {
		return updatedAt;
	}

	public void setUpdatedAt(OffsetDateTime updatedAt) {
		this.updatedAt = updatedAt;
	}

	public OffsetDateTime getDeletedAt() {
		return deletedAt;
	}

	public void setDeletedAt(OffsetDateTime deletedAt) {
		this.deletedAt = deletedAt;
	}
}
