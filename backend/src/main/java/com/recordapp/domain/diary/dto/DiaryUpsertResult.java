package com.recordapp.domain.diary.dto;

/**
 * 기록 upsert 결과. 하루 1기록 정책상 같은 날짜 재작성은 UPDATE 로 전환되므로,
 * 컨트롤러가 신규 생성(201)과 갱신(200)을 구분할 수 있도록 inserted 플래그를 함께 반환한다.
 *
 * @param diary    저장 후 재조회한 기록 단건(첨부 사진 포함)
 * @param inserted 신규 INSERT 면 true, 기존 행 UPDATE 면 false (SQL RETURNING xmax=0 기준)
 */
public record DiaryUpsertResult(
		DiaryResponse diary,
		boolean inserted) {
}
