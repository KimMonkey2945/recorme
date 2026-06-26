package com.recordapp.domain.diary.dto;

/**
 * 인라인 이미지 업로드 응답. 작성 중인 본문(Quill Delta)에 끼워 넣을 접근 경로(상대 URL)만 반환한다.
 * <p>url 은 {@code /files/diaries/yyyy/MM/{uuid}.ext} 형태의 상대경로다(호스트는 클라이언트가 조립).
 * 이 시점엔 어떤 일기에도 종속되지 않으며, 본문 저장(upsert/update) 시 content(Delta)에 그대로 임베드된다.
 */
public record ImageUploadResponse(String url) {
}
